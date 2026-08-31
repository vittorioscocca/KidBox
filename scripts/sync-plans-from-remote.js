#!/usr/bin/env node
/**
 * Riallinea il repo al listino vivo su `config/plans`.
 *
 *   node scripts/sync-plans-from-remote.js          # scrive plans.json + rigenera la landing
 *   node scripts/sync-plans-from-remote.js --check  # esce 1 se il repo è indietro (CI)
 *
 * I piani si modificano dalla console admin e da quel momento valgono ovunque:
 * backend, app, landing. Questo script NON cambia niente per gli utenti — serve
 * a riportare nel repo due cose che restano indietro:
 *
 *   1. `functions/plans.json`, la rete di sicurezza usata quando il documento
 *      manca o non è valido: se resta vecchio, il paracadute è della misura
 *      sbagliata proprio nel momento in cui serve;
 *   2. l'HTML statico della landing, che è quello che vedono i motori di
 *      ricerca e chi ha JS disabilitato.
 *
 * Non serve nessuna credenziale: `config/plans` è leggibile senza login (è la
 * stessa lettura che fa la landing). Vedi `internal/plans-source-of-truth.md`.
 */

const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");

const ROOT = path.join(__dirname, "..");
const PLANS_PATH = path.join(ROOT, "functions", "plans.json");

const PROJECT = "kidbox-42cd7";
/** Chiave web pubblica: identifica il progetto, non autorizza nulla. */
const API_KEY = "AIzaSyC7mDpJ1LadjvhhcoospAp2f0xuawCOOFk";
const URL_DOC = `https://firestore.googleapis.com/v1/projects/${PROJECT}` +
  `/databases/(default)/documents/config/plans?key=${API_KEY}`;

/** Campi che identificano il piano e il prodotto: restano quelli del repo. */
const CAMPI_IMMUTABILI = ["id", "order", "displayName", "productId", "currency"];
/** Ordine delle chiavi nel file, per avere diff leggibili invece che rimescolati. */
const ORDINE_CAMPI = [
  "id", "order", "displayName", "storageBytes", "aiLimit", "aiPeriod",
  "productId", "priceMonthly", "currency", "highlighted",
  "priceLabel", "tagline", "badge", "features",
];

/** Converte i valori tipizzati della REST di Firestore in oggetti normali. */
function fromFirestore(v) {
  if (!v || typeof v !== "object") return null;
  if ("integerValue" in v) return parseInt(v.integerValue, 10);
  if ("doubleValue" in v) return Number(v.doubleValue);
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("nullValue" in v) return null;
  if ("mapValue" in v) {
    const out = {};
    const fields = v.mapValue.fields || {};
    for (const k of Object.keys(fields)) out[k] = fromFirestore(fields[k]);
    return out;
  }
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(fromFirestore);
  return null;
}

/** Riordina le chiavi di un piano, così il diff mostra le modifiche e non l'ordine. */
function ordina(plan) {
  const out = {};
  for (const k of ORDINE_CAMPI) if (k in plan) out[k] = plan[k];
  for (const k of Object.keys(plan)) if (!(k in out)) out[k] = plan[k];
  return out;
}

/** Righe leggibili di ciò che cambia: prima le quote, che sono quelle che costano. */
function differenze(vecchi, nuovi) {
  const righe = [];
  for (const id of Object.keys(nuovi)) {
    const a = vecchi[id] || {};
    const b = nuovi[id];
    if (a.storageBytes !== b.storageBytes) righe.push(`  ${id}: storage ${a.storageBytes} → ${b.storageBytes}`);
    if (a.aiLimit !== b.aiLimit) righe.push(`  ${id}: messaggi AI ${a.aiLimit} → ${b.aiLimit}`);
    if (a.aiPeriod !== b.aiPeriod) righe.push(`  ${id}: periodo quota ${a.aiPeriod} → ${b.aiPeriod}`);
    if (a.priceMonthly !== b.priceMonthly) righe.push(`  ${id}: prezzo ${a.priceMonthly} → ${b.priceMonthly}`);
    if (JSON.stringify(a.features) !== JSON.stringify(b.features)) righe.push(`  ${id}: feature modificate`);
    for (const campo of ["priceLabel", "tagline", "badge"]) {
      if (JSON.stringify(a[campo]) !== JSON.stringify(b[campo])) righe.push(`  ${id}: ${campo} modificato`);
    }
  }
  return righe;
}

(async () => {
  const check = process.argv.includes("--check");
  const locale = JSON.parse(fs.readFileSync(PLANS_PATH, "utf8"));

  const risposta = await fetch(URL_DOC, {cache: "no-store"});
  if (!risposta.ok) {
    console.error(`✗ config/plans non leggibile (HTTP ${risposta.status})`);
    process.exit(1);
  }
  const doc = await risposta.json();
  const remoti = doc?.fields?.plans ? fromFirestore(doc.fields.plans) : null;
  if (!remoti || !remoti.free) {
    console.error("✗ documento config/plans vuoto o malformato: non tocco il repo");
    process.exit(1);
  }

  // Stessa validazione che usa il backend: se il listino remoto non la passa,
  // il backend NON lo sta applicando, quindi non deve nemmeno finire nel repo.
  const plansConfig = require(path.join(ROOT, "functions", "plansConfig.js"));
  const esito = plansConfig.validatePlans(remoti);
  if (!esito.ok) {
    console.error("✗ il listino remoto non supera la validazione:\n  " + esito.errors.join("\n  "));
    process.exit(1);
  }

  // Anche il listino locale passa dal validatore prima del confronto: la
  // normalizzazione aggiunge `strong: false` alle feature che lo omettono, e
  // senza questo passaggio ogni esecuzione segnalerebbe differenze inesistenti.
  const normalizzato = plansConfig.validatePlans(locale.plans);
  const localePiani = normalizzato.ok ? normalizzato.plans : locale.plans;

  const plans = {};
  for (const id of Object.keys(locale.plans)) {
    const base = locale.plans[id];
    const remoto = esito.plans[id];
    if (!remoto) {
      console.error(`✗ il documento remoto non contiene il piano "${id}"`);
      process.exit(1);
    }
    const unito = Object.assign({}, base, remoto);
    for (const campo of CAMPI_IMMUTABILI) unito[campo] = base[campo];
    plans[id] = ordina(unito);
  }

  const cambi = differenze(localePiani, plans);
  const nuovoFile = Object.assign({}, locale, {
    updatedAt: new Date().toISOString().slice(0, 10),
    plans,
  });

  // `updatedAt` cambia ogni giorno: si confronta solo il contenuto vero.
  const confrontabile = (m) => JSON.stringify(Object.keys(m).sort().map((k) => ordina(m[k])));
  const uguale = confrontabile(localePiani) === confrontabile(plans);
  if (uguale) {
    console.log("= functions/plans.json: già allineato a config/plans");
    execFileSync("node", [path.join(__dirname, "render-landing-plans.js"), ...(check ? ["--check"] : [])],
        {stdio: "inherit"});
    return;
  }

  console.log("Il repo è indietro rispetto a config/plans:");
  console.log(cambi.length ? cambi.join("\n") : "  (solo campi minori)");

  if (check) {
    console.error("\n✗ esegui `node scripts/sync-plans-from-remote.js` e rideploya functions + landing");
    process.exit(1);
  }

  fs.writeFileSync(PLANS_PATH, JSON.stringify(nuovoFile, null, 2) + "\n");
  console.log("\n✓ functions/plans.json aggiornato");
  execFileSync("node", [path.join(__dirname, "render-landing-plans.js")], {stdio: "inherit"});

  console.log([
    "",
    "Restano da fare, per rimettere in pari rete di sicurezza e HTML statico:",
    "  npx firebase-tools deploy --only functions --project kidbox-42cd7",
    "  cd KidboxLanding && npx firebase-tools deploy --only hosting:landing --project kidbox-42cd7",
  ].join("\n"));
})().catch((e) => {
  console.error("✗ " + e.message);
  process.exit(1);
});
