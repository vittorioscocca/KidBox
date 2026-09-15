#!/usr/bin/env node
/**
 * Fotografia giornaliera di App Store Connect per KidBox (app 6761055375).
 *
 *   node scripts/appstore-daily-report.js           # report testuale
 *   node scripts/appstore-daily-report.js --json    # stesso contenuto, in JSON
 *   node scripts/appstore-daily-report.js --raw     # colonne e prime righe dei TSV, per capire i formati
 *
 * Due fonti:
 * 1. **App Analytics Reports** (App Store Connect API, `analyticsReportRequests`):
 *    Discovery and Engagement (impression, viste pagina, conversione), App
 *    Downloads, Installation and Deletion, App Sessions, App Crashes. Apple li
 *    genera solo se qualcuno li chiede: la richiesta ONGOING è stata creata il
 *    15/09/2026 (id b82f1b10-…), più uno snapshot una tantum per lo storico.
 *    Le istanze DAILY arrivano con 1-2 giorni di ritardo, come TSV gzip a
 *    segmenti. Se non ci sono ancora, il report lo dice e passa oltre.
 * 2. **Recensioni** (`customerReviews`): stelle, data, titolo, testo, versione.
 *
 * Autenticazione: JWT ES256 firmato con la chiave API «KidBox Report Admin»
 * (Key ID 5XN458397C, ruolo Admin: «Vendite e report» non poteva creare le
 * richieste di report). Il file .p8 sta nel Portachiavi di macOS in base64:
 *
 *   security add-generic-password -a kidbox -s asc-api-key -w "$(base64 -i AuthKey.p8)" -U
 *
 * Solo lettura. Nessun dato personale nel report: delle recensioni si
 * stampano stelle, data, titolo e testo, mai il nickname.
 */

const crypto = require("node:crypto");
const zlib = require("node:zlib");
const { execFileSync } = require("node:child_process");

const APP_ID = "6761055375";
const KEY_ID = "5XN458397C";
const ISSUER_ID = "2deae1f9-70dc-49b6-b792-083e481811d3";
const API = "https://api.appstoreconnect.apple.com/v1";
const TZ = "Europe/Rome";

// Nome del report Apple → chiave nel nostro output.
const REPORTS = {
  "App Store Discovery and Engagement Standard": "engagement",
  "App Downloads Standard": "downloads",
  "App Store Installation and Deletion Standard": "installs",
  "App Sessions Standard": "sessions",
  "App Crashes": "crashes",
};

function privateKey() {
  try {
    const b64 = execFileSync("security", ["find-generic-password", "-a", "kidbox", "-s", "asc-api-key", "-w"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
    return Buffer.from(b64, "base64").toString("utf8");
  } catch {
    console.error(
      "Chiave App Store Connect non trovata nel Portachiavi (voce «asc-api-key», account «kidbox»).\n" +
        "Va salvata con: security add-generic-password -a kidbox -s asc-api-key -w \"$(base64 -i AuthKey.p8)\" -U"
    );
    process.exit(2);
  }
}

function jwt(pem) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const header = b64({ alg: "ES256", kid: KEY_ID, typ: "JWT" });
  const payload = b64({ iss: ISSUER_ID, iat: now, exp: now + 1200, aud: "appstoreconnect-v1" });
  const sig = crypto.sign("sha256", Buffer.from(`${header}.${payload}`), { key: pem, dsaEncoding: "ieee-p1363" }).toString("base64url");
  return `${header}.${payload}.${sig}`;
}

async function get(tok, path) {
  const url = path.startsWith("http") ? path : `${API}${path}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${tok}` } });
  const json = await res.json();
  if (!res.ok) throw new Error(`${path.replace(API, "")}: ${json.errors?.[0]?.detail || json.errors?.[0]?.title || res.status}`);
  return json;
}

async function getAll(tok, path) {
  const out = [];
  let next = path;
  while (next) {
    const j = await get(tok, next);
    out.push(...(j.data || []));
    next = j.links?.next || null;
  }
  return out;
}

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// TSV Apple: prima riga intestazione, tab-separati, gzip.
function parseTsv(buf) {
  let text;
  try {
    text = zlib.gunzipSync(buf).toString("utf8");
  } catch {
    text = buf.toString("utf8");
  }
  const lines = text.split(/\r?\n/).filter((l) => l.length);
  if (!lines.length) return { header: [], rows: [] };
  const header = lines[0].split("\t");
  const rows = lines.slice(1).map((l) => {
    const cells = l.split("\t");
    const o = {};
    header.forEach((h, i) => (o[h] = cells[i]));
    return o;
  });
  return { header, rows };
}

async function downloadInstance(tok, instanceId) {
  const segs = await getAll(tok, `/analyticsReportInstances/${instanceId}/segments`);
  const rows = [];
  let header = [];
  for (const s of segs) {
    const res = await fetch(s.attributes.url);
    if (!res.ok) throw new Error(`segmento ${s.id}: HTTP ${res.status}`);
    const parsed = parseTsv(Buffer.from(await res.arrayBuffer()));
    header = parsed.header;
    rows.push(...parsed.rows);
  }
  return { header, rows };
}

const num = (x) => Number(String(x ?? "0").replace(/,/g, "")) || 0;

// Somma per giorno di una colonna numerica, opzionalmente spaccata per un'altra colonna.
function sumByDay(rows, valueCol, splitCol) {
  const out = {};
  for (const r of rows) {
    const d = r.Date || r.date;
    if (!d) continue;
    const key = splitCol ? r[splitCol] || "?" : "_";
    (out[d] = out[d] || {})[key] = (out[d][key] || 0) + num(r[valueCol]);
  }
  return out;
}

async function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const raw = args.includes("--raw");
  const yesterday = shiftDay(romeDate(), -1);
  const since = shiftDay(yesterday, -13);
  const pem = privateKey();
  const tok = jwt(pem);
  const out = { app: APP_ID, yesterday, notes: [], reports: {} };

  // 1. Richiesta ONGOING (preferita) o snapshot.
  const requests = await getAll(tok, `/apps/${APP_ID}/analyticsReportRequests`);
  const ongoing = requests.find((r) => r.attributes.accessType === "ONGOING" && !r.attributes.stoppedDueToInactivity);
  const request = ongoing || requests[0];
  if (!request) {
    out.notes.push("Nessuna richiesta di report App Analytics: va creata (POST analyticsReportRequests, ONGOING).");
  } else {
    if (ongoing?.attributes.stoppedDueToInactivity) out.notes.push("La richiesta ONGOING è stata fermata da Apple per inattività: va ricreata.");
    const reports = await getAll(tok, `/analyticsReportRequests/${request.id}/reports?limit=200`);
    for (const rep of reports) {
      const key = REPORTS[rep.attributes.name];
      if (!key) continue;
      const instances = (await getAll(tok, `/analyticsReports/${rep.id}/instances?limit=200`))
        .filter((i) => i.attributes.granularity === "DAILY")
        .sort((a, b) => (b.attributes.processingDate || "").localeCompare(a.attributes.processingDate || ""));
      if (!instances.length) {
        out.reports[key] = { name: rep.attributes.name, available: false };
        continue;
      }
      // Ogni istanza DAILY copre un giorno: bastano le ultime 14.
      const rows = [];
      let header = [];
      for (const inst of instances.slice(0, 14)) {
        const d = await downloadInstance(tok, inst.id);
        header = d.header;
        rows.push(...d.rows.filter((r) => (r.Date || "") >= since));
      }
      out.reports[key] = {
        name: rep.attributes.name,
        available: true,
        latest: instances[0].attributes.processingDate,
        header,
        rowCount: rows.length,
        sample: raw ? rows.slice(0, 5) : undefined,
        rows: asJson || raw ? undefined : rows,
      };
      if (raw) continue;
      // Aggregati per giorno, secondo il report.
      const R = out.reports[key];
      switch (key) {
        case "engagement":
          // Colonne attese: Event (Impression / Page View / Tap …), Counts, Unique Counts, Source Type.
          R.byDay = sumByDay(rows, header.includes("Counts") ? "Counts" : header.at(-1), "Event");
          R.bySource = sumByDay(rows, header.includes("Counts") ? "Counts" : header.at(-1), "Source Type");
          break;
        case "downloads":
          R.byDay = sumByDay(rows, "Counts", "Download Type");
          R.byTerritory = sumByDay(rows, "Counts", "Territory");
          R.bySource = sumByDay(rows, "Counts", "Source Type");
          break;
        case "installs":
          R.byDay = sumByDay(rows, "Counts", "Event");
          break;
        case "sessions":
          R.byDay = sumByDay(rows, header.includes("Sessions") ? "Sessions" : "Counts");
          R.devices = sumByDay(rows, header.find((h) => /Unique Devices/i.test(h)) || "Unique Devices");
          break;
        case "crashes":
          R.byDay = sumByDay(rows, header.includes("Crashes") ? "Crashes" : "Counts", "App Version");
          break;
      }
      delete R.rows;
    }
    for (const name of Object.keys(REPORTS)) {
      if (!out.reports[REPORTS[name]]) out.notes.push(`Report «${name}» non presente nella richiesta.`);
    }
  }

  // 2. Recensioni.
  const reviews = await get(tok, `/apps/${APP_ID}/customerReviews?limit=20&sort=-createdDate`);
  out.reviews = (reviews.data || []).map((r) => ({
    date: (r.attributes.createdDate || "").slice(0, 10),
    stars: r.attributes.rating,
    territory: r.attributes.territory,
    title: r.attributes.title,
    text: (r.attributes.body || "").replace(/\s+/g, " ").trim().slice(0, 200),
  }));

  if (asJson || raw) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

const pad = (s, n) => String(s ?? "-").padEnd(n);

function printByDay(L, byDay, label) {
  const days = Object.keys(byDay).sort();
  if (!days.length) { L.push(`(nessuna riga negli ultimi 14 giorni)`); return; }
  const keys = [...new Set(days.flatMap((d) => Object.keys(byDay[d])))].sort();
  if (keys.length === 1 && keys[0] === "_") {
    for (const d of days) L.push(`${pad(d, 12)}${byDay[d]._}`);
    return;
  }
  L.push(pad("giorno", 12) + keys.map((k) => pad(k, 22)).join(""));
  for (const d of days) L.push(pad(d, 12) + keys.map((k) => pad(byDay[d][k] || 0, 22)).join(""));
  if (label) L.push(label);
}

function print(o) {
  const L = [];
  L.push(`# App Store KidBox — ieri ${o.yesterday} (app ${o.app})`);
  L.push("");
  const rep = (key) => o.reports[key];
  const section = (key, title, fn) => {
    const R = rep(key);
    L.push(`## ${title}`);
    if (!R) { L.push("(report non richiesto)"); L.push(""); return; }
    if (!R.available) { L.push("(Apple non ha ancora generato istanze giornaliere: normale nei primi 1-2 giorni dopo la richiesta)"); L.push(""); return; }
    L.push(`Ultima istanza: ${R.latest} · righe: ${R.rowCount}`);
    fn(R);
    L.push("");
  };
  section("engagement", "Pagina store: impression, viste, conversione (Discovery and Engagement)", (R) => {
    printByDay(L, R.byDay);
    const totals = {};
    for (const d of Object.keys(R.bySource || {})) for (const [k, v] of Object.entries(R.bySource[d])) totals[k] = (totals[k] || 0) + v;
    L.push("Per sorgente (14 gg): " + Object.entries(totals).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}=${v}`).join(", "));
  });
  section("downloads", "Download (App Downloads)", (R) => {
    printByDay(L, R.byDay);
    const terr = {};
    for (const d of Object.keys(R.byTerritory || {})) for (const [k, v] of Object.entries(R.byTerritory[d])) terr[k] = (terr[k] || 0) + v;
    L.push("Per paese (14 gg): " + Object.entries(terr).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([k, v]) => `${k}=${v}`).join(", "));
    const src = {};
    for (const d of Object.keys(R.bySource || {})) for (const [k, v] of Object.entries(R.bySource[d])) src[k] = (src[k] || 0) + v;
    L.push("Per sorgente (14 gg): " + Object.entries(src).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}=${v}`).join(", "));
  });
  section("installs", "Installazioni e cancellazioni", (R) => printByDay(L, R.byDay));
  section("sessions", "Sessioni", (R) => printByDay(L, R.byDay));
  section("crashes", "Crash (per versione)", (R) => printByDay(L, R.byDay));

  L.push("## Recensioni (ultime 20)");
  if (!o.reviews.length) L.push("(nessuna)");
  for (const r of o.reviews) L.push(`${r.date}  ${"★".repeat(r.stars || 0)}${"☆".repeat(5 - (r.stars || 0))}  ${r.territory || ""}  ${r.title ? `«${r.title}»` : ""} ${r.text}`);
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore App Store Connect: ${e.message}`);
  if (/401|NOT_AUTHORIZED|expired/i.test(e.message)) {
    console.error("Chiave API non valida o revocata: rigenerarla in App Store Connect (Utenti e accesso → Integrazioni → Chiavi API) e salvarla nel Portachiavi.");
  }
  process.exit(1);
});
