/**
 * Famiglia: porta sul web `FamilySettingsView`, `SettingsFamilyCard`,
 * `InviteCodeViewModel`, `FamilyRevokeService` e `FamilyLeaveService` (iOS).
 *
 * Sono tutte scritture Firestore dirette, tranne l'eliminazione della famiglia
 * che passa dalla function `deleteFamily`: cancellare a mano le sottocollezioni
 * dal client lascerebbe indietro tutto ciò che le regole non lasciano toccare.
 *
 * L'invito è la parte delicata: il link trasporta il materiale che sblocca la
 * chiave di famiglia, quindi il segreto vive solo nel frammento dell'URL e su
 * Firestore ne finisce esclusivamente l'hash. Le costanti di derivazione sono
 * le stesse di `InviteCrypto` — cambiarne una carattere renderebbe l'invito
 * illeggibile ai client nativi.
 */
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDocs,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { db, functions } from "../firebase";
import { loadFamilyKeyBytes } from "./familyKey";

const INVITE_BASE_URL = "https://kidboxapp.com/join";
const INVITE_TTL_SECONDS = 24 * 3600;

const enc = new TextEncoder();

function randomBytes(length) {
  return crypto.getRandomValues(new Uint8Array(length));
}

function bytesToB64(bytes) {
  let bin = "";
  for (const byte of bytes) bin += String.fromCharCode(byte);
  return btoa(bin);
}

/** Base64 URL-safe senza padding, come `Data.base64url()` su iOS. */
function bytesToB64url(bytes) {
  return bytesToB64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256B64(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return bytesToB64(new Uint8Array(digest));
}

/** wrapKey = HKDF-SHA256(secret, salt, info = "kidbox-wrap:{familyId}", 32 byte). */
async function deriveWrapKey(secret, salt, familyId) {
  const ikm = await crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt, info: enc.encode(`kidbox-wrap:${familyId}`) },
    ikm,
    256
  );
  return crypto.subtle.importKey("raw", bits, "AES-GCM", false, ["encrypt"]);
}

export function inviteShareLink({ familyId, inviteId, secret }) {
  return `${INVITE_BASE_URL}?familyId=${familyId}&inviteId=${inviteId}#k=${secret}`;
}

/**
 * Crea un invito cifrato e restituisce link e payload QR.
 *
 * Il documento su Firestore contiene solo l'hash del segreto e la chiave di
 * famiglia wrappata: senza il segreto — che sta unicamente nel link — non è
 * ricostruibile. Nome famiglia e nome di chi invita sono denormalizzati perché
 * chi riceve il link li deve poter leggere prima di entrare, quando ancora non
 * ha accesso al documento famiglia.
 */
export async function createInvite({ familyId, familyName, inviterDisplayName, uid }) {
  const familyKey = await loadFamilyKeyBytes({ familyId, userId: uid });

  const inviteId = crypto.randomUUID();
  const secret = randomBytes(32);
  const salt = randomBytes(16);
  const nonce = randomBytes(12);

  const wrapKey = await deriveWrapKey(secret, salt, familyId);
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, wrapKey, familyKey)
  );
  // CryptoKit tiene ciphertext e tag separati, WebCrypto li concatena: il tag
  // sono gli ultimi 16 byte e va riscritto nel suo campo, o i client nativi non
  // riescono a fare l'unwrap.
  const cipher = sealed.slice(0, sealed.length - 16);
  const tag = sealed.slice(sealed.length - 16);

  const now = new Date();
  const expiresAt = new Date(now.getTime() + INVITE_TTL_SECONDS * 1000);

  await setDoc(doc(db, "families", familyId, "invites", inviteId), {
    createdAt: Timestamp.fromDate(now),
    createdBy: uid,
    expiresAt: Timestamp.fromDate(expiresAt),
    familyName: familyName || "",
    createdByDisplayName: inviterDisplayName || "",
    secretHash: await sha256B64(secret),
    kdfSalt: bytesToB64(salt),
    wrappedKeyCipher: bytesToB64(cipher),
    wrappedKeyNonce: bytesToB64(nonce),
    wrappedKeyTag: bytesToB64(tag),
    usedAt: null,
    usedBy: null,
  });

  const secretB64url = bytesToB64url(secret);
  return {
    inviteId,
    expiresAt,
    shareLink: inviteShareLink({ familyId, inviteId, secret: secretB64url }),
    qrPayload: `kidbox://join?familyId=${familyId}&inviteId=${inviteId}&secret=${secretB64url}`,
  };
}

/**
 * Annulla l'invito in corso: è la difesa che conta quando il link finisce al
 * contatto sbagliato, perché il segreto viaggia dentro l'URL e resta valido
 * finché il documento esiste.
 */
export function revokeInvite({ familyId, inviteId }) {
  return deleteDoc(doc(db, "families", familyId, "invites", inviteId));
}

export function renameFamily({ familyId, uid, name }) {
  return updateDoc(doc(db, "families", familyId), {
    name: name.trim(),
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
}

/** Toglie l'accesso a un membro. Le regole lo permettono al solo owner. */
export async function revokeMember({ familyId, targetUid }) {
  await deleteDoc(doc(db, "families", familyId, "members", targetUid));
  try {
    await deleteDoc(doc(db, "users", targetUid, "memberships", familyId));
  } catch {
    // Best effort: l'indice del membro revocato può non essere scrivibile da qui.
    // Quel che conta è la riga membro, ed è già sparita.
  }
}

/**
 * Esce dalla famiglia. Come su iOS l'uscita dell'unico membro è rifiutata:
 * lascerebbe una famiglia orfana sul server, e la strada giusta è eliminarla.
 */
export async function leaveFamily({ familyId, uid }) {
  const members = await getDocs(collection(db, "families", familyId, "members"));
  const active = members.docs.filter((d) => d.data().isDeleted !== true);
  if (active.length <= 1) {
    throw new Error("ONLY_MEMBER");
  }

  await deleteDoc(doc(db, "families", familyId, "members", uid));
  try {
    await deleteDoc(doc(db, "users", uid, "memberships", familyId));
  } catch {
    /* vedi sopra */
  }
}

/** Passa la ownership a un altro membro e poi esce, in questo ordine. */
export async function transferOwnershipAndLeave({ familyId, uid, newOwnerUid }) {
  const batch = writeBatch(db);
  batch.update(doc(db, "families", familyId), {
    ownerUid: newOwnerUid,
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
  batch.update(doc(db, "families", familyId, "members", newOwnerUid), {
    role: "owner",
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
  batch.update(doc(db, "families", familyId, "members", uid), {
    role: "member",
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
  await batch.commit();
  await leaveFamily({ familyId, uid });
}

/** Eliminazione completa: la fa la function, che vede le sottocollezioni. */
export async function deleteFamily(familyId) {
  const callable = httpsCallable(functions, "deleteFamily", { timeout: 120_000 });
  await callable({ familyId });
}
