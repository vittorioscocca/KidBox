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
const { readSnapshot } = require("./lib/snapshot");
const C = require("../functions/reportCollectors/billing");
const { PROJECT, TZ, romeDate, shiftDay } = C;

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

/**
 * Di default legge lo snapshot scritto da `reportSnapshotStoreDaily`
 * (functions/reportCollectors/billing.js, stessa raccolta); `--live` forza `bq`.
 * Le righe di ieri arrivano spesso dopo le 08:30: lo snapshot (11:00) può non
 * averle, e lo dice `totals.yesterday.present`.
 */
async function main() {
  const asJson = process.argv.includes("--json");
  let out = null;
  let origin;
  if (!process.argv.includes("--live")) {
    const s = await readSnapshot("billing");
    if (s.payload) {
      out = s.payload;
      origin = `snapshot Firestore delle ${new Date(s.computedAt).toLocaleTimeString("it-IT", { timeZone: "Europe/Rome", hour: "2-digit", minute: "2-digit" })} (${Math.round(s.ageH)} h fa)`;
    } else {
      origin = `dal vivo (${s.reason})`;
    }
  } else {
    origin = "dal vivo (richiesto)";
  }
  if (!out) out = await C.collect(async (sql) => bq(sql));
  out.origin = origin;

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
  if (o.origin) L.push(`Fonte: ${o.origin}.`);
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
