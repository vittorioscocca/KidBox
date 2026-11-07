/* eslint-disable -- stile degli script (prettier), condiviso con scripts/ */
/**
 * Raccolta dei dati di Search Console per il report: UNICA copia del codice,
 * usata da `scripts/search-console-daily-report.js` (dal vivo) e dalla funzione
 * pianificata `reportSnapshotDaily` (che salva il risultato su Firestore).
 * Gli obiettivi (GOALS) restano nello script: si calcolano sul risultato.
 */

const SITE = "sc-domain:kidboxapp.com";
const API = `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(SITE)}`;
const TZ = "Europe/Rome";

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

async function call(tok, path, body) {
  const res = await fetch(`${API}/${path}`, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const e = json.error || {};
    const err = new Error(`${path}: ${e.message || res.status}`);
    err.status = res.status;
    throw err;
  }
  return json;
}

async function query(tok, startDate, endDate, dimensions, extra = {}) {
  const json = await call(tok, "searchAnalytics/query", {
    startDate,
    endDate,
    dimensions,
    rowLimit: 250,
    dataState: "final",
    ...extra,
  });
  return (json.rows || []).map((r) => ({
    keys: r.keys || [],
    clicks: r.clicks || 0,
    impressions: r.impressions || 0,
    ctr: r.ctr || 0,
    position: r.position || 0,
  }));
}

const sum = (rows, k) => rows.reduce((a, r) => a + r[k], 0);
function totals(rows) {
  const clicks = sum(rows, "clicks");
  const impressions = sum(rows, "impressions");
  // Posizione media pesata sulle impressioni, come fa la UI.
  const position = impressions ? rows.reduce((a, r) => a + r.position * r.impressions, 0) / impressions : 0;
  return { clicks, impressions, ctr: impressions ? clicks / impressions : 0, position };
}

async function collect(tok) {
  const out = { site: SITE, notes: [] };

  // Ultimo giorno disponibile: si chiedono gli ultimi 10 giorni per data e si
  // prende il più recente con almeno un'impressione.
  const today = romeDate();
  const probe = await query(tok, shiftDay(today, -10), today, ["date"]);
  const days = probe.map((r) => r.keys[0]).sort();
  const last = days[days.length - 1];
  if (!last) {
    out.notes.push("Nessun dato negli ultimi 10 giorni: property vuota o service account senza accesso.");
    out.empty = true;
    return out;
  }
  out.lastDay = last;
  out.lagDays = Math.round((Date.parse(today) - Date.parse(last)) / 86400000);

  const d7s = shiftDay(last, -6);
  const p7s = shiftDay(last, -13);
  const p7e = shiftDay(last, -7);
  const d28s = shiftDay(last, -27);
  const p28s = shiftDay(last, -55);
  const p28e = shiftDay(last, -28);

  // Serie giornaliera 28 gg (per il grafico) e totali con confronto.
  const series = await query(tok, d28s, last, ["date"]);
  const byDate = Object.fromEntries(series.map((r) => [r.keys[0], r]));
  out.series = [...Array(28)].map((_, i) => {
    const d = shiftDay(d28s, i);
    const r = byDate[d] || { clicks: 0, impressions: 0, ctr: 0, position: 0 };
    return { date: d, clicks: r.clicks, impressions: r.impressions, position: r.position };
  });
  out.last = byDate[last] ? totals([byDate[last]]) : totals([]);
  out.last7 = totals(series.filter((r) => r.keys[0] >= d7s));
  out.prev7 = totals(await query(tok, p7s, p7e, ["date"]));
  out.last28 = totals(series);
  out.prev28 = totals(await query(tok, p28s, p28e, ["date"]));

  // Top query e pagine, 28 gg (le 7 gg sono troppo poche a questi volumi).
  const top = (rows, n) => rows.sort((a, b) => b.clicks - a.clicks || b.impressions - a.impressions).slice(0, n);
  out.topQueries = top(await query(tok, d28s, last, ["query"]), 15).map((r) => ({ query: r.keys[0], ...r, keys: undefined }));
  out.topPages = top(await query(tok, d28s, last, ["page"]), 15).map((r) => ({ page: r.keys[0].replace(/^https?:\/\/(www\.)?kidboxapp\.com/, "") || "/", ...r, keys: undefined }));
  out.byCountry = top(await query(tok, d28s, last, ["country"]), 8).map((r) => ({ country: r.keys[0].toUpperCase(), ...r, keys: undefined }));
  out.byDevice = (await query(tok, d28s, last, ["device"])).map((r) => ({ device: r.keys[0].toLowerCase(), ...r, keys: undefined }));
  // Query con più impressioni ma senza click: dove si compare e nessuno clicca.
  out.impressionsNoClicks = (await query(tok, d28s, last, ["query"]))
    .filter((r) => r.clicks === 0)
    .sort((a, b) => b.impressions - a.impressions)
    .slice(0, 8)
    .map((r) => ({ query: r.keys[0], impressions: r.impressions, position: r.position }));
  // Query «brand» (kidbox): quanto del traffico è gente che ci cerca per nome.
  const brand = (await query(tok, d28s, last, ["query"])).filter((r) => /kid\s?box/i.test(r.keys[0]));
  out.brand28 = totals(brand);
  // La query brand pura: la sua posizione è l'indicatore della canonica.
  const brandQuery = brand.find((r) => r.keys[0].toLowerCase() === "kidbox");
  out.brandKidbox = brandQuery ? { impressions: brandQuery.impressions, clicks: brandQuery.clicks, position: brandQuery.position } : null;
  out.pagesWithImpressions28 = (await query(tok, d28s, last, ["page"], { rowLimit: 1000 })).filter((r) => r.impressions > 0).length;


  // Sitemap.
  try {
    const sm = await call(tok, "sitemaps");
    out.sitemaps = (sm.sitemap || []).map((s) => ({
      path: s.path.replace(/^https?:\/\/(www\.)?kidboxapp\.com/, ""),
      lastSubmitted: (s.lastSubmitted || "").slice(0, 10),
      lastDownloaded: (s.lastDownloaded || "").slice(0, 10),
      errors: Number(s.errors || 0),
      warnings: Number(s.warnings || 0),
      submitted: (s.contents || []).reduce((a, c) => a + Number(c.submitted || 0), 0),
      indexed: (s.contents || []).reduce((a, c) => a + Number(c.indexed || 0), 0),
      pending: !!s.isPending,
    }));
  } catch (e) {
    out.sitemaps = [];
    out.notes.push(`Sitemap non leggibili: ${e.message}`);
  }

  return out;
}

module.exports = { collect, SITE, romeDate, shiftDay };
