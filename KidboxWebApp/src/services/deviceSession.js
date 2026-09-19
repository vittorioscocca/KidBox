/**
 * Registro dei dispositivi collegati, e leva del logout remoto.
 *
 * Un documento per browser in `users/{uid}/sessions/{sessionId}`, esattamente
 * come fanno iOS (`KBDeviceSessionRegistry`) e Android (`DeviceSessionRegistry`).
 *
 * Firebase Auth non sa niente dei dispositivi: ognuno ha un refresh token suo,
 * ma lato server non esiste un elenco delle sessioni aperte né un modo di
 * revocarne una sola — `revokeRefreshTokens` vale per tutto l'account. Questo
 * registro è quell'elenco, tenuto da noi, e il logout che ne deriva è
 * **cooperativo**: ogni client ascolta il proprio documento e si slogga quando
 * lo vede sparire. Per la revoca vera c'è la callable `signOutAllDevices`.
 */
import { deleteDoc, doc, onSnapshot, serverTimestamp, setDoc } from "firebase/firestore";
import { db } from "../firebase";

const INSTALL_ID_KEY = "kidbox:installId";

/**
 * Identificatore di QUESTO browser, stabile finché non si cancellano i dati del
 * sito. Non identifica la persona: vive solo qui e serve a distinguere una riga
 * dall'altra nell'elenco.
 *
 * Il documento sta sotto l'uid, quindi stesso browser e account diversi restano
 * sessioni diverse — se sullo stesso computer entra un altro familiare, non
 * eredita la sessione di chi c'era prima.
 */
export function installId() {
  try {
    const existing = localStorage.getItem(INSTALL_ID_KEY);
    if (existing) return existing;
    const fresh = crypto.randomUUID();
    localStorage.setItem(INSTALL_ID_KEY, fresh);
    return fresh;
  } catch {
    // Navigazione privata con storage bloccato: la sessione non sarà stabile
    // fra un caricamento e l'altro, ma l'elenco continua a funzionare.
    return crypto.randomUUID();
  }
}

/** «Chrome su macOS». Dallo user agent, che è l'unica cosa che abbiamo. */
function deviceName() {
  const ua = navigator.userAgent || "";
  const browser =
    /Edg\//.test(ua) ? "Edge" :
    /OPR\//.test(ua) ? "Opera" :
    /Chrome\//.test(ua) ? "Chrome" :
    /Safari\//.test(ua) ? "Safari" :
    /Firefox\//.test(ua) ? "Firefox" : "Browser";
  const os =
    /Windows/.test(ua) ? "Windows" :
    /Android/.test(ua) ? "Android" :
    /iPhone|iPad|iPod/.test(ua) ? "iOS" :
    /Mac OS X/.test(ua) ? "macOS" :
    /Linux/.test(ua) ? "Linux" : "";
  return os ? `${browser} · ${os}` : browser;
}

let unsubscribe = null;
let activeUid = null;

/**
 * Registra questa sessione e comincia ad ascoltarla.
 *
 * `onRevoked` scatta quando il documento viene cancellato da un altro
 * dispositivo: è il chiamante a eseguire il logout, perché è lui a sapere cosa
 * ripulire.
 */
export async function startDeviceSession(uid, onRevoked) {
  if (activeUid === uid) return;
  stopDeviceSession();
  activeUid = uid;

  const ref = doc(db, "users", uid, "sessions", installId());

  try {
    await setDoc(
      ref,
      {
        platform: "web",
        deviceName: deviceName(),
        osVersion: "",
        lastSeenAt: serverTimestamp(),
      },
      { merge: true }
    );
  } catch {
    // L'ascolto parte lo stesso: la condizione qui sotto non slogga nessuno se
    // il documento non è mai esistito, quindi una registrazione fallita non si
    // trasforma in un logout.
  }

  let sawDocument = false;
  unsubscribe = onSnapshot(
    ref,
    { includeMetadataChanges: true },
    (snap) => {
      // Solo dal server. Offline, o al caricamento senza rete, Firestore
      // risponde dalla cache: un'assenza da lì non è una prova di
      // cancellazione e sloggherebbe chi apre la pagina senza connessione.
      if (snap.metadata.fromCache) return;
      if (snap.exists()) {
        sawDocument = true;
        return;
      }
      if (!sawDocument) return;
      stopDeviceSession();
      onRevoked();
    },
    () => {}
  );
}

/** Chiude l'ascolto senza toccare il documento. */
export function stopDeviceSession() {
  if (unsubscribe) unsubscribe();
  unsubscribe = null;
  activeUid = null;
}

/**
 * Logout volontario da questo browser: il documento va tolto, o la sessione
 * resterebbe nell'elenco degli altri dispositivi per sempre.
 *
 * Va chiamata PRIMA del `signOut`: dopo, le rules non lascerebbero più
 * scrivere.
 */
export async function removeDeviceSession(uid) {
  const id = installId();
  stopDeviceSession();
  if (!uid) return;
  await deleteDoc(doc(db, "users", uid, "sessions", id)).catch(() => {});
}
