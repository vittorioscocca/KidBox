/**
 * Salute, allineato agli store nativi di iOS e Android.
 *
 * Le collezioni vivono sotto `families/{familyId}` e viaggiano **in chiaro**,
 * come sui client nativi: cifrarle solo qui le renderebbe illeggibili sul
 * telefono. L'eliminazione è sempre `isDeleted: true` (soft delete), perché è
 * quello che i listener nativi si aspettano di trovare.
 *
 *   medicalVisits      → `VisitRemoteStore`
 *   medicalExams       → `MedicalExamRemoteStore`
 *   treatments         → `TreatmentRemoteStore`
 *   doseLogs           → `TreatmentRemoteStore` (log delle dosi assunte)
 *   vaccines           → `VaccineRemoteStore`
 *   pediatricProfiles  → `PediatricProfileRemoteStore` (id documento = childId)
 *
 * Il «soggetto» della sezione è un `childId` che vale sia per un bambino
 * (`families/{id}/children`) sia per un membro adulto (il suo `userId`): è la
 * stessa convenzione di `PediatricHomeView`, dove `childId` è l'id universale.
 *
 * I promemoria locali (`reminderOn`, `reminderEnabled`) restano campi di
 * trasporto: il web non arma notifiche, ma non deve nemmeno spegnere quelle
 * armate dal telefono, quindi il valore letto viene riscritto invariato.
 */
import {
  collection,
  doc,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  where,
} from "firebase/firestore";
import { db } from "../firebase";

/* ── Riferimenti alle collezioni ─────────────────────────────────────────── */

const col = (familyId, name) => collection(db, "families", familyId, name);

const visitsCol = (familyId) => col(familyId, "medicalVisits");
const examsCol = (familyId) => col(familyId, "medicalExams");
const treatmentsCol = (familyId) => col(familyId, "treatments");
const doseLogsCol = (familyId) => col(familyId, "doseLogs");
const vaccinesCol = (familyId) => col(familyId, "vaccines");
const profilesCol = (familyId) => col(familyId, "pediatricProfiles");

/* ── Tassonomie, con i `rawValue` esatti dei client nativi ───────────────── */

/**
 * `raw` è il valore persistito: non va tradotto né normalizzato, altrimenti i
 * record scritti dal telefono non verrebbero più riconosciuti.
 */
/* ── Allegati ───────────────────────────────────────────────────────────── */

/**
 * Tag su `notes` dei documenti allegati, identici a `VisitAttachmentTag`,
 * `ExamAttachmentTag` e `TreatmentAttachmentTag` su iOS: lo stesso referto si
 * vede dal telefono e da qui.
 */
export const visitTag = (id) => `visit:${id}`;
export const examTag = (id) => `exam:${id}`;
export const treatmentTag = (id) => `treatment:${id}`;
export const HEALTH_ATTACHMENT_PREFIXES = ["visit:", "exam:", "treatment:"];

export const DOCTOR_SPECIALIZATIONS = [
  { raw: "Pediatra", it: "Pediatra", en: "Pediatrician" },
  { raw: "Medico di Base", it: "Medico di Base", en: "General practitioner" },
  { raw: "Dermatologo", it: "Dermatologo", en: "Dermatologist" },
  { raw: "Ortopedico", it: "Ortopedico", en: "Orthopedist" },
  { raw: "Otorinolaringoiatra", it: "Otorinolaringoiatra", en: "ENT specialist" },
  { raw: "Oculista", it: "Oculista", en: "Ophthalmologist" },
  { raw: "Urologo", it: "Urologo", en: "Urologist" },
  { raw: "Cardiologo", it: "Cardiologo", en: "Cardiologist" },
  { raw: "Altro", it: "Altro", en: "Other" },
];

export const THERAPY_TYPES = [
  { raw: "Riposo", it: "Riposo", en: "Rest" },
  { raw: "Fisioterapia", it: "Fisioterapia", en: "Physiotherapy" },
  { raw: "Dieta", it: "Dieta", en: "Diet" },
  { raw: "Aerosol", it: "Aerosol", en: "Aerosol" },
  { raw: "Altro", it: "Altro", en: "Other" },
];

/**
 * Lo stato visita ha due codifiche: in locale i client usano l'etichetta
 * italiana (`KBVisitStatus.rawValue`), su Firestore il codice inglese. Qui si
 * lavora sempre col codice, e si converte solo in lettura per i documenti
 * storici scritti con l'etichetta.
 */
export const VISIT_STATUSES = [
  { code: "pending", localRaw: "In attesa", it: "In attesa", en: "Pending", color: "#8a8a8e" },
  { code: "booked", localRaw: "Prenotata", it: "Prenotata", en: "Booked", color: "#2E86FF" },
  { code: "completed", localRaw: "Eseguita", it: "Eseguita", en: "Completed", color: "#27AE60" },
  {
    code: "result_available",
    localRaw: "Risultato disponibile",
    it: "Risultato disponibile",
    en: "Result available",
    color: "#8E44AD",
  },
];

export const visitStatusInfo = (code) =>
  VISIT_STATUSES.find((s) => s.code === code) || null;

/** Firestore → codice. Accetta sia il codice inglese sia l'etichetta italiana. */
function visitStatusCode(value) {
  const v = (value || "").trim();
  if (!v) return null;
  const byCode = VISIT_STATUSES.find((s) => s.code === v.toLowerCase());
  if (byCode) return byCode.code;
  const byLabel = VISIT_STATUSES.find((s) => s.localRaw === v);
  return byLabel ? byLabel.code : null;
}

/** Gli esami usano l'etichetta italiana come `statusRaw`, anche su Firestore. */
export const EXAM_STATUSES = [
  { raw: "In attesa", it: "In attesa", en: "Pending", color: "#8a8a8e" },
  { raw: "Prenotato", it: "Prenotato", en: "Booked", color: "#2E86FF" },
  { raw: "Eseguito", it: "Eseguito", en: "Done", color: "#27AE60" },
  { raw: "Risultato disponibile", it: "Risultato disponibile", en: "Result available", color: "#8E44AD" },
];

export const examStatusInfo = (raw) =>
  EXAM_STATUSES.find((s) => s.raw === raw) || EXAM_STATUSES[0];

export const VACCINE_TYPES = [
  { raw: "esavalente", it: "Esavalente", en: "Hexavalent" },
  { raw: "pneumococco", it: "Pneumococco", en: "Pneumococcal" },
  { raw: "meningococcoB", it: "Meningococco B", en: "Meningococcal B" },
  { raw: "mpr", it: "MPR", en: "MMR" },
  { raw: "varicella", it: "Varicella", en: "Chickenpox" },
  { raw: "meningococcoACWY", it: "Meningococco ACWY", en: "Meningococcal ACWY" },
  { raw: "hpv", it: "HPV", en: "HPV" },
  { raw: "influenza", it: "Influenza", en: "Flu" },
  { raw: "altro", it: "Altro", en: "Other" },
];

export const vaccineTypeInfo = (raw) =>
  VACCINE_TYPES.find((v) => v.raw === raw) || VACCINE_TYPES[VACCINE_TYPES.length - 1];

export const VACCINE_STATUSES = [
  { raw: "administered", it: "Somministrato", en: "Administered", color: "#27AE60" },
  { raw: "scheduled", it: "Appuntamento fissato", en: "Scheduled", color: "#2E86FF" },
  { raw: "planned", it: "Da programmare", en: "To plan", color: "#E0913A" },
];

export const vaccineStatusInfo = (raw) =>
  VACCINE_STATUSES.find((v) => v.raw === raw) || VACCINE_STATUSES[VACCINE_STATUSES.length - 1];

/** Sedi di somministrazione, con gli stessi `raw` del telefono. */
export const ADMINISTRATION_SITES = [
  { raw: "braccio_sx", it: "Braccio sinistro", en: "Left arm" },
  { raw: "braccio_dx", it: "Braccio destro", en: "Right arm" },
  { raw: "coscia_sx", it: "Coscia sinistra", en: "Left thigh" },
  { raw: "coscia_dx", it: "Coscia destra", en: "Right thigh" },
  { raw: "gluteo", it: "Gluteo", en: "Buttock" },
  { raw: "orale", it: "Orale", en: "Oral" },
];

export const DOSAGE_UNITS = ["ml", "mg", "gocce", "compresse", "bustine", "puff", "UI"];

export const BLOOD_GROUPS = ["0-", "0+", "A-", "A+", "B-", "B+", "AB-", "AB+"];

export const WEEKDAYS_IT = [
  "Lunedì",
  "Martedì",
  "Mercoledì",
  "Giovedì",
  "Venerdì",
  "Sabato",
  "Domenica",
];

/* ── Helper di lettura/scrittura ─────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : typeof ts === "number" ? ts : null);
const tsOrNull = (v) => (v ? Timestamp.fromMillis(v) : null);
const trimmed = (v) => {
  const s = (v ?? "").toString().trim();
  return s.length > 0 ? s : null;
};
const num = (v) => (typeof v === "number" && Number.isFinite(v) ? v : null);

/**
 * Array di stringhe da Firestore. Android scrive anche una copia JSON in un
 * campo `*Json`: se l'array nativo manca si legge quella, come fa iOS.
 */
function readStringArray(data, arrayKey, jsonKey) {
  const arr = data[arrayKey];
  if (Array.isArray(arr)) {
    const mapped = arr.filter((x) => typeof x === "string");
    if (mapped.length > 0) return mapped;
  }
  const json = data[jsonKey];
  if (typeof json === "string") {
    try {
      const parsed = JSON.parse(json);
      if (Array.isArray(parsed)) return parsed.filter((x) => typeof x === "string");
    } catch {
      return [];
    }
  }
  return [];
}

const jsonArray = (values) => JSON.stringify(values || []);

/** Oggetti annidati: iOS li salva base64 (`*Data`) e in chiaro (`*Json`). */
function readJsonField(data, jsonKey, base64Key) {
  const json = data[jsonKey];
  if (typeof json === "string" && json.trim()) {
    try {
      const parsed = JSON.parse(json);
      if (Array.isArray(parsed)) return parsed;
      if (parsed && typeof parsed === "object") return parsed;
    } catch {
      /* passa al base64 */
    }
  }
  const b64 = data[base64Key];
  if (typeof b64 === "string" && b64.trim()) {
    try {
      return JSON.parse(atob(b64));
    } catch {
      return null;
    }
  }
  return null;
}

/** Controparte di `readJsonField`: scrive entrambe le codifiche. */
function writeJsonField(target, value, jsonKey, base64Key) {
  const isEmpty =
    value == null || (Array.isArray(value) && value.length === 0);
  if (isEmpty) {
    target[jsonKey] = null;
    target[base64Key] = null;
    return;
  }
  const json = JSON.stringify(value);
  target[jsonKey] = json;
  // `btoa` non regge i caratteri accentati: si passa da UTF-8 come fa `Data`.
  target[base64Key] = btoa(
    Array.from(new TextEncoder().encode(json))
      .map((b) => String.fromCharCode(b))
      .join("")
  );
}

const newId = () =>
  typeof crypto !== "undefined" && crypto.randomUUID
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

/**
 * Ascolto generico su una collezione di famiglia filtrata per soggetto.
 *
 * Il filtro `isDeleted` resta lato client: combinarlo con `childId` nella query
 * funziona, ma qui i volumi sono piccoli e così non si dipende da indici.
 */
function listenSubjectCollection({ ref, childId, read, sort, onChange, onError }) {
  return onSnapshot(
    query(ref, where("childId", "==", childId)),
    (snap) => {
      const rows = snap.docs
        .map(read)
        .filter((r) => !r.isDeleted)
        .sort(sort);
      onChange(rows);
    },
    (err) => onError?.(err)
  );
}

/* ── Visite mediche ──────────────────────────────────────────────────────── */

function readVisit(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    childId: d.childId || "",
    date: millis(d.date),
    doctorName: d.doctorName || null,
    doctorSpecialization: d.doctorSpecializationRaw || d.doctorSpecialization || null,
    reason: d.reason || "",
    diagnosis: d.diagnosis || null,
    recommendations: d.recommendations || null,
    linkedTreatmentIds: readStringArray(d, "linkedTreatmentIds", "linkedTreatmentIdsJson"),
    linkedExamIds: readStringArray(d, "linkedExamIds", "linkedExamIdsJson"),
    therapyTypes: readStringArray(d, "therapyTypesRaw", "therapyTypesJson"),
    photoURLs: readStringArray(d, "photoURLs", "photoUrlsJson"),
    asNeededDrugs: readJsonField(d, "asNeededDrugsJson", "asNeededDrugsData") || [],
    prescribedExams: readJsonField(d, "prescribedExamsJson", "prescribedExamsData") || [],
    travelDetails: readJsonField(d, "travelDetailsJson", "travelDetailsData") || null,
    notes: d.notes || null,
    cost: num(d.cost),
    linkedExpenseId: d.linkedExpenseId || null,
    nextVisitDate: millis(d.nextVisitDate),
    nextVisitReason: d.nextVisitReason || null,
    visitStatus: visitStatusCode(d.visitStatus),
    reminderOn: Boolean(d.reminderOn),
    nextVisitReminderOn: Boolean(d.nextVisitReminderOn),
    isDeleted: Boolean(d.isDeleted),
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
  };
}

export function listenVisits({ familyId, childId, onChange, onError }) {
  return listenSubjectCollection({
    ref: visitsCol(familyId),
    childId,
    read: readVisit,
    sort: (a, b) => (b.date || 0) - (a.date || 0),
    onChange,
    onError,
  });
}

export async function saveVisit({ familyId, userId, childId, visit }) {
  const id = visit.id || newId();
  const data = {
    familyId,
    childId,
    date: tsOrNull(visit.date) || Timestamp.now(),
    reason: visit.reason || "",
    doctorName: trimmed(visit.doctorName),
    doctorSpecializationRaw: trimmed(visit.doctorSpecialization),
    doctorSpecialization: trimmed(visit.doctorSpecialization),
    diagnosis: trimmed(visit.diagnosis),
    recommendations: trimmed(visit.recommendations),
    linkedTreatmentIds: visit.linkedTreatmentIds || [],
    linkedTreatmentIdsJson: jsonArray(visit.linkedTreatmentIds),
    linkedExamIds: visit.linkedExamIds || [],
    linkedExamIdsJson: jsonArray(visit.linkedExamIds),
    therapyTypesRaw: visit.therapyTypes || [],
    therapyTypesJson: jsonArray(visit.therapyTypes),
    photoURLs: visit.photoURLs || [],
    photoUrlsJson: jsonArray(visit.photoURLs),
    notes: trimmed(visit.notes),
    cost: num(visit.cost),
    linkedExpenseId: visit.linkedExpenseId || null,
    nextVisitDate: tsOrNull(visit.nextVisitDate),
    nextVisitReason: trimmed(visit.nextVisitReason),
    visitStatus: visitStatusCode(visit.visitStatus),
    reminderOn: Boolean(visit.reminderOn),
    nextVisitReminderOn: Boolean(visit.nextVisitReminderOn),
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  writeJsonField(data, visit.asNeededDrugs, "asNeededDrugsJson", "asNeededDrugsData");
  writeJsonField(data, visit.prescribedExams, "prescribedExamsJson", "prescribedExamsData");
  writeJsonField(data, visit.travelDetails, "travelDetailsJson", "travelDetailsData");

  if (!visit.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(visitsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteVisit({ familyId, userId, id }) {
  await setDoc(
    doc(visitsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/* ── Analisi ed esami ────────────────────────────────────────────────────── */

function readExam(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    childId: d.childId || "",
    name: d.name || "",
    isUrgent: Boolean(d.isUrgent),
    deadline: millis(d.deadline),
    preparation: d.preparation || null,
    notes: d.notes || null,
    cost: num(d.cost),
    linkedExpenseId: d.linkedExpenseId || null,
    location: d.location || null,
    statusRaw: d.statusRaw || EXAM_STATUSES[0].raw,
    resultText: d.resultText || null,
    resultDate: millis(d.resultDate),
    prescribingVisitId: d.prescribingVisitId || null,
    isDeleted: Boolean(d.isDeleted),
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
  };
}

export function listenExams({ familyId, childId, onChange, onError }) {
  return listenSubjectCollection({
    ref: examsCol(familyId),
    childId,
    read: readExam,
    // Come su iOS: prima le scadenze più vicine, gli esami senza scadenza in fondo.
    sort: (a, b) => (a.deadline || Infinity) - (b.deadline || Infinity),
    onChange,
    onError,
  });
}

export async function saveExam({ familyId, userId, childId, exam }) {
  const id = exam.id || newId();
  const data = {
    // `id` duplicato nel corpo: è quello che `MedicalExamRemoteStore` rilegge.
    id,
    familyId,
    childId,
    name: exam.name || "",
    isUrgent: Boolean(exam.isUrgent),
    deadline: tsOrNull(exam.deadline),
    preparation: trimmed(exam.preparation),
    notes: trimmed(exam.notes),
    cost: num(exam.cost),
    linkedExpenseId: exam.linkedExpenseId || null,
    location: trimmed(exam.location),
    statusRaw: exam.statusRaw || EXAM_STATUSES[0].raw,
    resultText: trimmed(exam.resultText),
    resultDate: tsOrNull(exam.resultDate),
    prescribingVisitId: exam.prescribingVisitId || null,
    isDeleted: false,
    updatedAt: serverTimestamp(),
    updatedBy: userId,
  };
  if (!exam.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(examsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteExam({ familyId, id }) {
  await setDoc(
    doc(examsCol(familyId), id),
    { isDeleted: true, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/* ── Cure ────────────────────────────────────────────────────────────────── */

function readTreatment(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    childId: (d.childId || "").trim(),
    petId: (d.petId || "").trim() || null,
    prescribingVisitId: d.prescribingVisitId || null,
    drugName: d.drugName || "",
    activeIngredient: d.activeIngredient || null,
    dosageValue: typeof d.dosageValue === "number" ? d.dosageValue : 0,
    dosageUnit: d.dosageUnit || "ml",
    isLongTerm: Boolean(d.isLongTerm),
    durationDays: typeof d.durationDays === "number" ? d.durationDays : 1,
    startDate: millis(d.startDate),
    endDate: millis(d.endDate),
    dailyFrequency: typeof d.dailyFrequency === "number" ? d.dailyFrequency : 1,
    intervalBetweenDosesDays:
      typeof d.intervalBetweenDosesDays === "number" ? d.intervalBetweenDosesDays : 0,
    scheduleTimes: Array.isArray(d.scheduleTimes)
      ? d.scheduleTimes.filter((x) => typeof x === "string")
      : [],
    isActive: d.isActive !== false,
    notes: d.notes || null,
    reminderEnabled: Boolean(d.reminderEnabled),
    isDeleted: Boolean(d.isDeleted),
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
  };
}

/**
 * Cure del soggetto. Le righe con `petId` sono cure di un animale e restano
 * fuori: hanno la loro sezione, e il `childId` lì è vuoto.
 */
export function listenTreatments({ familyId, childId, onChange, onError }) {
  return onSnapshot(
    query(treatmentsCol(familyId), where("childId", "==", childId)),
    (snap) => {
      const rows = snap.docs
        .map(readTreatment)
        .filter((t) => !t.isDeleted && !t.petId)
        .sort((a, b) => (b.startDate || 0) - (a.startDate || 0));
      onChange(rows);
    },
    (err) => onError?.(err)
  );
}

export async function saveTreatment({ familyId, userId, childId, treatment }) {
  const id = treatment.id || newId();
  const data = {
    familyId,
    childId,
    drugName: treatment.drugName || "",
    activeIngredient: trimmed(treatment.activeIngredient),
    dosageValue: typeof treatment.dosageValue === "number" ? treatment.dosageValue : 0,
    dosageUnit: treatment.dosageUnit || "ml",
    isLongTerm: Boolean(treatment.isLongTerm),
    durationDays: Math.max(1, Number(treatment.durationDays) || 1),
    startDate: tsOrNull(treatment.startDate) || Timestamp.now(),
    endDate: tsOrNull(treatment.endDate),
    dailyFrequency: Math.max(1, Number(treatment.dailyFrequency) || 1),
    intervalBetweenDosesDays: Math.max(0, Number(treatment.intervalBetweenDosesDays) || 0),
    scheduleTimes: treatment.scheduleTimes || [],
    isActive: treatment.isActive !== false,
    notes: trimmed(treatment.notes),
    // Il promemoria è una notifica locale del telefono: il web lo trasporta e basta.
    reminderEnabled: Boolean(treatment.reminderEnabled),
    prescribingVisitId: treatment.prescribingVisitId || null,
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!treatment.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(treatmentsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteTreatment({ familyId, userId, id }) {
  await setDoc(
    doc(treatmentsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Dosi totali previste, con la stessa formula di `KBTreatment.totalDoses`. */
export function totalDoses(treatment) {
  if (treatment.isLongTerm) return -1;
  if (treatment.intervalBetweenDosesDays > 0) {
    const n = treatment.intervalBetweenDosesDays;
    return Math.max(1, Math.ceil(treatment.durationDays / n));
  }
  return treatment.dailyFrequency * treatment.durationDays;
}

/** `true` se al giorno `offset` (0 = primo) è prevista una dose. */
export function isScheduledDoseDay(treatment, offset) {
  const n = treatment.intervalBetweenDosesDays;
  if (!n || n <= 0) return true;
  return offset >= 0 && offset % n === 0;
}

/* ── Log delle dosi ──────────────────────────────────────────────────────── */

function readDoseLog(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    childId: d.childId || "",
    treatmentId: d.treatmentId || "",
    dayNumber: Number(d.dayNumber) || 0,
    slotIndex: Number(d.slotIndex) || 0,
    scheduledTime: d.scheduledTime || "",
    takenAt: millis(d.takenAt),
    taken: Boolean(d.taken),
    isDeleted: Boolean(d.isDeleted),
  };
}

export function listenDoseLogs({ familyId, childId, onChange, onError }) {
  return onSnapshot(
    query(doseLogsCol(familyId), where("childId", "==", childId)),
    (snap) => onChange(snap.docs.map(readDoseLog).filter((l) => !l.isDeleted)),
    (err) => onError?.(err)
  );
}

/** Stesso id deterministico di `KBDoseLog.stableDocumentId`. */
export const doseLogId = (treatmentId, dayNumber, slotIndex) =>
  `dose_${treatmentId}_${dayNumber}_${slotIndex}`;

export async function setDoseTaken({
  familyId,
  userId,
  childId,
  treatmentId,
  dayNumber,
  slotIndex,
  scheduledTime,
  taken,
}) {
  const id = doseLogId(treatmentId, dayNumber, slotIndex);
  await setDoc(
    doc(doseLogsCol(familyId), id),
    {
      familyId,
      childId,
      treatmentId,
      dayNumber,
      slotIndex,
      scheduledTime: scheduledTime || "",
      taken,
      takenAt: taken ? Timestamp.now() : null,
      isDeleted: false,
      updatedBy: userId,
      updatedAt: serverTimestamp(),
      createdAt: serverTimestamp(),
    },
    { merge: true }
  );
}

/* ── Vaccini ─────────────────────────────────────────────────────────────── */

function readVaccine(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    childId: d.childId || "",
    vaccineTypeRaw: d.vaccineTypeRaw || "altro",
    statusRaw: d.statusRaw || "administered",
    commercialName: d.commercialName || null,
    doseNumber: Number(d.doseNumber) || 1,
    totalDoses: Number(d.totalDoses) || 1,
    administeredDate: millis(d.administeredDate),
    scheduledDate: millis(d.scheduledDate),
    lotNumber: d.lotNumber || null,
    administeredBy: d.administeredBy || null,
    administrationSiteRaw: d.administrationSiteRaw || null,
    notes: d.notes || null,
    reminderOn: Boolean(d.reminderOn),
    nextDoseDate: millis(d.nextDoseDate),
    isDeleted: Boolean(d.isDeleted),
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
  };
}

/** Data di riferimento di un vaccino: somministrazione, appuntamento, o creazione. */
export const vaccineDate = (v) =>
  v.administeredDate || v.scheduledDate || v.createdAt || null;

export function listenVaccines({ familyId, childId, onChange, onError }) {
  return listenSubjectCollection({
    ref: vaccinesCol(familyId),
    childId,
    read: readVaccine,
    sort: (a, b) => (vaccineDate(b) || 0) - (vaccineDate(a) || 0),
    onChange,
    onError,
  });
}

export async function saveVaccine({ familyId, userId, childId, vaccine }) {
  const id = vaccine.id || newId();
  const data = {
    familyId,
    childId,
    vaccineTypeRaw: vaccine.vaccineTypeRaw || "altro",
    statusRaw: vaccine.statusRaw || "administered",
    commercialName: trimmed(vaccine.commercialName),
    doseNumber: Math.max(1, Number(vaccine.doseNumber) || 1),
    totalDoses: Math.max(1, Number(vaccine.totalDoses) || 1),
    administeredDate: tsOrNull(vaccine.administeredDate),
    scheduledDate: tsOrNull(vaccine.scheduledDate),
    lotNumber: trimmed(vaccine.lotNumber),
    administeredBy: trimmed(vaccine.administeredBy),
    administrationSiteRaw: trimmed(vaccine.administrationSiteRaw),
    notes: trimmed(vaccine.notes),
    reminderOn: Boolean(vaccine.reminderOn),
    nextDoseDate: tsOrNull(vaccine.nextDoseDate),
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!vaccine.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(vaccinesCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteVaccine({ familyId, userId, id }) {
  await setDoc(
    doc(vaccinesCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/* ── Scheda medica ───────────────────────────────────────────────────────── */

function parseJsonList(raw) {
  if (typeof raw !== "string" || !raw.trim()) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function readProfile(snap, childId) {
  const d = snap.data() || {};
  return {
    childId: d.childId || childId,
    bloodGroup: d.bloodGroup || "",
    allergies: d.allergies || "",
    medicalNotes: d.medicalNotes || "",
    doctorName: d.doctorName || "",
    doctorPhone: d.doctorPhone || "",
    doctorEmail: d.doctorEmail || "",
    doctorAddress: d.doctorAddress || "",
    doctorWebsite: d.doctorWebsite || "",
    doctorOfficeHours: parseJsonList(d.doctorOfficeHoursJSON),
    emergencyContacts: parseJsonList(d.emergencyContactsJSON),
    isDeleted: Boolean(d.isDeleted),
    updatedAt: millis(d.updatedAt),
  };
}

/** Scheda medica del soggetto. Emette `null` finché il documento non esiste. */
export function listenPediatricProfile({ familyId, childId, onChange, onError }) {
  return onSnapshot(
    doc(profilesCol(familyId), childId),
    (snap) => onChange(snap.exists() ? readProfile(snap, childId) : null),
    (err) => onError?.(err)
  );
}

export async function savePediatricProfile({ familyId, userId, childId, profile }) {
  const officeHours = profile.doctorOfficeHours || [];
  const contacts = profile.emergencyContacts || [];
  await setDoc(
    doc(profilesCol(familyId), childId),
    {
      familyId,
      childId,
      bloodGroup: trimmed(profile.bloodGroup),
      allergies: trimmed(profile.allergies),
      medicalNotes: trimmed(profile.medicalNotes),
      doctorName: trimmed(profile.doctorName),
      doctorPhone: trimmed(profile.doctorPhone),
      doctorEmail: trimmed(profile.doctorEmail),
      doctorAddress: trimmed(profile.doctorAddress),
      doctorWebsite: trimmed(profile.doctorWebsite),
      doctorOfficeHoursJSON: officeHours.length ? JSON.stringify(officeHours) : null,
      emergencyContactsJSON: contacts.length ? JSON.stringify(contacts) : null,
      isDeleted: false,
      updatedBy: userId,
      updatedAt: serverTimestamp(),
      createdAt: serverTimestamp(),
    },
    { merge: true }
  );
}

/* ── Timeline ────────────────────────────────────────────────────────────── */

export const TIMELINE_KINDS = [
  { raw: "visit", it: "Visita", en: "Visit", emoji: "🩺", color: "#5A99D9" },
  { raw: "exam", it: "Esame", en: "Test", emoji: "🧪", color: "#40A6BF" },
  { raw: "treatment", it: "Cura", en: "Treatment", emoji: "💊", color: "#9973D9" },
  { raw: "vaccine", it: "Vaccino", en: "Vaccine", emoji: "💉", color: "#F28C73" },
];

export const timelineKindInfo = (raw) =>
  TIMELINE_KINDS.find((k) => k.raw === raw) || TIMELINE_KINDS[0];

/**
 * Eventi della timeline, con la stessa scelta di date di `PediatricHomeView`:
 * per l'esame vale la scadenza (o la creazione), per il vaccino la data di
 * somministrazione (o l'appuntamento), per la cura l'inizio.
 */
export function buildTimeline({ visits, exams, treatments, vaccines, locale = "it" }) {
  const label = (info) => (locale === "en" ? info.en : info.it);
  const events = [];

  for (const v of visits) {
    events.push({
      id: `visit-${v.id}`,
      sourceId: v.id,
      date: v.date,
      kind: "visit",
      title: v.reason || (locale === "en" ? "Medical visit" : "Visita medica"),
      subtitle: v.doctorName || null,
    });
  }
  for (const e of exams) {
    events.push({
      id: `exam-${e.id}`,
      sourceId: e.id,
      date: e.deadline || e.createdAt,
      kind: "exam",
      title: e.name,
      subtitle: label(examStatusInfo(e.statusRaw)),
    });
  }
  for (const t of treatments) {
    events.push({
      id: `treatment-${t.id}`,
      sourceId: t.id,
      date: t.startDate,
      kind: "treatment",
      title: t.drugName,
      subtitle: t.isLongTerm
        ? locale === "en"
          ? "Long term"
          : "Lungo termine"
        : t.durationDays > 0
          ? locale === "en"
            ? `${t.durationDays} days`
            : `${t.durationDays} giorni`
          : null,
    });
  }
  for (const v of vaccines) {
    events.push({
      id: `vaccine-${v.id}`,
      sourceId: v.id,
      date: vaccineDate(v),
      kind: "vaccine",
      title: v.commercialName || label(vaccineTypeInfo(v.vaccineTypeRaw)),
      subtitle: v.lotNumber ? `${locale === "en" ? "Lot" : "Lotto"}: ${v.lotNumber}` : null,
    });
  }

  return events.filter((e) => e.date).sort((a, b) => b.date - a.date);
}

/**
 * Cure davvero in corso: esclude quelle finite per data o perché tutte le dosi
 * previste risultano assunte. Stessa regola di `activeTreatments` su iOS.
 */
export function activeTreatments(treatments, doseLogs) {
  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);
  const today = startOfToday.getTime();

  return treatments.filter((t) => {
    if (!t.isActive) return false;
    if (t.isLongTerm) return true;
    if (t.endDate && t.endDate < today) return false;
    const total = totalDoses(t);
    if (total > 0) {
      const taken = doseLogs.filter((l) => l.treatmentId === t.id && l.taken).length;
      if (taken >= total) return false;
    }
    return true;
  });
}
