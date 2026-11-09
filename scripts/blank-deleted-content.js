#!/usr/bin/env node
/**
 * Svuota il testo dei documenti CANCELLATI (isDeleted: true) che nessun client
 * rilegge: to-do, liste, animali, eventi degli animali. Una volta sola, per lo
 * storico: da qui in avanti lo fanno le functions (`functions/deletedContent.js`).
 *
 * Perché: i client li leggono con `isDeleted == false`, quindi nessuno li
 * ricifra, e restavano su Firestore con titolo e note in chiaro
 * (`internal/cifratura-sezioni.md`, «Prova su device»).
 *
 * Svuota SOLO i campi di testo (stringa → ""), non tocca `secure`,
 * `updatedAt`, `updatedBy` né altro. Non cancella documenti. Non stampa mai i
 * valori: solo conteggi.
 *
 * Uso:
 *   node scripts/blank-deleted-content.js            # prova: conta e basta
 *   node scripts/blank-deleted-content.js --yes      # scrive
 *   node scripts/blank-deleted-content.js --family <id> [--yes]
 * Token: `gcloud auth print-access-token` dell'utente (Owner del progetto).
 */
"use strict";

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const BASE = `https://firestore.googleapis.com/v1/${ROOT}`;

// Identica a DELETED_BLANK_FIELDS di functions/deletedContent.js.
const FIELDS = {
  todos: ["title", "notes"],
  todoLists: ["name"],
  pets: ["name", "breed", "color", "chipCode", "notes"],
  petEvents: ["title", "vetName", "notes"],
};

const args = process.argv.slice(2);
const WRITE = args.includes("--yes");
const onlyFamily = args.includes("--family") ? args[args.indexOf("--family") + 1] : null;

const TOKEN = execFileSync("gcloud", ["auth", "print-access-token"], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
}).trim();
const H = { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" };

async function familyIds() {
  if (onlyFamily) return [onlyFamily];
  const ids = [];
  let pageToken = "";
  do {
    const url = `${BASE}/families?pageSize=300&mask.fieldPaths=__name__${pageToken ? `&pageToken=${pageToken}` : ""}`;
    const res = await fetch(url, { headers: H });
    if (!res.ok) throw new Error(`families: HTTP ${res.status}`);
    const body = await res.json();
    for (const d of body.documents || []) ids.push(d.name.split("/").pop());
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return ids;
}

async function deletedDocs(familyId, coll) {
  const res = await fetch(`${BASE}/families/${familyId}:runQuery`, {
    method: "POST",
    headers: H,
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: coll }],
        where: { fieldFilter: { field: { fieldPath: "isDeleted" }, op: "EQUAL", value: { booleanValue: true } } },
        select: { fields: FIELDS[coll].map((f) => ({ fieldPath: f })) },
      },
    }),
  });
  if (!res.ok) throw new Error(`${familyId}/${coll}: HTTP ${res.status} ${await res.text()}`);
  return (await res.json()).filter((r) => r.document).map((r) => r.document);
}

async function commit(writes) {
  for (let i = 0; i < writes.length; i += 400) {
    const res = await fetch(`https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:commit`, {
      method: "POST",
      headers: H,
      body: JSON.stringify({ writes: writes.slice(i, i + 400) }),
    });
    if (!res.ok) throw new Error(`commit: HTTP ${res.status} ${await res.text()}`);
  }
}

(async () => {
  const families = await familyIds();
  const totals = Object.fromEntries(Object.keys(FIELDS).map((c) => [c, { docs: 0, families: new Set() }]));
  const writes = [];

  for (const fid of families) {
    for (const coll of Object.keys(FIELDS)) {
      for (const doc of await deletedDocs(fid, coll)) {
        const f = doc.fields || {};
        const toBlank = FIELDS[coll].filter((k) => f[k] && "stringValue" in f[k] && f[k].stringValue.trim() !== "");
        if (!toBlank.length) continue;
        totals[coll].docs += 1;
        totals[coll].families.add(fid);
        writes.push({
          update: { name: doc.name, fields: Object.fromEntries(toBlank.map((k) => [k, { stringValue: "" }])) },
          updateMask: { fieldPaths: toBlank },
          currentDocument: { exists: true },
        });
      }
    }
  }

  console.log(`Famiglie esaminate: ${families.length}`);
  for (const [coll, t] of Object.entries(totals)) {
    console.log(`${coll.padEnd(10)} ${String(t.docs).padStart(5)} documenti cancellati con testo in chiaro, in ${t.families.size} famiglie`);
  }
  if (!WRITE) {
    console.log(`\nProva: niente scritto. ${writes.length} documenti da svuotare. Rilanciare con --yes.`);
    return;
  }
  await commit(writes);
  console.log(`\nSvuotati ${writes.length} documenti.`);
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
