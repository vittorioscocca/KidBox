/**
 * Scheda «Lavoro» (`families/{fid}/workProfiles/{ownerUid}` e `workRecords/{id}`),
 * gemella di `WorkRemoteStore` + `WorkDocumentService` (iOS) e `WorkRepository`
 * (Android).
 *
 * Buste paga, contratti e fogli ferie letti dall'AI (purpose `workDoc`, solo Pro
 * e Max, bloccato anche dal server). I valori estratti stanno in `fieldsEnc`,
 * JSON cifrato con la chiave di famiglia (stessa forma sugli altri client); la
 * scheda è privata di default e si condivide con adulti scelti.
 *
 * Le rules hanno una regola dedicata e una LIST non filtra: i listener sono
 * SEMPRE vincolati (la propria scheda = documento, le schede condivise con me =
 * `array-contains` sul mio uid, i documenti = `ownerUid ==`). Un errore di
 * permessi qui NON deve passare da `FamilyContext` (lo leggerebbe come
 * «membership orfana»): si gestisce in locale.
 */
import {
  collection,
  deleteField,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  where,
} from "firebase/firestore";
import { db } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { decryptString, encryptString } from "./noteCrypto";
import { askAssistant } from "./aiChat";
import { ensureFolder } from "./attachments";
import { fetchDocumentBlob, softDeleteDocument, updateDocumentVisibility, uploadDocument } from "./documents";

export const WORK_KIND = { PAYSLIP: "payslip", CONTRACT: "contract", LEAVE_PLAN: "leavePlan" };
export const workFolderId = (familyId) => `work-root-${familyId}`;

const profilesCol = (familyId) => collection(db, "families", familyId, "workProfiles");
const recordsCol = (familyId) => collection(db, "families", familyId, "workRecords");
const eventsCol = (familyId) => collection(db, "families", familyId, "calendarEvents");
const documentsCol = (familyId) => collection(db, "families", familyId, "documents");

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

// ── Valori ───────────────────────────────────────────────────────────────

export const EMPTY_FIELDS = Object.freeze({
  title: "", employer: "", period: "",
  gross: null, net: null, taxes: null, contributions: null,
  vacationAccrued: null, vacationTaken: null, vacationRemaining: null,
  permitHoursAccrued: null, permitHoursRemaining: null, tfr: null,
  contractType: "", startDate: null, endDate: null,
  grossAnnual: null, level: "", noticePeriod: "", vacationDaysPerYear: null,
  notes: "", leavePeriods: [], eventIds: [],
});

const NUM_KEYS = [
  "gross", "net", "taxes", "contributions", "vacationAccrued", "vacationTaken", "vacationRemaining",
  "permitHoursAccrued", "permitHoursRemaining", "tfr", "grossAnnual", "vacationDaysPerYear",
];
const TEXT_KEYS = ["title", "employer", "period", "contractType", "level", "noticePeriod", "notes"];

function toNumber(v) {
  if (v === null || v === undefined || v === "") return null;
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  const cleaned = String(v).replace("€", "").replace(/\s/g, "");
  const normalized = cleaned.includes(",") ? cleaned.replace(/\./g, "").replace(",", ".") : cleaned;
  const n = Number(normalized);
  return Number.isFinite(n) ? n : null;
}

/** Decodifica tollerante: campi mancanti, importi scritti come testo («1.234,56»). */
export function normalizeFields(raw) {
  const o = raw && typeof raw === "object" ? raw : {};
  const f = { ...EMPTY_FIELDS, leavePeriods: [], eventIds: [] };
  TEXT_KEYS.forEach((k) => { f[k] = typeof o[k] === "string" ? o[k] : ""; });
  NUM_KEYS.forEach((k) => { f[k] = toNumber(o[k]); });
  f.startDate = typeof o.startDate === "string" && o.startDate ? o.startDate.slice(0, 10) : null;
  f.endDate = typeof o.endDate === "string" && o.endDate ? o.endDate.slice(0, 10) : null;
  f.leavePeriods = (Array.isArray(o.leavePeriods) ? o.leavePeriods : [])
    .map((p) => {
      const start = String(p?.start || "").slice(0, 10);
      const end = String(p?.end || "").slice(0, 10) || start;
      return {
        id: crypto.randomUUID(),
        start, end, label: typeof p?.label === "string" ? p.label : "",
        inCalendar: p?.inCalendar === true,
        eventId: typeof p?.eventId === "string" && p.eventId ? p.eventId : null,
      };
    });
  f.eventIds = (Array.isArray(o.eventIds) ? o.eventIds : []).filter((x) => typeof x === "string" && x);
  return f;
}

/** JSON con le stesse chiavi di iOS e Android: ciò che è vuoto si omette. */
export function fieldsToJson(f) {
  const o = {};
  TEXT_KEYS.forEach((k) => { if (f[k]) o[k] = f[k]; });
  NUM_KEYS.forEach((k) => { if (f[k] !== null && f[k] !== undefined) o[k] = f[k]; });
  if (f.startDate) o.startDate = f.startDate;
  if (f.endDate) o.endDate = f.endDate;
  if (f.leavePeriods?.length) {
    o.leavePeriods = f.leavePeriods.map((p) => {
      const out = { start: p.start, end: p.end, label: p.label, inCalendar: !!p.inCalendar };
      if (p.eventId) out.eventId = p.eventId;
      return out;
    });
  }
  if (f.eventIds?.length) o.eventIds = f.eventIds;
  return JSON.stringify(o);
}

export const parseDay = (s) => {
  if (!s || s.length < 10) return null;
  const [y, m, d] = s.slice(0, 10).split("-").map(Number);
  if (!y || !m || !d) return null;
  return new Date(y, m - 1, d);
};
export const formatDay = (date) => {
  const p = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())}`;
};

/** «Ferie» per le ferie (anche la sigla PAR del foglio), mai una sigla da sola. */
export function cleanLabel(raw, labels) {
  const t = String(raw || "").trim();
  switch (t.toLowerCase()) {
    case "": case "par": case "fer": case "f": case "ferie": return labels.leave;
    case "rol": return labels.rol;
    case "mal": case "m": return labels.sick;
    default: return t.charAt(0).toUpperCase() + t.slice(1);
  }
}

// ── Ascolto ──────────────────────────────────────────────────────────────

/**
 * Avvia i tre ascolti vincolati. Chiama `onChange({profiles, records})` a ogni
 * variazione, con i valori già decifrati (`fields: null` = blob che non si apre).
 * Ritorna la funzione che li ferma.
 */
export function listenWork({ familyId, userId, onChange, onError }) {
  let stopped = false;
  const profilesMap = new Map();      // ownerUid → profilo grezzo
  const recordsByOwner = new Map();   // ownerUid → [record decifrati]
  const recordUnsubs = new Map();
  let sharedIds = new Set();
  let keyPromise = null;
  let emitSeq = 0;

  const key = () => {
    keyPromise ||= loadFamilyKey({ familyId, userId });
    return keyPromise;
  };
  const fail = (err) => { if (!stopped) onError?.(err); };

  async function openFields(d) {
    if (!d.fieldsEnc) return normalizeFields({});
    try {
      const json = await decryptString(d.fieldsEnc, await key());
      return normalizeFields(JSON.parse(json));
    } catch {
      return null;
    }
  }

  async function emit() {
    const seq = ++emitSeq;
    const profiles = await Promise.all(
      [...profilesMap.values()].map(async (p) => {
        let employer = "";
        try { employer = p.employerEnc ? await decryptString(p.employerEnc, await key()) : ""; } catch { employer = ""; }
        return { ...p, employer };
      })
    );
    if (stopped || seq !== emitSeq) return;
    onChange({ profiles, records: [...recordsByOwner.values()].flat() });
  }

  function profileOf(snap) {
    const d = snap.data();
    return {
      ownerUid: snap.id,
      employerEnc: d.employerEnc || null,
      visibilityScope: d.visibilityScope === "members" ? "members" : "private",
      visibilityMemberIds: Array.isArray(d.visibilityMemberIds) ? d.visibilityMemberIds : [],
      createdByName: d.createdByName || "",
      updatedAt: millis(d.updatedAt),
    };
  }

  function attachRecords(ownerUid) {
    if (recordUnsubs.has(ownerUid)) return;
    const unsub = onSnapshot(
      query(recordsCol(familyId), where("ownerUid", "==", ownerUid)),
      async (snap) => {
        const list = await Promise.all(
          snap.docs
            .filter((s) => s.data().isDeleted !== true)
            .map(async (s) => {
              const d = s.data();
              return {
                id: s.id,
                ownerUid: d.ownerUid || ownerUid,
                kind: d.kind || WORK_KIND.PAYSLIP,
                referenceDate: millis(d.referenceDate) ?? millis(d.createdAt) ?? Date.now(),
                attachmentDocumentId: d.attachmentDocumentId || null,
                createdByName: d.createdByName || "",
                updatedAt: millis(d.updatedAt),
                fields: await openFields(d),
              };
            })
        );
        if (stopped) return;
        recordsByOwner.set(ownerUid, list);
        emit();
      },
      fail
    );
    recordUnsubs.set(ownerUid, unsub);
  }

  function dropOwner(ownerUid) {
    recordUnsubs.get(ownerUid)?.();
    recordUnsubs.delete(ownerUid);
    recordsByOwner.delete(ownerUid);
    profilesMap.delete(ownerUid);
  }

  attachRecords(userId);

  const unsubOwn = onSnapshot(
    doc(profilesCol(familyId), userId),
    (snap) => {
      if (snap.exists() && snap.data().isDeleted !== true) profilesMap.set(userId, profileOf(snap));
      else profilesMap.delete(userId);
      emit();
    },
    fail
  );

  const unsubShared = onSnapshot(
    query(profilesCol(familyId), where("visibilityMemberIds", "array-contains", userId)),
    (snap) => {
      const next = new Set();
      snap.docs.forEach((s) => {
        if (s.id === userId || s.data().isDeleted === true) return;
        next.add(s.id);
        profilesMap.set(s.id, profileOf(s));
        attachRecords(s.id);
      });
      // Il proprietario ha smesso di condividere: via scheda e documenti in cache.
      sharedIds.forEach((id) => { if (!next.has(id)) dropOwner(id); });
      sharedIds = next;
      emit();
    },
    fail
  );

  return () => {
    stopped = true;
    unsubOwn();
    unsubShared();
    recordUnsubs.forEach((u) => u());
  };
}

// ── Scritture ────────────────────────────────────────────────────────────

/** La mia scheda: la crea (privata) se non c'è. */
export async function ensureProfile({ familyId, userId, name }) {
  const ref = doc(profilesCol(familyId), userId);
  const snap = await getDoc(ref);
  if (snap.exists()) return;
  await setDoc(ref, {
    schemaVersion: 1,
    ownerUid: userId,
    visibilityScope: "private",
    visibilityMemberIds: [],
    isDeleted: false,
    createdAt: serverTimestamp(),
    createdBy: userId,
    createdByName: name,
    updatedAt: serverTimestamp(),
    updatedBy: userId,
    updatedByName: name,
  });
}

export async function setEmployerIfMissing({ familyId, userId, name, employer }) {
  if (!employer) return;
  const ref = doc(profilesCol(familyId), userId);
  const snap = await getDoc(ref);
  if (!snap.exists() || snap.data().employerEnc) return;
  await setDoc(ref, {
    employerEnc: await encryptString(employer, await loadFamilyKey({ familyId, userId })),
    updatedAt: serverTimestamp(), updatedBy: userId, updatedByName: name,
  }, { merge: true });
}

/** Condivisione: `memberIds` vuoto = solo io. I file seguono la scheda. */
export async function setSharing({ familyId, userId, name, memberIds }) {
  await ensureProfile({ familyId, userId, name });
  const ids = [...new Set(memberIds.filter((id) => id !== userId))].sort();
  const sharing = ids.length > 0;
  await setDoc(doc(profilesCol(familyId), userId), {
    visibilityScope: sharing ? "members" : "private",
    // Autorevole per le rules: tornando privata la lista si svuota.
    visibilityMemberIds: sharing ? ids : [],
    updatedAt: serverTimestamp(), updatedBy: userId, updatedByName: name,
  }, { merge: true });
  await syncAttachmentVisibility({ familyId, userId, memberIds: ids });
}

/** I file di Lavoro seguono la scheda: condivisa, il file la segue; tornata privata, torna privato. */
async function syncAttachmentVisibility({ familyId, userId, memberIds }) {
  const tag = `work:${userId}`;
  const snap = await getDocs(query(documentsCol(familyId), where("notes", "==", tag)));
  await Promise.all(
    snap.docs
      .filter((d) => d.data().isDeleted !== true)
      .map((d) =>
        updateDocumentVisibility({
          familyId, userId, documentId: d.id,
          visibilityScope: memberIds.length ? "members" : "private",
          visibilityMemberIds: memberIds,
        })
      )
  );
}

/** Crea (`recordId` assente) o aggiorna un documento. Cifra prima di scrivere. */
export async function saveRecord({ familyId, userId, name, recordId, kind, referenceDate, fields, attachmentDocumentId }) {
  const key = await loadFamilyKey({ familyId, userId });
  const fieldsEnc = await encryptString(fieldsToJson(fields), key);
  const id = recordId || crypto.randomUUID();
  const data = {
    schemaVersion: 1,
    ownerUid: userId,
    kind,
    referenceDate: Timestamp.fromDate(referenceDate),
    fieldsEnc,
    isDeleted: false,
    updatedAt: serverTimestamp(),
    updatedBy: userId,
    updatedByName: name,
  };
  if (attachmentDocumentId) data.attachmentDocumentId = attachmentDocumentId;
  if (!recordId) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
    data.createdByName = name;
  }
  await setDoc(doc(recordsCol(familyId), id), data, { merge: true });
  return id;
}

/** Il tombstone svuota i campi cifrati: un documento cancellato non porta con sé i valori. */
export async function deleteRecord({ familyId, userId, record }) {
  if (record.kind === WORK_KIND.LEAVE_PLAN && record.fields) {
    const ids = new Set([...record.fields.eventIds, ...record.fields.leavePeriods.map((p) => p.eventId).filter(Boolean)]);
    await Promise.all([...ids].map((id) => removeEvent({ familyId, userId, eventId: id })));
  }
  if (record.attachmentDocumentId) {
    await softDeleteDocument({ familyId, userId, documentId: record.attachmentDocumentId }).catch(() => {});
  }
  await setDoc(doc(recordsCol(familyId), record.id), {
    isDeleted: true,
    fieldsEnc: deleteField(),
    attachmentDocumentId: deleteField(),
    updatedAt: serverTimestamp(),
    updatedBy: userId,
  }, { merge: true });
}

// ── File originale ───────────────────────────────────────────────────────

/** Carica il file e ritorna l'id del documento (con la visibilità della scheda). */
export async function uploadWorkFile({ familyId, userId, file, sharedWith, folderTitle }) {
  await ensureFolder({ familyId, userId, id: workFolderId(familyId), title: folderTitle });
  const sharing = sharedWith.length > 0;
  return uploadDocument({
    familyId, userId, file,
    categoryId: workFolderId(familyId),
    notes: `work:${userId}`,
    visibilityScope: sharing ? "members" : "private",
    visibilityMemberIds: sharing ? sharedWith : [],
  });
}

export async function openWorkFile({ familyId, userId, documentId }) {
  const snap = await getDoc(doc(documentsCol(familyId), documentId));
  if (!snap.exists()) throw new Error("File non disponibile");
  return fetchDocumentBlob({ familyId, userId, document: { ...snap.data(), id: snap.id } });
}

// ── Eventi del foglio ferie ──────────────────────────────────────────────

const eventTitle = (p, ownerName, labels) => `${cleanLabel(p.label, labels)} - ${ownerName}`;

/** Il calendario chiude i tutto-il-giorno alle 23:59:59 dell'ultimo giorno. */
function eventSpan(p) {
  const first = parseDay(p.start);
  if (!first) return null;
  const last = parseDay(p.end) && parseDay(p.end) >= first ? parseDay(p.end) : first;
  const start = new Date(first.getFullYear(), first.getMonth(), first.getDate(), 0, 0, 0, 0);
  const end = new Date(last.getFullYear(), last.getMonth(), last.getDate(), 23, 59, 59, 0);
  return { start, end };
}

async function writeEvent({ familyId, userId, eventId, title, span, isNew }) {
  const payload = {
    id: eventId,
    familyId,
    title,
    isAllDay: true,
    categoryRaw: "family",
    recurrenceRaw: "none",
    isDeleted: false,
    startDate: Timestamp.fromDate(span.start),
    endDate: Timestamp.fromDate(span.end),
    location: null,
    notes: null,
    reminderMinutes: null,
    priority: 0,
    updatedAt: serverTimestamp(),
    updatedBy: userId,
    visibilityScope: "family",
    visibilityMemberIds: [],
  };
  if (isNew) {
    payload.createdAt = serverTimestamp();
    payload.createdBy = userId;
  }
  await setDoc(doc(eventsCol(familyId), eventId), payload, { merge: true });
}

async function removeEvent({ familyId, userId, eventId }) {
  await setDoc(doc(eventsCol(familyId), eventId), {
    isDeleted: true, updatedAt: serverTimestamp(), updatedBy: userId,
  }, { merge: true });
}

async function eventExists(familyId, eventId) {
  const snap = await getDoc(doc(eventsCol(familyId), eventId));
  return snap.exists() && snap.data().isDeleted !== true ? snap : null;
}

/** Crea gli eventi dei periodi accesi che non ne hanno ancora uno. */
export async function createLeaveEvents({ familyId, userId, ownerName, periods, labels }) {
  const out = [];
  for (const p of periods) {
    if (!p.inCalendar || p.eventId) { out.push(p); continue; }
    const span = eventSpan(p);
    if (!span) { out.push(p); continue; }
    const eventId = crypto.randomUUID();
    await writeEvent({ familyId, userId, eventId, title: eventTitle(p, ownerName, labels), span, isNew: true });
    out.push({ ...p, eventId });
  }
  return out;
}

/**
 * I fogli scritti prima che ogni periodo ricordasse il suo evento: lo si ritrova
 * dalle date fra gli eventi elencati in `eventIds`, così l'interruttore mostra
 * il vero stato e si può revocare.
 */
export async function linkLegacyEvents({ familyId, fields }) {
  if (!fields.eventIds.length || fields.leavePeriods.every((p) => p.eventId)) return fields;
  const events = (await Promise.all(fields.eventIds.map((id) => eventExists(familyId, id)))).filter(Boolean);
  const claimed = new Set(fields.leavePeriods.map((p) => p.eventId).filter(Boolean));
  const sameDay = (a, b) => a.toDateString() === b.toDateString();
  const periods = fields.leavePeriods.map((p) => {
    if (p.eventId) return p;
    const span = eventSpan(p);
    if (!span) return p;
    const ev = events.find((e) => !claimed.has(e.id)
      && sameDay(e.data().startDate.toDate(), span.start) && sameDay(e.data().endDate.toDate(), span.end));
    if (!ev) return p;
    claimed.add(ev.id);
    return { ...p, eventId: ev.id, inCalendar: true };
  });
  return { ...fields, leavePeriods: periods };
}

/**
 * Dopo una modifica: un periodo acceso e già in calendario si sposta, uno acceso
 * e nuovo si crea, uno spento o tolto si revoca dal calendario.
 */
export async function reconcileLeaveEvents({ familyId, userId, ownerName, base, fields, labels }) {
  const kept = new Set(fields.leavePeriods.map((p) => p.id));
  for (const p of base?.leavePeriods || []) {
    if (!kept.has(p.id) && p.eventId) await removeEvent({ familyId, userId, eventId: p.eventId });
  }
  const updated = [];
  for (const p of fields.leavePeriods) {
    if (p.inCalendar) {
      const exists = p.eventId ? await eventExists(familyId, p.eventId) : null;
      const span = eventSpan(p);
      if (exists && span) {
        await writeEvent({ familyId, userId, eventId: p.eventId, title: eventTitle(p, ownerName, labels), span, isNew: false });
        updated.push(p);
      } else {
        updated.push({ ...p, eventId: null });   // l'evento non c'è più: si ricrea
      }
    } else {
      if (p.eventId) await removeEvent({ familyId, userId, eventId: p.eventId });
      updated.push({ ...p, eventId: null });
    }
  }
  const withNew = await createLeaveEvents({ familyId, userId, ownerName, periods: updated, labels });
  return { ...fields, leavePeriods: withNew, eventIds: withNew.map((p) => p.eventId).filter(Boolean) };
}

// ── Lettura AI ───────────────────────────────────────────────────────────

const MAX_PAGES = 3;
const MAX_IMAGE_SIDE = 1600;

function canvasToJpegBase64(canvas) {
  const url = canvas.toDataURL("image/jpeg", 0.6);
  return url.slice(url.indexOf(",") + 1);
}

function drawScaled(source, width, height) {
  const scale = Math.min(1, MAX_IMAGE_SIDE / Math.max(width, height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(width * scale));
  canvas.height = Math.max(1, Math.round(height * scale));
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = "#fff";
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.drawImage(source, 0, 0, canvas.width, canvas.height);
  return canvas;
}

/** Pagine del documento come JPEG base64: al massimo 3 (ogni pagina = 1 messaggio AI). */
async function renderPages(file) {
  const isPdf = file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf");
  if (!isPdf) {
    const bitmap = await createImageBitmap(file);
    return [canvasToJpegBase64(drawScaled(bitmap, bitmap.width, bitmap.height))];
  }
  const pdfjs = await import("pdfjs-dist");
  pdfjs.GlobalWorkerOptions.workerSrc = (await import("pdfjs-dist/build/pdf.worker.min.mjs?url")).default;
  const pdf = await pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) }).promise;
  const pages = [];
  for (let i = 1; i <= Math.min(pdf.numPages, MAX_PAGES); i += 1) {
    const page = await pdf.getPage(i);
    const base = page.getViewport({ scale: 1 });
    const scale = Math.min(MAX_IMAGE_SIDE / Math.max(base.width, base.height), 2);
    const viewport = page.getViewport({ scale });
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(viewport.width);
    canvas.height = Math.round(viewport.height);
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#fff";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    await page.render({ canvasContext: ctx, viewport }).promise;
    pages.push(canvasToJpegBase64(canvas));
  }
  return pages;
}

const SYSTEM_PROMPT = `Sei l'assistente di KidBox. Leggi un documento di lavoro (immagini delle pagine) e ne estrai i valori. Rispondi ESCLUSIVAMENTE con un oggetto JSON valido (nessun testo prima o dopo, niente markdown, niente \`\`\`), con questa forma:
{
  "kind": "payslip|contract|leavePlan|other",
  "referenceDate": "yyyy-MM-dd",
  "fields": {
    "title": "titolo breve, es. Busta paga settembre 2026 / Contratto a tempo indeterminato",
    "employer": "datore di lavoro",
    "period": "mese di competenza della busta paga, es. Settembre 2026",
    "gross": 0, "net": 0, "taxes": 0, "contributions": 0,
    "vacationAccrued": 0, "vacationTaken": 0, "vacationRemaining": 0,
    "permitHoursAccrued": 0, "permitHoursRemaining": 0, "tfr": 0,
    "contractType": "tempo indeterminato|tempo determinato|apprendistato|partita IVA|altro",
    "startDate": "yyyy-MM-dd", "endDate": "yyyy-MM-dd",
    "grossAnnual": 0, "level": "livello e/o CCNL", "noticePeriod": "preavviso",
    "vacationDaysPerYear": 0, "notes": "altro di rilevante",
    "leavePeriods": [{"start": "yyyy-MM-dd", "end": "yyyy-MM-dd", "label": "Ferie|Permesso|ROL|Malattia|altro"}]
  }
}

REGOLE:
- "payslip" = busta paga / cedolino; "contract" = contratto di lavoro o lettera di assunzione/proroga; "leavePlan" = foglio, piano o calendario delle ferie e dei permessi con date precise; altro documento → "other" con "fields": {}.
- NON INVENTARE. Se un valore non c'è nel documento OMETTI il campo: niente zeri di ripiego.
- Importi come numeri con il punto decimale, in euro, senza simbolo. "gross" = totale competenze lorde del mese; "net" = netto in busta; "taxes" = IRPEF e addizionali trattenute nel mese; "contributions" = contributi previdenziali a carico del lavoratore (INPS).
- Ferie in GIORNI (o in ORE se così è scritto: in tal caso convertile solo se il documento dice quante ore valgono un giorno, altrimenti riporta il numero e scrivilo in "notes"). "vacationRemaining" è il saldo residuo, "vacationAccrued" quanto maturato nel periodo o nell'anno, "vacationTaken" il goduto.
- Permessi (ROL, ex festività) in ORE: "permitHoursRemaining" è il saldo residuo.
- "leavePlan": in "leavePeriods" metti SOLO i giorni di assenza segnati nel documento, uno per periodo; raggruppa i giorni consecutivi in un solo periodo (start = primo giorno, end = ultimo), un giorno solo ha start = end. Non aggiungere giorni non segnati, non includere festivi o weekend che non sono indicati. Se manca l'anno, usa quello più probabile dal contesto del documento. "label" è il tipo di assenza come scritto ma in italiano esteso: una sigla va sciolta (PAR → «Ferie», ROL → «Permesso (ROL)», FER → «Ferie», MAL → «Malattia»); mai una sigla da sola. "referenceDate" è l'inizio del primo periodo; "title" es. «Ferie 2026».
- "referenceDate": per la busta paga il primo giorno del mese di competenza; per il contratto la data di inizio. Date in formato yyyy-MM-dd.
- Non dare giudizi né consigli: estrai solo ciò che è scritto.`;

export class NotAWorkDocumentError extends Error {}
export class UnreadableDocumentError extends Error {}
export class BadResponseError extends Error {}

/** Legge un file (PDF o immagine) e ne estrae i valori. L'unico punto in cui parte la lettura (e il messaggio AI). */
export async function analyzeWorkDocument({ familyId, file, labels }) {
  let pages;
  try {
    pages = await renderPages(file);
  } catch {
    throw new UnreadableDocumentError();
  }
  if (!pages.length) throw new UnreadableDocumentError();

  const content = [
    ...pages.map((data) => ({ type: "image", source: { type: "base64", media_type: "image/jpeg", data } })),
    { type: "text", text: `File: ${file.name}. Leggi il documento e rispondi con il JSON richiesto.` },
  ];
  const { reply } = await askAssistant({
    messages: [{ role: "user", content }],
    systemPrompt: SYSTEM_PROMPT,
    familyId,
    purpose: "workDoc",
  });

  let text = reply.trim();
  if (text.startsWith("```")) {
    text = text.slice(text.indexOf("\n") + 1);
    const fence = text.lastIndexOf("```");
    if (fence >= 0) text = text.slice(0, fence);
  }
  const a = text.indexOf("{");
  const b = text.lastIndexOf("}");
  if (a < 0 || b <= a) throw new BadResponseError();
  let root;
  try { root = JSON.parse(text.slice(a, b + 1)); } catch { throw new BadResponseError(); }

  const kind = root.kind;
  if (![WORK_KIND.PAYSLIP, WORK_KIND.CONTRACT, WORK_KIND.LEAVE_PLAN].includes(kind) || !root.fields) {
    throw new NotAWorkDocumentError();
  }
  let fields = normalizeFields(root.fields);
  if (kind === WORK_KIND.LEAVE_PLAN) {
    // In bozza ogni periodo parte con «Aggiungi al calendario» acceso: lo spegne chi non lo vuole.
    const periods = fields.leavePeriods
      .filter((p) => parseDay(p.start))
      .sort((x, y) => parseDay(x.start) - parseDay(y.start))
      .map((p) => ({ ...p, inCalendar: true, label: cleanLabel(p.label, labels) }));
    if (!periods.length) throw new NotAWorkDocumentError();
    fields = { ...fields, leavePeriods: periods };
  }
  const referenceDate = parseDay(root.referenceDate)
    || parseDay(fields.leavePeriods[0]?.start)
    || parseDay(fields.startDate)
    || new Date();
  return { kind, fields, referenceDate };
}

// ── Lettura una tantum (quaderno dell'assistente) ────────────────────────

/**
 * Le schede visibili a chi chiede (la sua e quelle condivise con lui) e i loro
 * documenti, già decifrati: stesse query vincolate dei listener, una volta sola.
 */
export async function loadWorkSnapshot({ familyId, userId }) {
  const key = await loadFamilyKey({ familyId, userId }).catch(() => null);
  const opened = async (enc) => {
    if (!enc || !key) return null;
    try { return await decryptString(enc, key); } catch { return null; }
  };
  const profiles = [];
  const own = await getDoc(doc(profilesCol(familyId), userId)).catch(() => null);
  if (own?.exists() && own.data().isDeleted !== true) profiles.push({ id: own.id, ...own.data() });
  const shared = await getDocs(
    query(profilesCol(familyId), where("visibilityMemberIds", "array-contains", userId))
  ).catch(() => null);
  shared?.docs.forEach((d) => {
    if (d.id !== userId && d.data().isDeleted !== true) profiles.push({ id: d.id, ...d.data() });
  });
  const owners = profiles.map((p) => p.id);
  if (!owners.includes(userId)) owners.unshift(userId);
  const out = { profiles: [], records: [] };
  for (const p of profiles) {
    out.profiles.push({ ownerUid: p.id, employer: (await opened(p.employerEnc)) || "" });
  }
  for (const ownerUid of owners) {
    const snap = await getDocs(query(recordsCol(familyId), where("ownerUid", "==", ownerUid))).catch(() => null);
    for (const s of snap?.docs || []) {
      const d = s.data();
      if (d.isDeleted === true) continue;
      const json = await opened(d.fieldsEnc);
      let fields = null;
      try { fields = json ? normalizeFields(JSON.parse(json)) : null; } catch { fields = null; }
      out.records.push({
        id: s.id, ownerUid, kind: d.kind || WORK_KIND.PAYSLIP,
        referenceDate: millis(d.referenceDate) ?? millis(d.createdAt) ?? Date.now(), fields,
      });
    }
  }
  return out;
}
