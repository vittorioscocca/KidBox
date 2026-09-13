/**
 * Onboarding: porta sul web `FamilyCreationService`, `JoinWrapService`,
 * `FamilyInviteLinkJoiner` e `KBActiveFamilyRemoteStore` (iOS).
 *
 * Due strade, come nel wizard nativo:
 * - creare una famiglia: documenti su Firestore, poi la chiave di famiglia
 *   nasce QUI e una volta sola, e finisce subito sull'escrow del creatore;
 * - entrare con un invito: il link porta il segreto nel frammento, che
 *   sblocca la chiave wrappata nell'invito; la chiave va sull'escrow del nuovo
 *   membro PRIMA della membership, così non esiste mai un membro senza chiave.
 *
 * Costanti e derivazioni sono quelle di `InviteCrypto`: un carattere diverso e
 * i client nativi non riescono più a fare l'unwrap di ciò che il web scrive.
 */
import {
  Timestamp,
  deleteField,
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  writeBatch,
} from "firebase/firestore";
import { db } from "../firebase";
import { backupFamilyKey } from "./familyKey";
import { PLACEHOLDER_NAME } from "./profile";

const enc = new TextEncoder();

export class JoinInviteError extends Error {
  /** @param {"invalidPayload"|"expired"|"invalidSecret"|"alreadyUsed"|"alreadyMember"} code */
  constructor(code) {
    super(code);
    this.name = "JoinInviteError";
    this.code = code;
  }
}

function bytesToB64(bytes) {
  let bin = "";
  for (const byte of bytes) bin += String.fromCharCode(byte);
  return btoa(bin);
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

/** Inverso di `Data.base64url()`: tollera anche il base64 standard. */
function b64urlToBytes(str) {
  let b64 = str.replace(/-/g, "+").replace(/_/g, "/");
  while (b64.length % 4) b64 += "=";
  try {
    return b64ToBytes(b64);
  } catch {
    return null;
  }
}

async function sha256B64(bytes) {
  return bytesToB64(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}

async function deriveWrapKey(secret, salt, familyId) {
  const ikm = await crypto.subtle.importKey("raw", secret, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt, info: enc.encode(`kidbox-wrap:${familyId}`) },
    ikm,
    256
  );
  return crypto.subtle.importKey("raw", bits, "AES-GCM", false, ["decrypt"]);
}

/**
 * Riconosce un invito in tutte le forme in cui può arrivare:
 * - link web `https://kidboxapp.com/join?familyId=…&inviteId=…#k=…`
 *   (il segreto sta nel frammento, che non viaggia mai verso il server);
 * - payload del QR `kidbox://join?familyId=…&inviteId=…&secret=…`.
 * Restituisce null se manca un pezzo. Non logga mai il segreto.
 */
export function parseInvite(raw) {
  const text = (raw || "").trim();
  if (!text) return null;
  let url;
  try {
    url = new URL(text);
  } catch {
    return null;
  }
  const isWeb = /^https?:$/.test(url.protocol) && url.pathname.replace(/\/$/, "") === "/join";
  const isScheme = url.protocol === "kidbox:" && (url.host === "join" || url.pathname === "//join");
  if (!isWeb && !isScheme) return null;

  const familyId = url.searchParams.get("familyId");
  const inviteId = url.searchParams.get("inviteId");
  const secretStr =
    url.searchParams.get("secret") || new URLSearchParams(url.hash.replace(/^#/, "")).get("k");
  if (!familyId || !inviteId || !secretStr) return null;
  const secret = b64urlToBytes(secretStr);
  if (!secret || secret.length === 0) return null;
  return { familyId, inviteId, secret };
}

/**
 * Nome famiglia e di chi invita, letti dall'invito prima di entrare: sono
 * denormalizzati lì apposta, perché il documento famiglia non è leggibile a
 * chi non è ancora membro. Null se l'invito non esiste più.
 */
export async function readInvitePreview({ familyId, inviteId }) {
  const snap = await getDoc(doc(db, "families", familyId, "invites", inviteId));
  if (!snap.exists()) return null;
  const d = snap.data();
  return {
    familyName: d.familyName || "",
    inviterName: d.createdByDisplayName || "",
    used: !!d.usedAt,
    expired: d.expiresAt ? d.expiresAt.toDate() <= new Date() : false,
  };
}

/** Come `KBActiveFamilyRemoteStore.save`: best effort, non blocca. */
export async function saveActiveFamily({ uid, familyId }) {
  try {
    await setDoc(
      doc(db, "users", uid),
      { activeFamilyId: familyId, activeFamilyUpdatedAt: serverTimestamp() },
      { merge: true }
    );
  } catch {
    // La prossima scrittura riallinea.
  }
}

/**
 * Crea la famiglia. Stesso ordine di `FamilyRemoteStore.createFamilyWithChild`:
 * prima famiglia + membro + indice membership in un batch (le regole del figlio
 * pretendono la membership già scritta), poi il figlio, poi la chiave.
 */
export async function createFamily({ uid, displayName, name, childName, childBirthDate }) {
  const familyId = crypto.randomUUID().toUpperCase();
  const child = childName.trim();

  const familyRef = doc(db, "families", familyId);
  const batch = writeBatch(db);
  batch.set(familyRef, {
    name: name.trim(),
    ownerUid: uid,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  const member = { uid, role: "owner", createdAt: serverTimestamp() };
  if (displayName && displayName !== PLACEHOLDER_NAME) member.displayName = displayName;
  batch.set(doc(db, "families", familyId, "members", uid), member);
  batch.set(doc(db, "users", uid, "memberships", familyId), {
    familyId,
    role: "owner",
    createdAt: serverTimestamp(),
  });
  await batch.commit();

  if (child) {
    const childData = {
      name: child,
      isDeleted: false,
      createdAt: serverTimestamp(),
      updatedBy: uid,
      updatedAt: serverTimestamp(),
    };
    if (childBirthDate) childData.birthDate = Timestamp.fromDate(childBirthDate);
    await setDoc(doc(db, "families", familyId, "children", crypto.randomUUID().toUpperCase()), childData);
  }

  // La chiave di famiglia nasce qui e una volta sola (vedi MasterKeyMigration
  // su iOS): senza Keychain, l'escrow è l'unico posto in cui vive.
  const rawKey = crypto.getRandomValues(new Uint8Array(32));
  await backupFamilyKey({ familyId, userId: uid, rawKey });

  await saveActiveFamily({ uid, familyId });
  return familyId;
}

/**
 * Consuma l'invito ed entra nella famiglia.
 *
 * 1. Transazione: scadenza, uso singolo, hash del segreto; poi l'invito resta
 *    marcato usato e SVUOTATO del materiale cifrato — serve alle regole come
 *    prova dell'iscrizione, ma non deve continuare a portare la chiave.
 * 2. Unwrap della chiave e deposito sull'escrow del nuovo membro.
 * 3. Membro + membership, con `inviteId` sul membro (è ciò che le regole
 *    future chiederanno) e il nome già dentro, così non nasce anonimo.
 */
export async function joinWithInvite({ uid, displayName, invite, alreadyMemberOf = [] }) {
  const { familyId, inviteId, secret } = invite;
  if (alreadyMemberOf.includes(familyId)) throw new JoinInviteError("alreadyMember");

  const inviteRef = doc(db, "families", familyId, "invites", inviteId);
  const expectedHash = await sha256B64(secret);

  const data = await runTransaction(db, async (txn) => {
    const snap = await txn.get(inviteRef);
    if (!snap.exists()) throw new JoinInviteError("invalidPayload");
    const d = snap.data();
    if (d.expiresAt && d.expiresAt.toDate() <= new Date()) throw new JoinInviteError("expired");
    if (d.usedAt) throw new JoinInviteError("alreadyUsed");
    if ((d.secretHash || "") !== expectedHash) throw new JoinInviteError("invalidSecret");
    txn.update(inviteRef, {
      usedAt: Timestamp.now(),
      usedBy: uid,
      kdfSalt: deleteField(),
      secretHash: deleteField(),
      wrappedKeyCipher: deleteField(),
      wrappedKeyNonce: deleteField(),
      wrappedKeyTag: deleteField(),
    });
    return d;
  });

  if (!data.kdfSalt || !data.wrappedKeyCipher || !data.wrappedKeyNonce || !data.wrappedKeyTag) {
    throw new JoinInviteError("invalidPayload");
  }
  const wrapKey = await deriveWrapKey(secret, b64ToBytes(data.kdfSalt), familyId);
  const cipher = b64ToBytes(data.wrappedKeyCipher);
  const tag = b64ToBytes(data.wrappedKeyTag);
  const payload = new Uint8Array(cipher.length + tag.length);
  payload.set(cipher, 0);
  payload.set(tag, cipher.length);
  let rawKey;
  try {
    rawKey = new Uint8Array(
      await crypto.subtle.decrypt({ name: "AES-GCM", iv: b64ToBytes(data.wrappedKeyNonce) }, wrapKey, payload)
    );
  } catch {
    throw new JoinInviteError("invalidSecret");
  }
  await backupFamilyKey({ familyId, userId: uid, rawKey });

  const batch = writeBatch(db);
  const member = {
    uid,
    role: "member",
    isDeleted: false,
    inviteId,
    updatedBy: uid,
    updatedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  };
  if (displayName && displayName !== PLACEHOLDER_NAME) member.displayName = displayName;
  batch.set(doc(db, "families", familyId, "members", uid), member, { merge: true });
  batch.set(
    doc(db, "users", uid, "memberships", familyId),
    { familyId, role: "member", createdAt: serverTimestamp() },
    { merge: true }
  );
  await batch.commit();

  await saveActiveFamily({ uid, familyId });
  return familyId;
}
