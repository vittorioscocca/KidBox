#!/usr/bin/env node
/**
 * Stato di App Check: quante richieste arrivano con un'attestazione valida.
 *
 *   node scripts/appcheck-daily-report.js            # report testuale
 *   node scripts/appcheck-daily-report.js --json     # stesso contenuto, in JSON
 *   node scripts/appcheck-daily-report.js --days 14  # finestra diversa (default 7)
 *   node scripts/appcheck-daily-report.js --hours 2  # ultime 2 ore (per una prova mirata:
 *                                                    # la metrica arriva con ~25 min di ritardo)
 *
 * A cosa serve: l'enforcement di App Check è SPENTO, e va acceso solo quando
 * la quota di richieste verificate è alta — accenderlo prima spegne l'app a
 * chi non supera l'attestazione. Questo script è il cancello: legge la
 * metrica `firebaseappcheck.googleapis.com/services/verification_count` da
 * Cloud Monitoring e dice a che punto siamo, per servizio e per app.
 *
 * Come si leggono i valori dell'etichetta `security`:
 *   VALID                   il token c'era ed è stato accettato
 *   INVALID                 il token c'era ed è stato RIFIUTATO (attestazione
 *                           fallita) — è il caso grave: con l'enforcement
 *                           acceso queste richieste verrebbero negate
 *   MISSING_*               nessun token (client vecchio, origine sconosciuta)
 *
 * L'etichetta `result` (ALLOW/DENY) dice solo se la richiesta è stata servita,
 * e finché l'enforcement è spento è sempre ALLOW: non è quella da guardare.
 *
 * Nota: le richieste rifiutate hanno `app_id = UNKNOWN`, quindi la metrica non
 * dice DA QUALE app arrivano. L'indizio utile è l'opposto: quali piattaforme
 * compaiono tra le VALID. Una piattaforma che non compare mai non sta
 * superando l'attestazione.
 *
 * Token: `gcloud auth print-access-token` (utente owner del progetto).
 * Solo lettura.
 */

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const TZ = "Europe/Rome";
const METRIC = "firebaseappcheck.googleapis.com/services/verification_count";
const SOGLIA = 90; // % di VALID sotto cui l'enforcement non si accende
const PIATTAFORME_ATTESE = ["ios", "android", "web"];

const asJson = process.argv.includes("--json");
const iDays = process.argv.indexOf("--days");
const iHours = process.argv.indexOf("--hours");
// In ore, così una prova su un singolo device si legge senza annegare nel traffico
// del giorno. La metrica arriva con ~25 minuti di ritardo: guardare prima è inutile.
const HOURS = iHours >= 0 ? Math.max(1, Number(process.argv[iHours + 1]) || 2) : null;
const DAYS = iDays >= 0 ? Math.max(1, Number(process.argv[iDays + 1]) || 7) : 7;
const FINESTRA = HOURS ? `${HOURS} ore` : `${DAYS} giorni`;

function token() {
  try {
    return execFileSync("gcloud", ["auth", "print-access-token"], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
  } catch {
    console.error("Token gcloud non disponibile: esegui `gcloud auth login` (utente owner di kidbox-42cd7).");
    process.exit(2);
  }
}

async function timeSeries(tok) {
  const end = new Date();
  const start = new Date(end.getTime() - (HOURS ? HOURS * 3600e3 : DAYS * 86400e3));
  const p = new URLSearchParams({
    filter: `metric.type="${METRIC}"`,
    "interval.startTime": start.toISOString().replace(/\.\d+/, ""),
    "interval.endTime": end.toISOString().replace(/\.\d+/, ""),
    // 3600s e somma lato client: `alignmentPeriod` da un giorno darebbe
    // finestre mobili di 24h ancorate all'ora della query, non giorni veri.
    "aggregation.alignmentPeriod": "3600s",
    "aggregation.perSeriesAligner": "ALIGN_SUM",
  });
  const res = await fetch(`https://monitoring.googleapis.com/v3/projects/${PROJECT}/timeSeries?${p}`, {
    headers: { Authorization: `Bearer ${tok}` },
  });
  const j = await res.json();
  if (!res.ok) throw new Error(j.error?.message || `HTTP ${res.status}`);
  return j.timeSeries || [];
}

const giorno = (iso) =>
  HOURS
    ? new Date(iso).toLocaleString("sv-SE", { timeZone: TZ, hour: "2-digit", minute: "2-digit", day: "2-digit", month: "2-digit" })
    : new Date(iso).toLocaleDateString("sv-SE", { timeZone: TZ });
const piattaforma = (appId) => (appId || "").split(":")[2] || "?";
const breve = (appId) => (appId === "UNKNOWN" ? "UNKNOWN" : `${piattaforma(appId)}…${(appId || "").slice(-6)}`);
const quota = (c) => {
  const tot = Object.values(c).reduce((a, b) => a + b, 0);
  return tot ? Math.round((100 * (c.VALID || 0)) / tot) : null;
};

function aggrega(ts) {
  const perServizio = {};
  const perApp = {};
  const perGiorno = {}; // solo Firestore: è il servizio che regge l'app
  for (const s of ts) {
    const sec = s.metric?.labels?.security || "?";
    const app = s.metric?.labels?.app_id || "UNKNOWN";
    const svc = (s.resource?.labels?.service_id || "?").replace(".googleapis.com", "");
    for (const pt of s.points || []) {
      const n = Number(pt.value?.int64Value || 0);
      if (!n) continue;
      ((perServizio[svc] ||= {})[sec] ||= 0), (perServizio[svc][sec] += n);
      const k = breve(app);
      ((perApp[k] ||= {})[sec] ||= 0), (perApp[k][sec] += n);
      if (svc === "firestore") {
        const g = giorno(pt.interval?.endTime);
        ((perGiorno[g] ||= {})[sec] ||= 0), (perGiorno[g][sec] += n);
      }
    }
  }
  return { perServizio, perApp, perGiorno };
}

function verdetto({ perServizio, perApp, perGiorno }) {
  const firestore = perServizio.firestore || {};
  const valide = quota(firestore);
  const giorniSopra = Object.entries(perGiorno)
    .sort()
    .filter(([, c]) => (quota(c) ?? 0) >= SOGLIA).length;
  const piattaformeValide = new Set(
    Object.entries(perApp)
      .filter(([, c]) => (c.VALID || 0) > 0)
      .map(([k]) => k.split("…")[0])
  );
  const mancanti = PIATTAFORME_ATTESE.filter((p) => !piattaformeValide.has(p));
  return {
    valideFirestore: valide,
    soglia: SOGLIA,
    giorniSopraSoglia: giorniSopra,
    giorniTotali: Object.keys(perGiorno).length,
    piattaformeSenzaAttestazioniValide: mancanti,
    cancelloSuperato: valide !== null && valide >= SOGLIA && mancanti.length === 0,
  };
}

function stampa(a, v) {
  const L = [];
  L.push(`# App Check KidBox — ultime ${FINESTRA} (progetto ${PROJECT})`);
  L.push("");
  L.push("## Per servizio");
  const servizi = Object.entries(a.perServizio).sort((x, y) => tot(y[1]) - tot(x[1]));
  if (!servizi.length) L.push("(nessuna richiesta nella finestra: App Check non riceve traffico)");
  for (const [svc, c] of servizi) {
    L.push(`  ${svc.padEnd(18)} ${String(tot(c)).padStart(8)} richieste   VALIDE ${String(quota(c)).padStart(3)}%`);
    for (const [k, n] of Object.entries(c).sort((x, y) => y[1] - x[1])) {
      L.push(`      ${k.padEnd(24)} ${String(n).padStart(8)}  (${Math.round((100 * n) / tot(c))}%)`);
    }
  }
  L.push("");
  L.push("## Per app (chi supera l'attestazione)");
  for (const [app, c] of Object.entries(a.perApp).sort((x, y) => tot(y[1]) - tot(x[1]))) {
    const dettaglio = Object.entries(c)
      .sort((x, y) => y[1] - x[1])
      .map(([k, n]) => `${k} ${n}`)
      .join(" · ");
    L.push(`  ${app.padEnd(16)} ${String(tot(c)).padStart(8)}   ${dettaglio}`);
  }
  L.push("");
  L.push(HOURS ? "## Firestore per ora" : "## Firestore giorno per giorno (è il cancello)");
  for (const [g, c] of Object.entries(a.perGiorno).sort()) {
    const q = quota(c);
    L.push(`  ${g}  ${String(tot(c)).padStart(7)} richieste   VALIDE ${String(q).padStart(3)}%  ${q >= SOGLIA ? "✅" : ""}`);
  }
  L.push("");
  L.push("## Verdetto");
  if (v.valideFirestore === null) {
    L.push("  Nessun dato: impossibile dire se l'enforcement si può accendere.");
  } else if (v.cancelloSuperato) {
    L.push(`  ✅ Cancello superato: Firestore al ${v.valideFirestore}% di valide, tutte le piattaforme attestano.`);
    L.push(`     Prossimo passo: accendere l'enforcement dai prodotti Firebase in console, poi`);
    L.push(`     \`enforceAppCheck: true\` sulle functions. Procedura: internal/app-check.md`);
  } else {
    L.push(`  ⛔️ NON accendere l'enforcement: Firestore è al ${v.valideFirestore}% di valide, serve ≥ ${SOGLIA}%.`);
    L.push(`     Giorni sopra soglia nella finestra: ${v.giorniSopraSoglia} su ${v.giorniTotali}.`);
    if (v.piattaformeSenzaAttestazioniValide.length) {
      L.push(`     Nessuna attestazione valida da: ${v.piattaformeSenzaAttestazioniValide.join(", ")}.`);
      L.push(`     Una piattaforma assente tra le VALID non sta superando l'attestazione: è la prima cosa da risolvere.`);
    }
    L.push(`     Con l'enforcement acceso oggi, le richieste INVALID verrebbero negate. Vedi internal/app-check.md`);
  }
  return L.join("\n");
}
const tot = (c) => Object.values(c).reduce((a, b) => a + b, 0);

(async () => {
  const a = aggrega(await timeSeries(token()));
  const v = verdetto(a);
  if (asJson) {
    process.stdout.write(JSON.stringify({ finestra: FINESTRA, ...a, verdetto: v }, null, 2) + "\n");
    return;
  }
  process.stdout.write(stampa(a, v) + "\n");
})().catch((e) => {
  console.error(`Errore App Check: ${e.message}`);
  process.exit(1);
});
