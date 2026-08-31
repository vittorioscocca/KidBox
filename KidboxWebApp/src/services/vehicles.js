/**
 * Garage: veicoli e interventi, allineato a `VehicleRemoteStore` e
 * `VehicleEventRemoteStore` su iOS.
 *
 * Tutto in chiaro, eliminazione con `isDeleted: true`.
 *
 * Gli interventi hanno un `linkedExpenseId`: se c'è un costo, alimentano le
 * Spese di famiglia nella categoria «automobile», con la regola condivisa in
 * `linkedExpense.js` (la stessa di scontrini e scadenze di casa).
 *
 * Gli allegati sono documenti marcati `vehicle:{id}` e `vehicleEvent:{id}`.
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
  writeBatch,
} from "firebase/firestore";
import { db } from "../firebase";
import { deleteLinkedExpense, syncLinkedExpense } from "./linkedExpense";

const vehiclesCol = (familyId) => collection(db, "families", familyId, "vehicles");
const eventsCol = (familyId) => collection(db, "families", familyId, "vehicleEvents");

/* ── Carburanti e tipi di intervento ─────────────────────────────────────── */

export const FUELS = [
  { raw: "benzina", it: "Benzina", en: "Petrol" },
  { raw: "diesel", it: "Diesel", en: "Diesel" },
  { raw: "elettrica", it: "Elettrica", en: "Electric" },
  { raw: "ibrida", it: "Ibrida", en: "Hybrid" },
  { raw: "gpl", it: "GPL", en: "LPG" },
];

export const EVENT_TYPES = [
  { raw: "service", it: "Tagliando", en: "Service", emoji: "🔧", color: "#2E86FF" },
  { raw: "oil_filter", it: "Filtro olio", en: "Oil filter", emoji: "🛢", color: "#B4661E" },
  { raw: "gpl_filter", it: "Filtro GPL", en: "LPG filter", emoji: "⛽️", color: "#27AE60" },
  { raw: "brake_pads", it: "Pasticche freni", en: "Brake pads", emoji: "🛑", color: "#D32F2F" },
  { raw: "repair", it: "Riparazione", en: "Repair", emoji: "🔩", color: "#8E44AD" },
  { raw: "tire", it: "Cambio gomme", en: "Tyre change", emoji: "🛞", color: "#455A64" },
  { raw: "revision", it: "Revisione", en: "Inspection", emoji: "📋", color: "#00838F" },
  { raw: "other", it: "Altro", en: "Other", emoji: "🚗", color: "#5E5CE6" },
];

export const fuelInfo = (raw) => FUELS.find((f) => f.raw === raw) || FUELS[0];
export const eventTypeInfo = (raw) =>
  EVENT_TYPES.find((t) => t.raw === raw) || EVENT_TYPES[EVENT_TYPES.length - 1];

/**
 * Preavvisi dei promemoria, in giorni. Valori ammessi e default sono quelli di
 * `VehicleReminderOffsets`: cambiarli qui li renderebbe incoerenti col telefono.
 */
export const ALLOWED_OFFSETS = [0, 2, 7];
export const DEFAULT_OFFSETS = [0, 7];
export const OFFSET_KEYS = ["insurance", "revision", "tax", "service"];

export const defaultOffsets = () =>
  Object.fromEntries(OFFSET_KEYS.map((k) => [k, [...DEFAULT_OFFSETS]]));

export const vehicleTag = (id) => `vehicle:${id}`;
export const vehicleEventTag = (id) => `vehicleEvent:${id}`;
// `gar-root-`, non `garage-root-`: è l'id che usa iOS, e sbagliarlo creerebbe
// una seconda cartella Garage accanto a quella già esistente.
export const garageFolderId = (familyId) => `gar-root-${familyId}`;

/* ── Lettura ─────────────────────────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

function readVehicle(snap) {
  const d = snap.data();
  const offsets = d.reminderOffsets || {};
  return {
    id: snap.id,
    name: d.name || "",
    licensePlate: d.licensePlate || null,
    brand: d.brand || null,
    model: d.model || null,
    year: typeof d.year === "number" ? d.year : null,
    fuelTypeRaw: d.fuelTypeRaw || null,
    color: d.color || null,
    vin: d.vin || null,
    insuranceExpiryDate: millis(d.insuranceExpiryDate),
    revisionExpiryDate: millis(d.revisionExpiryDate),
    taxExpiryDate: millis(d.taxExpiryDate),
    lastServiceDate: millis(d.lastServiceDate),
    nextServiceDate: millis(d.nextServiceDate),
    currentKm: typeof d.currentKm === "number" ? d.currentKm : null,
    notes: d.notes || null,
    photoURL: d.photoURL || null,
    reminderEnabled: Boolean(d.reminderEnabled),
    reminderOffsets: Object.fromEntries(
      OFFSET_KEYS.map((k) => [k, Array.isArray(offsets[k]) ? offsets[k] : [...DEFAULT_OFFSETS]])
    ),
    updatedAt: millis(d.updatedAt),
  };
}

function readEvent(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    vehicleId: d.vehicleId || "",
    title: d.title || "",
    eventTypeRaw: d.eventTypeRaw || "other",
    date: millis(d.date),
    km: typeof d.km === "number" ? d.km : null,
    cost: typeof d.cost === "number" ? d.cost : null,
    linkedExpenseId: d.linkedExpenseId || null,
    garageName: d.garageName || null,
    notes: d.notes || null,
    updatedAt: millis(d.updatedAt),
  };
}

export function listenGarage({ familyId, onChange, onError }) {
  let vehicles = null;
  let events = null;
  const emit = () => {
    if (vehicles === null || events === null) return;
    onChange({ vehicles, events });
  };

  const stopVehicles = onSnapshot(
    query(vehiclesCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      vehicles = snap.docs.map(readVehicle).sort((a, b) => a.name.localeCompare(b.name));
      emit();
    },
    (err) => onError?.(err)
  );

  const stopEvents = onSnapshot(
    query(eventsCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      events = snap.docs.map(readEvent).sort((a, b) => (b.date || 0) - (a.date || 0));
      emit();
    },
    (err) => onError?.(err)
  );

  return () => {
    stopVehicles();
    stopEvents();
  };
}

/* ── Scrittura ───────────────────────────────────────────────────────────── */

const tsOrNull = (v) => (v ? Timestamp.fromMillis(v) : null);

export async function saveVehicle({ familyId, userId, vehicle }) {
  const id = vehicle.id || crypto.randomUUID();
  const data = {
    name: vehicle.name || "",
    licensePlate: vehicle.licensePlate || null,
    brand: vehicle.brand || null,
    model: vehicle.model || null,
    year: vehicle.year ?? null,
    fuelTypeRaw: vehicle.fuelTypeRaw || null,
    color: vehicle.color || null,
    vin: vehicle.vin || null,
    insuranceExpiryDate: tsOrNull(vehicle.insuranceExpiryDate),
    revisionExpiryDate: tsOrNull(vehicle.revisionExpiryDate),
    taxExpiryDate: tsOrNull(vehicle.taxExpiryDate),
    lastServiceDate: tsOrNull(vehicle.lastServiceDate),
    nextServiceDate: tsOrNull(vehicle.nextServiceDate),
    currentKm: vehicle.currentKm ?? null,
    notes: vehicle.notes || null,
    photoURL: vehicle.photoURL || null,
    reminderEnabled: Boolean(vehicle.reminderEnabled),
    reminderOffsets: vehicle.reminderOffsets || defaultOffsets(),
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!vehicle.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(vehiclesCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteVehicle({ familyId, userId, id }) {
  await setDoc(
    doc(vehiclesCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Officina, chilometri e note finiscono nelle note della spesa, come `notesFor`. */
function expenseNotesFor(event) {
  return (
    [event.garageName, event.km != null ? `${event.km} km` : null, event.notes]
      .map((v) => (v == null ? "" : String(v).trim()))
      .filter(Boolean)
      .join(" · ") || null
  );
}

export async function saveVehicleEvent({ familyId, userId, event }) {
  const id = event.id || crypto.randomUUID();
  const batch = writeBatch(db);

  const linkedExpenseId = syncLinkedExpense({
    batch,
    familyId,
    userId,
    linkedExpenseId: event.linkedExpenseId,
    amount: event.cost,
    title: event.title,
    fallbackTitle: "Intervento auto",
    date: event.date || Date.now(),
    notes: expenseNotesFor(event),
    categorySlug: "automobile",
  });

  const data = {
    vehicleId: event.vehicleId,
    title: event.title || "",
    eventTypeRaw: event.eventTypeRaw || "other",
    date: tsOrNull(event.date) || serverTimestamp(),
    km: event.km ?? null,
    cost: event.cost ?? null,
    linkedExpenseId,
    garageName: event.garageName || null,
    notes: event.notes || null,
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!event.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }

  batch.set(doc(eventsCol(familyId), id), data, { merge: true });
  await batch.commit();
  return id;
}

/** Elimina l'intervento e la spesa collegata: sono lo stesso fatto. */
export async function deleteVehicleEvent({ familyId, userId, id, linkedExpenseId }) {
  const batch = writeBatch(db);
  deleteLinkedExpense({ batch, familyId, userId, linkedExpenseId });
  batch.set(
    doc(eventsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
  await batch.commit();
}
