/**
 * Carte di pagamento del Wallet (`families/{familyId}/paymentCards`),
 * allineato a `PaymentCardRemoteStore` su iOS e Android.
 *
 * Tutto ciò che scrive l'utente è cifrato con la chiave di famiglia (campi
 * `*Enc`, base64 di AES-GCM combined) e si decifra solo in memoria. Le foto
 * passano da `walletPhotos.js`, sullo stesso path degli altri client.
 * Nessuna AI legge queste carte, e il CVV non si salva. Il PIN sì, su richiesta
 * dell'utente: mai sulla carta disegnata, nascosto finché non lo si chiede.
 */
import { collection, deleteField, doc, onSnapshot, serverTimestamp, setDoc } from "firebase/firestore";
import { db } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { encryptBytes, decryptBytes } from "./familyCrypto";
import { contentCreated } from "./analytics";
import { isVisibleTo, normalizedWalletScope, WALLET_MEMBERS } from "./wallet";
import { PAYMENT_CARD_DEFAULT_HEX } from "./paymentCardFormat";
import { deleteWalletPhoto, fetchWalletPhoto, uploadWalletPhoto } from "./walletPhotos";

const col = (familyId) => collection(db, "families", familyId, "paymentCards");

const ENC_FIELDS = ["label", "cardNumber", "holderName", "iban", "expiry", "notes", "pin"];
const PHOTO_FIELDS = ["frontPhotoStorageURL", "frontPhotoStoragePath", "backPhotoStorageURL", "backPhotoStoragePath"];

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

async function seal(value, key) {
  if (!value) return null;
  return bytesToB64(await encryptBytes(enc.encode(value), key));
}

async function open(b64, key) {
  if (!b64) return "";
  return dec.decode(await decryptBytes(b64ToBytes(b64), key));
}

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

async function readCard(snap, key) {
  const d = snap.data();
  const card = {
    id: snap.id,
    colorHex: d.colorHex || PAYMENT_CARD_DEFAULT_HEX,
    frontPhotoStorageURL: d.frontPhotoStorageURL || null,
    frontPhotoStoragePath: d.frontPhotoStoragePath || null,
    backPhotoStorageURL: d.backPhotoStorageURL || null,
    backPhotoStoragePath: d.backPhotoStoragePath || null,
    visibilityScope: normalizedWalletScope(d.visibilityScope),
    visibilityMemberIds: d.visibilityMemberIds || [],
    createdBy: d.createdBy || "",
    createdAt: millis(d.createdAt),
    updatedAt: millis(d.updatedAt),
    unreadable: false,
  };
  try {
    const values = await Promise.all(ENC_FIELDS.map((f) => open(d[`${f}Enc`], key)));
    ENC_FIELDS.forEach((f, i) => {
      card[f] = values[i];
    });
  } catch {
    ENC_FIELDS.forEach((f) => {
      card[f] = "";
    });
    card.unreadable = true;
  }
  return card;
}

/** Ascolta le carte visibili all'utente. Restituisce la funzione per smettere. */
export function listenPaymentCards({ familyId, userId, onChange, onError }) {
  let cancelled = false;
  let keyPromise = null;
  const stop = onSnapshot(
    col(familyId),
    async (snap) => {
      try {
        keyPromise = keyPromise || loadFamilyKey({ familyId, userId });
        const key = await keyPromise;
        const docs = snap.docs.filter((s) => !s.data().isDeleted);
        const cards = (await Promise.all(docs.map((s) => readCard(s, key))))
          .filter((c) => isVisibleTo(c, userId))
          .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
        if (!cancelled) onChange(cards);
      } catch (err) {
        if (!cancelled) onError?.(err);
      }
    },
    (err) => onError?.(err)
  );
  return () => {
    cancelled = true;
    stop();
  };
}

/** Crea o aggiorna. `card.id` assente = nuova. Restituisce l'id. */
export async function savePaymentCard({ familyId, userId, userName, card }) {
  // Una carta che qui non si decifra ha i campi vuoti: risalvarla li cancellerebbe.
  if (card.unreadable) throw new Error("Carta non leggibile su questo dispositivo.");
  const id = card.id || crypto.randomUUID();
  const isNew = !card.id;
  const key = await loadFamilyKey({ familyId, userId });
  const scope = normalizedWalletScope(card.visibilityScope);

  const data = {
    schemaVersion: 1,
    colorHex: card.colorHex || PAYMENT_CARD_DEFAULT_HEX,
    visibilityScope: scope,
    visibilityMemberIds: scope === WALLET_MEMBERS ? card.visibilityMemberIds || [] : [],
    isDeleted: false,
    updatedBy: userId,
    updatedByName: userName || "",
    updatedAt: serverTimestamp(),
  };
  for (const f of ENC_FIELDS) data[`${f}Enc`] = await seal(card[f], key);
  for (const f of PHOTO_FIELDS) data[f] = card[f] || null;
  if (isNew) {
    data.createdAt = serverTimestamp();
    data.createdBy = userId;
    data.createdByName = userName || "";
  }

  await setDoc(doc(col(familyId), id), data, { merge: true });
  if (isNew) contentCreated("payment_card");
  return id;
}

/** Tombstone: svuota anche i campi cifrati e cancella le foto. */
export async function deletePaymentCard({ familyId, userId, card }) {
  for (const path of [card.frontPhotoStoragePath, card.backPhotoStoragePath]) {
    await deleteWalletPhoto(path);
  }
  const cleared = {};
  for (const f of ENC_FIELDS) cleared[`${f}Enc`] = deleteField();
  for (const f of PHOTO_FIELDS) cleared[f] = deleteField();
  await setDoc(
    doc(col(familyId), card.id),
    { ...cleared, isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Cifra e carica la foto di un lato. Restituisce `{ url, path }`. */
export const uploadPaymentCardPhoto = ({ familyId, userId, cardId, side, file }) =>
  uploadWalletPhoto({ familyId, userId, folder: "paymentCards", module: "paymentCard", cardId, side, file });

export const fetchPaymentCardPhoto = fetchWalletPhoto;
export const deletePaymentCardPhoto = deleteWalletPhoto;
