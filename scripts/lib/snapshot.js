/**
 * Lettura degli snapshot che la funzione `reportSnapshotDaily` scrive su
 * Firestore (`reportSnapshots/{fonte}_{YYYY-MM-DD}`), per gli script di report.
 *
 * Token utente di gcloud (Owner del progetto, passa le rules come admin via
 * IAM); sola lettura. Se lo snapshot manca, è fallito o è vecchio, restituisce
 * `null` e lo script ripiega sulla lettura dal vivo dicendolo.
 */
const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const MAX_AGE_H = 30;

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
}

/**
 * @param {string} source  "ga4" | "searchConsole" | ...
 * @returns {Promise<{payload: object, dataThrough: string|null, computedAt: string, ageH: number}|{reason: string}>}
 */
async function readSnapshot(source) {
  let tok;
  try {
    tok = execFileSync("gcloud", ["auth", "print-access-token"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
  } catch {
    return { reason: "gcloud non autenticato" };
  }
  const id = `${source}_${romeDate()}`;
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/reportSnapshots/${id}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${tok}`, "x-goog-user-project": PROJECT } });
  if (res.status === 404) return { reason: `snapshot ${id} non ancora scritto` };
  const doc = await res.json().catch(() => ({}));
  if (!res.ok) return { reason: `lettura ${id}: ${doc.error?.message || res.status}` };
  const f = doc.fields || {};
  if (!f.ok?.booleanValue) return { reason: `snapshot ${id} fallito: ${f.error?.stringValue || "?"}` };
  const computedAt = f.computedAt?.timestampValue;
  const ageH = computedAt ? (Date.now() - Date.parse(computedAt)) / 3.6e6 : Infinity;
  if (ageH > MAX_AGE_H) return { reason: `snapshot ${id} vecchio di ${Math.round(ageH)} h` };
  try {
    return { payload: JSON.parse(f.payloadJson.stringValue), dataThrough: f.dataThrough?.stringValue || null, computedAt, ageH };
  } catch {
    return { reason: `snapshot ${id} illeggibile` };
  }
}

module.exports = { readSnapshot };
