/**
 * Profilo utente: porta sul web `ProfileView`, `UserProfileWriter` e
 * `AvatarRemoteStore` (iOS).
 *
 * L'anagrafica sta su `users/{uid}` — privata dell'utente — mentre il nome
 * mostrato agli altri viene propagato su `families/{familyId}/members/{uid}`.
 * Sono due scritture perché sono due cose diverse: la seconda è ciò che gli
 * altri membri vedono, e senza di essa il nome cambia solo per sé stessi.
 */
import { doc, getDoc, serverTimestamp, setDoc, Timestamp } from "firebase/firestore";
import { deleteObject, getDownloadURL, ref as storageRef, uploadBytes } from "firebase/storage";
import { httpsCallable } from "firebase/functions";
import { db, functions, storage } from "../firebase";

/** Nome di riserva quando l'anagrafica è vuota. Stesso sentinella di iOS: va
 *  trattato come «non impostato», non come un nome vero. */
export const PLACEHOLDER_NAME = "Utente";

/** Lato massimo dell'avatar, come `AvatarRemoteStore.resized(maxSide: 256)`. */
const AVATAR_MAX_SIDE = 256;

const userRef = (uid) => doc(db, "users", uid);
const memberRef = (familyId, uid) => doc(db, "families", familyId, "members", uid);
/** iOS scrive l'avatar del membro sul documento posizione, non su `members`. */
const locationRef = (familyId, uid) => doc(db, "families", familyId, "locations", uid);

export async function loadProfile(uid) {
  const snap = await getDoc(userRef(uid));
  const d = snap.exists() ? snap.data() : {};
  return {
    firstName: d.firstName || "",
    lastName: d.lastName || "",
    displayName: d.displayName || "",
    familyAddress: d.familyAddress || "",
    email: d.email || "",
    avatarURL: d.avatarURL || "",
  };
}

/**
 * Salva anagrafica e indirizzo, poi propaga il nome al membro famiglia.
 *
 * La propagazione è best effort e non blocca: se fallisce, il profilo è
 * comunque salvato e il nome si riallinea al salvataggio successivo. Non
 * si propaga il segnaposto, altrimenti gli altri vedrebbero «Utente».
 */
export async function saveProfile({ uid, familyId, firstName, lastName, familyAddress, email }) {
  const fn = firstName.trim();
  const ln = lastName.trim();
  const full = `${fn} ${ln}`.trim();
  const displayName = full || PLACEHOLDER_NAME;

  await setDoc(
    userRef(uid),
    {
      firstName: fn,
      lastName: ln,
      displayName,
      familyAddress: familyAddress.trim(),
      email: email || "",
      updatedAt: Timestamp.now(),
    },
    { merge: true }
  );

  if (familyId && displayName !== PLACEHOLDER_NAME) {
    try {
      await setDoc(
        memberRef(familyId, uid),
        { displayName, updatedAt: Timestamp.now() },
        { merge: true }
      );
    } catch {
      // Silenzioso di proposito: vedi la nota sopra.
    }
  }

  return displayName;
}

/* ── Avatar ──────────────────────────────────────────────────────────────── */

const avatarPath = (uid, familyId) =>
  familyId ? `families/${familyId}/avatars/${uid}.jpg` : `users/${uid}/avatar.jpg`;

/**
 * Riduce l'immagine a 256px di lato e la riscrive in JPEG, come fa iOS prima
 * di caricarla: un avatar è un cerchio da 80 pixel, caricare l'originale da
 * 4 MB sarebbe spreco puro.
 */
async function resizeToJpeg(file) {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, AVATAR_MAX_SIDE / Math.max(bitmap.width, bitmap.height));
  const width = Math.max(1, Math.round(bitmap.width * scale));
  const height = Math.max(1, Math.round(bitmap.height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  // Il JPEG non ha trasparenza: senza fondo un PNG trasparente uscirebbe nero.
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, width, height);
  context.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.9));
  if (!blob) throw new Error("Immagine non convertibile.");
  return blob;
}

/**
 * Carica l'avatar e ne propaga l'URL dove i client lo cercano: sul profilo
 * utente e, se c'è una famiglia, sul documento posizione — che è il posto da
 * cui le altre schermate leggono la faccia dei membri.
 */
export async function uploadAvatar({ uid, familyId, file }) {
  const blob = await resizeToJpeg(file);
  const path = avatarPath(uid, familyId);
  const ref = storageRef(storage, path);
  await uploadBytes(ref, blob, { contentType: "image/jpeg" });
  const avatarURL = await getDownloadURL(ref);

  await setDoc(userRef(uid), { avatarURL, updatedAt: Timestamp.now() }, { merge: true });
  if (familyId) {
    try {
      await setDoc(locationRef(familyId, uid), { avatarURL }, { merge: true });
    } catch {
      // Il profilo ha comunque la foto: il resto si riallinea al prossimo salvataggio.
    }
  }
  return avatarURL;
}

export async function removeAvatar({ uid, familyId }) {
  for (const path of [avatarPath(uid, familyId), avatarPath(uid, null)]) {
    try {
      await deleteObject(storageRef(storage, path));
    } catch {
      // Il file può non esserci: l'obiettivo è che sparisca, non che ci fosse.
    }
  }
  await setDoc(userRef(uid), { avatarURL: "", updatedAt: serverTimestamp() }, { merge: true });
  if (familyId) {
    try {
      await setDoc(locationRef(familyId, uid), { avatarURL: "" }, { merge: true });
    } catch {
      /* vedi sopra */
    }
  }
}

/* ── Piano e spazio ──────────────────────────────────────────────────────── */

/**
 * Piano attivo: prima la famiglia, poi l'utente, infine `free`.
 *
 * È l'ordine di `KBSubscriptionManager`, e non è una preferenza: il piano si
 * compra per la famiglia, quindi quello del documento famiglia vince.
 */
export async function loadPlan({ familyId, uid }) {
  if (familyId) {
    const snap = await getDoc(doc(db, "families", familyId));
    const plan = snap.exists() ? snap.data().plan : null;
    if (plan) return String(plan).toLowerCase();
  }
  const snap = await getDoc(userRef(uid));
  return String(snap.data()?.plan || "free").toLowerCase();
}

export async function fetchStorageUsage(familyId) {
  const callable = httpsCallable(functions, "getStorageUsage");
  const { data } = await callable({ familyId });
  return {
    usedBytes: data?.usedBytes ?? 0,
    quotaBytes: data?.quotaBytes ?? 0,
    sections: data?.sections ?? {},
  };
}

/** Cancellazione definitiva dell'account, la stessa function che usa l'app. */
export async function deleteAccount() {
  const callable = httpsCallable(functions, "deleteAccount", { timeout: 120_000 });
  await callable({});
}
