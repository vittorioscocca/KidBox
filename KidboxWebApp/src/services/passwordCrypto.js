/**
 * Cifratura del modulo Password, allineata a `PasswordCypher` su iOS.
 *
 * ## Quale chiave
 * - visibilità `family` e `members` → la chiave AES-256 di famiglia, la stessa
 *   che usano documenti, foto e note;
 * - visibilità `private` (su iOS `onlyCreator`) → una sotto-chiave derivata con
 *   HKDF-SHA256 da:
 *     IKM  = chiave di famiglia
 *     salt = UTF-8 dell'UID del CREATORE (`createdBy`)
 *     info = "KidBox.Password.v1.onlyCreator"
 *   così il testo cifrato è legato a chi l'ha scritto. Come su iOS, chi non è il
 *   creatore viene fermato prima ancora di provare a decifrare.
 *
 * Il formato è quello "combined" di CryptoKit — nonce(12) ‖ ciphertext ‖ tag(16) —
 * e su Firestore viaggia in base64.
 */
import { loadFamilyKey, loadFamilyKeyBytes } from "./familyKey";
import { encryptBytes, decryptBytes } from "./familyCrypto";

export const VISIBILITY_FAMILY = "family";
export const VISIBILITY_MEMBERS = "members";
export const VISIBILITY_PRIVATE = "private";

const HKDF_INFO = "KidBox.Password.v1.onlyCreator";

const enc = new TextEncoder();
const dec = new TextDecoder();

/** Le sotto-chiavi HKDF derivate, per non ripetere la derivazione a ogni campo. */
const subKeyCache = new Map();

/** Come `KBVisibilityScope.normalized` su iOS: tutto ciò che non è noto è `family`. */
export function normalizedVisibility(raw) {
  if (raw === VISIBILITY_MEMBERS) return VISIBILITY_MEMBERS;
  if (raw === VISIBILITY_PRIVATE) return VISIBILITY_PRIVATE;
  return VISIBILITY_FAMILY;
}

/** Chi può vedere la voce. Stessa regola di `KBVisibilityScope.isVisible`. */
export function isVisibleTo({ visibility, visibilityMemberIds, createdBy }, uid) {
  if (!uid) return false;
  switch (normalizedVisibility(visibility)) {
    case VISIBILITY_MEMBERS:
      return createdBy === uid || (visibilityMemberIds || []).includes(uid);
    case VISIBILITY_PRIVATE:
      return Boolean(createdBy) && createdBy === uid;
    default:
      return true;
  }
}

export class NotCreatorError extends Error {
  constructor() {
    super("Voce privata di un altro membro");
    this.name = "NotCreatorError";
  }
}

async function keyFor({ familyId, userId, visibility, createdBy }) {
  const vis = normalizedVisibility(visibility);
  if (vis !== VISIBILITY_PRIVATE) {
    return loadFamilyKey({ familyId, userId });
  }
  if (userId !== createdBy) throw new NotCreatorError();

  const cacheKey = `${familyId}.${userId}.${createdBy}`;
  if (subKeyCache.has(cacheKey)) return subKeyCache.get(cacheKey);

  const ikm = await loadFamilyKeyBytes({ familyId, userId });
  const hkdfKey = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveKey"]);
  const subKey = await crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: enc.encode(createdBy),
      info: enc.encode(HKDF_INFO),
    },
    hkdfKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"]
  );
  subKeyCache.set(cacheKey, subKey);
  return subKey;
}

export function bytesToB64(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 1) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

export function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

/** Cifra una stringa e restituisce il base64 pronto per Firestore. */
export async function encryptField(plain, ctx) {
  const key = await keyFor(ctx);
  return bytesToB64(await encryptBytes(enc.encode(plain), key));
}

/** Decifra un campo base64. `null`/vuoto restituisce `null`, come su iOS. */
export async function decryptField(b64, ctx) {
  if (!b64) return null;
  const key = await keyFor(ctx);
  return dec.decode(await decryptBytes(b64ToBytes(b64), key));
}

export function clearPasswordKeyCache() {
  subKeyCache.clear();
}
