/**
 * Wallet: biglietti e tessere fedeltà, allineato a `WalletRemoteStore` e
 * `LoyaltyCardRemoteStore` su iOS.
 *
 * ## Cosa è cifrato e cosa no
 * I **biglietti** cifrano i campi testuali con la chiave di famiglia — la stessa
 * di Documenti, via `WalletCryptoService` → `DocumentCryptoService` — e lasciano
 * in chiaro i metadati non sensibili (tipo, date, emittente): serve alle Cloud
 * Function per i promemoria, che devono leggere `eventDate` senza poter leggere
 * il PNR. I campi cifrati hanno il suffisso `Enc` e viaggiano in base64.
 *
 * Le **tessere fedeltà** non sono cifrate: è la scelta fatta su iOS, e cambiarla
 * qui renderebbe illeggibili le tessere sugli altri client.
 *
 * L'eliminazione è `isDeleted: true`, non un campo `deletedAt`: è il contratto
 * che usano gli altri client per questo modulo.
 */
import {
  collection,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { getDownloadURL, ref, uploadBytes, deleteObject } from "firebase/storage";
import { db, storage } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { encryptBytes, decryptBytes } from "./familyCrypto";

const SCHEMA_VERSION = 1;

const ticketsCol = (familyId) => collection(db, "families", familyId, "walletTickets");
const cardsCol = (familyId) => collection(db, "families", familyId, "loyaltyCards");

/* ── Tipi di biglietto, come `KBWalletTicketKind` ────────────────────────── */

export const TICKET_KINDS = [
  { id: "train", it: "Treno", en: "Train", emoji: "🚆", color: "#297DC7" },
  { id: "flight", it: "Volo", en: "Flight", emoji: "✈️", color: "#1A548C" },
  { id: "ferry", it: "Traghetto", en: "Ferry", emoji: "⛴", color: "#0E7C86" },
  { id: "bus", it: "Autobus", en: "Bus", emoji: "🚌", color: "#B4661E" },
  { id: "concert", it: "Concerto", en: "Concert", emoji: "🎵", color: "#8E44AD" },
  { id: "cinema", it: "Cinema", en: "Cinema", emoji: "🎟", color: "#C0392B" },
  { id: "parking", it: "Parcheggio", en: "Parking", emoji: "🅿️", color: "#2C7A4B" },
  { id: "museum", it: "Museo / Mostra", en: "Museum", emoji: "🏛", color: "#7A5C2E" },
  { id: "other", it: "Biglietto", en: "Ticket", emoji: "🎫", color: "#5E5CE6" },
];

export const kindInfo = (raw) =>
  TICKET_KINDS.find((k) => k.id === raw) || TICKET_KINDS[TICKET_KINDS.length - 1];

/* ── Visibilità: sul Wallet il default è «solo io» ───────────────────────── */

export const WALLET_FAMILY = "family";
export const WALLET_MEMBERS = "members";
export const WALLET_PRIVATE = "private";

/** Come `normalizedVisibilityScopeForWallet`: vuoto o ignoto → «solo io». */
export function normalizedWalletScope(raw) {
  const s = (raw || "").trim();
  if (s === WALLET_FAMILY || s === WALLET_MEMBERS || s === WALLET_PRIVATE) return s;
  return WALLET_PRIVATE;
}

export function isVisibleTo({ visibilityScope, visibilityMemberIds, createdBy }, uid) {
  if (!uid) return false;
  switch (normalizedWalletScope(visibilityScope)) {
    case WALLET_FAMILY:
      return true;
    case WALLET_MEMBERS:
      return createdBy === uid || (visibilityMemberIds || []).includes(uid);
    default:
      return Boolean(createdBy) && createdBy === uid;
  }
}

/* ── Cifratura dei campi testuali ────────────────────────────────────────── */

const enc = new TextEncoder();
const dec = new TextDecoder();

function bytesToB64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 1) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

async function encField(value, key) {
  if (!value) return null;
  return bytesToB64(await encryptBytes(enc.encode(value), key));
}

async function decField(b64, key) {
  if (!b64) return null;
  try {
    return dec.decode(await decryptBytes(b64ToBytes(b64), key));
  } catch {
    return null;
  }
}

/* ── Lettura ─────────────────────────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

async function readTicket(snap, key) {
  const d = snap.data();
  const [title, location, seat, bookingCode, arrivalLocation, holderName, notes, barcodeText, fileName] =
    await Promise.all([
      decField(d.titleEnc, key),
      decField(d.locationEnc, key),
      decField(d.seatEnc, key),
      decField(d.bookingCodeEnc, key),
      decField(d.arrivalLocationEnc, key),
      decField(d.holderNameEnc, key),
      decField(d.notesEnc, key),
      decField(d.barcodeTextEnc, key),
      decField(d.fileNameEnc, key),
    ]);

  return {
    id: snap.id,
    title: title || "",
    location,
    seat,
    bookingCode,
    arrivalLocation,
    holderName,
    notes,
    barcodeText,
    barcodeFormat: d.barcodeFormat || null,
    pdfFileName: fileName,
    kind: d.kind || "other",
    emitter: d.emitter || null,
    reminderOffsetHours:
      typeof d.reminderOffsetHours === "number" ? d.reminderOffsetHours : null,
    eventDate: millis(d.eventDate),
    eventEndDate: millis(d.eventEndDate),
    pdfStorageURL: d.pdfStorageURL || null,
    pdfStorageBytes: d.pdfStorageBytes || 0,
    addToAppleWalletURL: d.addToAppleWalletURL || null,
    visibilityScope: normalizedWalletScope(d.visibilityScope),
    visibilityMemberIds: d.visibilityMemberIds || [],
    createdBy: d.createdBy || "",
    createdByName: d.createdByName || "",
    updatedAt: millis(d.updatedAt),
    createdAt: millis(d.createdAt),
    isDeleted: Boolean(d.isDeleted),
  };
}

function readCard(snap) {
  const d = snap.data();
  return {
    id: snap.id,
    brandId: d.brandId || null,
    brandName: d.brandName || "",
    cardNumber: d.cardNumber || "",
    barcodeFormat: d.barcodeFormat || "",
    note: d.note || null,
    primaryColorHex: d.primaryColorHex || "#3A3A3C",
    secondaryColorHex: d.secondaryColorHex || "#1C1C1E",
    logoURL: d.logoURL || null,
    frontPhotoStorageURL: d.frontPhotoStorageURL || null,
    frontPhotoStoragePath: d.frontPhotoStoragePath || null,
    backPhotoStorageURL: d.backPhotoStorageURL || null,
    backPhotoStoragePath: d.backPhotoStoragePath || null,
    visibilityScope: normalizedWalletScope(d.visibilityScope),
    visibilityMemberIds: d.visibilityMemberIds || [],
    createdBy: d.createdBy || "",
    updatedAt: millis(d.updatedAt),
    isDeleted: Boolean(d.isDeleted),
  };
}

/** Ascolta biglietti e tessere. Restituisce la funzione per smettere. */
export function listenWallet({ familyId, userId, onChange, onError }) {
  let cancelled = false;
  let ticketDocs = null;
  let cardDocs = null;
  let keyPromise = null;

  const emit = async () => {
    if (ticketDocs === null || cardDocs === null) return;
    try {
      keyPromise = keyPromise || loadFamilyKey({ familyId, userId });
      const key = await keyPromise;
      const tickets = await Promise.all(ticketDocs.map((s) => readTicket(s, key)));
      if (cancelled) return;
      onChange({
        tickets: tickets.filter((t) => isVisibleTo(t, userId)),
        cards: cardDocs.map(readCard).filter((c) => isVisibleTo(c, userId)),
      });
    } catch (err) {
      if (!cancelled) onError?.(err);
    }
  };

  const stopTickets = onSnapshot(
    ticketsCol(familyId),
    (snap) => {
      ticketDocs = snap.docs.filter((s) => !s.data().isDeleted);
      emit();
    },
    (err) => onError?.(err)
  );
  const stopCards = onSnapshot(
    cardsCol(familyId),
    (snap) => {
      cardDocs = snap.docs.filter((s) => !s.data().isDeleted);
      emit();
    },
    (err) => onError?.(err)
  );

  return () => {
    cancelled = true;
    stopTickets();
    stopCards();
  };
}

/* ── Scrittura: biglietti ────────────────────────────────────────────────── */

const tsOrNull = (v) => (v ? Timestamp.fromMillis(v) : null);

export async function saveTicket({ familyId, userId, userName, ticket }) {
  const id = ticket.id || crypto.randomUUID();
  const key = await loadFamilyKey({ familyId, userId });

  const data = {
    schemaVersion: SCHEMA_VERSION,
    familyId,
    titleEnc: await encField(ticket.title || "", key),
    locationEnc: await encField(ticket.location, key),
    seatEnc: await encField(ticket.seat, key),
    bookingCodeEnc: await encField(ticket.bookingCode, key),
    arrivalLocationEnc: await encField(ticket.arrivalLocation, key),
    holderNameEnc: await encField(ticket.holderName, key),
    notesEnc: await encField(ticket.notes, key),
    barcodeTextEnc: await encField(ticket.barcodeText, key),
    fileNameEnc: await encField(ticket.pdfFileName, key),
    kind: ticket.kind || "other",
    emitter: ticket.emitter || null,
    reminderOffsetHours: ticket.reminderOffsetHours ?? null,
    eventDate: tsOrNull(ticket.eventDate),
    eventEndDate: tsOrNull(ticket.eventEndDate),
    pdfStorageURL: ticket.pdfStorageURL || null,
    pdfStorageBytes: ticket.pdfStorageBytes || 0,
    addToAppleWalletURL: ticket.addToAppleWalletURL || null,
    barcodeFormat: ticket.barcodeFormat || null,
    visibilityScope: normalizedWalletScope(ticket.visibilityScope),
    visibilityMemberIds:
      normalizedWalletScope(ticket.visibilityScope) === WALLET_MEMBERS
        ? ticket.visibilityMemberIds || []
        : [],
    isDeleted: false,
    updatedBy: userId,
    updatedByName: userName || "",
    updatedAt: serverTimestamp(),
  };
  if (!ticket.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
    data.createdByName = userName || "";
  }

  await setDoc(doc(ticketsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteTicket({ familyId, userId, id }) {
  await setDoc(
    doc(ticketsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/* ── PDF dei biglietti ───────────────────────────────────────────────────── */

const pdfPath = (familyId, ticketId) => `families/${familyId}/walletTickets/${ticketId}.pdf`;

/**
 * Il PDF sale cifrato in byte grezzi — non base64 — come fa iOS: sono ~33% in
 * meno di banda, e il file a riposo è indistinguibile da quelli di Documenti.
 */
export async function uploadTicketPdf({ familyId, userId, ticketId, file }) {
  const key = await loadFamilyKey({ familyId, userId });
  const sealed = await encryptBytes(new Uint8Array(await file.arrayBuffer()), key);
  const storageRef = ref(storage, pdfPath(familyId, ticketId));
  await uploadBytes(storageRef, sealed, { contentType: "application/octet-stream" });
  return {
    url: await getDownloadURL(storageRef),
    bytes: sealed.byteLength,
    fileName: file.name,
  };
}

/** Scarica e decifra il PDF, pronto per essere aperto o mostrato. */
export async function fetchTicketPdf({ familyId, userId, ticket }) {
  if (!ticket.pdfStorageURL) return null;
  const key = await loadFamilyKey({ familyId, userId });
  const res = await fetch(ticket.pdfStorageURL);
  if (!res.ok) throw new Error(`Download del PDF non riuscito (${res.status})`);
  const plain = await decryptBytes(new Uint8Array(await res.arrayBuffer()), key);
  return new Blob([plain], { type: "application/pdf" });
}

export async function deleteTicketPdf({ familyId, ticketId }) {
  try {
    await deleteObject(ref(storage, pdfPath(familyId, ticketId)));
  } catch {
    // Già assente: non è un errore da mostrare.
  }
}

/* ── Scrittura: tessere fedeltà ──────────────────────────────────────────── */

export async function saveCard({ familyId, userId, userName, card }) {
  const id = card.id || crypto.randomUUID();
  const data = {
    schemaVersion: SCHEMA_VERSION,
    familyId,
    brandId: card.brandId || null,
    brandName: card.brandName || "",
    cardNumber: card.cardNumber || "",
    barcodeFormat: card.barcodeFormat || "",
    note: card.note || null,
    primaryColorHex: card.primaryColorHex || "#3A3A3C",
    secondaryColorHex: card.secondaryColorHex || "#1C1C1E",
    logoURL: card.logoURL || null,
    frontPhotoStorageURL: card.frontPhotoStorageURL || null,
    frontPhotoStoragePath: card.frontPhotoStoragePath || null,
    backPhotoStorageURL: card.backPhotoStorageURL || null,
    backPhotoStoragePath: card.backPhotoStoragePath || null,
    visibilityScope: normalizedWalletScope(card.visibilityScope),
    visibilityMemberIds:
      normalizedWalletScope(card.visibilityScope) === WALLET_MEMBERS
        ? card.visibilityMemberIds || []
        : [],
    isDeleted: false,
    updatedBy: userId,
    updatedByName: userName || "",
    updatedAt: serverTimestamp(),
  };
  if (!card.id) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
    data.createdByName = userName || "";
  }
  await setDoc(doc(cardsCol(familyId), id), data, { merge: true });
  return id;
}

export async function deleteCard({ familyId, userId, id }) {
  await setDoc(
    doc(cardsCol(familyId), id),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/**
 * Le foto delle tessere NON sono cifrate: su iOS finiscono su Storage in chiaro,
 * e cifrarle solo qui le renderebbe illeggibili sul telefono.
 */
export async function uploadCardPhoto({ familyId, cardId, side, file }) {
  const path = `families/${familyId}/loyaltyCards/${cardId}-${side}.jpg`;
  const storageRef = ref(storage, path);
  await uploadBytes(storageRef, file, { contentType: file.type || "image/jpeg" });
  return { url: await getDownloadURL(storageRef), path };
}
