#!/usr/bin/env node
/**
 * Fotografia giornaliera di Google Play per KidBox (it.vittorioscocca.kidbox).
 *
 *   node scripts/play-daily-report.js           # report testuale
 *   node scripts/play-daily-report.js --json    # stesso contenuto, in JSON
 *
 * Tre fonti, tre credenziali diverse, tutte già in casa:
 *
 * 1. **Statistiche** (installazioni, disinstallazioni, dispositivi attivi,
 *    valutazione media, per giorno e per paese): i CSV che Play esporta nel
 *    bucket `gs://pubsite_prod_rev_00873204915190884037/stats/…`. Li legge il
 *    token dell'utente (`gcloud auth print-access-token`): è il proprietario
 *    dell'account Play, e il bucket è suo. UTF-16LE con BOM, gzip.
 *    **Ritardo di ~5-7 giorni**: il report dice fino a che giorno arriva.
 * 2. **Crash e ANR**: Play Developer Reporting API, freschi a ieri. Token del
 *    service account `play-purchase-validator@…` (già collegato a Play per le
 *    ricevute) impersonato con scope `playdeveloperreporting`; API abilitata
 *    sul progetto il 15/09/2026. `crashRateMetricSet` risponde vuoto sotto una
 *    soglia di utenti: si usa `errorCountMetricSet`, che conta e basta.
 * 3. **Recensioni**: Android Publisher API, stesso service account, scope
 *    `androidpublisher`. Solo stelle, data, versione e testo: mai il nome.
 *
 * Solo lettura. Il giorno di riferimento è «ieri» in Europe/Rome come per gli
 * altri script, ma qui i dati arrivano quando arrivano.
 */

const { execFileSync } = require("node:child_process");

const PACKAGE = "it.vittorioscocca.kidbox";
const BUCKET = "pubsite_prod_rev_00873204915190884037";
const SA = "play-purchase-validator@kidbox-42cd7.iam.gserviceaccount.com";
const TZ = "Europe/Rome";

function gcloudToken(args) {
  try {
    return execFileSync("gcloud", ["auth", "print-access-token", ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (e) {
    console.error(`gcloud: impossibile ottenere il token (${args.join(" ") || "utente"}).`);
    console.error(String(e.stderr || "").trim());
    process.exit(2);
  }
}
const userToken = () => gcloudToken([]);
const saToken = (scope) =>
  gcloudToken([`--impersonate-service-account=${SA}`, `--scopes=https://www.googleapis.com/auth/${scope}`]);

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// ------------------------------------------------------------ CSV del bucket

async function readStatsCsv(tok, kind, month, dimension) {
  const name = `stats/${kind}/${kind}_${PACKAGE}_${month}_${dimension}.csv`;
  const url = `https://storage.googleapis.com/download/storage/v1/b/${BUCKET}/o/${encodeURIComponent(name)}?alt=media`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${tok}` } });
  if (res.status === 404) return null; // mese non ancora esportato
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const text = new TextDecoder("utf-16le").decode(buf).replace(/^﻿/, "");
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  const header = lines[0].split(",");
  return lines.slice(1).map((l) => {
    const cells = l.split(",");
    const o = {};
    header.forEach((h, i) => (o[h.trim()] = cells[i]));
    return o;
  });
}

async function readMonths(tok, kind, dimension, months) {
  const out = [];
  for (const m of months) {
    const rows = await readStatsCsv(tok, kind, m, dimension);
    if (rows) out.push(...rows);
  }
  return out;
}

// ------------------------------------------------------------ Reporting API

async function errorCounts(tok, startIso, endIso) {
  const day = (iso) => {
    const [y, m, d] = iso.split("-").map(Number);
    return { year: y, month: m, day: d, timeZone: { id: "America/Los_Angeles" } };
  };
  const res = await fetch(
    `https://playdeveloperreporting.googleapis.com/v1beta1/apps/${PACKAGE}/errorCountMetricSet:query`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        timelineSpec: { aggregationPeriod: "DAILY", startTime: day(startIso), endTime: day(endIso) },
        metrics: ["errorReportCount", "distinctUsers"],
        dimensions: ["reportType"],
        pageSize: 1000,
      }),
    }
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`Reporting API: ${json.error?.message || res.status}`);
  return (json.rows || []).map((r) => {
    const t = r.startTime;
    const metrics = Object.fromEntries(r.metrics.map((m) => [m.metric, Number(m.decimalValue?.value || 0)]));
    return {
      date: `${t.year}-${String(t.month).padStart(2, "0")}-${String(t.day).padStart(2, "0")}`,
      type: r.dimensions?.[0]?.stringValue || "?",
      reports: metrics.errorReportCount || 0,
      users: metrics.distinctUsers || 0,
    };
  });
}

// ------------------------------------------------------------ Recensioni

async function reviews(tok) {
  const res = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE}/reviews?maxResults=20`,
    { headers: { Authorization: `Bearer ${tok}` } }
  );
  const json = await res.json();
  if (!res.ok) throw new Error(`Publisher API: ${json.error?.message || res.status}`);
  return (json.reviews || []).map((r) => {
    const c = r.comments?.[0]?.userComment || {};
    return {
      date: new Date(Number(c.lastModified?.seconds || 0) * 1000).toISOString().slice(0, 10),
      stars: c.starRating,
      version: c.appVersionName,
      lang: c.reviewerLanguage,
      text: (c.text || "").replace(/\s+/g, " ").trim().slice(0, 160),
      replied: (r.comments || []).some((x) => x.developerComment),
    };
  });
}

// ------------------------------------------------------------ main

async function main() {
  const asJson = process.argv.includes("--json");
  const yesterday = shiftDay(romeDate(), -1);
  const months = [...new Set([shiftDay(yesterday, -35).slice(0, 7), shiftDay(yesterday, -14).slice(0, 7), yesterday.slice(0, 7)])].map((m) => m.replace("-", ""));
  const out = { package: PACKAGE, yesterday, notes: [] };

  const utok = userToken();
  const installs = await readMonths(utok, "installs", "overview", months);
  const num = (x) => Number(x || 0);
  out.installs = installs
    .map((r) => ({
      date: r.Date,
      installs: num(r["Daily Device Installs"]),
      uninstalls: num(r["Daily Device Uninstalls"]),
      upgrades: num(r["Daily Device Upgrades"]),
      activeDevices: num(r["Active Device Installs"]),
      installEvents: num(r["Install events"]),
      updateEvents: num(r["Update events"]),
    }))
    .sort((a, b) => a.date.localeCompare(b.date));
  out.installsUpTo = out.installs.length ? out.installs[out.installs.length - 1].date : null;
  if (!out.installsUpTo) out.notes.push("Nessun CSV installazioni trovato nel bucket.");
  else if (shiftDay(out.installsUpTo, 8) < yesterday) out.notes.push(`Export installazioni fermo al ${out.installsUpTo}: più indietro del solito (5-7 giorni).`);

  // Paesi: ultimi 7 giorni disponibili.
  const byCountry = await readMonths(utok, "installs", "country", months);
  if (out.installsUpTo) {
    const from = shiftDay(out.installsUpTo, -6);
    const agg = {};
    for (const r of byCountry) {
      if (r.Date < from || r.Date > out.installsUpTo) continue;
      const c = r.Country || "?";
      agg[c] = (agg[c] || 0) + num(r["Daily Device Installs"]);
    }
    out.countries7d = Object.entries(agg).filter(([, v]) => v).sort((a, b) => b[1] - a[1]).slice(0, 8);
  }

  const ratings = await readMonths(utok, "ratings", "overview", months);
  const lastRating = ratings.sort((a, b) => a.Date.localeCompare(b.Date)).at(-1);
  out.rating = lastRating ? { date: lastRating.Date, total: Number(lastRating["Total Average Rating"]) } : null;

  // Crash e ANR, freschi.
  const rtok = saToken("playdeveloperreporting");
  const errs = await errorCounts(rtok, shiftDay(yesterday, -13), yesterday);
  out.errors = errs;

  // Recensioni.
  const ptok = saToken("androidpublisher");
  out.reviews = await reviews(ptok);

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

const pad = (s, n) => String(s ?? "-").padEnd(n);

function print(o) {
  const L = [];
  L.push(`# Google Play KidBox — ieri ${o.yesterday} (${o.package})`);
  L.push("");
  L.push(`## Installazioni per giorno (export Play, aggiornato al ${o.installsUpTo || "?"})`);
  L.push(pad("giorno", 12) + pad("install", 9) + pad("disinst", 9) + pad("aggiorn", 9) + pad("device attivi", 15) + "eventi install/update");
  // Giorni di calendario, non righe: l'export di Play ha buchi (agosto 2026
  // si ferma al 21) e una finestra «ultime 14 righe» li nasconderebbe.
  const byDay = Object.fromEntries(o.installs.map((r) => [r.date, r]));
  const end = o.installsUpTo || o.yesterday;
  const window = [];
  for (let i = 13; i >= 0; i--) window.push(shiftDay(end, -i));
  let missing = 0;
  for (const d of window) {
    const r = byDay[d];
    if (!r) { missing++; L.push(pad(d, 12) + "(non esportato)"); continue; }
    L.push(pad(d, 12) + pad(r.installs, 9) + pad(r.uninstalls, 9) + pad(r.upgrades, 9) + pad(r.activeDevices, 15) + `${r.installEvents}/${r.updateEvents}`);
  }
  const sumDays = (days, k) => days.reduce((a, d) => a + (byDay[d]?.[k] || 0), 0);
  const last7 = window.slice(7);
  const prev7 = window.slice(0, 7);
  const cover = (days) => `${days.filter((d) => byDay[d]).length}/7 gg`;
  L.push(`Ultimi 7 gg (${cover(last7)}): ${sumDays(last7, "installs")} installazioni, ${sumDays(last7, "uninstalls")} disinstallazioni · 7 gg prima (${cover(prev7)}): ${sumDays(prev7, "installs")} / ${sumDays(prev7, "uninstalls")}`);
  if (missing) L.push(`${missing} giorni senza export nella finestra: confronti da prendere con le pinze.`);
  L.push("«Device attivi» = dispositivi con l'app installata (Play), non utenti che la usano.");
  L.push("");
  if (o.countries7d) {
    L.push("## Installazioni per paese (ultimi 7 gg disponibili)");
    L.push(o.countries7d.map(([c, n]) => `${c}=${n}`).join(", ") || "(nessuna)");
    L.push("");
  }
  L.push("## Valutazione");
  L.push(o.rating ? `Media complessiva ${o.rating.total.toFixed(2)} (al ${o.rating.date})` : "(nessun dato)");
  L.push("");
  L.push("## Crash e ANR (Reporting API, a ieri) — 14 gg");
  const byDate = {};
  for (const e of o.errors) (byDate[e.date] = byDate[e.date] || {})[e.type] = e;
  const dates = Object.keys(byDate).sort();
  const withErrors = dates.filter((d) => Object.values(byDate[d]).some((e) => e.reports));
  if (!withErrors.length) L.push("(nessun crash né ANR)");
  for (const d of withErrors) {
    const parts = Object.values(byDate[d]).filter((e) => e.reports).map((e) => `${e.type}: ${e.reports} report da ${e.users} utenti`);
    L.push(`${d}  ${parts.join(" · ")}`);
  }
  const tot = o.errors.reduce((a, e) => ((a[e.type] = (a[e.type] || 0) + e.reports), a), {});
  L.push(`Totale 14 gg: ${Object.entries(tot).map(([k, v]) => `${k}=${v}`).join(", ") || "0"}`);
  L.push("");
  L.push("## Recensioni (ultime 20 modificate)");
  if (!o.reviews.length) L.push("(nessuna)");
  for (const r of o.reviews) L.push(`${r.date}  ${"★".repeat(r.stars || 0)}${"☆".repeat(5 - (r.stars || 0))}  v${r.version || "?"} ${r.lang || ""}${r.replied ? " (risposta)" : ""}  ${r.text ? `«${r.text}»` : ""}`);
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore Google Play: ${e.message}`);
  process.exit(1);
});
