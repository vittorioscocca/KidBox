#!/usr/bin/env node
/**
 * Scrive la descrizione dell'App Store di una versione, per ogni lingua della
 * scheda, dai file internal/store-listings/appstore-<ios|mac>-<lingua>.txt
 * (generati da genera-descrizioni.py).
 *
 *   node scripts/asc-descrizione.js --version 2.4.2 [--platform IOS|MAC_OS] \
 *        [--only it,en-GB] [--apply]
 *
 * Senza --apply mostra solo la lunghezza attuale e nuova. Si può scrivere su una
 * versione in PREPARE_FOR_SUBMISSION, WAITING_FOR_REVIEW o simili; in IN_REVIEW no.
 * Autenticazione come asc-whatsnew.js (chiave .p8 nel Portachiavi).
 */
const { execFileSync } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");

const KEY_ID = "5XN458397C";
const ISSUER_ID = "2deae1f9-70dc-49b6-b792-083e481811d3";
const API = "https://api.appstoreconnect.apple.com/v1";
const APP_ID = "6761055375";
const EDITABLE = new Set(["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"]);

function arg(name, dflt) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : dflt;
}
const PLATFORM = arg("platform", "IOS");
const VERSION = arg("version");
const DIR = arg("dir", "internal/store-listings");
const APPLY = process.argv.includes("--apply");
const ONLY = arg("only") ? arg("only").split(",") : null; // es. --only it-IT
const REPLACE = arg("replace"); // es. --replace 02-chiuso.png
const CUSTOM_PAGE = arg("custom-page");
if (!VERSION && !CUSTOM_PAGE) {
  console.error("Uso: --version X.Y.Z [--platform IOS] [--dir <cartella>] [--display APP_IPHONE_67] [--apply]");
  process.exit(2);
}
// Cartella delle immagini → lingua della scheda su App Store Connect.
const LOCALES = ["it", "en-GB", "es-ES", "fr-FR"];
const LIMIT = 4000;

function privateKey() {
  try {
    const b64 = execFileSync("security", ["find-generic-password", "-a", "kidbox", "-s", "asc-api-key", "-w"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
    return Buffer.from(b64, "base64").toString("utf8");
  } catch {
    console.error("Chiave App Store Connect non trovata nel Portachiavi (voce «asc-api-key», account «kidbox»).");
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

// Il token vale 20 minuti: un giro lungo li supera, e App Store Connect ogni
// tanto rifiuta un token perfettamente valido (401 isolato, visto il
// 20/09/2026 su una chiave attiva e un orologio allineato). Il token sta in un
// posto solo, si rifà dopo 15 minuti, e la richiesta ritenta una volta sola
// con uno nuovo prima di dare la colpa alla chiave.
let TOKEN = null;
let TOKEN_AT = 0;
let RITENTATI = 0;
function auth(pem) {
  return (nuovo = false) => {
    if (nuovo || !TOKEN || Date.now() - TOKEN_AT > 15 * 60 * 1000) {
      if (nuovo) RITENTATI++;
      TOKEN = jwt(pem);
      TOKEN_AT = Date.now();
    }
    return TOKEN;
  };
}

const ERRORE_401 = [
  "401 rimasto anche dopo un token nuovo (la riprova è automatica): questa volta non è transitorio.",
  `Prima di rigenerare la chiave, controlla che ${KEY_ID} risulti «Attiva» in App Store Connect`,
  "(Utenti e accesso → Integrazioni → Chiavi API), che Key ID e Issuer ID qui nello script combacino",
  "con quelli mostrati lì, e che l'ora della macchina sia giusta. Solo se tutto torna, rigenera la",
  "chiave con ruolo Admin («Vendite e report» non basta: non può creare le istanze dei report) e",
  'salvala con: security add-generic-password -a kidbox -s asc-api-key -w "$(base64 -i AuthKey.p8)" -U',
].join("\n");

async function call(tok, method, path, body, riprova = true) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${tok()}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401 && riprova) {
    // Il 401 dice che la richiesta non è passata: ripeterla non scrive due volte.
    tok(true);
    return call(tok, method, path, body, false);
  }
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(`${method} ${path}: ${json.errors?.[0]?.detail || json.errors?.[0]?.title || res.status}`);
  return json;
}



const path = require("path");

(async () => {
  const tok = auth(privateKey());
  const prefix = PLATFORM === "MAC_OS" ? "appstore-mac" : "appstore-ios";
  const versions = await call(tok, "GET", `/apps/${APP_ID}/appStoreVersions?filter[platform]=${PLATFORM}&filter[versionString]=${VERSION}&fields[appStoreVersions]=platform,versionString,appVersionState`);
  const v = versions.data?.[0];
  if (!v) { console.error(`Nessuna versione ${VERSION} per ${PLATFORM}.`); process.exit(1); }
  const state = v.attributes.appVersionState;
  console.log(`${PLATFORM} ${VERSION} — ${state} (${v.id})`);
  if (!EDITABLE.has(state)) { console.error(`Stato ${state}: la descrizione non è modificabile.`); process.exit(1); }

  const locs = await call(tok, "GET", `/appStoreVersions/${v.id}/appStoreVersionLocalizations?limit=50&fields[appStoreVersionLocalizations]=locale,description`);
  const byLocale = Object.fromEntries((locs.data || []).map((l) => [l.attributes.locale, l]));

  for (const locale of LOCALES) {
    if (ONLY && !ONLY.includes(locale)) continue;
    const file = path.join(DIR, `${prefix}-${locale}.txt`);
    if (!fs.existsSync(file)) { console.log(`\n── ${locale}: ${file} assente, salto`); continue; }
    const text = fs.readFileSync(file, "utf8").trim();
    if (text.length > LIMIT) { console.error(`${locale}: ${text.length} caratteri, oltre ${LIMIT}`); process.exit(2); }
    const loc = byLocale[locale];
    const current = (loc?.attributes.description || "").trim();
    console.log(`\n── ${locale}: ${current.length} → ${text.length} caratteri${current === text ? " (già uguale)" : ""}`);
    if (!loc) { console.log("   localizzazione assente sulla versione: salto"); continue; }
    if (!APPLY || current === text) continue;
    await call(tok, "PATCH", `/appStoreVersionLocalizations/${loc.id}`, {
      data: { type: "appStoreVersionLocalizations", id: loc.id, attributes: { description: text } },
    });
    console.log("   scritta ✔");
  }
  if (!APPLY) console.log("\n(prova: niente scritto; aggiungi --apply)");
})().catch((e) => {
  console.error(e.message);
  if (/401|NOT_AUTHORIZED|expired|bearer token/i.test(e.message)) console.error(ERRORE_401);
  process.exit(1);
});
