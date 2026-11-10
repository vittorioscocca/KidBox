#!/usr/bin/env node
/**
 * Stato delle copie della chiave di UNA famiglia, membro per membro. SOLA LETTURA.
 *
 * Per ogni documento in `families/{fid}/members` dice:
 *   - ruolo, cancellato o no
 *   - copia v1 (cipher/nonce/tag) presente o no
 *   - copia v2 presente, e se il suo `rkId` è quello di una cassaforte
 *     dell'utente (`users/{uid}/keyVault`): «v2 ok» solo se coincide
 *   - quante strade apre la sua cassaforte (codice, passkey)
 * più `keyV1Closed` della famiglia.
 *
 * Non stampa MAI cipher, nonce, tag, salt né la RK: solo presenza, tipi e i
 * primi 4 caratteri di `rkId`. Serve alla tabella di prova della sezione 4 bis
 * di `internal/cifratura-chiave-di-riserva-v2.md` e all'elenco «con i nomi»
 * prima della Fase 3.
 *
 * Uso:  node scripts/key-vault-check.js <familyId> [--json]
 * Token: `gcloud auth print-access-token` dell'utente (Owner del progetto).
 */
"use strict";

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const args = process.argv.slice(2);
const familyId = args.find((a) => !a.startsWith("--"));
const asJson = args.includes("--json");
if (!familyId) {
  console.error("Uso: node scripts/key-vault-check.js <familyId> [--json]");
  process.exit(1);
}

const TOKEN = execFileSync("gcloud", ["auth", "print-access-token"], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
}).trim();
const H = { Authorization: `Bearer ${TOKEN}` };

async function get(path) {
  const res = await fetch(`${BASE}/${path}`, { headers: H });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return res.json();
}

async function list(path) {
  const out = [];
  let pageToken = "";
  do {
    const res = await fetch(`${BASE}/${path}?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ""}`, { headers: H });
    if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
    const body = await res.json();
    out.push(...(body.documents || []));
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return out;
}

const s = (v) => (v && "stringValue" in v ? v.stringValue : null);
const filled = (v) => !!s(v);

(async () => {
  const fam = await get(`families/${familyId}`);
  if (!fam) throw new Error(`famiglia ${familyId} non trovata`);
  const v1Closed = fam.fields?.keyV1Closed?.booleanValue === true;

  const rows = [];
  for (const m of await list(`families/${familyId}/members`)) {
    const uid = m.name.split("/").pop();
    const f = m.fields || {};
    const backup = (await get(`families/${familyId}/memberKeyBackups/${uid}`))?.fields || {};
    const v2 = backup.v2?.mapValue?.fields || null;
    const slots = await list(`users/${uid}/keyVault`);
    const rkIds = new Set(slots.map((d) => s(d.fields?.rkId)).filter(Boolean));
    const types = slots.map((d) => s(d.fields?.type)).filter(Boolean);
    const v2RkId = v2 ? s(v2.rkId) : null;
    rows.push({
      uid: uid.slice(0, 6),
      name: s(f.displayName) || s(f.name) || "",
      role: s(f.role) || "(nessuno)",
      deleted: f.isDeleted?.booleanValue === true,
      v1: filled(backup.cipher) && filled(backup.nonce) && filled(backup.tag),
      v2: !!v2,
      v2MatchesVault: !!v2RkId && rkIds.has(v2RkId),
      v2RkId: v2RkId ? v2RkId.slice(0, 4) : null,
      vault: {
        recoveryCode: types.filter((t) => t === "recoveryCode").length,
        passkey: types.filter((t) => t === "passkey").length,
      },
    });
  }

  if (asJson) {
    console.log(JSON.stringify({ familyId, keyV1Closed: v1Closed, members: rows }, null, 2));
    return;
  }
  console.log(`Famiglia ${familyId} · keyV1Closed=${v1Closed}\n`);
  for (const r of rows) {
    const state = r.deleted || r.role === "(nessuno)" ? "fuori" : r.role;
    const v2 = r.v2 ? (r.v2MatchesVault ? `v2 ok (${r.v2RkId}…)` : `v2 SENZA cassaforte corrispondente (${r.v2RkId}…)`) : "v2 no";
    const vault = r.vault.recoveryCode + r.vault.passkey
      ? `cassaforte: codice ${r.vault.recoveryCode}, passkey ${r.vault.passkey}`
      : "cassaforte: nessuna";
    console.log(`${r.uid}  ${(r.name || "").padEnd(20).slice(0, 20)} ${state.padEnd(8)} v1 ${r.v1 ? "sì" : "no"} · ${v2} · ${vault}`);
  }
  const live = rows.filter((r) => !r.deleted && r.role !== "(nessuno)");
  const noCopy = live.filter((r) => !r.v1 && !r.v2MatchesVault);
  if (noCopy.length) {
    console.log(`\n⚠ ${noCopy.length} membri attivi senza nessuna copia apribile sul server: ${noCopy.map((r) => r.uid).join(", ")}`);
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
