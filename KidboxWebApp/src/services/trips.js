/**
 * Viaggi: lettura e gestione, allineato a `TripRemoteStore` su iOS.
 *
 * `families/{familyId}/trips/{tripId}` con tre sottocollezioni usate
 * dall'app — `legs`, `dayPlans`, `packingItems`. Esiste anche `expenses`, ma
 * nessuno la scrive: iOS la nomina solo per ripulirla alla cancellazione, e
 * le spese di viaggio vivono nelle Spese di famiglia. Qui è ignorata.
 *
 * Tutto in chiaro e senza `isDeleted`: la cancellazione di un viaggio è reale,
 * documento e sottocollezioni.
 */
import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  onSnapshot,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";
import { db } from "../firebase";

const tripsCol = (familyId) => collection(db, "families", familyId, "trips");
const tripDoc = (familyId, tripId) => doc(db, "families", familyId, "trips", tripId);
const subCol = (familyId, tripId, name) =>
  collection(db, "families", familyId, "trips", tripId, name);

/* ── Tabelle condivise con iOS ───────────────────────────────────────────── */

/** Le tre fasi di `TripStatus`, con gli stessi `raw` del telefono. */
export const TRIP_PHASES = [
  { raw: "planning", it: "In programma", en: "Planned", color: "#2E86FF" },
  { raw: "active", it: "In corso", en: "Ongoing", color: "#27AE60" },
  { raw: "completed", it: "Concluso", en: "Completed", color: "#8E8E93" },
];

/** `TransportMode`, con un'emoji al posto del simbolo SF. */
export const TRANSPORT_MODES = [
  { raw: "flight", it: "Aereo", en: "Flight", emoji: "✈️" },
  { raw: "train", it: "Treno", en: "Train", emoji: "🚆" },
  { raw: "ship", it: "Nave", en: "Ship", emoji: "🛳" },
  { raw: "car", it: "Auto", en: "Car", emoji: "🚗" },
  { raw: "walk", it: "A piedi", en: "On foot", emoji: "🚶" },
  { raw: "bike", it: "Bici", en: "Bike", emoji: "🚲" },
];

/** `PackingCategory`, nell'ordine in cui iOS le elenca. */
export const PACKING_CATEGORIES = [
  { raw: "documents", it: "Documenti", en: "Documents", emoji: "🛂" },
  { raw: "clothing", it: "Abbigliamento", en: "Clothing", emoji: "👕" },
  { raw: "health", it: "Salute", en: "Health", emoji: "💊" },
  { raw: "kids", it: "Bambini", en: "Kids", emoji: "🧸" },
  { raw: "other", it: "Altro", en: "Other", emoji: "🎒" },
];

const lookup = (table, raw, fallbackIndex) =>
  table.find((entry) => entry.raw === raw) || table[fallbackIndex];

export const transportInfo = (raw) => lookup(TRANSPORT_MODES, raw, 3);
export const packingInfo = (raw) => lookup(PACKING_CATEGORIES, raw, PACKING_CATEGORIES.length - 1);

/**
 * Fase del viaggio, calcolata dalle date e NON dal campo `status`.
 *
 * `status` esiste sul documento, ma nessuna piattaforma lo fa mai avanzare:
 * l'app lo scrive `planning` alla creazione (`KBTrip.init`) e non lo tocca più.
 * Fidarsene voleva dire presentare come «In programma» anche un viaggio fatto
 * l'anno prima. Le date ci sono sempre e non possono mentire.
 *
 * Il confronto è a giorni interi: un viaggio che finisce oggi è ancora in
 * corso fino a mezzanotte, non concluso stamattina.
 */
export function tripPhase(trip, now = Date.now()) {
  const dayStart = new Date(trip.startDate);
  dayStart.setHours(0, 0, 0, 0);
  if (now < dayStart.getTime()) return TRIP_PHASES[0];

  const dayEnd = new Date(trip.endDate);
  dayEnd.setHours(23, 59, 59, 999);
  if (now > dayEnd.getTime()) return TRIP_PHASES[2];

  return TRIP_PHASES[1];
}

/* ── Lettura ─────────────────────────────────────────────────────────────── */

/** Timestamp, oppure secondi da epoch: `firestoreDate` accetta entrambi. */
const millis = (value) => {
  if (value?.toMillis) return value.toMillis();
  if (typeof value === "number") return value * 1000;
  return null;
};

const numberOrNull = (value) => (typeof value === "number" ? value : null);

function readTrip(snap) {
  const d = snap.data();
  const startDate = millis(d.startDate);
  const endDate = millis(d.endDate);
  // Stessa scelta di `decodeTrip`: senza le due date il viaggio non è
  // rappresentabile, e mostrarlo mezzo vuoto sarebbe peggio che ometterlo.
  if (startDate == null || endDate == null) return null;

  const createdAt = millis(d.createdAt) ?? Date.now();
  return {
    id: snap.id,
    name: d.name || "",
    startDate,
    endDate,
    participantIdsJson: d.participantIdsJson || "[]",
    budgetTotal: typeof d.budgetTotal === "number" ? d.budgetTotal : 0,
    currency: d.currency || "EUR",
    status: d.status || "planning",
    aiProposalJson: d.aiProposalJson || null,
    photoAlbumId: d.photoAlbumId || null,
    notesNoteId: d.notesNoteId || null,
    todoListId: d.todoListId || null,
    createdBy: d.createdBy || "",
    updatedBy: d.updatedBy || d.createdBy || "",
    createdAt,
    updatedAt: millis(d.updatedAt) ?? createdAt,
  };
}

function readLeg(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    order: typeof d.order === "number" ? d.order : 0,
    fromLocation: d.fromLocation || "",
    toLocation: d.toLocation || "",
    transportMode: d.transportMode || "car",
    notes: d.notes || null,
  };
}

function readDayPlan(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    dateString: d.date || "",
    location: d.location || "",
    morningPlan: d.morningPlan || "",
    afternoonPlan: d.afternoonPlan || "",
    eveningPlan: d.eveningPlan || "",
    accommodationName: d.accommodationName || null,
    accommodationType: d.accommodationType || null,
    accommodationCostPerNight: numberOrNull(d.accommodationCostPerNight),
    weatherBackupPlan: d.weatherBackupPlan || null,
    estimatedDailyCost: numberOrNull(d.estimatedDailyCost),
  };
}

function readPackingItem(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    label: d.label || "",
    category: d.category || "other",
    isChecked: Boolean(d.isChecked),
    isAIGenerated: Boolean(d.isAIGenerated),
    fromMedicalProfile: Boolean(d.fromMedicalProfile),
  };
}

/** I viaggi della famiglia, dal più recente — l'ordine della lista su iOS. */
export function listenTrips({ familyId, onChange, onError }) {
  return onSnapshot(
    tripsCol(familyId),
    (snap) => {
      const trips = snap.docs
        .map(readTrip)
        .filter(Boolean)
        .sort((a, b) => b.startDate - a.startDate);
      onChange(trips);
    },
    (err) => onError?.(err)
  );
}

/**
 * Contenuto di un viaggio: tratte, giorni e packing list insieme, così la
 * scheda non si disegna a pezzi mentre arrivano tre snapshot separati.
 */
export function listenTripContent({ familyId, tripId, onChange, onError }) {
  const content = { legs: null, dayPlans: null, packingItems: null };
  const emit = () => {
    if (content.legs === null || content.dayPlans === null || content.packingItems === null) return;
    onChange({ ...content });
  };

  const watch = (name, read, sort) =>
    onSnapshot(
      subCol(familyId, tripId, name),
      (snap) => {
        content[name] = snap.docs.map(read).sort(sort);
        emit();
      },
      (err) => onError?.(err)
    );

  const stops = [
    watch("legs", readLeg, (a, b) => a.order - b.order),
    watch("dayPlans", readDayPlan, (a, b) => a.dateString.localeCompare(b.dateString)),
    watch("packingItems", readPackingItem, (a, b) => {
      const byCategory =
        PACKING_CATEGORIES.findIndex((c) => c.raw === a.category) -
        PACKING_CATEGORIES.findIndex((c) => c.raw === b.category);
      return byCategory !== 0 ? byCategory : a.label.localeCompare(b.label);
    }),
  ];

  return () => stops.forEach((stop) => stop());
}

/* ── Scrittura ───────────────────────────────────────────────────────────── */

/** Spunta di una voce della packing list: l'unico campo che il web tocca. */
export async function setPackingItemChecked({ familyId, tripId, itemId, isChecked }) {
  await setDoc(
    doc(subCol(familyId, tripId, "packingItems"), itemId),
    { isChecked, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/**
 * Elimina il viaggio. Il documento PRIMA delle sottocollezioni, come in
 * `deleteTripRemote`: se si comincia dalle sottocollezioni e una fallisce a
 * metà, il documento resta e il viaggio riappare al primo snapshot. Cancellando
 * prima il padre, la sparizione è garantita; quel che resta sono documenti
 * orfani, invisibili perché i viaggi si elencano dal documento padre.
 */
export async function deleteTrip({ familyId, tripId }) {
  await deleteDoc(tripDoc(familyId, tripId));

  for (const name of ["legs", "dayPlans", "packingItems", "expenses"]) {
    try {
      const snap = await getDocs(subCol(familyId, tripId, name));
      await Promise.all(snap.docs.map((d) => deleteDoc(d.ref)));
    } catch {
      // Pulizia best-effort: il viaggio è già sparito per l'utente.
    }
  }
}
