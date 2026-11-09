/**
 * Cifratura delle sezioni (Garage, Animali, Spese, Salute; dal secondo giro
 * anche figli, to-do, liste e calendario), specifica in
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
import { deleteField, doc, getDoc, onSnapshot, setDoc } from "firebase/firestore";
import { auth, db } from "../firebase";
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
  medicalVisits: [
    "doctorName",
    "reason",
    "diagnosis",
    "recommendations",
    "notes",
    "nextVisitReason",
    "travelDetailsData",
    "travelDetailsJson",
    "asNeededDrugsData",
    "asNeededDrugsJson",
    "prescribedExamsData",
    "prescribedExamsJson",
  ],
  medicalExams: ["name", "preparation", "location", "resultText", "notes"],
  treatments: ["drugName", "activeIngredient", "notes"],
  vaccines: ["commercialName", "lotNumber", "administeredBy", "notes", "name", "doctorName", "location"],
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
  children: ["name"],
  todos: ["title", "notes"],
  todoLists: ["name"],
  calendarEvents: ["title", "notes", "location"],
};

/**
 * Campi «*» della tabella: sigillati si scrivono cancellati invece che "".
 * Sono opzionali e contengono JSON o base64, che un parser vecchio potrebbe
 * non reggere vuoti. In lettura un campo assente vale come vuoto.
 */
export const SECURE_DELETED_FIELDS = {
  medicalVisits: [
    "travelDetailsData",
    "travelDetailsJson",
    "asNeededDrugsData",
    "asNeededDrugsJson",
    "prescribedExamsData",
    "prescribedExamsJson",
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
  return sectionsEncryptionEnabled(familyId) ? sectionKey(familyId) : null;
}

/* ── Calendario esportato ────────────────────────────────────────────────── */

/**
 * `calendarExported` del documento famiglia: con un link iCal attivo gli
 * eventi restano in chiaro (il feed li legge dal server) e quelli già
 * sigillati si riaprono. Il valore lo tiene aggiornato `FamilyContext`, che
 * segue il documento famiglia; se manca si legge una volta il documento.
 */
const calendarExportedByFamily = new Map();

export function setCalendarExported(familyId, exported) {
  if (familyId) calendarExportedByFamily.set(familyId, exported === true);
}

export async function isCalendarExported(familyId) {
  if (!familyId) return false;
  if (!calendarExportedByFamily.has(familyId)) {
    const pending = getDoc(doc(db, "families", familyId))
      .then((snap) => snap.data()?.calendarExported === true)
      // Lettura fallita: si tratta come non esportato, ma non si memorizza,
      // così la prossima volta si riprova.
      .catch(() => {
        calendarExportedByFamily.delete(familyId);
        return false;
      });
    calendarExportedByFamily.set(familyId, pending);
  }
  return calendarExportedByFamily.get(familyId);
}

/** `families/{familyId}/…` → familyId. */
const familyIdOf = (ref) => ref?.path?.split("/")[1] || null;

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

/**
 * `secure` + `secureV` + i campi della tabella svuotati: "" per quelli normali
 * (le build vecchie li vogliono presenti), cancellati per quelli «*». Con
 * `merge: false` (documento sostituito per intero) i campi «*» si omettono:
 * `deleteField()` lì non è ammesso, e un campo omesso sparisce comunque.
 */
async function sealedPatch(collection, values, familyKey, { merge = true } = {}) {
  const fields = SECURE_FIELDS[collection];
  const deleted = SECURE_DELETED_FIELDS[collection] || [];
  const plain = {};
  for (const f of fields) if (filled(values[f])) plain[f] = values[f];
  const patch = {
    secure: await encryptString(JSON.stringify(plain), familyKey),
    secureV: SECURE_VERSION,
  };
  const omit = [];
  for (const f of fields) {
    if (!deleted.includes(f)) patch[f] = "";
    else if (merge) patch[f] = deleteField();
    else omit.push(f);
  }
  return { patch, omit };
}

/**
 * Dati pronti per Firestore. Interruttore acceso e chiave presente: i campi
 * della tabella vanno in `secure` e si scrivono svuotati (vedi `sealedPatch`).
 * Altrimenti tornano invariati, in chiaro.
 *
 * `ref` è il documento che si sta per scrivere; `merge` dice se la scrittura
 * è in merge (`setDoc(…, { merge: true })`, `batch.set` in merge,
 * `updateDoc`) o sostituisce il documento.
 *
 * Scrittura parziale (in merge, senza tutti i campi della tabella): `secure`
 * si riscrive intero, quindi i campi mancanti si prendono dal documento
 * esistente, letto e risolto con la regola di lettura. Così non si perde un
 * campo che questo client non scrive (es. `name` dei vaccini, solo Android).
 * Se la lettura fallisce, o il `secure` esistente non si apre, si scrive in
 * chiaro: il chiaro vince in lettura, e il primo client che legge ricifra.
 *
 * Una scrittura che non porta nessun campo della tabella (cancellazione,
 * spunta di un to-do) torna invariata, senza letture.
 *
 * `calendarEvents` di una famiglia con il calendario esportato: mai sigillati.
 */
export async function sealForWrite(collection, data, familyKey, ref, { merge = true } = {}) {
  const fields = SECURE_FIELDS[collection];
  if (!fields || !data || !familyKey || !sectionsEncryptionEnabled(familyIdOf(ref))) return data;
  if (!fields.some((f) => f in data)) return data;
  if (collection === "calendarEvents" && (await isCalendarExported(familyIdOf(ref)))) return data;

  let values = data;
  const missing = fields.filter((f) => !(f in data));
  if (missing.length && merge) {
    if (!ref) return data;
    try {
      const snap = await getDoc(ref);
      if (snap.exists()) {
        const existing = snap.data() || {};
        let opened = {};
        if (filled(existing.secure)) {
          opened = await openSecure(existing.secure, familyKey);
          if (!opened) return data;
        }
        values = { ...data };
        // Regola di lettura sul documento esistente: chiaro non vuoto, poi `secure`.
        for (const f of missing) values[f] = filled(existing[f]) ? existing[f] : opened[f];
      }
    } catch {
      return data;
    }
  }
  const { patch, omit } = await sealedPatch(collection, values, familyKey, { merge });
  const out = { ...data, ...patch };
  for (const f of omit) delete out[f];
  return out;
}

/**
 * `sealForWrite` con la chiave della famiglia del documento: per i punti che
 * scrivono un solo documento e non hanno già la chiave in mano.
 */
export async function sealDocWrite(collection, ref, data, { merge = true } = {}) {
  if (!SECURE_FIELDS[collection] || !sectionsEncryptionEnabled(familyIdOf(ref))) return data;
  return sealForWrite(collection, data, await sectionWriteKey(familyIdOf(ref)), ref, { merge });
}

/* ── Ricifratura e riapertura ────────────────────────────────────────────── */

/** Documenti già ricifrati o riaperti (o tentati) in questa sessione, per path. */
const resealed = new Set();

/**
 * Documento vecchio con un campo in chiaro: si riscrive in merge solo
 * `secure` (valori uniti con la regola di lettura), `secureV` e i campi
 * svuotati. `updatedAt`/`updatedBy` non si toccano. Se c'è un `secure` che
 * non si apre non si scrive niente: lo si perderebbe.
 */
export function resealIfPlain(collection, ref, data, familyKey) {
  const fields = SECURE_FIELDS[collection];
  if (!fields || !ref || !data || !familyKey || !sectionsEncryptionEnabled(familyIdOf(ref))) return;
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
    const { patch } = await sealedPatch(collection, values, familyKey);
    await setDoc(ref, patch, { merge: true });
  })().catch(() => {
    // Riprova alla prossima sessione.
  });
}

/**
 * Calendario esportato: un evento con `secure` si riapre. Si scrivono in
 * merge i campi risolti in chiaro e si cancellano `secure` e `secureV`,
 * senza toccare `updatedAt`/`updatedBy`. Se il blob non si apre non si
 * scrive niente.
 */
export function reopenIfSealed(collection, ref, data, familyKey) {
  const fields = SECURE_FIELDS[collection];
  if (!fields || !ref || !data || !familyKey || !filled(data.secure)) return;
  if (resealed.has(ref.path)) return;
  resealed.add(ref.path);
  (async () => {
    const opened = await openSecure(data.secure, familyKey);
    if (!opened) return;
    const patch = { secure: deleteField(), secureV: deleteField() };
    for (const f of fields) {
      const v = filled(data[f]) ? data[f] : opened[f];
      if (filled(v)) patch[f] = v;
    }
    await setDoc(ref, patch, { merge: true });
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
  const anySecure = raws.some((r) => filled(r.secure));
  // Calendario esportato: niente ricifratura, e quello già sigillato si riapre.
  const exported =
    collection === "calendarEvents" && !!fields && docs.length > 0 && (await isCalendarExported(familyId));
  const resealing = sectionsEncryptionEnabled(familyId) && !exported;
  const needsKey =
    !!fields && (anySecure || (resealing && raws.some((r) => fields.some((f) => filled(r[f])))));
  const familyKey = needsKey ? await sectionKey(familyId) : null;
  const opened = await Promise.all(
    docs.map(async (d, i) => {
      const data = await resolveSecure(collection, raws[i], familyKey);
      return { id: d.id, ref: d.ref, exists: () => true, data: () => data };
    })
  );
  if (familyKey) {
    docs.forEach((d, i) =>
      exported
        ? reopenIfSealed(collection, d.ref, raws[i], familyKey)
        : resealIfPlain(collection, d.ref, raws[i], familyKey)
    );
  }
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
