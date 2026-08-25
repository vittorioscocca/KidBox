import { doc, serverTimestamp, setDoc } from "firebase/firestore";
import { getDownloadURL, ref, uploadBytes } from "firebase/storage";
import { db, storage } from "../firebase";

/**
 * Porting web di FamilyHeroPhotoService (iOS/Android): stesso path di Storage,
 * stessi campi Firestore. Il path è stabile e viene sempre sovrascritto, così i
 * client nativi ritrovano la foto dove la cercano.
 */
const MAX_EDGE = 1600;
const JPEG_QUALITY = 0.85;

/**
 * I client nativi caricano JPEG già ridimensionati. Dal browser un utente può
 * scegliere uno scatto da reflex da 8 MB: senza questo passaggio finirebbe intero
 * su Storage, pesando sulla quota della famiglia e sui tempi di caricamento di
 * tutti i device.
 */
async function toJpegBlob(file) {
  const bitmap = await createImageBitmap(file);
  const ratio = Math.min(1, MAX_EDGE / Math.max(bitmap.width, bitmap.height));
  const width = Math.round(bitmap.width * ratio);
  const height = Math.round(bitmap.height * ratio);

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  canvas.getContext("2d").drawImage(bitmap, 0, 0, width, height);
  bitmap.close?.();

  const blob = await new Promise((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY)
  );
  if (!blob) throw new Error("Conversione immagine fallita");
  return blob;
}

/**
 * Carica la foto e aggiorna i campi su `families/{familyId}`.
 *
 * @param crop scale/offsetX/offsetY. Il web non ha ancora un editor di crop, quindi
 *   di default riusa i valori già presenti sulla famiglia invece di azzerarli: un
 *   crop impostato da iOS non va perso solo perché la foto è stata cambiata da qui.
 */
export async function setHeroPhoto({ familyId, file, uid, crop }) {
  if (!familyId) throw new Error("familyId mancante");
  if (!file) throw new Error("Nessun file selezionato");

  const blob = await toJpegBlob(file);
  const path = `families/${familyId}/hero/hero.jpg`;
  const storageRef = ref(storage, path);

  await uploadBytes(storageRef, blob, { contentType: "image/jpeg" });
  const url = await getDownloadURL(storageRef);

  await setDoc(
    doc(db, "families", familyId),
    {
      heroPhotoURL: url,
      heroPhotoUpdatedAt: serverTimestamp(),
      heroPhotoScale: crop?.scale ?? 1,
      heroPhotoOffsetX: crop?.offsetX ?? 0,
      heroPhotoOffsetY: crop?.offsetY ?? 0,
      updatedBy: uid,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );

  return url;
}
