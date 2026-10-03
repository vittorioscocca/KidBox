/**
 * Foto del Wallet (fronte/retro di tessere fedeltà e carte di pagamento) su
 * Storage, cifrate con la chiave di famiglia come su iOS e Android.
 *
 * Path: `families/{familyId}/wallet/{loyaltyCards|paymentCards}/{cardId}/{front|back}.jpg.kbenc`.
 * Deve restare dentro `wallet/`: le Storage Rules ammettono solo sottopath
 * espliciti, e `families/{id}/loyaltyCards/…` (dove scriveva il web fino al
 * 03/10/2026) è negato. Il blob è il formato combined (nonce + cipher + tag),
 * in byte grezzi: lo stesso che scrivono `LoyaltyCardPhotoStore` (iOS) e
 * `DocumentStorageManager.uploadEncryptedToPath` (Android).
 */
import { deleteObject, getBytes, getDownloadURL, ref, uploadBytes } from "firebase/storage";
import { storage } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { encryptBytes, decryptBytes } from "./familyCrypto";

export const walletPhotoPath = (familyId, folder, cardId, side) =>
  `families/${familyId}/wallet/${folder}/${cardId}/${side}.jpg.kbenc`;

/** Ridimensiona a 2000 px di lato lungo e ricomprime in JPEG, come iOS. */
async function toJpeg(file) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 2000 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.82));
  return new Uint8Array(await blob.arrayBuffer());
}

/** Cifra e carica la foto di un lato. Restituisce `{ url, path }`. */
export async function uploadWalletPhoto({ familyId, userId, folder, module, cardId, side, file }) {
  const key = await loadFamilyKey({ familyId, userId });
  const sealed = await encryptBytes(await toJpeg(file), key);
  const path = walletPhotoPath(familyId, folder, cardId, side);
  const storageRef = ref(storage, path);
  await uploadBytes(storageRef, sealed, {
    contentType: "application/octet-stream",
    customMetadata: {
      kb_encrypted: "1",
      kb_alg: "AES-GCM",
      kb_orig_mime: "image/jpeg",
      kb_orig_name: `${side}.jpg`,
      kb_module: module,
    },
  });
  return { url: await getDownloadURL(storageRef), path };
}

/** Scarica e decifra una foto: un object URL da revocare quando non serve più. */
export async function fetchWalletPhoto({ familyId, userId, path }) {
  if (!path) return null;
  const key = await loadFamilyKey({ familyId, userId });
  const sealed = new Uint8Array(await getBytes(ref(storage, path), 15 * 1024 * 1024));
  const plain = await decryptBytes(sealed, key);
  return URL.createObjectURL(new Blob([plain], { type: "image/jpeg" }));
}

/** Elimina una foto. Idempotente: un oggetto già assente non è un errore. */
export async function deleteWalletPhoto(path) {
  if (!path) return;
  try {
    await deleteObject(ref(storage, path));
  } catch {
    // Già assente.
  }
}
