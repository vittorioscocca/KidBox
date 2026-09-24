#!/usr/bin/env node
/**
 * Cancella SINGOLI documenti Firestore, con i paletti dentro. È l'unica strada
 * con cui Claude può cancellare su Firestore (regola di permesso in
 * `.claude/settings.local.json`); `firebase firestore:delete` resta all'utente.
 *
 * Paletti:
 *   - solo documenti (numero pari di segmenti), mai collezioni;
 *   - mai ricorsivo: la DELETE REST tocca un documento e basta, le
 *     sottocollezioni restano dove sono;
 *   - mai la radice di una famiglia o di un utente (`families/{id}`,
 *     `users/{uid}`): quelle passano da `deleteFamily` / cancellazione account;
 *   - mai un membro attivo (`families/{id}/members/{uid}` con `role` e non
 *     cancellato): toglierlo è una revoca, e passa dall'app;
 *   - al massimo 20 documenti per invocazione;
 *   - senza `--yes` è una prova: mostra cosa cancellerebbe e si ferma;
 *   - ogni cancellazione vera finisce nel log
 *     `~/Library/Logs/kidbox-firestore-deletes.log`, con i campi del documento.
 *
 * Uso:  node scripts/firestore-delete-doc.js [--yes] <path> [<path> ...]
 * Token: `gcloud auth print-access-token` dell'utente (Owner del progetto).
 */
"use strict";

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const PROJECT = "kidbox-42cd7";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const MAX_DOCS = 20;
const LOG = path.join(os.homedir(), "Library", "Logs", "kidbox-firestore-deletes.log");

function fail(msg) {
  console.error(`✖ ${msg}`);
  process.exit(1);
}

const args = process.argv.slice(2);
const confirmed = args.includes("--yes");
const paths = args.filter((a) => a !== "--yes");

const unknownFlags = paths.filter((p) => p.startsWith("-"));
if (unknownFlags.length) fail(`opzioni non ammesse: ${unknownFlags.join(" ")} (nessuna ricorsione, nessun flag)`);
if (paths.length === 0) fail("nessun documento indicato");
if (paths.length > MAX_DOCS) fail(`${paths.length} documenti: il massimo è ${MAX_DOCS} per invocazione`);

for (const p of paths) {
  const seg = p.split("/");
  if (seg.some((s) => s === "" || s === "." || s === "..")) fail(`path non valido: ${p}`);
  if (seg.length % 2 !== 0) fail(`non è un documento (segmenti dispari, cioè una collezione): ${p}`);
  if (seg.length === 2 && (seg[0] === "families" || seg[0] === "users")) {
    fail(`radice di ${seg[0] === "families" ? "una famiglia" : "un utente"}: ${p} — passa da deleteFamily / cancellazione account`);
  }
}

const TOKEN = execFileSync("gcloud", ["auth", "print-access-token"], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
}).trim();
const HEADERS = { Authorization: `Bearer ${TOKEN}`, "x-goog-user-project": PROJECT };

async function main() {
  let deleted = 0;
  for (const p of paths) {
    const url = `${BASE}/${p.split("/").map(encodeURIComponent).join("/")}`;
    const res = await fetch(url, { headers: HEADERS });
    if (res.status === 404) {
      console.log(`· ${p}: non esiste, salto`);
      continue;
    }
    if (!res.ok) fail(`lettura ${p}: HTTP ${res.status}`);
    const doc = await res.json();
    const fields = Object.keys(doc.fields || {}).sort();

    // Un membro attivo (con role e non cancellato) non si toglie da qui: toglierlo
    // è una revoca, e passa dall'app. Si cancellano solo i fantasmi senza role
    // e i documenti già soft-deleted.
    const seg = p.split("/");
    if (seg.length === 4 && seg[0] === "families" && seg[2] === "members") {
      const f = doc.fields || {};
      const role = f.role?.stringValue;
      const isDeleted = f.isDeleted?.booleanValue === true;
      if (typeof role === "string" && role.trim() && !isDeleted) {
        fail(`${p} è un membro ATTIVO (role=${role}): toglierlo è una revoca, si fa dall'app`);
      }
    }

    if (!confirmed) {
      console.log(`? ${p} (campi: ${fields.join(", ") || "nessuno"}) — prova, non cancellato`);
      continue;
    }

    // `currentDocument.updateTime`: se il documento è cambiato fra la lettura e
    // la cancellazione, la DELETE fallisce invece di cancellare altro.
    const del = await fetch(`${url}?currentDocument.updateTime=${encodeURIComponent(doc.updateTime)}`, {
      method: "DELETE",
      headers: HEADERS,
    });
    if (!del.ok) fail(`cancellazione ${p}: HTTP ${del.status} ${await del.text()}`);
    deleted += 1;
    fs.mkdirSync(path.dirname(LOG), { recursive: true });
    fs.appendFileSync(LOG, JSON.stringify({ at: new Date().toISOString(), path: p, document: doc }) + "\n");
    console.log(`✓ ${p} cancellato (campi: ${fields.join(", ") || "nessuno"})`);
  }
  if (!confirmed) console.log("\nProva: niente è stato cancellato. Aggiungi --yes per cancellare.");
  else console.log(`\n${deleted} documenti cancellati · log: ${LOG}`);
}

main().catch((err) => fail(err.message));
