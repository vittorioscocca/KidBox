import {
  collection,
  doc,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { getDownloadURL, ref as storageRef, uploadBytes } from "firebase/storage";
import { db, storage } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { decryptBytes, encryptBytes } from "./familyCrypto";

/**
 * Foto e video: porting di PhotoRemoteStore (iOS).
 *
 * L'originale viene cifrato e caricato come blob opaco; su Firestore restano i
 * metadati più una **miniatura JPEG in base64**. È quest'ultima a rendere
 * scorrevole la griglia: senza, ogni cella richiederebbe di scaricare e
 * decifrare il file intero.
 */

const THUMB_MAX = 200; // px, come maxDimension su iOS
const THUMB_QUALITY = 0.7;

export function photosCol(familyId) {
  return collection(db, "families", familyId, "photos");
}

export function albumsCol(familyId) {
  return collection(db, "families", familyId, "photoAlbums");
}

function canvasToJpegBase64(canvas) {
  // `toDataURL` include il prefisso data:; su Firestore va solo il base64,
  // com'è nel campo thumbnailBase64 scritto dai client nativi.
  return canvas.toDataURL("image/jpeg", THUMB_QUALITY).split(",")[1];
}

function drawScaled(source, width, height) {
  const ratio = Math.min(1, THUMB_MAX / Math.max(width, height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(width * ratio));
  canvas.height = Math.max(1, Math.round(height * ratio));
  canvas.getContext("2d").drawImage(source, 0, 0, canvas.width, canvas.height);
  return canvas;
}

async function imageThumbnail(file) {
  // createImageBitmap applica da sé l'orientamento EXIF: senza, le foto
  // scattate in verticale avrebbero la miniatura ruotata.
  const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  const canvas = drawScaled(bitmap, bitmap.width, bitmap.height);
  bitmap.close?.();
  return canvasToJpegBase64(canvas);
}

/** Primo frame utile del video, come fa AVAssetImageGenerator su iOS. */
async function videoThumbnail(file) {
  const url = URL.createObjectURL(file);
  try {
    const video = document.createElement("video");
    video.muted = true;
    video.playsInline = true;
    video.src = url;

    await new Promise((resolve, reject) => {
      video.onloadeddata = resolve;
      video.onerror = () => reject(new Error("Video non leggibile"));
    });
    // Un istante dopo l'inizio: il frame 0 è spesso nero.
    video.currentTime = Math.min(0.1, (video.duration || 1) / 2);
    await new Promise((resolve) => {
      video.onseeked = resolve;
    });

    const canvas = drawScaled(video, video.videoWidth, video.videoHeight);
    return {
      thumb: canvasToJpegBase64(canvas),
      duration: Number.isFinite(video.duration) ? video.duration : null,
    };
  } finally {
    URL.revokeObjectURL(url);
  }
}

export async function uploadPhoto({ familyId, userId, file, albumIds = [] }) {
  const key = await loadFamilyKey({ familyId, userId });
  const photoId = crypto.randomUUID();
  const isVideo = (file.type || "").startsWith("video/");

  let thumbnailBase64 = null;
  let videoDurationSeconds = null;
  try {
    if (isVideo) {
      const { thumb, duration } = await videoThumbnail(file);
      thumbnailBase64 = thumb;
      videoDurationSeconds = duration;
    } else {
      thumbnailBase64 = await imageThumbnail(file);
    }
  } catch {
    // Senza miniatura la griglia mostra un segnaposto: meglio che perdere il file.
  }

  const plain = new Uint8Array(await file.arrayBuffer());
  const encrypted = await encryptBytes(plain, key);

  const storagePath = `families/${familyId}/photos/${photoId}/original.enc`;
  const ref = storageRef(storage, storagePath);
  await uploadBytes(ref, encrypted, { contentType: "application/octet-stream" });
  const downloadURL = await getDownloadURL(ref);

  await setDoc(doc(photosCol(familyId), photoId), {
    fileName: file.name,
    mimeType: file.type || "application/octet-stream",
    fileSize: file.size,
    storagePath,
    downloadURL,
    thumbnailBase64,
    videoDurationSeconds,
    // Su iOS è la data EXIF quando c'è; dal browser resta la data del file.
    takenAt: Timestamp.fromDate(new Date(file.lastModified || Date.now())),
    albumIdsRaw: albumIds.join(","),
    isDeleted: false,
    createdBy: userId,
    createdAt: serverTimestamp(),
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  });

  return photoId;
}

/** Scarica e decifra l'originale, per la vista a schermo intero o il download. */
export async function fetchPhotoBlob({ familyId, userId, photo }) {
  if (!photo.downloadURL) throw new Error("Foto senza URL di download");
  const response = await fetch(photo.downloadURL);
  if (!response.ok) throw new Error(`Download fallito (${response.status})`);
  const raw = new Uint8Array(await response.arrayBuffer());

  const key = await loadFamilyKey({ familyId, userId });
  const plain = await decryptBytes(raw, key);
  return new Blob([plain], { type: photo.mimeType || "application/octet-stream" });
}

export async function softDeletePhoto({ familyId, userId, photoId }) {
  await setDoc(
    doc(photosCol(familyId), photoId),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

export async function setPhotoCaption({ familyId, userId, photoId, caption }) {
  await setDoc(
    doc(photosCol(familyId), photoId),
    { caption: caption || null, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Gli album di una foto stanno in una stringa separata da virgole (albumIdsRaw). */
export async function setPhotoAlbums({ familyId, userId, photoId, albumIds }) {
  await setDoc(
    doc(photosCol(familyId), photoId),
    {
      albumIdsRaw: albumIds.join(","),
      updatedBy: userId,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

export function parseAlbumIds(raw) {
  return (raw ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

/* ── Album ─────────────────────────────────────────────────────────────── */

export async function createAlbum({ familyId, userId, title }) {
  const id = crypto.randomUUID();
  await setDoc(doc(albumsCol(familyId), id), {
    familyId,
    title,
    sortOrder: 0,
    isDeleted: false,
    createdBy: userId,
    createdAt: serverTimestamp(),
    updatedBy: userId,
    updatedAt: serverTimestamp(),
  });
  return id;
}

export async function renameAlbum({ familyId, userId, albumId, title }) {
  await setDoc(
    doc(albumsCol(familyId), albumId),
    { title, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/**
 * Elimina l'album ma NON le foto che contiene: restano nella libreria, come su
 * iOS. Le foto perdono solo il riferimento all'album.
 */
export async function deleteAlbum({ familyId, userId, albumId, photos }) {
  await Promise.all([
    setDoc(
      doc(albumsCol(familyId), albumId),
      { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
      { merge: true }
    ),
    ...photos
      .filter((p) => parseAlbumIds(p.albumIdsRaw).includes(albumId))
      .map((p) =>
        setPhotoAlbums({
          familyId,
          userId,
          photoId: p.id,
          albumIds: parseAlbumIds(p.albumIdsRaw).filter((a) => a !== albumId),
        })
      ),
  ]);
}
