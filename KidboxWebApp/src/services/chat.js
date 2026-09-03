/**
 * Chat di famiglia: porta sul web `ChatViewModel`, `ChatRemoteStore` e
 * `ChatStorageService` (iOS).
 *
 * Due regole del client nativo che qui vanno rispettate alla lettera, o i
 * messaggi scritti dal sito risultano illeggibili sul telefono e viceversa:
 *
 * • **Il testo è cifrato**, sempre. Vive in `textEnc` con lo stesso formato
 *   delle note (nonce‖ciphertext‖tag in base64) e il campo `text` in chiaro
 *   viene cancellato a ogni scrittura. Un messaggio vecchio può ancora averlo:
 *   in lettura si prova prima `textEnc` e poi il chiaro, come fa iOS.
 * • **I media non sono cifrati**: le Storage Rules già limitano l'accesso ai
 *   membri, e lasciare i file in chiaro è ciò che permette lo streaming
 *   nativo di audio e video. Il path è `families/{familyId}/chat/{messageId}/…`.
 *
 * `readBy` non si scrive mai nel documento intero: solo con `arrayUnion` da
 * `markAsRead`, o due lettori simultanei si cancellerebbero a vicenda.
 */
import {
  arrayUnion,
  collection,
  deleteDoc,
  doc,
  endBefore,
  getDocs,
  limitToLast,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";
import {
  deleteObject,
  getDownloadURL,
  ref as storageRef,
  uploadBytesResumable,
} from "firebase/storage";
import { db, storage } from "../firebase";
import { decryptString, encryptString } from "./noteCrypto";

export const PAGE_SIZE = 50;
/** Come su iOS: oltre dieci elementi il gruppo non si legge più. */
export const MAX_GROUP_ITEMS = 10;
export const REACTION_EMOJIS = ["❤️", "👍", "😂", "😮", "😢", "🙏"];

const messagesCol = (familyId) => collection(db, "families", familyId, "chatMessages");
const messageRef = (familyId, id) => doc(db, "families", familyId, "chatMessages", id);
const typingRef = (familyId, uid) => doc(db, "families", familyId, "typing", uid);

const parseJSON = (raw, fallback) => {
  if (!raw) return fallback;
  try {
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
};

const toDate = (value) => (value?.toDate ? value.toDate() : value || null);

/** Un documento Firestore → il messaggio che l'interfaccia usa. */
async function mapMessage(snap, familyKey) {
  const d = snap.data();
  let text = d.text ?? "";
  if (d.textEnc && familyKey) {
    try {
      text = await decryptString(d.textEnc, familyKey);
    } catch {
      // Chiave sbagliata o payload rovinato: meglio il campo in chiaro (se c'è)
      // che un messaggio che sparisce dalla conversazione.
      text = d.text ?? "";
    }
  }

  return {
    id: snap.id,
    senderId: d.senderId || "",
    senderName: d.senderName || "",
    type: d.type || "text",
    text,
    // Finché il server non conferma, `createdAt` è nullo sul documento appena
    // scritto: senza ripiego il messaggio appena inviato resterebbe senza ora
    // e fuori dal suo giorno per qualche istante.
    createdAt: toDate(d.createdAt) || new Date(),
    editedAt: toDate(d.editedAt),
    isDeleted: d.isDeleted === true,
    deletedFor: d.deletedFor || [],
    replyToId: d.replyToId || null,
    reactions: parseJSON(d.reactionsJSON, {}),
    readBy: d.readBy || [],
    mentions: d.mentions || [],
    latitude: typeof d.latitude === "number" ? d.latitude : null,
    longitude: typeof d.longitude === "number" ? d.longitude : null,
    mediaURL: d.mediaURL || null,
    mediaStoragePath: d.mediaStoragePath || null,
    mediaThumbnailURL: d.mediaThumbnailURL || null,
    mediaDurationSeconds: d.mediaDurationSeconds ?? null,
    mediaFileSize: d.mediaFileSize ?? null,
    mediaGroupURLs: parseJSON(d.mediaGroupURLsJSON, []),
    mediaGroupTypes: parseJSON(d.mediaGroupTypesJSON, []),
    contact: parseJSON(d.contactPayloadJSON, null),
  };
}

/**
 * Ascolta gli ultimi `limit` messaggi. Il listener restituisce la finestra
 * intera già decifrata: sul web non c'è un database locale da riconciliare
 * come su iOS, quindi tenere lo stato in memoria è più semplice e non perde
 * nulla — al reload si riparte dal server.
 */
export function listenMessages({ familyId, familyKey, limit = PAGE_SIZE, onChange, onError }) {
  const q = query(messagesCol(familyId), orderBy("createdAt", "asc"), limitToLast(limit));
  return onSnapshot(
    q,
    async (snap) => {
      const messages = await Promise.all(snap.docs.map((d) => mapMessage(d, familyKey)));
      onChange({ messages, oldestDoc: snap.docs[0] || null });
    },
    (err) => onError?.(err)
  );
}

/**
 * Pagina all'indietro a partire dal documento più vecchio già in pagina.
 * `hasMore` è falso quando il server ne restituisce meno di quanti richiesti:
 * significa che siamo arrivati all'inizio della conversazione.
 */
export async function fetchOlderMessages({ familyId, familyKey, beforeDoc, limit = PAGE_SIZE }) {
  const snap = await getDocs(
    query(messagesCol(familyId), orderBy("createdAt", "asc"), endBefore(beforeDoc), limitToLast(limit))
  );
  const messages = await Promise.all(snap.docs.map((d) => mapMessage(d, familyKey)));
  return {
    messages,
    oldestDoc: snap.docs[0] || null,
    hasMore: snap.docs.length === limit,
  };
}

/* ── Invio ───────────────────────────────────────────────────────────────── */

async function writeMessage({ familyId, familyKey, uid, id, data, text }) {
  const payload = {
    familyId,
    updatedBy: uid,
    updatedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
    isDeleted: false,
    ...data,
  };

  if (typeof text === "string") {
    payload.textEnc = await encryptString(text, familyKey);
  }

  await setDoc(messageRef(familyId, id), payload, { merge: true });
}

export async function sendText({
  familyId,
  familyKey,
  uid,
  senderName,
  text,
  replyToId = null,
  mentions = [],
}) {
  const id = crypto.randomUUID();
  const data = {
    senderId: uid,
    senderName,
    type: "text",
  };
  if (replyToId) data.replyToId = replyToId;
  // Le menzioni vanno anche piatte in `mentionedUids`: è il campo su cui le
  // Cloud Functions decidono a chi mandare la notifica.
  if (mentions.length) {
    data.mentions = mentions.map((m) => ({ uid: m.uid, displayName: m.displayName }));
    data.mentionedUids = mentions.map((m) => m.uid);
  }
  await writeMessage({ familyId, familyKey, uid, id, data, text });
  return id;
}

export async function sendLocation({ familyId, familyKey, uid, senderName, latitude, longitude, replyToId = null }) {
  const id = crypto.randomUUID();
  const data = { senderId: uid, senderName, type: "location", latitude, longitude };
  if (replyToId) data.replyToId = replyToId;
  await writeMessage({ familyId, familyKey, uid, id, data });
  return id;
}

export async function sendContact({ familyId, familyKey, uid, senderName, contact, replyToId = null }) {
  const id = crypto.randomUUID();
  const fullName = `${contact.givenName} ${contact.familyName}`.trim() || "Contatto";
  const data = {
    senderId: uid,
    senderName,
    type: "contact",
    contactPayloadJSON: JSON.stringify({
      givenName: contact.givenName || "",
      familyName: contact.familyName || "",
      phoneNumbers: contact.phoneNumbers || [],
      emailAddresses: contact.emailAddresses || [],
      avatarData: null,
    }),
  };
  if (replyToId) data.replyToId = replyToId;
  await writeMessage({ familyId, familyKey, uid, id, data, text: fullName });
  return id;
}

/** Carica un file nella cartella del messaggio e ne restituisce path e URL. */
function uploadMedia({ familyId, messageId, fileName, blob, contentType, onProgress }) {
  const path = `families/${familyId}/chat/${messageId}/${fileName}`;
  const task = uploadBytesResumable(storageRef(storage, path), blob, { contentType });
  return new Promise((resolve, reject) => {
    task.on(
      "state_changed",
      (snap) => onProgress?.(snap.totalBytes ? snap.bytesTransferred / snap.totalBytes : 0),
      reject,
      async () => resolve({ path, url: await getDownloadURL(task.snapshot.ref) })
    );
  });
}

const MEDIA_FILE = {
  photo: { name: "photo.jpg", mime: "image/jpeg" },
  video: { name: "video.mp4", mime: "video/mp4" },
  audio: { name: "audio.m4a", mime: "audio/mp4" },
};

export async function sendMedia({
  familyId,
  familyKey,
  uid,
  senderName,
  type,
  blob,
  fileName,
  durationSeconds = null,
  replyToId = null,
  onProgress,
}) {
  const id = crypto.randomUUID();
  const isDocument = type === "document";
  const info = MEDIA_FILE[type];
  const name = isDocument ? fileName : info.name;
  const mime = isDocument ? blob.type || "application/octet-stream" : info.mime;

  const { path, url } = await uploadMedia({
    familyId,
    messageId: id,
    fileName: name,
    blob,
    contentType: mime,
    onProgress,
  });

  const data = {
    senderId: uid,
    senderName,
    type,
    mediaStoragePath: path,
    mediaURL: url,
    mediaFileSize: blob.size,
  };
  if (durationSeconds != null) data.mediaDurationSeconds = Math.round(durationSeconds);
  if (replyToId) data.replyToId = replyToId;

  // Il documento porta il nome del file nel testo: è ciò che la bolla mostra.
  await writeMessage({
    familyId,
    familyKey,
    uid,
    id,
    data,
    text: isDocument ? fileName : undefined,
  });
  return id;
}

/** Fino a dieci foto/video in un solo messaggio, come il mediaGroup di iOS. */
export async function sendMediaGroup({
  familyId,
  familyKey,
  uid,
  senderName,
  items,
  replyToId = null,
  onProgress,
}) {
  const capped = items.slice(0, MAX_GROUP_ITEMS);
  const id = crypto.randomUUID();
  const urls = [];
  const types = [];
  let uploadedBytes = 0;
  const totalBytes = capped.reduce((sum, item) => sum + item.blob.size, 0) || 1;

  for (let index = 0; index < capped.length; index += 1) {
    const item = capped[index];
    const isVideo = item.type === "video";
    const start = uploadedBytes;
    const { url } = await uploadMedia({
      // Ogni elemento ha la sua cartella `{messageId}_{index}`, esattamente
      // come li scrive iOS: altrimenti il secondo file sovrascriverebbe il primo.
      familyId,
      messageId: `${id}_${index}`,
      fileName: `group_${index}.${isVideo ? "mp4" : "jpg"}`,
      blob: item.blob,
      contentType: isVideo ? "video/mp4" : "image/jpeg",
      onProgress: (p) => onProgress?.((start + item.blob.size * p) / totalBytes),
    });
    urls.push(url);
    types.push(isVideo ? "video" : "photo");
    uploadedBytes += item.blob.size;
  }

  const data = {
    senderId: uid,
    senderName,
    type: "mediaGroup",
    mediaGroupURLsJSON: JSON.stringify(urls),
    mediaGroupTypesJSON: JSON.stringify(types),
    mediaFileSize: uploadedBytes,
  };
  if (replyToId) data.replyToId = replyToId;
  await writeMessage({ familyId, familyKey, uid, id, data });
  return id;
}

/* ── Modifica, reazioni, eliminazione ────────────────────────────────────── */

export async function editMessage({ familyId, familyKey, uid, messageId, text }) {
  await setDoc(
    messageRef(familyId, messageId),
    {
      textEnc: await encryptString(text, familyKey),
      isEdited: true,
      editedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      updatedBy: uid,
    },
    { merge: true }
  );
}

export function toggleReaction({ familyId, messageId, reactions, emoji, uid }) {
  const next = { ...reactions };
  const current = next[emoji] || [];
  if (current.includes(uid)) {
    const remaining = current.filter((id) => id !== uid);
    if (remaining.length) next[emoji] = remaining;
    else delete next[emoji];
  } else {
    next[emoji] = [...current, uid];
  }
  const json = Object.keys(next).length ? JSON.stringify(next) : null;
  return setDoc(
    messageRef(familyId, messageId),
    { reactionsJSON: json, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Elimina per tutti: il documento resta, ma la bolla diventa «eliminato». */
export async function deleteForEveryone({ familyId, uid, message }) {
  if (message.mediaStoragePath) {
    try {
      await deleteObject(storageRef(storage, message.mediaStoragePath));
    } catch {
      // Il file può già non esserci: quel che conta è che il messaggio sparisca.
    }
  }
  await setDoc(
    messageRef(familyId, message.id),
    { isDeleted: true, updatedBy: uid, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Elimina solo per me: gli altri continuano a vederlo. */
export function deleteForMe({ familyId, messageId, uid }) {
  return updateDoc(messageRef(familyId, messageId), { deletedFor: arrayUnion(uid) });
}

/** Svuota la chat: come su iOS ogni messaggio viene eliminato per tutti. */
export async function clearChat({ familyId, uid, messages }) {
  for (const message of messages) {
    await deleteForEveryone({ familyId, uid, message });
  }
}

/**
 * Rimuove un elemento da un mediaGroup. Se ne resta uno solo il messaggio
 * diventa una foto (o un video) singolo; se non ne resta nessuno sparisce.
 */
export async function removeFromGroup({ familyId, uid, message, index }) {
  const urls = [...message.mediaGroupURLs];
  const types = [...message.mediaGroupTypes];
  if (index < 0 || index >= urls.length) return;
  urls.splice(index, 1);
  types.splice(index, 1);

  if (!urls.length) {
    await deleteForEveryone({ familyId, uid, message });
    return;
  }
  if (urls.length === 1) {
    await setDoc(
      messageRef(familyId, message.id),
      {
        type: types[0] === "video" ? "video" : "photo",
        mediaURL: urls[0],
        mediaGroupURLsJSON: null,
        mediaGroupTypesJSON: null,
        updatedBy: uid,
        updatedAt: serverTimestamp(),
      },
      { merge: true }
    );
    return;
  }
  await setDoc(
    messageRef(familyId, message.id),
    {
      mediaGroupURLsJSON: JSON.stringify(urls),
      mediaGroupTypesJSON: JSON.stringify(types),
      updatedBy: uid,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

/* ── Letture e «sta scrivendo» ───────────────────────────────────────────── */

export async function markAsRead({ familyId, messageIds, uid }) {
  if (!messageIds.length) return;
  // Il limite del batch Firestore è 500 operazioni: si spezza a 450 come iOS.
  for (let i = 0; i < messageIds.length; i += 450) {
    const batch = writeBatch(db);
    for (const id of messageIds.slice(i, i + 450)) {
      batch.update(messageRef(familyId, id), { readBy: arrayUnion(uid) });
    }
    await batch.commit();
  }
}

export function setTyping({ familyId, uid, displayName, isTyping }) {
  return setDoc(
    typingRef(familyId, uid),
    { isTyping, name: displayName, updatedAt: serverTimestamp() },
    { merge: true }
  ).catch(() => {
    // «Sta scrivendo» è un di più: se fallisce non deve rompere l'invio.
  });
}

export function listenTyping({ familyId, excludeUid, onChange }) {
  return onSnapshot(collection(db, "families", familyId, "typing"), (snap) => {
    onChange(
      snap.docs
        .filter((d) => d.id !== excludeUid && d.data().isTyping === true)
        .map((d) => d.data().name || "")
        .filter(Boolean)
    );
  });
}

/** Elimina la riga «sta scrivendo» all'uscita dalla pagina. */
export function clearTyping({ familyId, uid }) {
  return deleteDoc(typingRef(familyId, uid)).catch(() => {});
}
