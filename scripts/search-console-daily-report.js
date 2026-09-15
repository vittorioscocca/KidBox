#!/usr/bin/env node
/**
 * Fotografia giornaliera di Google Search Console per kidboxapp.com
 * (property di dominio `sc-domain:kidboxapp.com`: landing, blog, app.).
 *
 *   node scripts/search-console-daily-report.js           # report testuale
 *   node scripts/search-console-daily-report.js --json    # stesso contenuto, in JSON
 *
 * È il pezzo a monte del funnel che GA4 non vede: quante volte KidBox compare
 * su Google (impressioni), quante persone cliccano, con che posizione media,
 * per quali query e su quali pagine. Più lo stato delle sitemap.
 *
 * Search Console pubblica i dati con 2-3 giorni di ritardo: «ieri» qui è
 * l'ultimo giorno disponibile, non il giorno di calendario. Le finestre
 * (7 gg, 28 gg, confronto col periodo precedente) partono da lì.
 *
 * Stesso meccanismo di GA4: token del service account ga4-reader per
 * impersonazione, con lo scope `webmasters.readonly`. Il service account va
 * aggiunto una volta come utente della property (Search Console →
 * Impostazioni → Utenti e autorizzazioni → Aggiungi utente, autorizzazione
 * «Limitata» basta).
 *
 * Solo lettura.
 */

const { execFileSync } = require("node:child_process");

const SITE = "sc-domain:kidboxapp.com";
const API = `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(SITE)}`;
const SERVICE_ACCOUNT = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";
const TZ = "Europe/Rome";

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function token() {
  try {
    return execFileSync(
      "gcloud",
      [
        "auth",
        "print-access-token",
        `--impersonate-service-account=${SERVICE_ACCOUNT}`,
        "--scopes=https://www.googleapis.com/auth/webmasters.readonly",
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    ).trim();
  } catch (e) {
    console.error(
      `Non riesco a impersonare ${SERVICE_ACCOUNT}.\n` +
        "Serve gcloud autenticato come ing.vittorioscocca@gmail.com, che ha\n" +
        "roles/iam.serviceAccountTokenCreator su quel service account.\n" +
        (e.stderr ? `\n${String(e.stderr).trim()}\n` : "")
    );
    process.exit(2);
  }
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

async function main() {
  const asJson = process.argv.includes("--json");
  const tok = token();
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
    if (asJson) process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    else print(out);
    return;
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

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

const pad = (s, n) => String(s ?? "-").padEnd(n);
const pct = (x) => `${((x || 0) * 100).toFixed(1)}%`;
const pos = (x) => (x ? x.toFixed(1) : "-");
const delta = (a, b) => (b ? ` (${a >= b ? "+" : ""}${(((a - b) / b) * 100).toFixed(0)}%)` : "");
const line = (label, t, p) => `${pad(label, 14)}click ${pad(String(t.clicks) + (p ? delta(t.clicks, p.clicks) : ""), 14)}impr. ${pad(String(t.impressions) + (p ? delta(t.impressions, p.impressions) : ""), 16)}CTR ${pad(pct(t.ctr), 8)}pos. ${pos(t.position)}`;

function print(o) {
  const L = [];
  L.push(`# Search Console — ${o.site}`);
  if (o.empty) {
    for (const n of o.notes) L.push(`- ${n}`);
    process.stdout.write(L.join("\n") + "\n");
    return;
  }
  L.push(`Ultimo giorno disponibile: ${o.lastDay} (Search Console pubblica con ${o.lagDays} gg di ritardo). Le finestre partono da lì.`);
  L.push("");
  L.push(line("Ultimo giorno", o.last));
  L.push(line("Ultimi 7 gg", o.last7, o.prev7));
  L.push(line("Ultimi 28 gg", o.last28, o.prev28));
  L.push(`Brand (query con «kidbox») 28 gg: ${o.brand28.clicks} click su ${o.last28.clicks} (${o.last28.clicks ? Math.round((o.brand28.clicks / o.last28.clicks) * 100) : 0}%), ${o.brand28.impressions} impressioni. Il resto è gente che non ci conosceva.`);
  L.push("");

  L.push("## Serie 28 gg (click / impressioni / posizione)");
  for (const s of o.series) L.push(`${pad(s.date, 12)}${pad(s.clicks, 6)}${pad(s.impressions, 8)}${pos(s.position)}`);
  L.push("");

  L.push("## Query più cliccate — 28 gg");
  if (!o.topQueries.length) L.push("(nessuna)");
  for (const q of o.topQueries) L.push(`${pad(q.clicks, 6)}${pad(q.impressions, 8)}${pad(pct(q.ctr), 8)}${pad(pos(q.position), 6)}${q.query}`);
  L.push("");
  L.push("## Pagine più cliccate — 28 gg");
  for (const p of o.topPages) L.push(`${pad(p.clicks, 6)}${pad(p.impressions, 8)}${pad(pct(p.ctr), 8)}${pad(pos(p.position), 6)}${p.page}`);
  L.push("");
  L.push("## Compare ma nessuno clicca — 28 gg (impressioni, posizione)");
  if (!o.impressionsNoClicks.length) L.push("(nessuna)");
  for (const q of o.impressionsNoClicks) L.push(`${pad(q.impressions, 8)}${pad(pos(q.position), 6)}${q.query}`);
  L.push("");
  L.push("## Paesi e dispositivi — 28 gg");
  L.push(o.byCountry.map((c) => `${c.country} ${c.clicks}/${c.impressions}`).join(" · ") || "(nessuno)");
  L.push(o.byDevice.map((d) => `${d.device} ${d.clicks}/${d.impressions}`).join(" · ") || "(nessuno)");
  L.push("");
  L.push("## Sitemap");
  if (!o.sitemaps.length) L.push("(nessuna sitemap inviata)");
  for (const s of o.sitemaps) L.push(`${pad(s.path, 28)}inviate ${pad(s.submitted, 6)}indicizzate ${pad(s.indexed, 6)}errori ${s.errors} avvisi ${s.warnings} · letta il ${s.lastDownloaded || "-"}${s.pending ? " (in attesa)" : ""}`);
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore Search Console: ${e.message}`);
  if (e.status === 403) {
    console.error(`Il service account ${SERVICE_ACCOUNT} non è utente della property ${SITE}: aggiungerlo in Search Console → Impostazioni → Utenti e autorizzazioni.`);
  }
  process.exit(1);
});
