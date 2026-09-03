/**
 * Notifiche push del browser.
 *
 * Porta sul web la registrazione dei token che su iOS fa `NotificationManager`:
 * stesso posto (`users/{uid}/fcmTokens/{token}`), stessi campi, `platform`
 * "web". Le preferenze su cosa notificare restano quelle dell'account, in
 * `notificationPrefs`: il server le legge una volta sola per tutti i
 * dispositivi, quindi qui non c'è niente da duplicare.
 *
 * Il permesso del browser è invece per forza locale: vale per questo browser su
 * questa macchina, e va chiesto con un gesto dell'utente — chiederlo al
 * caricamento della pagina è ciò che spinge le persone a bloccare le notifiche
 * per sempre.
 */
import { deleteDoc, doc, serverTimestamp, setDoc } from "firebase/firestore";
import { deleteToken, getMessaging, getToken, isSupported, onMessage } from "firebase/messaging";
import { app, db } from "../firebase";

/**
 * Chiave pubblica VAPID del progetto (Impostazioni Firebase → Cloud Messaging →
 * certificati push web). È pubblica per definizione — viaggia nella richiesta
 * di sottoscrizione — ma sta in una variabile d'ambiente perché cambia per
 * progetto e non deve finire hardcodata nel sorgente.
 */
const VAPID_KEY = import.meta.env.VITE_FIREBASE_VAPID_KEY || "";

const TOKEN_CACHE_KEY = "kidbox:pushToken";

/** Errore riconoscibile: manca la configurazione, non è colpa dell'utente. */
export class PushNotConfiguredError extends Error {
  constructor() {
    super("VAPID_KEY_MISSING");
    this.name = "PushNotConfiguredError";
  }
}

/**
 * Stato delle push su questo browser, senza chiedere niente all'utente.
 *
 * `supported` è falso dove manca l'infrastruttura (Safari su iOS finché il sito
 * non è aggiunto alla schermata Home, i browser senza service worker): meglio
 * dirlo che mostrare un interruttore che non farebbe nulla.
 */
export async function pushStatus() {
  const supported = (await isSupported().catch(() => false)) && "Notification" in window;
  return {
    supported,
    configured: !!VAPID_KEY,
    permission: supported ? Notification.permission : "unsupported",
    enabled: supported && Notification.permission === "granted" && !!localStorage.getItem(TOKEN_CACHE_KEY),
  };
}

/**
 * Chiede il permesso, ottiene il token e lo registra sull'account.
 *
 * Il token è anche l'id del documento, come sui client nativi: riscriverlo è
 * idempotente e non lascia duplicati quando il browser lo rinnova.
 */
export async function enablePush({ uid }) {
  if (!VAPID_KEY) throw new PushNotConfiguredError();

  const permission = await Notification.requestPermission();
  if (permission !== "granted") return { granted: false };

  const registration = await navigator.serviceWorker.register("/firebase-messaging-sw.js");
  const messaging = getMessaging(app);
  const token = await getToken(messaging, {
    vapidKey: VAPID_KEY,
    serviceWorkerRegistration: registration,
  });
  if (!token) return { granted: false };

  await setDoc(
    doc(db, "users", uid, "fcmTokens", token),
    { token, platform: "web", updatedAt: serverTimestamp() },
    { merge: true }
  );
  localStorage.setItem(TOKEN_CACHE_KEY, token);
  return { granted: true, token };
}

/**
 * Spegne le push su questo browser: il token va tolto anche dall'account, o il
 * server continuerebbe a mandare messaggi a un browser che non li mostra più.
 */
export async function disablePush({ uid }) {
  const token = localStorage.getItem(TOKEN_CACHE_KEY);
  localStorage.removeItem(TOKEN_CACHE_KEY);
  if (!token) return;

  try {
    await deleteToken(getMessaging(app));
  } catch {
    // Il token può essere già stato invalidato dal browser: quel che conta è
    // che sparisca dall'account, cosa che avviene comunque qui sotto.
  }
  await deleteDoc(doc(db, "users", uid, "fcmTokens", token)).catch(() => {});
}

/**
 * Notifiche mentre la scheda è aperta.
 *
 * In primo piano il browser non mostra niente da solo: il messaggio arriva qui
 * e tocca a noi decidere. Si passa da `Notification` invece che da un banner
 * interno per avere lo stesso avviso di sistema anche quando la scheda è
 * aperta ma nascosta dietro altre finestre.
 */
export function listenForegroundPush(onNotification) {
  isSupported().then((ok) => {
    if (!ok) return;
    onMessage(getMessaging(app), (payload) => {
      const data = payload.data || {};
      const title = data.title || payload.notification?.title || "KidBox";
      const body = data.body || payload.notification?.body || "";
      onNotification?.({ title, body, data });
      if (Notification.permission === "granted" && document.visibilityState !== "visible") {
        new Notification(title, { body, icon: "/favicon-192.png", tag: data.type || "kidbox" });
      }
    });
  });
}
