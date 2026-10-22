#!/usr/bin/env node
/**
 * Carica gli screenshot dell'app su una versione App Store Connect, per ogni
 * lingua della scheda, da internal/store-listings/screenshots/final/<lingua>/.
 *
 *   node scripts/asc-screenshots.js --version 2.4.2 [--platform IOS] \
 *        [--display APP_IPHONE_67] [--dir <cartella>] [--only it,en] [--apply]
 *        [--replace 02-chiuso.png] [--custom-page "Pagina prodotto KidBox"]
 *
 * Senza --apply mostra, per ogni lingua, i set presenti e le immagini che ci
 * sono dentro, e non tocca nulla. Con --apply SOSTITUISCE le immagini del set
 * scelto: toglie le vecchie e carica quelle della cartella, in ordine di nome.
 * Si può scrivere solo su una versione in PREPARE_FOR_SUBMISSION,
 * WAITING_FOR_REVIEW o simili. Le immagini della versione in vendita non si
 * toccano: se serve tornare indietro, si rimettono quelle.
 *
 * Con --replace <file> tocca una sola immagine per lingua: cancella quella col
 * nome dato e carica il file omonimo della cartella, allo stesso posto. Le
 * altre del set restano come sono.
 *
 * Con --custom-page <nome> scrive sulla pagina prodotto personalizzata con quel
 * nome, nella sua versione in PREPARE_FOR_SUBMISSION (non la invia in
 * revisione), invece che sulla versione dell'app.
 *
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
const DIR = arg("dir", "internal/store-listings/screenshots/final");
const DISPLAY = arg("display", "APP_IPHONE_67");
const APPLY = process.argv.includes("--apply");
const ONLY = arg("only") ? arg("only").split(",") : null; // es. --only it
const REPLACE = arg("replace"); // es. --replace 02-chiuso.png
const CUSTOM_PAGE = arg("custom-page");
if (!VERSION && !CUSTOM_PAGE) {
  console.error("Uso: --version X.Y.Z [--platform IOS] [--dir <cartella>] [--display APP_IPHONE_67] [--apply]");
  process.exit(2);
}
// Cartella delle immagini → lingua della scheda su App Store Connect.
const LOCALES = { it: "it", en: "en-GB", es: "es-ES", fr: "fr-FR" };

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

/** Carica un file dentro a un set: prenotazione, invio a pezzi, conferma col checksum. */
async function upload(tok, setId, file) {
  const data = fs.readFileSync(file);
  const created = await call(tok, "POST", "/appScreenshots", {
    data: {
      type: "appScreenshots",
      attributes: { fileName: path.basename(file), fileSize: data.length },
      relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: setId } } },
    },
  });
  const shot = created.data;
  for (const op of shot.attributes.uploadOperations || []) {
    const headers = Object.fromEntries((op.requestHeaders || []).map((h) => [h.name, h.value]));
    const part = data.subarray(op.offset, op.offset + op.length);
    const res = await fetch(op.url, { method: op.method, headers, body: part });
    if (!res.ok) throw new Error(`invio di ${path.basename(file)}: HTTP ${res.status}`);
  }
  const md5 = crypto.createHash("md5").update(data).digest("hex");
  await call(tok, "PATCH", `/appScreenshots/${shot.id}`, {
    data: { type: "appScreenshots", id: shot.id, attributes: { uploaded: true, sourceFileChecksum: md5 } },
  });
  return shot.id;
}

async function waitComplete(tok, ids) {
  for (let i = 0; i < 40; i++) {
    const states = [];
    for (const id of ids) {
      const r = await call(tok, "GET", `/appScreenshots/${id}?fields[appScreenshots]=assetDeliveryState`);
      states.push(r.data.attributes.assetDeliveryState?.state);
    }
    if (states.every((s) => s === "COMPLETE")) return;
    const failed = states.findIndex((s) => s === "FAILED");
    if (failed >= 0) throw new Error(`elaborazione fallita per ${ids[failed]}`);
    await new Promise((r) => setTimeout(r, 3000));
  }
  throw new Error("App Store Connect non ha finito di elaborare le immagini in 2 minuti");
}

(async () => {
  const tok = auth(privateKey());
  let locs, LOC_TYPE, LOC_REL;
  if (CUSTOM_PAGE) {
    const pages = await call(tok, "GET", `/apps/${APP_ID}/appCustomProductPages?limit=50`);
    const page = (pages.data || []).find((pg) => pg.attributes.name === CUSTOM_PAGE);
    if (!page) { console.error(`Nessuna pagina personalizzata «${CUSTOM_PAGE}».`); process.exit(1); }
    const vers = await call(tok, "GET", `/appCustomProductPages/${page.id}/appCustomProductPageVersions?limit=20`);
    const cv = (vers.data || []).find((x) => x.attributes.state === "PREPARE_FOR_SUBMISSION");
    if (!cv) { console.error(`«${CUSTOM_PAGE}» non ha una versione in preparazione: creane una in App Store Connect.`); process.exit(1); }
    console.log(`Pagina «${CUSTOM_PAGE}» versione ${cv.attributes.version} — ${cv.attributes.state} (${cv.id}) — set ${DISPLAY}`);
    locs = await call(tok, "GET", `/appCustomProductPageVersions/${cv.id}/appCustomProductPageLocalizations?limit=50`);
    LOC_TYPE = "appCustomProductPageLocalizations";
    LOC_REL = "appCustomProductPageLocalization";
  } else {
    const versions = await call(tok, "GET", `/apps/${APP_ID}/appStoreVersions?filter[platform]=${PLATFORM}&filter[versionString]=${VERSION}&fields[appStoreVersions]=platform,versionString,appVersionState`);
    const v = versions.data?.[0];
    if (!v) { console.error(`Nessuna versione ${VERSION} per ${PLATFORM}.`); process.exit(1); }
    const state = v.attributes.appVersionState;
    console.log(`${PLATFORM} ${VERSION} — ${state} (${v.id}) — set ${DISPLAY}`);
    if (!EDITABLE.has(state)) { console.error(`Stato ${state}: le immagini non sono modificabili.`); process.exit(1); }
    locs = await call(tok, "GET", `/appStoreVersions/${v.id}/appStoreVersionLocalizations?limit=50&fields[appStoreVersionLocalizations]=locale`);
    LOC_TYPE = "appStoreVersionLocalizations";
    LOC_REL = "appStoreVersionLocalization";
  }
  const byLocale = Object.fromEntries((locs.data || []).map((l) => [l.attributes.locale, l]));

  for (const [dirName, locale] of Object.entries(LOCALES)) {
    if (ONLY && !ONLY.includes(dirName)) continue;
    const folder = path.join(DIR, dirName);
    if (!fs.existsSync(folder)) { console.log(`\n── ${locale}: cartella ${folder} assente, salto`); continue; }
    const files = REPLACE
      ? [path.join(folder, REPLACE)].filter((f) => fs.existsSync(f))
      : fs.readdirSync(folder).filter((f) => f.endsWith(".png")).sort().map((f) => path.join(folder, f));
    const loc = byLocale[locale];
    console.log(`\n── ${locale}: ${files.length} file da caricare`);
    if (!loc) { console.log("   localizzazione assente sulla versione: salto"); continue; }

    const sets = await call(tok, "GET", `/${LOC_TYPE}/${loc.id}/appScreenshotSets?limit=50`);
    const present = (sets.data || []).map((s) => s.attributes.screenshotDisplayType);
    console.log(`   set presenti: ${present.join(", ") || "(nessuno)"}`);
    let set = (sets.data || []).find((s) => s.attributes.screenshotDisplayType === DISPLAY);
    let old = [];
    if (set) {
      const shots = await call(tok, "GET", `/appScreenshotSets/${set.id}/appScreenshots?limit=50`);
      old = shots.data || [];
      console.log(`   nel set ${DISPLAY}: ${old.length} immagini (${old.map((s) => s.attributes.fileName).join(", ")})`);
    } else {
      console.log(`   il set ${DISPLAY} non esiste: verrà creato`);
    }
    if (REPLACE) {
      const target = old.find((s) => s.attributes.fileName === REPLACE);
      console.log(target ? `   da sostituire: ${REPLACE} (posizione ${old.indexOf(target) + 1})` : `   ${REPLACE} non c'è nel set: verrà aggiunta in fondo`);
      if (!APPLY || !set || files.length === 0) continue;
      const id = await upload(tok, set.id, files[0]);
      await waitComplete(tok, [id]);
      if (target) await call(tok, "DELETE", `/appScreenshots/${target.id}`);
      const order = target ? old.map((s) => (s.id === target.id ? id : s.id)) : [...old.map((s) => s.id), id];
      await call(tok, "PATCH", `/appScreenshotSets/${set.id}/relationships/appScreenshots`, {
        data: order.map((x) => ({ type: "appScreenshots", id: x })),
      });
      console.log(`   sostituita ${REPLACE} ✔`);
      continue;
    }
    if (!APPLY) continue;

    if (!set) {
      const made = await call(tok, "POST", "/appScreenshotSets", {
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: DISPLAY },
          relationships: { [LOC_REL]: { data: { type: LOC_TYPE, id: loc.id } } },
        },
      });
      set = made.data;
    }
    for (const s of old) await call(tok, "DELETE", `/appScreenshots/${s.id}`);
    if (old.length) console.log(`   tolte ${old.length} immagini vecchie`);
    const ids = [];
    for (const f of files) {
      ids.push(await upload(tok, set.id, f));
      console.log(`   caricata ${path.basename(f)}`);
    }
    await waitComplete(tok, ids);
    await call(tok, "PATCH", `/appScreenshotSets/${set.id}/relationships/appScreenshots`, {
      data: ids.map((id) => ({ type: "appScreenshots", id })),
    });
    console.log("   elaborate e ordinate ✔");
  }
  if (!APPLY) console.log("\n(prova: niente scritto; aggiungi --apply)");
})().catch((e) => {
  console.error(e.message);
  if (/401|NOT_AUTHORIZED|expired|bearer token/i.test(e.message)) console.error(ERRORE_401);
  process.exit(1);
});
