/**
 * «Salva in…»: porta sul web `ChatSaveSheet` (iOS), che prende un messaggio
 * della chat e lo trasforma in qualcosa che vive in un'altra sezione.
 *
 * Le destinazioni sono le stesse dell'app: un testo può diventare To-Do,
 * evento, voce della spesa o nota; una foto, un video o un documento finiscono
 * in Foto o in Documenti. I payload non li inventa questo file: sono copiati
 * dai punti in cui il sito già crea quelle entità, così una nota salvata dalla
 * chat è identica a una nota scritta a mano.
 */
import { Timestamp, doc, serverTimestamp, setDoc } from "firebase/firestore";
import { getBytes, ref as storageRef } from "firebase/storage";
import { db, storage } from "../firebase";
import { encryptString } from "./noteCrypto";
import { loadFamilyKey } from "./familyKey";
import { uploadDocument } from "./documents";
import { uploadPhoto } from "./photos";

/**
 * I byte di un media della chat.
 *
 * Passa dall'SDK e non da `fetch(url)`: il download URL di Storage è
 * cross-origin e senza CORS il browser lo blocca, mentre il percorso dell'SDK
 * è lo stesso già usato da Foto e Documenti su questo sito.
 */
async function mediaBytes({ storagePath, url }) {
  if (storagePath) {
    try {
      return new Uint8Array(await getBytes(storageRef(storage, storagePath)));
    } catch {
      // Path assente o non leggibile: si prova l'URL, che a volte è servito
      // con CORS aperto.
    }
  }
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download fallito (${res.status})`);
  return new Uint8Array(await res.arrayBuffer());
}

const guessName = (message, fallbackExt) =>
  message.type === "document" && message.text
    ? message.text
    : `chat-${message.id.slice(0, 8)}.${fallbackExt}`;

const mimeFor = (message) => {
  switch (message.type) {
    case "photo":
      return "image/jpeg";
    case "video":
      return "video/mp4";
    case "audio":
      return "audio/mp4";
    default:
      return "application/octet-stream";
  }
};

const extFor = (message) =>
  ({ photo: "jpg", video: "mp4", audio: "m4a" })[message.type] || "bin";

export async function saveToDocuments({ familyId, uid, message, url, storagePath }) {
  const bytes = await mediaBytes({
    storagePath: storagePath ?? message.mediaStoragePath,
    url: url ?? message.mediaURL,
  });
  return uploadDocument({
    familyId,
    userId: uid,
    bytes,
    name: guessName(message, extFor(message)),
    mimeType: mimeFor(message),
  });
}

export async function saveToPhotos({ familyId, uid, message, url, storagePath, isVideo }) {
  const bytes = await mediaBytes({
    storagePath: storagePath ?? message.mediaStoragePath,
    url: url ?? message.mediaURL,
  });
  const video = isVideo ?? message.type === "video";
  const name = guessName(message, video ? "mp4" : "jpg");
  const file = new File([bytes], name, { type: video ? "video/mp4" : "image/jpeg" });
  return uploadPhoto({ familyId, userId: uid, file });
}

export async function saveAsNote({ familyId, uid, displayName, text }) {
  const key = await loadFamilyKey({ familyId, userId: uid });
  const id = crypto.randomUUID();
  const lines = text.split("\n");
  await setDoc(doc(db, "families", familyId, "notes", id), {
    schemaVersion: 1,
    titleEnc: await encryptString(lines[0]?.slice(0, 80) || "", key),
    bodyEnc: await encryptString(text, key),
    visibilityScope: "family",
    visibilityMemberIds: [],
    isDeleted: false,
    createdAt: serverTimestamp(),
    createdBy: uid,
    createdByName: displayName ?? null,
    updatedBy: uid,
    updatedByName: displayName ?? null,
    updatedAt: serverTimestamp(),
  });
  return id;
}

export async function saveAsTodo({ familyId, uid, title }) {
  const id = crypto.randomUUID();
  await setDoc(doc(db, "families", familyId, "todos", id), {
    childId: "",
    title,
    listId: "",
    isDone: false,
    isDeleted: false,
    notes: null,
    dueAt: null,
    assignedTo: null,
    priority: 0,
    visibilityScope: "family",
    visibilityMemberIds: [],
    doneAt: null,
    doneBy: null,
    createdBy: uid,
    createdAt: serverTimestamp(),
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
  return id;
}

export async function saveAsEvent({ familyId, uid, title, startAt }) {
  const id = crypto.randomUUID();
  const start = startAt || new Date();
  const end = new Date(start.getTime() + 60 * 60 * 1000);
  await setDoc(doc(db, "families", familyId, "calendarEvents", id), {
    id,
    familyId,
    title,
    isAllDay: false,
    categoryRaw: "family",
    recurrenceRaw: "none",
    isDeleted: false,
    startDate: Timestamp.fromDate(start),
    endDate: Timestamp.fromDate(end),
    location: null,
    notes: null,
    visibilityScope: "family",
    visibilityMemberIds: [],
    createdAt: serverTimestamp(),
    createdBy: uid,
    updatedAt: serverTimestamp(),
    updatedBy: uid,
  });
  return id;
}

export async function saveAsGrocery({ familyId, uid, name }) {
  const id = crypto.randomUUID();
  await setDoc(doc(db, "families", familyId, "groceries", id), {
    name,
    category: null,
    notes: null,
    isPurchased: false,
    isDeleted: false,
    purchasedAt: null,
    purchasedBy: null,
    createdBy: uid,
    createdAt: serverTimestamp(),
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
  return id;
}
