import { doc, getDoc } from "firebase/firestore";
import { db } from "../firebase";

/**
 * Recupero della master key di famiglia sul web.
 *
 * Porting di FamilyKeyEscrowService (iOS) / FamilyKeyEscrow.kt (Android): la
 * chiave AES-256 della famiglia è wrappata con una chiave derivata in modo
 * deterministico da (userId, familyId) e depositata su
 * `families/{familyId}/memberKeyBackups/{userId}`.
 *
 * Il web non ha un Keychain/Keystore in cui la chiave possa essere già presente,
 * quindi passa sempre dall'escrow — che è esattamente il percorso previsto dai
 * client nativi dopo una reinstallazione o un cambio device.
 *
 * ⚠️ Costanti e stringhe di derivazione DEVONO restare identiche ai client: un
 * carattere diverso produce una chiave diversa e le note diventano illeggibili.
 */
const ESCROW_SALT = "kidbox-escrow-salt-2026";
const ESCROW_CONTEXT = "kidbox-key-escrow-v1";

const enc = new TextEncoder();
const keyCache = new Map();

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

/**
 * ikm  = SHA-256("{userId}:{familyId}:{context}")
 * key  = HKDF-SHA256(ikm, salt, info = "{context}:{userId}:{familyId}", 32 byte)
 */
async function deriveEscrowKey(userId, familyId) {
  const ikmBytes = await crypto.subtle.digest(
    "SHA-256",
    enc.encode(`${userId}:${familyId}:${ESCROW_CONTEXT}`)
  );
  const ikm = await crypto.subtle.importKey("raw", ikmBytes, "HKDF", false, [
    "deriveBits",
  ]);
  const bits = await crypto.subtle.deriveBits(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: enc.encode(ESCROW_SALT),
      info: enc.encode(`${ESCROW_CONTEXT}:${userId}:${familyId}`),
    },
    ikm,
    256
  );
  return crypto.subtle.importKey("raw", bits, "AES-GCM", false, ["decrypt"]);
}

/** Errore distinguibile: la famiglia non ha (ancora) un backup della chiave. */
export class MissingFamilyKeyError extends Error {
  constructor(familyId) {
    super(`Chiave di famiglia non disponibile per ${familyId}`);
    this.name = "MissingFamilyKeyError";
    this.familyId = familyId;
  }
}

/**
 * Carica la master key della famiglia, o lancia MissingFamilyKeyError.
 * Il risultato è tenuto in memoria per la sessione: la derivazione è costosa e
 * la chiave non cambia.
 */
export async function loadFamilyKey({ familyId, userId }) {
  if (!familyId || !userId) throw new MissingFamilyKeyError(familyId);

  const cacheKey = `${userId}.${familyId}`;
  if (keyCache.has(cacheKey)) return keyCache.get(cacheKey);

  const snap = await getDoc(
    doc(db, "families", familyId, "memberKeyBackups", userId)
  );
  if (!snap.exists()) throw new MissingFamilyKeyError(familyId);

  const { cipher, nonce, tag } = snap.data();
  if (!cipher || !nonce || !tag) throw new MissingFamilyKeyError(familyId);

  const escrowKey = await deriveEscrowKey(userId, familyId);

  // CryptoKit tiene ciphertext e tag separati, WebCrypto li vuole concatenati.
  const cipherBytes = b64ToBytes(cipher);
  const tagBytes = b64ToBytes(tag);
  const payload = new Uint8Array(cipherBytes.length + tagBytes.length);
  payload.set(cipherBytes, 0);
  payload.set(tagBytes, cipherBytes.length);

  let rawKey;
  try {
    rawKey = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: b64ToBytes(nonce) },
      escrowKey,
      payload
    );
  } catch {
    // Unwrap fallito: payload corrotto o costanti di derivazione disallineate.
    throw new MissingFamilyKeyError(familyId);
  }

  const familyKey = await crypto.subtle.importKey(
    "raw",
    rawKey,
    "AES-GCM",
    false,
    ["encrypt", "decrypt"]
  );
  keyCache.set(cacheKey, familyKey);
  return familyKey;
}

export function clearFamilyKeyCache() {
  keyCache.clear();
}
