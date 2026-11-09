/**
 * Cifratura delle sezioni (Garage, Animali, Spese, Salute), specifica in
 * `internal/cifratura-sezioni.md`.
 *
 * Un solo campo in più per documento: `secure`, `base64(AES-GCM combined)` di
 * un JSON `{"campo": "valore"}` con i campi della tabella qui sotto, e
 * `secureV: 1`. Stessa chiave e stesso formato delle note (`noteCrypto`).
 *
 * Lettura (sempre): il chiaro vince se è una stringa non vuota, altrimenti
 * vale `secure`. Una build vecchia che modifica il documento riscrive il
 * chiaro, e quella è la modifica più recente.
 *
 * Scrittura e ricifratura solo con `sections_encryption_enabled` acceso e la
 * chiave presente; altrimenti in chiaro come prima.
 *
 * ⚠️ La tabella è identica sui tre client: un campo in più o in meno qui e il
 * telefono non lo ritrova.
 */
import { onSnapshot, setDoc } from "firebase/firestore";
import { auth } from "../firebase";
import { sectionsEncryptionEnabled } from "./featureFlags";
import { loadFamilyKey } from "./familyKey";
import { decryptString, encryptString } from "./noteCrypto";

export const SECURE_VERSION = 1;

/** Campi in `secure`, per collezione sotto `families/{familyId}/`. */
export const SECURE_FIELDS = {
  vehicles: ["name", "licensePlate", "brand", "model", "color", "vin", "notes"],
  vehicleEvents: ["title", "garageName", "notes"],
  pets: ["name", "breed", "color", "chipCode", "notes"],
  petEvents: ["title", "vetName", "notes"],
  expenses: ["title", "notes"],
  medicalVisits: ["doctorName", "reason", "diagnosis", "recommendations", "notes", "nextVisitReason"],
  medicalExams: ["name", "preparation", "location", "resultText", "notes"],
  treatments: ["drugName", "activeIngredient", "notes"],
  vaccines: ["commercialName", "lotNumber", "administeredBy", "notes"],
  pediatricProfiles: [
    "bloodGroup",
    "allergies",
    "medicalNotes",
    "doctorName",
    "doctorPhone",
    "doctorEmail",
    "doctorAddress",
    "doctorWebsite",
    "doctorOfficeHoursJSON",
    "emergencyContactsJSON",
  ],
};

const filled = (v) => typeof v === "string" && v.length > 0;

/* ── Chiave ──────────────────────────────────────────────────────────────── */

/**
 * Chiave di famiglia o null. Un'assenza resta in memoria un minuto: senza,
 * ogni snapshot di una lista con `secure` rileggerebbe l'escrow.
 */
const MISSING_TTL_MS = 60_000;
const pendingKeys = new Map();
const missingKeys = new Map();

export async function sectionKey(familyId) {
  const userId = auth.currentUser?.uid;
  if (!familyId || !userId) return null;
  const cacheKey = `${userId}.${familyId}`;
  if ((missingKeys.get(cacheKey) || 0) > Date.now()) return null;
  if (!pendingKeys.has(cacheKey)) {
    pendingKeys.set(
      cacheKey,
      loadFamilyKey({ familyId, userId })
        .catch(() => {
          missingKeys.set(cacheKey, Date.now() + MISSING_TTL_MS);
          return null;
        })
        .finally(() => pendingKeys.delete(cacheKey))
    );
  }
  return pendingKeys.get(cacheKey);
}

/** Chiave per scrivere: null a interruttore spento, così non si carica nemmeno. */
export async function sectionWriteKey(familyId) {
  return sectionsEncryptionEnabled() ? sectionKey(familyId) : null;
}

/* ── Lettura ─────────────────────────────────────────────────────────────── */

/** Valori del blob, o null se manca, la chiave non c'è o non si decifra. */
async function openSecure(secure, familyKey) {
  if (!filled(secure) || !familyKey) return null;
  try {
    const parsed = JSON.parse(await decryptString(secure, familyKey));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

/**
 * Dati del documento con i campi della tabella risolti: chiaro non vuoto,
 * altrimenti `secure`. Senza chiave o con un blob illeggibile restano i
 * valori in chiaro (vuoti), senza errori.
 */
export async function resolveSecure(collection, data, familyKey) {
  const fields = SECURE_FIELDS[collection];
  if (!fields || !data || !filled(data.secure)) return data;
  const opened = await openSecure(data.secure, familyKey);
  if (!opened) return data;
  const out = { ...data };
  for (const f of fields) {
    if (!filled(out[f]) && filled(opened[f])) out[f] = opened[f];
  }
  return out;
}

/* ── Scrittura ───────────────────────────────────────────────────────────── */

/** `secure` + `secureV` + campi a "" per i valori dati. */
async function sealedPatch(fields, values, familyKey) {
  const plain = {};
  for (const f of fields) if (filled(values[f])) plain[f] = values[f];
  const patch = {
    secure: await encryptString(JSON.stringify(plain), familyKey),
    secureV: SECURE_VERSION,
  };
  for (const f of fields) patch[f] = "";
  return patch;
}

/**
 * Dati pronti per Firestore. Interruttore acceso e chiave presente: i campi
 * della tabella vanno in `secure` e si scrivono "" (non cancellati: le build
 * vecchie li vogliono). Altrimenti tornano invariati, in chiaro.
 *
 * Solo per scritture che portano **tutti** i campi della tabella: `secure`
 * si riscrive intero, e un campo assente andrebbe perso. Una scrittura
 * parziale resta in chiaro (e il chiaro vince in lettura).
 */
export async function sealForWrite(collection, data, familyKey) {
  const fields = SECURE_FIELDS[collection];
  if (!fields || !familyKey || !sectionsEncryptionEnabled()) return data;
  if (!fields.every((f) => f in data)) return data;
  return { ...data, ...(await sealedPatch(fields, data, familyKey)) };
}

/* ── Ricifratura ─────────────────────────────────────────────────────────── */

/** Documenti già ricifrati (o tentati) in questa sessione, per path. */
const resealed = new Set();

/**
 * Documento vecchio con un campo in chiaro: si riscrive in merge solo
 * `secure` (valori uniti con la regola di lettura), `secureV` e i campi a "".
 * `updatedAt`/`updatedBy` non si toccano. Se c'è un `secure` che non si apre
 * non si scrive niente: lo si perderebbe.
 */
export function resealIfPlain(collection, ref, data, familyKey) {
  const fields = SECURE_FIELDS[collection];
  if (!fields || !ref || !data || !familyKey || !sectionsEncryptionEnabled()) return;
  if (!fields.some((f) => filled(data[f]))) return;
  if (resealed.has(ref.path)) return;
  resealed.add(ref.path);
  (async () => {
    let values = data;
    if (filled(data.secure)) {
      const opened = await openSecure(data.secure, familyKey);
      if (!opened) return;
      values = { ...opened };
      for (const f of fields) if (filled(data[f])) values[f] = data[f];
    }
    await setDoc(ref, await sealedPatch(fields, values, familyKey), { merge: true });
  })().catch(() => {
    // Riprova alla prossima sessione.
  });
}

/* ── Liste ───────────────────────────────────────────────────────────────── */

/**
 * Documenti di uno snapshot con i campi risolti, nella forma di uno snapshot
 * (`id`, `ref`, `exists()`, `data()`): i lettori esistenti restano uguali.
 * La chiave si carica solo se serve; i documenti in chiaro si ricifrano.
 */
export async function openDocs(collection, familyId, docs) {
  const fields = SECURE_FIELDS[collection];
  const raws = docs.map((d) => d.data() || {});
  const resealing = sectionsEncryptionEnabled();
  const needsKey =
    !!fields &&
    raws.some((r) => filled(r.secure) || (resealing && fields.some((f) => filled(r[f]))));
  const familyKey = needsKey ? await sectionKey(familyId) : null;
  const opened = await Promise.all(
    docs.map(async (d, i) => {
      const data = await resolveSecure(collection, raws[i], familyKey);
      return { id: d.id, ref: d.ref, exists: () => true, data: () => data };
    })
  );
  if (familyKey) docs.forEach((d, i) => resealIfPlain(collection, d.ref, raws[i], familyKey));
  return opened;
}

/** Dati semplici `{ id, ...campi }` di uno snapshot, risolti. */
export async function openRows(collection, familyId, docs) {
  return (await openDocs(collection, familyId, docs)).map((d) => ({ id: d.id, ...d.data() }));
}

/**
 * `onSnapshot` su una query, con i documenti risolti. La decifratura è
 * asincrona: uno snapshot superato da uno più nuovo, o arrivato dopo lo stop,
 * si scarta.
 */
export function listenSecure(q, collection, familyId, onDocs, onError) {
  let seq = 0;
  let stopped = false;
  const stop = onSnapshot(
    q,
    (snap) => {
      const mine = ++seq;
      openDocs(collection, familyId, snap.docs)
        .then((docs) => {
          if (!stopped && mine === seq) onDocs(docs);
        })
        .catch((err) => onError?.(err));
    },
    (err) => onError?.(err)
  );
  return () => {
    stopped = true;
    stop();
  };
}
