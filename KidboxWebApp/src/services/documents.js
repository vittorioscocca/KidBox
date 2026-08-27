import {
  collection,
  deleteField,
  doc,
  serverTimestamp,
  setDoc,
} from "firebase/firestore";
import {
  getDownloadURL,
  ref as storageRef,
  uploadBytes,
  deleteObject,
} from "firebase/storage";
import { db, storage } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { decryptBytes, encryptBytes, looksLikePlainFile } from "./familyCrypto";

/**
 * Documenti: porting di DocumentRemoteStore + DocumentStorageService +
 * DocumentCryptoService (iOS).
 *
 * I file NON stanno in chiaro su Storage: vengono cifrati con la master key di
 * famiglia (AES-GCM) e caricati come blob opachi con estensione `.kbenc`. Il web
 * usa la stessa chiave recuperata dall'escrow, quindi produce e legge file
 * interscambiabili con quelli dei client nativi.
 */

export function documentsCol(familyId) {
  return collection(db, "families", familyId, "documents");
}

export function categoriesCol(familyId) {
  return collection(db, "families", familyId, "documentCategories");
}

/**
 * I contenuti sotto `/chat/` sono in chiaro (eccetto i vecchi `.kbenc`), come
 * stabilito da DocumentCryptoService.isPlainChatStoragePath: un documento
 * arrivato dalla chat non va decifrato.
 */
function isPlainPayload(storagePath, notes) {
  if (notes === "chat_plain") return true;
  if (!storagePath) return false;
  const lower = storagePath.toLowerCase();
  return lower.includes("/chat/") && !lower.endsWith(".kbenc");
}

/** Nome file "sicuro" come safeFileName su iOS: niente separatori di percorso. */
function safeFileName(name) {
  return (name || "file").replace(/[/\\]/g, "_");
}

/**
 * Carica un file: lo cifra, lo mette su Storage e crea il documento Firestore.
 *
 * Accetta un File dal selettore oppure byte già in memoria (`bytes` + `name` +
 * `mimeType`), come nel caso di un PDF unito o sbloccato che non esiste su disco.
 */
export async function uploadDocument({
  familyId,
  userId,
  file,
  bytes,
  name,
  mimeType,
  categoryId,
  onProgress,
}) {
  const key = await loadFamilyKey({ familyId, userId });
  const docId = crypto.randomUUID();
  const displayName = file?.name ?? name ?? "documento";
  const fileName = safeFileName(displayName);
  const type = file?.type || mimeType || "application/octet-stream";

  const plain = bytes
    ? new Uint8Array(bytes)
    : new Uint8Array(await file.arrayBuffer());
  const encrypted = await encryptBytes(plain, key);

  const path = `families/${familyId}/documents/${docId}/${fileName}.kbenc`;
  const ref = storageRef(storage, path);

  await uploadBytes(ref, encrypted, {
    contentType: "application/octet-stream",
    customMetadata: {
      kb_encrypted: "1",
      kb_original_mime: type,
      kb_original_name: fileName,
    },
  });
  const downloadURL = await getDownloadURL(ref);

  await setDoc(doc(documentsCol(familyId), docId), {
    title: displayName,
    fileName,
    mimeType: type,
    fileSize: plain.length,
    storagePath: path,
    downloadURL,
    categoryId: categoryId ?? deleteField(),
    isDeleted: false,
    createdBy: userId,
    createdAt: serverTimestamp(),
    updatedBy: userId,
    updatedAt: serverTimestamp(),
    visibilityScope: "family",
    visibilityMemberIds: [],
  });

  onProgress?.(1);
  return docId;
}

/**
 * Scarica un documento e lo restituisce come Blob decifrato, pronto da mostrare
 * o salvare. Richiede CORS abilitato sul bucket per l'origine del web.
 */
export async function fetchDocumentBlob({ familyId, userId, document: docData }) {
  const url = docData.downloadURL;
  if (!url) throw new Error("Documento senza URL di download");

  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download fallito (${response.status})`);
  const raw = new Uint8Array(await response.arrayBuffer());

  const mime = docData.mimeType || "application/octet-stream";
  if (isPlainPayload(docData.storagePath, docData.notes)) {
    return new Blob([raw], { type: mime });
  }

  const key = await loadFamilyKey({ familyId, userId });
  try {
    const plain = await decryptBytes(raw, key);
    return new Blob([plain], { type: mime });
  } catch (err) {
    // Come su iOS: alcune righe legacy hanno il suffisso .kbenc ma contenuto in
    // chiaro. Se i primi byte sono di un formato noto, si usa il file com'è.
    if (looksLikePlainFile(raw)) return new Blob([raw], { type: mime });
    throw err;
  }
}

/** Soft delete: il blob su Storage lo rimuove il garbage collector schedulato. */
export async function softDeleteDocument({ familyId, userId, documentId }) {
  await setDoc(
    doc(documentsCol(familyId), documentId),
    { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

export async function renameDocument({ familyId, userId, documentId, title }) {
  await setDoc(
    doc(documentsCol(familyId), documentId),
    { title, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

export async function moveDocument({ familyId, userId, documentId, categoryId }) {
  await setDoc(
    doc(documentsCol(familyId), documentId),
    {
      categoryId: categoryId ?? deleteField(),
      updatedBy: userId,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

/* ── Cartelle (documentCategories) ─────────────────────────────────────── */

export async function createFolder({ familyId, userId, title, parentId }) {
  const id = crypto.randomUUID();
  await setDoc(doc(categoriesCol(familyId), id), {
    familyId,
    title,
    sortOrder: 0,
    parentId: parentId ?? deleteField(),
    isDeleted: false,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    updatedBy: userId,
  });
  return id;
}

export async function renameFolder({ familyId, userId, folderId, title }) {
  await setDoc(
    doc(categoriesCol(familyId), folderId),
    { title, updatedBy: userId, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/** Elimina la cartella con tutto il suo contenuto, ricorsivamente. */
export async function deleteFolderRecursive({
  familyId,
  userId,
  folderId,
  allFolders,
  allDocuments,
}) {
  const toVisit = [folderId];
  const folderIds = [];
  while (toVisit.length) {
    const current = toVisit.pop();
    folderIds.push(current);
    allFolders
      .filter((f) => f.parentId === current)
      .forEach((f) => toVisit.push(f.id));
  }

  await Promise.all([
    ...folderIds.map((id) =>
      setDoc(
        doc(categoriesCol(familyId), id),
        { isDeleted: true, updatedBy: userId, updatedAt: serverTimestamp() },
        { merge: true }
      )
    ),
    ...allDocuments
      .filter((d) => folderIds.includes(d.categoryId))
      .map((d) => softDeleteDocument({ familyId, userId, documentId: d.id })),
  ]);
}

/**
 * Condivide i documenti col foglio di sistema (Web Share API), come fa
 * prepareShareURLs + UIActivityViewController su iOS.
 *
 * Non tutti i browser condividono file: dove non è supportato si ripiega sul
 * download, così l'utente può comunque inoltrarli a mano.
 * @returns {"shared"|"downloaded"|"cancelled"}
 */
export async function shareDocuments({ familyId, userId, documents: docs }) {
  const files = await Promise.all(
    docs.map(async (d) => {
      const blob = await fetchDocumentBlob({ familyId, userId, document: d });
      return new File([blob], d.fileName || d.title || "documento", {
        type: d.mimeType || "application/octet-stream",
      });
    })
  );

  if (navigator.canShare?.({ files })) {
    try {
      await navigator.share({ files });
      return "shared";
    } catch (err) {
      if (err?.name === "AbortError") return "cancelled";
      // Qualsiasi altro errore: si prosegue col download.
    }
  }

  files.forEach((file) => {
    const url = URL.createObjectURL(file);
    const a = window.document.createElement("a");
    a.href = url;
    a.download = file.name;
    a.click();
    URL.revokeObjectURL(url);
  });
  return "downloaded";
}

export { deleteObject };
