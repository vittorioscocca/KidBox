#!/usr/bin/env node
/**
 * Audit dell'indice delle famiglie: `users/{uid}/memberships/{familyId}` contro
 * i documenti membro `families/{familyId}/members/{memberId}`. SOLA LETTURA.
 *
 * L'indice è una copia (la tiene allineata la function `syncMembershipIndex`),
 * la verità è il documento membro. Da un'incongruenza nascono due guasti:
 *
 *   - MEMBRO ATTIVO SENZA INDICE → la famiglia è invisibile per quell'utente
 *     (23/09/2026: famiglia con cinque membri sparita dal selettore iOS).
 *   - INDICE SENZA MEMBRO ATTIVO → il client ha in lista una famiglia che le
 *     rules non gli fanno leggere: errori di permesso, famiglie fantasma, e su
 *     iOS il PERMISSION_DENIED può innescare l'auto-espulsione.
 *
 * «Attivo» usa il criterio di `isMember` nelle rules e di `isActiveMember` in
 * functions/index.js: non cancellato E con `role`. Un documento senza `role` è
 * il fantasma che iOS e web ricreano rinominandosi dopo una revoca: lo si
 * elenca a parte, non conta come membro.
 *
 * Non corregge niente. Stampa i comandi di cancellazione per chi deve eseguirli
 * (le cancellazioni Firestore le lancia l'utente).
 *
 * Uso:  node scripts/membership-index-audit.js [--json]
 * Token: `gcloud auth print-access-token` dell'utente (Owner del progetto).
 */
"use strict";

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

function token() {
  return execFileSync("gcloud", ["auth", "print-access-token"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  }).trim();
}

const TOKEN = token();
const HEADERS = {
  Authorization: `Bearer ${TOKEN}`,
  "x-goog-user-project": PROJECT,
  "Content-Type": "application/json",
};

/** Tutti i documenti di un collection group, paginati per nome. */
async function collectionGroup(collectionId) {
  const out = [];
  let cursor = null;
  for (;;) {
    const q = {
      from: [{ collectionId, allDescendants: true }],
      orderBy: [{ field: { fieldPath: "__name__" } }],
      limit: 500,
    };
    if (cursor) q.startAt = { values: [{ referenceValue: cursor }], before: false };
    const res = await fetch(`${BASE}:runQuery`, {
      method: "POST",
      headers: HEADERS,
      body: JSON.stringify({ structuredQuery: q }),
    });
    if (!res.ok) throw new Error(`runQuery ${collectionId}: HTTP ${res.status} ${await res.text()}`);
    const docs = (await res.json()).filter((r) => r.document).map((r) => r.document);
    out.push(...docs);
    if (docs.length < 500) return out;
    cursor = docs[docs.length - 1].name;
  }
}

async function exists(path) {
  const res = await fetch(`${BASE}/${path}`, { headers: HEADERS });
  if (res.status === 404) return false;
  if (!res.ok) throw new Error(`GET ${path}: HTTP ${res.status}`);
  return true;
}

function value(field) {
  if (!field) return undefined;
  const [k, v] = Object.entries(field)[0];
  return k === "nullValue" ? null : v;
}

/** ["families", fid, "members", mid] dal nome completo del documento. */
function segments(name) {
  return name.split("/documents/")[1].split("/");
}

async function main() {
  const [members, memberships] = await Promise.all([
    collectionGroup("members"),
    collectionGroup("memberships"),
  ]);

  const active = new Map(); // "uid|fid" → role
  const ghosts = []; // documenti membro senza role (e non cancellati)
  const undetermined = [];
  let softDeleted = 0;
  const unexpectedPaths = [];

  for (const doc of members) {
    const p = segments(doc.name);
    if (p.length !== 4 || p[0] !== "families") {
      unexpectedPaths.push(p.join("/"));
      continue;
    }
    const [, fid, , mid] = p;
    const f = doc.fields || {};
    if (value(f.isDeleted) === true) {
      softDeleted += 1;
      continue;
    }
    let uid = value(f.uid) || value(f.userId);
    if (!uid) {
      // Righe legacy `{familyId}_{uid}` di iOS: l'id non è un uid.
      if (mid.startsWith(`${fid}_`)) {
        undetermined.push(`families/${fid}/members/${mid}`);
        continue;
      }
      uid = mid;
    }
    const role = value(f.role);
    if (typeof role !== "string" || !role.trim()) {
      ghosts.push({ uid, fid, path: `families/${fid}/members/${mid}`, fields: Object.keys(f).sort() });
      continue;
    }
    active.set(`${uid}|${fid}`, role);
  }

  const index = new Map(); // "uid|fid" → fields
  for (const doc of memberships) {
    const p = segments(doc.name);
    if (p.length !== 4 || p[0] !== "users") {
      unexpectedPaths.push(p.join("/"));
      continue;
    }
    index.set(`${p[1]}|${p[3]}`, doc.fields || {});
  }

  const missing = [...active.entries()]
    .filter(([k]) => !index.has(k))
    .map(([k, role]) => ({ uid: k.split("|")[0], fid: k.split("|")[1], role }));

  const orphans = [];
  for (const k of index.keys()) {
    if (active.has(k)) continue;
    const [uid, fid] = k.split("|");
    orphans.push({ uid, fid, familyExists: await exists(`families/${fid}`) });
  }

  const roleMismatch = [...active.entries()]
    .filter(([k, role]) => index.has(k) && value(index.get(k).role) !== role)
    .map(([k, role]) => ({ key: k, member: role, index: value(index.get(k).role) }));

  for (const g of ghosts) g.familyExists = await exists(`families/${g.fid}`);

  const report = {
    memberDocs: members.length,
    activeMembers: active.size,
    softDeleted,
    indexDocs: index.size,
    missing,
    orphans,
    roleMismatch,
    ghosts,
    undetermined,
    unexpectedPaths,
  };

  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }

  console.log(`Documenti membro: ${members.length} · attivi: ${active.size} · soft-deleted: ${softDeleted}`);
  console.log(`Documenti indice: ${index.size}`);
  if (unexpectedPaths.length) console.log(`⚠️  path inattesi (altre collezioni con lo stesso nome): ${unexpectedPaths.join(", ")}`);

  console.log(`\nMembri attivi SENZA indice (famiglia invisibile): ${missing.length}`);
  for (const m of missing) console.log(`  uid=${m.uid} family=${m.fid} role=${m.role}`);
  if (missing.length) console.log("  → rimedio: backfillMembershipIndex (prima con dryRun: true) dalla console admin");

  console.log(`\nIndici SENZA membro attivo (famiglia fantasma): ${orphans.length}`);
  for (const o of orphans) console.log(`  uid=${o.uid} family=${o.fid} famigliaEsiste=${o.familyExists}`);

  console.log(`\nRuolo diverso fra membro e indice: ${roleMismatch.length}`);
  for (const r of roleMismatch) console.log(`  ${r.key} membro=${r.member} indice=${r.index}`);

  console.log(`\nDocumenti membro SENZA role (fantasmi da rinomina dopo revoca): ${ghosts.length}`);
  for (const g of ghosts) console.log(`  ${g.path} famigliaEsiste=${g.familyExists} campi=${g.fields.join(",")}`);

  if (undetermined.length) console.log(`\nUid non determinabili (righe legacy): ${undetermined.join(", ")}`);

  const toDelete = [
    ...orphans.map((o) => `users/${o.uid}/memberships/${o.fid}`),
    ...ghosts.map((g) => g.path),
  ];
  if (toDelete.length) {
    console.log("\nCancellazioni da far eseguire all'UTENTE (verificare caso per caso prima):");
    for (const p of toDelete) console.log(`  npx firebase firestore:delete "${p}" --project ${PROJECT} -f`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
