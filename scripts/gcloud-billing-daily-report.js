#!/usr/bin/env node
/**
 * Fotografia giornaliera dei costi Google Cloud / Firebase di KidBox.
 *
 *   node scripts/gcloud-billing-daily-report.js           # report testuale
 *   node scripts/gcloud-billing-daily-report.js --json    # stesso contenuto, in JSON
 *
 * La Cloud Billing API non espone gli importi: l'unica fonte programmatica è
 * l'**export della fatturazione su BigQuery** («Costo di utilizzo standard»),
 * attivato il 15/09/2026 sull'account 015E5B-092B59-BED0B8 verso
 * `kidbox-42cd7.billing_export`. Niente storico prima di quella data; le
 * righe di un giorno arrivano nel corso del giorno dopo, e possono essere
 * riviste per qualche giorno (crediti, arrotondamenti).
 *
 * Lo script interroga la tabella con `bq` (credenziali gcloud dell'utente):
 * costo lordo, crediti (free tier, sconti, promozioni) e netto, per giorno e
 * per servizio (Firestore, Cloud Functions/Run, Storage, BigQuery…). Importi
 * in EUR, la valuta dell'account. Una query al giorno su pochi MB: dentro il
 * free tier di BigQuery di molte volte.
 *
 * Solo lettura.
 */

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const TABLE = `\`${PROJECT}.billing_export.gcp_billing_export_v1_015E5B_092B59_BED0B8\``;
const TZ = "Europe/Rome";

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function bq(sql) {
  try {
    const out = execFileSync(
      "bq",
      [`--project_id=${PROJECT}`, "--format=json", "--headless", "query", "--use_legacy_sql=false", "--max_rows=5000", sql],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 50 * 1024 * 1024 }
    );
    const trimmed = out.trim();
    return trimmed ? JSON.parse(trimmed) : [];
  } catch (e) {
    // bq scrive l'errore su stdout e va a capo dentro il messaggio: si legge
    // tutto e si confronta senza gli a capo.
    const msg = [e.stdout, e.stderr, e.message].map((x) => String(x || "")).join(" ").replace(/\s+/g, " ");
    if (/Not found: Table/i.test(msg)) {
      const err = new Error("tabella dell'export non ancora creata");
      err.notYet = true;
      throw err;
    }
    const m = /BigQuery error in query operation: (.*?)(?: SELECT |$)/.exec(msg);
    throw new Error(m ? m[1].trim() : msg.slice(0, 300));
  }
}

async function main() {
  const asJson = process.argv.includes("--json");
  const yesterday = shiftDay(romeDate(), -1);
  const start = shiftDay(yesterday, -13);
  const monthStart = `${yesterday.slice(0, 7)}-01`;
  const from = start < monthStart ? start : monthStart;
  const out = { project: PROJECT, yesterday, notes: [] };

  let rows;
  try {
    rows = bq(`
      SELECT
        FORMAT_DATE('%F', DATE(usage_start_time, '${TZ}')) AS day,
        service.description AS service,
        sku.description AS sku,
        currency,
        SUM(cost) AS cost,
        SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)) AS credits,
        MAX(export_time) AS last_export
      FROM ${TABLE}
      WHERE DATE(usage_start_time, '${TZ}') BETWEEN '${from}' AND '${yesterday}'
      GROUP BY day, service, sku, currency
      ORDER BY day, service, sku
    `);
  } catch (e) {
    if (e.notYet) {
      out.notes.push("L'export della fatturazione non ha ancora scritto la tabella su BigQuery (attivato il 15/09/2026: le prime righe arrivano entro qualche ora, poi ogni giorno).");
      rows = [];
    } else {
      throw e;
    }
  }

  const num = (x) => Number(x || 0);
  out.currency = rows[0]?.currency || "EUR";
  out.lastExport = rows.reduce((a, r) => (r.last_export > a ? r.last_export : a), "") || null;
  // giorno → servizio → {cost, credits}
  const byDay = {};
  const bySku = {};
  for (const r of rows) {
    const d = (byDay[r.day] = byDay[r.day] || {});
    const s = (d[r.service] = d[r.service] || { cost: 0, credits: 0 });
    s.cost += num(r.cost);
    s.credits += num(r.credits);
    if (r.day >= shiftDay(yesterday, -6)) {
      const k = `${r.service} — ${r.sku}`;
      bySku[k] = (bySku[k] || 0) + num(r.cost) + num(r.credits);
    }
  }
  out.byDay = byDay;
  out.topSku7d = Object.entries(bySku).filter(([, v]) => Math.abs(v) >= 0.001).sort((a, b) => b[1] - a[1]).slice(0, 10);

  const dayNet = (d) => Object.values(byDay[d] || {}).reduce((a, s) => a + s.cost + s.credits, 0);
  const dayGross = (d) => Object.values(byDay[d] || {}).reduce((a, s) => a + s.cost, 0);
  const days = Object.keys(byDay).sort();
  out.totals = {
    yesterday: { gross: dayGross(yesterday), net: dayNet(yesterday), present: !!byDay[yesterday] },
    last7: [...Array(7)].reduce((a, _, i) => a + dayNet(shiftDay(yesterday, -i)), 0),
    monthNet: days.filter((d) => d >= monthStart).reduce((a, d) => a + dayNet(d), 0),
    monthGross: days.filter((d) => d >= monthStart).reduce((a, d) => a + dayGross(d), 0),
    daysWithData: days.length,
    firstDay: days[0] || null,
  };
  if (rows.length && !byDay[yesterday]) out.notes.push(`Nessuna riga per ${yesterday}: l'export del giorno arriva nel corso della giornata successiva, spesso dopo le 08:30.`);

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

const pad = (s, n) => String(s ?? "-").padEnd(n);
const money = (x, c) => `${(x || 0).toFixed(2)} ${c}`;

function print(o) {
  const L = [];
  const c = o.currency;
  L.push(`# Google Cloud / Firebase — costi (export BigQuery), ieri ${o.yesterday}`);
  const t = o.totals;
  if (!t.daysWithData) {
    L.push("(nessun dato ancora)");
  } else {
    L.push(`Ieri: lordo ${money(t.yesterday.gross, c)}, netto ${money(t.yesterday.net, c)}${t.yesterday.present ? "" : " (non ancora esportato)"} · ultimi 7 gg netto ${money(t.last7, c)} · mese: lordo ${money(t.monthGross, c)}, netto ${money(t.monthNet, c)} (dati dal ${t.firstDay}; export aggiornato al ${(o.lastExport || "").slice(0, 16)})`);
    L.push("Netto = lordo + crediti (free tier, sconti): è quello che si paga. Un lordo alto con netto zero significa che il free tier sta assorbendo tutto — guardare quanto margine resta.");
    L.push("");
    L.push("## Per giorno e servizio (netto; tra parentesi il lordo se diverso)");
    const services = [...new Set(Object.values(o.byDay).flatMap((d) => Object.keys(d)))].sort();
    for (let i = 13; i >= 0; i--) {
      const d = shiftDay(o.yesterday, -i);
      const day = o.byDay[d];
      if (!day) { L.push(pad(d, 12) + "—"); continue; }
      const parts = services.filter((s) => day[s]).map((s) => {
        const net = day[s].cost + day[s].credits;
        const gross = day[s].cost;
        return `${s} ${net.toFixed(2)}${Math.abs(gross - net) > 0.004 ? ` (${gross.toFixed(2)})` : ""}`;
      });
      L.push(pad(d, 12) + parts.join(" · "));
    }
    L.push("");
    L.push("## Voci più costose — ultimi 7 gg (netto)");
    if (!o.topSku7d.length) L.push("(tutto a zero: dentro il free tier)");
    for (const [k, v] of o.topSku7d) L.push(`${pad(v.toFixed(3), 9)}${k}`);
  }
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore export fatturazione: ${e.message}`);
  process.exit(1);
});
