/**
 * Animali domestici, allineato a `PetRemoteStore` e `PetEventRemoteStore`.
 *
 * Animali ed eventi viaggiano **in chiaro**: è la scelta dei client nativi per
 * questo modulo, e cifrarli solo qui li renderebbe illeggibili sul telefono.
 * L'eliminazione è `isDeleted: true`, come per Wallet.
 *
 * Gli allegati non hanno una collezione propria: sono documenti di famiglia
 * marcati nel campo `notes` con `pet:{id}` per la scheda dell'animale e
 * `petEvent:{id}` per il singolo evento, dentro la cartella «Animali»
 * (id deterministico `pets-root-{familyId}`).
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

const petsCol = (familyId) => collection(db, "families", familyId, "pets");
const eventsCol = (familyId) => collection(db, "families", familyId, "petEvents");

/* ── Specie e tipi di evento, come sui client nativi ─────────────────────── */

export const SPECIES = [
  { raw: "cane", it: "Cane", en: "Dog", emoji: "🐕" },
  { raw: "gatto", it: "Gatto", en: "Cat", emoji: "🐈" },
  { raw: "coniglio", it: "Coniglio", en: "Rabbit", emoji: "🐇" },
  { raw: "criceto", it: "Criceto", en: "Hamster", emoji: "🐹" },
  { raw: "uccello", it: "Uccello", en: "Bird", emoji: "🐦" },
  { raw: "altro", it: "Altro", en: "Other", emoji: "🐾" },
];

export const speciesInfo = (raw) =>
  SPECIES.find((s) => s.raw === (raw || "").toLowerCase()) || SPECIES[SPECIES.length - 1];

export const EVENT_TYPES = [
  { raw: "vaccine", it: "Vaccino", en: "Vaccine", emoji: "💉", color: "#2E86FF" },
  { raw: "vet_visit", it: "Visita veterinaria", en: "Vet visit", emoji: "🩺", color: "#27AE60" },
  { raw: "medication", it: "Farmaco", en: "Medication", emoji: "💊", color: "#8E44AD" },
  { raw: "grooming", it: "Toelettatura", en: "Grooming", emoji: "✂️", color: "#E0509A" },
  { raw: "other", it: "Altro", en: "Other", emoji: "📅", color: "#5E5CE6" },
];

export const eventTypeInfo = (raw) =>
  EVENT_TYPES.find((t) => t.raw === raw) || EVENT_TYPES[EVENT_TYPES.length - 1];

/* ── Tag degli allegati ──────────────────────────────────────────────────── */

export const petTag = (petId) => `pet:${petId}`;
export const petEventTag = (eventId) => `petEvent:${eventId}`;
export const petsFolderId = (familyId) => `pets-root-${familyId}`;

/* ── Lettura ─────────────────────────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

function readPet(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    name: d.name || "",
    species: d.species || "altro",
    breed: d.breed || null,
    birthDate: millis(d.birthDate),
    color: d.color || null,
    chipCode: d.chipCode || null,
    notes: d.notes || null,
    photoURL: d.photoURL || null,
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
  };
}

function readEvent(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    petId: d.petId || "",
    title: d.title || "",
    eventTypeRaw: d.eventTypeRaw || "other",
    date: millis(d.date),
    nextDueDate: millis(d.nextDueDate),
    notes: d.notes || null,
    vetName: d.vetName || null,
    cost: typeof d.cost === "number" ? d.cost : null,
    reminderEnabled: Boolean(d.reminderEnabled),
    updatedAt: millis(d.updatedAt),
  };
}

/** Ascolta animali ed eventi. Restituisce la funzione per smettere. */
export function listenPets({ familyId, onChange, onError }) {
  let pets = null;
  let events = null;

  const emit = () => {
    if (pets === null || events === null) return;
    onChange({ pets, events });
  };

  const stopPets = onSnapshot(
    query(petsCol(familyId), where("isDeleted", "==", false)),
    (snap) => {
      pets = snap.docs.map(readPet).sort((a, b) => a.name.localeCompare(b.name));
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
    stopPets();
    stopEvents();
  };
}

/* ── Scrittura ───────────────────────────────────────────────────────────── */

const tsOrNull = (v) => (v ? Timestamp.fromMillis(v) : null);

export async function savePet({ familyId, userId, pet }) {
  const id = pet.id || crypto.randomUUID();
  const data = {
    name: pet.name || "",
    species: pet.species || "altro",
    breed: pet.breed || null,
    birthDate: tsOrNull(pet.birthDate),
    color: pet.color || null,
    chipCode: pet.chipCode || null,
    notes: pet.notes || null,
    photoURL: pet.photoURL || null,
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!pet.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(petsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deletePet({ familyId, userId, id }) {
  await setDoc(
    doc(petsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

export async function saveEvent({ familyId, userId, event }) {
  const id = event.id || crypto.randomUUID();
  const data = {
    petId: event.petId,
    title: event.title || "",
    eventTypeRaw: event.eventTypeRaw || "other",
    date: tsOrNull(event.date) || serverTimestamp(),
    nextDueDate: tsOrNull(event.nextDueDate),
    notes: event.notes || null,
    vetName: event.vetName || null,
    cost: typeof event.cost === "number" ? event.cost : null,
    reminderEnabled: Boolean(event.reminderEnabled),
    isDeleted: false,
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  };
  if (!event.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
  }
  await setDoc(doc(eventsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteEvent({ familyId, userId, id }) {
  await setDoc(
    doc(eventsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

