#!/usr/bin/env node
/**
 * Scrive le note «Novità» (whatsNew) di una versione App Store Connect nelle
 * lingue della scheda, leggendole da un file di internal/store-listings.
 *
 *   node scripts/asc-whatsnew.js --platform IOS --version 2.3.1 \
 *        --file internal/store-listings/appstore-whatsnew-2.3.1.txt [--apply]
 *
 * Senza --apply mostra per ogni lingua il testo attuale e quello che verrebbe
 * scritto, e non tocca nulla. Il file è quello prodotto a mano: blocchi
 * `## <locale>` (it, en-GB, es-ES, fr-FR) seguiti dal testo. Le note si possono
 * modificare solo su una versione in PREPARE_FOR_SUBMISSION o
 * WAITING_FOR_REVIEW; una localizzazione assente viene creata.
 *
 * Autenticazione come appstore-daily-report.js: chiave .p8 nel Portachiavi
 * (voce «asc-api-key», account «kidbox»).
 */
const { execFileSync } = require("child_process");
const crypto = require("crypto");
const fs = require("fs");

const KEY_ID = "5XN458397C";
const ISSUER_ID = "2deae1f9-70dc-49b6-b792-083e481811d3";
const API = "https://api.appstoreconnect.apple.com/v1";
const APP_ID = "6761055375";
const EDITABLE = new Set(["PREPARE_FOR_SUBMISSION", "WAITING_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"]);
const LIMIT = 4000;

function arg(name, dflt) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : dflt;
}
const PLATFORM = arg("platform");
const VERSION = arg("version");
const FILE = arg("file");
const APPLY = process.argv.includes("--apply");
if (!PLATFORM || !VERSION || !FILE) {
  console.error("Uso: --platform IOS|MAC_OS --version X.Y.Z --file <note.txt> [--apply]");
  process.exit(2);
}

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

async function call(tok, method, path, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(`${method} ${path}: ${json.errors?.[0]?.detail || json.errors?.[0]?.title || res.status}`);
  return json;
}

/** Blocchi `## locale` → { locale: testo }. */
function parseNotes(file) {
  const out = {};
  let cur = null;
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    const m = line.match(/^## (\S+)\s*$/);
    if (m) { cur = m[1]; out[cur] = []; continue; }
    if (cur && !line.startsWith("# ")) out[cur].push(line);
  }
  for (const k of Object.keys(out)) {
    out[k] = out[k].join("\n").trim();
    if (!out[k]) delete out[k];
  }
  return out;
}

(async () => {
  const notes = parseNotes(FILE);
  for (const [loc, txt] of Object.entries(notes)) {
    if (txt.length > LIMIT) { console.error(`${loc}: ${txt.length} caratteri, oltre il limite di ${LIMIT}`); process.exit(2); }
  }
  const tok = jwt(privateKey());

  const versions = await call(tok, "GET", `/apps/${APP_ID}/appStoreVersions?filter[platform]=${PLATFORM}&filter[versionString]=${VERSION}&fields[appStoreVersions]=platform,versionString,appVersionState`);
  const v = versions.data?.[0];
  if (!v) { console.error(`Nessuna versione ${VERSION} per ${PLATFORM} in App Store Connect: va creata lì prima.`); process.exit(1); }
  const state = v.attributes.appVersionState;
  console.log(`${PLATFORM} ${VERSION} — ${state} (${v.id})`);
  if (!EDITABLE.has(state)) { console.error(`Stato ${state}: le note non sono modificabili.`); process.exit(1); }

  const locs = await call(tok, "GET", `/appStoreVersions/${v.id}/appStoreVersionLocalizations?limit=50&fields[appStoreVersionLocalizations]=locale,whatsNew`);
  const byLocale = Object.fromEntries((locs.data || []).map((l) => [l.attributes.locale, l]));

  for (const [locale, text] of Object.entries(notes)) {
    const existing = byLocale[locale];
    const current = existing?.attributes.whatsNew || "";
    const same = current.trim() === text.trim();
    console.log(`\n── ${locale} ${existing ? "" : "(localizzazione assente: verrà creata)"}`);
    console.log(same ? "già uguale" : `attuale: ${current ? JSON.stringify(current.slice(0, 80)) + (current.length > 80 ? "…" : "") : "(vuoto)"}\nnuovo:   ${JSON.stringify(text.slice(0, 80))}… (${text.length} caratteri)`);
    if (!APPLY || same) continue;
    if (existing) {
      await call(tok, "PATCH", `/appStoreVersionLocalizations/${existing.id}`, {
        data: { type: "appStoreVersionLocalizations", id: existing.id, attributes: { whatsNew: text } },
      });
    } else {
      await call(tok, "POST", `/appStoreVersionLocalizations`, {
        data: {
          type: "appStoreVersionLocalizations",
          attributes: { locale, whatsNew: text },
          relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: v.id } } },
        },
      });
    }
    console.log("scritto ✔");
  }
  const extra = Object.keys(byLocale).filter((l) => !notes[l]);
  if (extra.length) console.log(`\nLingue sulla scheda senza note nel file: ${extra.join(", ")}`);
  if (!APPLY) console.log("\n(prova: niente scritto; aggiungi --apply)");
})().catch((e) => { console.error(e.message); process.exit(1); });
