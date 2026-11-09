import { doc, getDoc, serverTimestamp, setDoc } from "firebase/firestore";
import { db } from "../firebase";
import {
  getLocalVault,
  keyVaultFlags,
  openFamilyKeyV2,
  sealFamilyKeyV2,
  writeAndVerifyFamilyKeyV2,
} from "./familyKeyVault";

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
 * Dal 09/11/2026 lo stesso documento porta anche la copia v2 (mappa `v2`,
 * chiusa con la chiave personale: `familyKeyVault.js`). Ordine di lettura: v2
 * se questo browser ha la chiave personale, poi v1 finché esiste. La v1 si
 * scrive sempre, come prima: è la rete fino alla Fase 3 del piano.
 *
 * ⚠️ Costanti e stringhe di derivazione DEVONO restare identiche ai client: un
 * carattere diverso produce una chiave diversa e le note diventano illeggibili.
 */
const ESCROW_SALT = "kidbox-escrow-salt-2026";
const ESCROW_CONTEXT = "kidbox-key-escrow-v1";

const enc = new TextEncoder();
const keyCache = new Map();
const rawKeyCache = new Map();

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

/**
 * ikm  = SHA-256("{userId}:{familyId}:{context}")
 * key  = HKDF-SHA256(ikm, salt, info = "{context}:{userId}:{familyId}", 32 byte)
 */
async function deriveEscrowKey(userId, familyId, usages = ["decrypt"]) {
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
  return crypto.subtle.importKey("raw", bits, "AES-GCM", false, usages);
}

/** Stesso valore di `FamilyKeyEscrowService.currentVersion` su iOS. */
const ESCROW_VERSION = 1;

/**
 * Deposita la chiave di famiglia sull'escrow del membro corrente.
 *
 * Porting di `FamilyKeyEscrowService.backup`. Sul web è un passo obbligato e
 * non un backup: non c'è un Keychain, quindi la chiave appena generata (o
 * appena ricevuta da un invito) sopravvive alla sessione solo qui. Il payload
 * segue il formato dei nativi — ciphertext e tag separati — perché lo stesso
 * documento va letto anche da iOS e Android dopo un cambio device.
 */
export async function backupFamilyKey({ familyId, userId, rawKey }) {
  const escrowKey = await deriveEscrowKey(userId, familyId, ["encrypt"]);
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, escrowKey, rawKey)
  );
  const cipher = sealed.slice(0, sealed.length - 16);
  const tag = sealed.slice(sealed.length - 16);

  const data = {
    cipher: bytesToB64(cipher),
    nonce: bytesToB64(nonce),
    tag: bytesToB64(tag),
    updatedAt: serverTimestamp(),
    version: ESCROW_VERSION,
  };
  // La copia v2 nello stesso documento, se questo browser ha già la chiave
  // personale. Senza, il documento resta solo v1 e la v2 si aggiunge quando
  // l'utente crea o apre la cassaforte. Un errore qui non deve mai fermare
  // l'ingresso in famiglia (sezione 4 bis, regola 1).
  try {
    const local = (await keyVaultFlags(userId)).active ? await getLocalVault(userId) : null;
    if (local) data.v2 = await sealFamilyKeyV2({ uid: userId, familyId, rawFamilyKey: rawKey, local });
  } catch (err) {
    console.warn("[Vault] copia v2 rimandata", err?.name);
  }
  // Fase 3 per questa famiglia (`keyV1Closed`): le rules accettano solo la v2.
  // Si scrive quella sola; senza cassaforte qui non si scrive niente, ma
  // l'ingresso in famiglia va avanti (la chiave resta in sessione).
  const familySnap = await getDoc(doc(db, "families", familyId)).catch(() => null);
  if (familySnap?.data()?.keyV1Closed === true) {
    if (data.v2) {
      await setDoc(
        doc(db, "families", familyId, "memberKeyBackups", userId),
        { version: 2, v2: data.v2, updatedAt: serverTimestamp() },
        { merge: true }
      );
    } else {
      console.warn("[Vault] v1 chiusa e nessuna cassaforte qui: copia non scritta");
    }
  } else {
    try {
      await setDoc(doc(db, "families", familyId, "memberKeyBackups", userId), data);
    } catch (err) {
      // Chi sta entrando non legge ancora il documento famiglia: se la v1 è
      // chiusa lo dice solo il rifiuto delle rules. Non si ferma l'ingresso.
      if (familySnap === null && err?.code === "permission-denied") {
        console.warn("[Vault] copia v1 rifiutata (famiglia con v1 chiusa?): non scritta");
      } else {
        throw err;
      }
    }
  }

  const cacheKey = `${userId}.${familyId}`;
  rawKeyCache.set(cacheKey, new Uint8Array(rawKey));
  keyCache.set(
    cacheKey,
    await crypto.subtle.importKey("raw", rawKey, "AES-GCM", false, ["encrypt", "decrypt"])
  );
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

  const backup = snap.data();
  const local = backup.v2 ? await getLocalVault(userId) : null;
  const fromV2 = await openFamilyKeyV2({ uid: userId, familyId, v2: backup.v2, local });
  if (fromV2) return remember(cacheKey, fromV2);

  const { cipher, nonce, tag } = backup;
  if (!cipher || !nonce || !tag) {
    // Solo v2 (dopo la Fase 3) e questo browser non ha la chiave personale:
    // la cassaforte va aperta, non è un errore dei dati.
    const err = new MissingFamilyKeyError(familyId);
    err.vaultLocked = !!backup.v2;
    throw err;
  }

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

  const raw = new Uint8Array(rawKey);
  // Aperta dalla v1: se la cassaforte è attiva su questo browser e la copia v2
  // manca, la si aggiunge adesso, in background e senza bloccare la lettura.
  if (!backup.v2) addMissingV2(userId, familyId, raw);
  return remember(cacheKey, raw);
}

async function remember(cacheKey, raw) {
  const familyKey = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
  keyCache.set(cacheKey, familyKey);
  rawKeyCache.set(cacheKey, new Uint8Array(raw));
  return familyKey;
}

function addMissingV2(userId, familyId, raw) {
  (async () => {
    if (!(await keyVaultFlags(userId)).active) return;
    if (!(await getLocalVault(userId))) return;
    await writeAndVerifyFamilyKeyV2({ uid: userId, familyId, rawFamilyKey: raw });
  })().catch((err) => console.warn("[Vault] copia v2 non scritta", err?.code || err?.name));
}

/**
 * Dopo aver creato o aperto la cassaforte: copia v2 (verificata) per ogni
 * famiglia la cui chiave questo browser sa leggere. Le famiglie senza chiave
 * si saltano: non è compito di questo passo.
 */
export async function syncFamilyKeysV2({ userId, familyIds }) {
  const out = {};
  for (const familyId of familyIds) {
    try {
      const raw = await loadFamilyKeyBytes({ familyId, userId });
      out[familyId] = await writeAndVerifyFamilyKeyV2({ uid: userId, familyId, rawFamilyKey: raw });
    } catch (err) {
      out[familyId] = false;
      console.warn(`[Vault] copia v2 saltata per ${familyId}`, err?.name || err?.code);
    }
  }
  return out;
}

/**
 * I byte grezzi della chiave di famiglia.
 *
 * Servono alle password con visibilità «solo io»: iOS ne deriva una sotto-chiave
 * con HKDF, e HKDF vuole il materiale grezzo, mentre `loadFamilyKey` restituisce
 * di proposito una chiave AES non esportabile. Non è un indebolimento — sono gli
 * stessi byte che questo modulo maneggia già per fare l'unwrap — ma resta una
 * funzione separata, così chi cifra file continua a passare dalla chiave chiusa.
 */
export async function loadFamilyKeyBytes({ familyId, userId }) {
  const cacheKey = `${userId}.${familyId}`;
  if (!rawKeyCache.has(cacheKey)) await loadFamilyKey({ familyId, userId });
  return rawKeyCache.get(cacheKey);
}

export function clearFamilyKeyCache() {
  keyCache.clear();
  rawKeyCache.clear();
}

/**
 * La chiave di una famiglia arrivata col QR da un familiare: la si ricorda per
 * la sessione, la si salva nella copia v1 (finché esiste) e, se la cassaforte
 * è aperta qui, nella copia v2.
 */
export async function adoptHandedFamilyKey({ familyId, userId, rawKey }) {
  await remember(`${userId}.${familyId}`, rawKey);
  try {
    await backupFamilyKey({ familyId, userId, rawKey });
  } catch (err) {
    console.warn("[Vault] copia v1 non scritta", err?.code || err?.name);
  }
  addMissingV2(userId, familyId, rawKey);
}
