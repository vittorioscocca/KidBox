#!/usr/bin/env node
/**
 * Controllo della cifratura delle sezioni su UNA famiglia. SOLA LETTURA.
 *
 * Per ogni collezione della tabella (`internal/cifratura-sezioni.md`) dice,
 * documento per documento, se è:
 *   - CIFRATO  → `secure` presente e nessun campo della tabella in chiaro
 *   - CHIARO   → nessun `secure`, almeno un campo della tabella pieno
 *   - MISTO    → `secure` presente E qualche campo ancora in chiaro (il chiaro
 *                vince in lettura: va capito chi l'ha riscritto)
 *   - VUOTO    → né `secure` né campi pieni (es. spunta di un to-do senza testo)
 *
 * Non stampa MAI i valori: solo i nomi dei campi pieni, `secureV`, `updatedAt`.
 * Serve alla prova su una famiglia di test (sezione «Come provarla» della
 * specifica), non a guardare dentro le famiglie degli utenti.
 *
 * Uso:  node scripts/section-encryption-check.js <familyId> [--since 2026-11-10T10:00] [--json]
 *       --since  solo i documenti con updatedAt/createdAt successivo
 * Token: `gcloud auth print-access-token` dell'utente (Owner del progetto).
 */
"use strict";

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// Identica a SECURE_FIELDS di KidboxWebApp/src/services/sectionCrypto.js.
const SECURE_FIELDS = {
  vehicles: ["name", "licensePlate", "brand", "model", "color", "vin", "notes"],
  vehicleEvents: ["title", "garageName", "notes"],
  pets: ["name", "breed", "color", "chipCode", "notes"],
  petEvents: ["title", "vetName", "notes"],
  expenses: ["title", "notes"],
  medicalVisits: [
    "doctorName", "reason", "diagnosis", "recommendations", "notes", "nextVisitReason",
    "travelDetailsData", "travelDetailsJson", "asNeededDrugsData", "asNeededDrugsJson",
    "prescribedExamsData", "prescribedExamsJson",
  ],
  medicalExams: ["name", "preparation", "location", "resultText", "notes"],
  treatments: ["drugName", "activeIngredient", "notes"],
  vaccines: ["commercialName", "lotNumber", "administeredBy", "notes", "name", "doctorName", "location"],
  pediatricProfiles: [
    "bloodGroup", "allergies", "medicalNotes", "doctorName", "doctorPhone", "doctorEmail",
    "doctorAddress", "doctorWebsite", "doctorOfficeHoursJSON", "emergencyContactsJSON",
  ],
  children: ["name"],
  todos: ["title", "notes"],
  todoLists: ["name"],
  calendarEvents: ["title", "notes", "location"],
};

const args = process.argv.slice(2);
const familyId = args.find((a) => !a.startsWith("--") && args[args.indexOf(a) - 1] !== "--since");
const sinceArg = args.includes("--since") ? args[args.indexOf("--since") + 1] : null;
const since = sinceArg ? new Date(sinceArg) : null;
const asJson = args.includes("--json");
if (!familyId) {
  console.error("Uso: node scripts/section-encryption-check.js <familyId> [--since <data>] [--json]");
  process.exit(1);
}

const TOKEN = execFileSync("gcloud", ["auth", "print-access-token"], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "ignore"],
}).trim();

async function listAll(coll) {
  const out = [];
  let pageToken = "";
  do {
    const url = `${BASE}/families/${familyId}/${coll}?pageSize=300${pageToken ? `&pageToken=${pageToken}` : ""}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}` } });
    if (!res.ok) throw new Error(`${coll}: HTTP ${res.status} ${await res.text()}`);
    const body = await res.json();
    out.push(...(body.documents || []));
    pageToken = body.nextPageToken || "";
  } while (pageToken);
  return out;
}

const str = (v) => (v && "stringValue" in v ? v.stringValue : null);
const time = (v) => (v && v.timestampValue ? new Date(v.timestampValue) : null);

function classify(doc, fields) {
  const f = doc.fields || {};
  const secure = str(f.secure);
  const plain = fields.filter((k) => {
    const v = f[k];
    if (!v) return false;
    if ("stringValue" in v) return v.stringValue.trim() !== "";
    if ("bytesValue" in v) return v.bytesValue !== "";
    return !("nullValue" in v);
  });
  const state = secure ? (plain.length ? "MISTO" : "CIFRATO") : plain.length ? "CHIARO" : "VUOTO";
  return {
    id: doc.name.split("/").pop(),
    state,
    plainFields: plain,
    secureV: f.secureV ? Number(f.secureV.integerValue ?? f.secureV.doubleValue) : null,
    isDeleted: f.isDeleted?.booleanValue === true,
    updatedAt: (time(f.updatedAt) || time(f.createdAt) || new Date(doc.updateTime)).toISOString(),
    writtenAt: doc.updateTime,
  };
}

(async () => {
  const famRes = await fetch(`${BASE}/families/${familyId}`, { headers: { Authorization: `Bearer ${TOKEN}` } });
  if (!famRes.ok) throw new Error(`famiglia ${familyId}: HTTP ${famRes.status}`);
  const fam = await famRes.json();
  const exported = fam.fields?.calendarExported?.booleanValue === true;

  const report = { familyId, calendarExported: exported, collections: {} };
  for (const [coll, fields] of Object.entries(SECURE_FIELDS)) {
    const docs = (await listAll(coll)).map((d) => classify(d, fields));
    report.collections[coll] = since ? docs.filter((d) => new Date(d.writtenAt) >= since) : docs;
  }

  if (asJson) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }
  console.log(`Famiglia ${familyId} · calendarExported=${exported}${since ? ` · scritti dal ${since.toISOString()}` : ""}\n`);
  for (const [coll, docs] of Object.entries(report.collections)) {
    if (!docs.length) continue;
    const count = (s) => docs.filter((d) => d.state === s).length;
    console.log(
      `${coll.padEnd(18)} ${String(docs.length).padStart(3)} doc · cifrati ${count("CIFRATO")} · chiari ${count("CHIARO")} · misti ${count("MISTO")} · vuoti ${count("VUOTO")}`,
    );
    for (const d of docs.filter((x) => x.state !== "CIFRATO" && x.state !== "VUOTO")) {
      console.log(`    ${d.state.padEnd(7)} ${d.id}  campi in chiaro: ${d.plainFields.join(", ")}${d.isDeleted ? " (cancellato)" : ""}  scritto ${d.writtenAt}`);
    }
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
