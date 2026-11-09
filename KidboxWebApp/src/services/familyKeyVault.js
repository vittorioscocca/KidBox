import {
  collection,
  doc,
  getDoc,
  getDocFromServer,
  getDocs,
  runTransaction,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";
import { db } from "../firebase";

/**
 * Cassaforte della chiave di famiglia, v2 (piano in
 * `internal/cifratura-chiave-di-riserva-v2.md`, sezione 3 e «Costanti v2»).
 *
 *   segreto (codice di recupero / passkey)
 *       └─ apre ─▶ chiave personale RK (32 byte, una per utente)
 *                      └─ apre ─▶ chiave di famiglia A, B, …
 *
 * - La RK è dell'utente, non della famiglia: un solo codice anche con più
 *   famiglie. Su questo browser vive in IndexedDB come `CryptoKey` HKDF **non
 *   esportabile**; i byte grezzi esistono in memoria solo mentre si crea la
 *   cassaforte o si aggiunge uno slot.
 * - Gli slot stanno in `users/{uid}/keyVault/{slotId}`: `recoveryCode` e
 *   `passkey_<id>`, uno per credenziale. Il server vede solo byte chiusi.
 * - La copia v2 della chiave di famiglia sta nel documento di sempre,
 *   `families/{fid}/memberKeyBackups/{uid}`, nella mappa `v2`, ACCANTO ai campi
 *   della v1: la v1 resta come rete finché non si chiude (Fase 3).
 *
 * ⚠️ Le costanti qui sotto vanno copiate IDENTICHE su iOS e Android: un
 * carattere diverso = chiave diversa = dati illeggibili, senza un errore.
 */
export const VAULT_CONTEXT = "kidbox-vault-v2";
export const VAULT_VERSION = 2;
const INFO_SLOT_RECOVERY = "kidbox-vault-v2:slot:recoveryCode";
const INFO_SLOT_PASSKEY = "kidbox-vault-v2:slot:passkey";
const INFO_RK_ID = "kidbox-vault-v2:rk-id";
const INFO_FAMILY = "kidbox-vault-v2:family";
const AAD_SLOT_PREFIX = "kidbox-vault-v2:rk:"; // + uid
const AAD_FAMILY_PREFIX = "kidbox-vault-v2:family:"; // + uid + ":" + familyId
const PRF_INPUT = "kidbox-vault-v2:prf";
/** Alfabeto base32 di Crockford: niente I, L, O, U. 24 caratteri = 120 bit. */
const CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
const CODE_LENGTH = 24;

const SLOT_RECOVERY = "recoveryCode";
const enc = new TextEncoder();

// ── byte ──────────────────────────────────────────────────────────────────

function bytesToB64(bytes) {
  let bin = "";
  for (const byte of bytes) bin += String.fromCharCode(byte);
  return btoa(bin);
}

function b64ToBytes(b64) {
  const norm = b64.replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(norm + "===".slice((norm.length + 3) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

const bytesToB64Url = (bytes) =>
  bytesToB64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** AES-GCM con ciphertext e tag separati, come CryptoKit e gli altri client. */
async function seal(key, plain, aad) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const sealed = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce, additionalData: enc.encode(aad) }, key, plain)
  );
  return {
    cipher: bytesToB64(sealed.slice(0, sealed.length - 16)),
    nonce: bytesToB64(nonce),
    tag: bytesToB64(sealed.slice(sealed.length - 16)),
  };
}

async function open(key, { cipher, nonce, tag }, aad) {
  const c = b64ToBytes(cipher);
  const t = b64ToBytes(tag);
  const payload = new Uint8Array(c.length + t.length);
  payload.set(c, 0);
  payload.set(t, c.length);
  return new Uint8Array(
    await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: b64ToBytes(nonce), additionalData: enc.encode(aad) },
      key,
      payload
    )
  );
}

async function hkdfAesKey(ikmBytesOrKey, salt, info, usages) {
  const base =
    ikmBytesOrKey instanceof CryptoKey
      ? ikmBytesOrKey
      : await crypto.subtle.importKey("raw", ikmBytesOrKey, "HKDF", false, ["deriveKey"]);
  return crypto.subtle.deriveKey(
    { name: "HKDF", hash: "SHA-256", salt, info: enc.encode(info) },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    usages
  );
}

/** Identificativo pubblico della RK: dice quale RK apre una copia, non la svela. */
async function rkIdOf(rkBase) {
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: enc.encode(INFO_RK_ID) },
    rkBase,
    128
  );
  return bytesToB64Url(new Uint8Array(bits));
}

const importRkBase = (rkBytes) =>
  crypto.subtle.importKey("raw", rkBytes, "HKDF", false, ["deriveKey", "deriveBits"]);

// ── codice di recupero ────────────────────────────────────────────────────

/** 24 caratteri da 15 byte casuali, a gruppi di 4: XXXX-XXXX-…-XXXX. */
export function generateRecoveryCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(15));
  let bits = 0;
  let value = 0;
  let out = "";
  for (const b of bytes) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += CODE_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  return formatRecoveryCode(out);
}

/**
 * Forma canonica: maiuscole, senza spazi né trattini, O→0 e I/L→1 (gli
 * errori di battitura che l'alfabeto di Crockford perdona). `null` se non è
 * un codice valido.
 */
export function normalizeRecoveryCode(input) {
  const s = String(input || "")
    .toUpperCase()
    .replace(/[\s-]/g, "")
    .replace(/O/g, "0")
    .replace(/[IL]/g, "1");
  if (s.length !== CODE_LENGTH) return null;
  for (const ch of s) if (!CODE_ALPHABET.includes(ch)) return null;
  return s;
}

export const formatRecoveryCode = (canonical) => canonical.match(/.{1,4}/g).join("-");

// ── IndexedDB: la RK di questo browser ────────────────────────────────────

const IDB_NAME = "kidbox-vault";
const IDB_STORE = "rk";

function idb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(IDB_STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function idbDo(mode, fn) {
  const dbh = await idb();
  try {
    return await new Promise((resolve, reject) => {
      const tx = dbh.transaction(IDB_STORE, mode);
      const req = fn(tx.objectStore(IDB_STORE));
      tx.oncomplete = () => resolve(req?.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    dbh.close();
  }
}

const localCache = new Map();

/** La RK di questo browser per `uid`, o null. Mai un errore: IndexedDB può mancare. */
export async function getLocalVault(uid) {
  if (!uid) return null;
  if (localCache.has(uid)) return localCache.get(uid);
  let entry = null;
  try {
    const row = await idbDo("readonly", (s) => s.get(uid));
    if (row?.rkBase instanceof CryptoKey && row.rkId) entry = { rkBase: row.rkBase, rkId: row.rkId };
  } catch (err) {
    console.warn("[Vault] IndexedDB non leggibile", err?.name);
  }
  localCache.set(uid, entry);
  return entry;
}

async function saveLocalVault(uid, rkBase, rkId) {
  localCache.set(uid, { rkBase, rkId });
  try {
    await idbDo("readwrite", (s) => s.put({ rkBase, rkId, savedAt: Date.now() }, uid));
  } catch (err) {
    // Navigazione privata o spazio negato: la RK vale per questa sessione.
    console.warn("[Vault] RK non salvata in IndexedDB", err?.name);
  }
}

/** All'uscita dall'account questo browser dimentica la RK (come WhatsApp Web). */
export async function forgetLocalVault(uid) {
  if (!uid) return;
  localCache.delete(uid);
  try {
    await idbDo("readwrite", (s) => s.delete(uid));
  } catch {
    /* niente da dimenticare */
  }
}

// ── la cassaforte sul server ──────────────────────────────────────────────

const vaultCol = (uid) => collection(db, "users", uid, "keyVault");

/** Gli slot della cassaforte, letti dal server. `[]` = la cassaforte non esiste. */
export async function listVaultSlots(uid) {
  const snap = await getDocs(vaultCol(uid));
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function slotRecord({ uid, rkBytes, rkId, type, ikm, credentialId, label }) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const slotKey = await hkdfAesKey(
    ikm,
    salt,
    type === SLOT_RECOVERY ? INFO_SLOT_RECOVERY : INFO_SLOT_PASSKEY,
    ["encrypt"]
  );
  const sealed = await seal(slotKey, rkBytes, AAD_SLOT_PREFIX + uid);
  const rec = {
    type,
    version: VAULT_VERSION,
    rkId,
    salt: bytesToB64(salt),
    ...sealed,
    createdAt: serverTimestamp(),
  };
  if (credentialId) rec.credentialId = credentialId;
  if (label) rec.label = label.slice(0, 80);
  return rec;
}

async function openSlot({ uid, slot, ikm }) {
  const slotKey = await hkdfAesKey(
    ikm,
    b64ToBytes(slot.salt),
    slot.type === SLOT_RECOVERY ? INFO_SLOT_RECOVERY : INFO_SLOT_PASSKEY,
    ["decrypt"]
  );
  const rkBytes = await open(slotKey, slot, AAD_SLOT_PREFIX + uid);
  if (rkBytes.length !== 32) throw new Error("RK di lunghezza inattesa");
  return rkBytes;
}

export class VaultExistsError extends Error {
  constructor() {
    super("La cassaforte esiste già");
    this.name = "VaultExistsError";
  }
}

export class WrongSecretError extends Error {
  constructor() {
    super("Segreto non valido");
    this.name = "WrongSecretError";
  }
}

/**
 * Crea la cassaforte: RK nuova + slot del codice di recupero. Il codice va
 * mostrato all'utente PRIMA (è lui a passarlo qui dopo la conferma).
 * Transazione: se un altro dispositivo l'ha appena creata, `VaultExistsError`
 * e si passa ad aprirla, senza sovrascrivere la RK di nessuno.
 *
 * Restituisce `rkBytes` per aggiungere subito una passkey: chi chiama li azzera.
 */
export async function createVault({ uid, recoveryCode }) {
  const canonical = normalizeRecoveryCode(recoveryCode);
  if (!canonical) throw new WrongSecretError();
  const rkBytes = crypto.getRandomValues(new Uint8Array(32));
  const rkBase = await importRkBase(rkBytes);
  const rkId = await rkIdOf(rkBase);
  const rec = await slotRecord({
    uid,
    rkBytes,
    rkId,
    type: SLOT_RECOVERY,
    ikm: enc.encode(canonical),
  });

  const existing = await getDocs(vaultCol(uid));
  if (!existing.empty) throw new VaultExistsError();
  const ref = doc(db, "users", uid, "keyVault", SLOT_RECOVERY);
  await runTransaction(db, async (txn) => {
    const snap = await txn.get(ref);
    if (snap.exists()) throw new VaultExistsError();
    txn.set(ref, rec);
  });

  await saveLocalVault(uid, rkBase, rkId);
  return { rkId, rkBytes };
}

/** Apre la cassaforte col codice di recupero e la salva su questo browser. */
export async function openVaultWithRecoveryCode({ uid, recoveryCode }) {
  const canonical = normalizeRecoveryCode(recoveryCode);
  if (!canonical) throw new WrongSecretError();
  const snap = await getDoc(doc(db, "users", uid, "keyVault", SLOT_RECOVERY));
  if (!snap.exists()) throw new WrongSecretError();
  let rkBytes;
  try {
    rkBytes = await openSlot({ uid, slot: snap.data(), ikm: enc.encode(canonical) });
  } catch {
    throw new WrongSecretError();
  }
  return adoptRk(uid, rkBytes, snap.data().rkId);
}

async function adoptRk(uid, rkBytes, expectedRkId) {
  const rkBase = await importRkBase(rkBytes);
  const rkId = await rkIdOf(rkBase);
  if (expectedRkId && rkId !== expectedRkId) throw new WrongSecretError();
  await saveLocalVault(uid, rkBase, rkId);
  return { rkId, rkBytes };
}

/** «Rigenera codice»: slot nuovo con la stessa RK, il vecchio smette di valere. */
export async function replaceRecoveryCode({ uid, rkBytes, rkId, recoveryCode }) {
  const canonical = normalizeRecoveryCode(recoveryCode);
  if (!canonical) throw new WrongSecretError();
  const rec = await slotRecord({ uid, rkBytes, rkId, type: SLOT_RECOVERY, ikm: enc.encode(canonical) });
  rec.updatedAt = serverTimestamp();
  await setDoc(doc(db, "users", uid, "keyVault", SLOT_RECOVERY), rec);
}

// ── passaggio col QR (keyHandoff.js) ──────────────────────────────────────

/** Byte e AES-GCM condivisi col modulo del QR: stessi formati di tutto il resto. */
export const vaultBytes = { bytesToB64, b64ToBytes, bytesToB64Url, open, hkdfAesKey };

/**
 * La RK arrivata da un altro dispositivo dello stesso utente: vale solo se è
 * quella della cassaforte (stesso `rkId` di uno slot).
 */
export async function adoptHandedRk(uid, rkBytes) {
  const slots = await listVaultSlots(uid);
  const expected = slots[0]?.rkId;
  if (!expected) throw new WrongSecretError();
  return adoptRk(uid, rkBytes, expected);
}

// ── passkey (WebAuthn PRF) ────────────────────────────────────────────────

/**
 * Il dominio della passkey (RP ID) è una costante come quelle HKDF: su
 * `*.kidboxapp.com` vale `kidboxapp.com`, così la passkey creata dall'app iOS
 * (Associated Domains `webcredentials:kidboxapp.com`) funziona anche qui. In
 * sviluppo è l'host stesso (`localhost`).
 */
export function passkeyRpId() {
  const host = window.location.hostname;
  return host === "kidboxapp.com" || host.endsWith(".kidboxapp.com") ? "kidboxapp.com" : host;
}

export class PasskeyUnsupportedError extends Error {
  constructor(reason) {
    super(`Passkey non disponibile: ${reason}`);
    this.name = "PasskeyUnsupportedError";
  }
}

/** true se il browser può provarci: il PRF si scopre davvero solo alla prova. */
export async function passkeyMaybeSupported() {
  if (!window.PublicKeyCredential || !navigator.credentials?.create) return false;
  try {
    if (typeof PublicKeyCredential.getClientCapabilities === "function") {
      const caps = await PublicKeyCredential.getClientCapabilities();
      if (caps && caps["extension:prf"] === false) return false;
    }
  } catch {
    /* capacità non dichiarate: si prova */
  }
  return true;
}

const prfInput = () => enc.encode(PRF_INPUT);

async function slotIdForCredential(rawId) {
  const h = new Uint8Array(await crypto.subtle.digest("SHA-256", rawId));
  return `passkey_${bytesToB64Url(h.slice(0, 16))}`;
}

function prfFirst(cred) {
  const r = cred?.getClientExtensionResults?.().prf?.results?.first;
  return r ? new Uint8Array(r) : null;
}

async function prfAssertion(allowIds) {
  const cred = await navigator.credentials.get({
    publicKey: {
      challenge: crypto.getRandomValues(new Uint8Array(32)),
      rpId: passkeyRpId(),
      userVerification: "required",
      timeout: 120000,
      allowCredentials: allowIds.map((id) => ({ type: "public-key", id: b64ToBytes(id) })),
      extensions: { prf: { eval: { first: prfInput() } } },
    },
  });
  if (!cred) throw new PasskeyUnsupportedError("annullata");
  return cred;
}

/**
 * Crea una passkey su questo dispositivo e la aggiunge come slot. Serve la RK
 * in chiaro (subito dopo aver creato o aperto la cassaforte). Se il browser o
 * il gestore delle passkey non danno il PRF: `PasskeyUnsupportedError`, e il
 * codice di recupero resta la strada.
 */
export async function addPasskeySlot({ uid, email, displayName, rkBytes, rkId, label }) {
  if (!(await passkeyMaybeSupported())) throw new PasskeyUnsupportedError("browser");
  const cred = await navigator.credentials.create({
    publicKey: {
      challenge: crypto.getRandomValues(new Uint8Array(32)),
      rp: { id: passkeyRpId(), name: "KidBox" },
      user: { id: enc.encode(uid), name: email || uid, displayName: displayName || email || "KidBox" },
      pubKeyCredParams: [
        { type: "public-key", alg: -7 },
        { type: "public-key", alg: -257 },
      ],
      authenticatorSelection: { residentKey: "required", userVerification: "required" },
      timeout: 120000,
      extensions: { prf: { eval: { first: prfInput() } } },
    },
  });
  if (!cred) throw new PasskeyUnsupportedError("annullata");
  const credentialId = bytesToB64Url(new Uint8Array(cred.rawId));
  let prf = prfFirst(cred);
  if (!prf) {
    // Molti autenticatori dicono solo `enabled` alla creazione: l'uscita PRF
    // arriva con una prima asserzione.
    if (cred.getClientExtensionResults?.().prf?.enabled === false) {
      throw new PasskeyUnsupportedError("prf");
    }
    prf = prfFirst(await prfAssertion([credentialId]));
  }
  if (!prf || prf.length < 32) throw new PasskeyUnsupportedError("prf");
  const slotId = await slotIdForCredential(cred.rawId);
  const rec = await slotRecord({ uid, rkBytes, rkId, type: "passkey", ikm: prf, credentialId, label });
  await setDoc(doc(db, "users", uid, "keyVault", slotId), rec);
  return slotId;
}

/** Apre la cassaforte con una delle passkey registrate. */
export async function openVaultWithPasskey({ uid, slots }) {
  const passkeys = (slots || (await listVaultSlots(uid))).filter((s) => s.type === "passkey");
  if (passkeys.length === 0) throw new PasskeyUnsupportedError("nessuna");
  if (!(await passkeyMaybeSupported())) throw new PasskeyUnsupportedError("browser");
  const cred = await prfAssertion(passkeys.map((s) => s.credentialId));
  const prf = prfFirst(cred);
  if (!prf) throw new PasskeyUnsupportedError("prf");
  const slotId = await slotIdForCredential(cred.rawId);
  const slot = passkeys.find((s) => s.id === slotId);
  if (!slot) throw new WrongSecretError();
  let rkBytes;
  try {
    rkBytes = await openSlot({ uid, slot, ikm: prf });
  } catch {
    throw new WrongSecretError();
  }
  return adoptRk(uid, rkBytes, slot.rkId);
}

// ── copia v2 della chiave di famiglia ─────────────────────────────────────

const familyAad = (uid, familyId) => `${AAD_FAMILY_PREFIX}${uid}:${familyId}`;

/** Il blocco `v2` di memberKeyBackups per questa famiglia, chiuso con la RK. */
export async function sealFamilyKeyV2({ uid, familyId, rawFamilyKey, local }) {
  const wrap = await hkdfAesKey(local.rkBase, new Uint8Array(0), INFO_FAMILY, ["encrypt"]);
  const sealed = await seal(wrap, rawFamilyKey, familyAad(uid, familyId));
  return { ...sealed, rkId: local.rkId, updatedAt: serverTimestamp() };
}

/** Apre il blocco `v2`. null se manca, se è di un'altra RK o se non torna. */
export async function openFamilyKeyV2({ uid, familyId, v2, local }) {
  if (!v2 || !local || v2.rkId !== local.rkId) return null;
  try {
    const wrap = await hkdfAesKey(local.rkBase, new Uint8Array(0), INFO_FAMILY, ["decrypt"]);
    const raw = await open(wrap, v2, familyAad(uid, familyId));
    return raw.length === 32 ? raw : null;
  } catch {
    return null;
  }
}

/**
 * Scrive la copia v2 accanto alla v1 (merge: la v1 non si tocca) e la
 * VERIFICA: rilettura dal server, non dalla cache, e apertura vera con la RK
 * (sezione 4 bis, regola 4). Con la v1 tenuta fino alla Fase 3 la verifica
 * non cancella niente: dice solo se la v2 regge.
 */
export async function writeAndVerifyFamilyKeyV2({ uid, familyId, rawFamilyKey }) {
  const local = await getLocalVault(uid);
  if (!local) return false;
  const ref = doc(db, "families", familyId, "memberKeyBackups", uid);
  const v2 = await sealFamilyKeyV2({ uid, familyId, rawFamilyKey, local });
  await setDoc(ref, { v2 }, { merge: true });
  const fresh = await getDocFromServer(ref);
  const reopened = await openFamilyKeyV2({ uid, familyId, v2: fresh.data()?.v2, local });
  const ok = !!reopened && reopened.every((b, i) => b === rawFamilyKey[i]);
  if (!ok) console.warn(`[Vault] copia v2 non verificata per ${familyId}`);
  return ok;
}

// ── interruttore ──────────────────────────────────────────────────────────

let flagCache = null;

/**
 * `config/keyVault`: `enabled` = per tutti; `internal` = solo gli account di
 * `config/internalUsers.uids` (la prova); `enforce` = il segreto non si
 * rimanda più.
 * Spento o illeggibile = il web si comporta come prima della v2.
 */
export async function keyVaultFlags(uid) {
  if (flagCache && flagCache.uid === uid && Date.now() - flagCache.at < 5 * 60 * 1000) {
    return flagCache.value;
  }
  let value = { active: false, enforce: false };
  try {
    const [cfg, internal] = await Promise.all([
      getDoc(doc(db, "config", "keyVault")),
      getDoc(doc(db, "config", "internalUsers")),
    ]);
    const c = cfg.exists() ? cfg.data() : {};
    const isInternal = (internal.exists() ? internal.data().uids || [] : []).includes(uid);
    const active = c.enabled === true || (isInternal && c.internal === true);
    value = { active, enforce: active && c.enforce === true };
  } catch (err) {
    console.warn("[Vault] interruttore non leggibile", err?.code);
  }
  flagCache = { uid, at: Date.now(), value };
  return value;
}
