/**
 * Impostazioni utente: porta sul web `SettingsView` e le sue schermate figlie
 * (iOS), che scrivono tutte sullo stesso documento `users/{uid}`.
 *
 * Tre gruppi di campi, con significati diversi:
 * • `notificationPrefs` — quali notifiche il server ha il permesso di mandare.
 *   Campo assente = attiva, come in `getUserTokensIfEnabled`: leggere `false`
 *   dove non c'è scritto niente mostrerebbe spento ciò che invece arriva.
 * • `appPrefs.chatEnabled` — interruttore della chat di famiglia, preferenza
 *   dell'account e non del dispositivo (gemello di `KBChatAvailability`).
 * • `aiPrefs` — scelte dell'assistente che riguardano i dati sanitari.
 *
 * Le preferenze che su iOS vivono solo in `UserDefaults` (trascrizione vocale,
 * consigli, report errori) restano del dispositivo: la pagina le mostra come
 * tali invece di fingere di comandarle da qui.
 */
import { doc, getDoc, serverTimestamp, setDoc } from "firebase/firestore";
import { db } from "../firebase";

const userRef = (uid) => doc(db, "users", uid);

/** Chiavi di `notificationPrefs`, nell'ordine in cui iOS le elenca. */
export const NOTIFICATION_PREFS = [
  "notifyOnNewMessages",
  "notifyOnLocationSharing",
  "notifyOnTodoAssigned",
  "notifyOnNewGroceryItem",
  "notifyOnNewNote",
  "notifyOnNewExpense",
  "notifyOnNewCalendarEvent",
  "notifyOnNewDocument",
  "notifyOnWallet",
];

export const HEALTH_CONTEXT_PREFS = ["ask_each_time", "full_accuracy", "compact_summary"];

/** Lingue con cui il server sa tradurre le push (`notificationLanguage`). */
export const LANGUAGES = [
  { code: "it", label: "Italiano", flag: "🇮🇹" },
  { code: "en", label: "English", flag: "🇬🇧" },
];

/**
 * Stato completo delle impostazioni dell'account, con i default di iOS già
 * applicati: una sola lettura invece di una per interruttore.
 */
export async function loadSettings(uid) {
  const snap = await getDoc(userRef(uid));
  const d = snap.exists() ? snap.data() : {};
  const prefs = d.notificationPrefs || {};

  const notifications = {};
  for (const key of NOTIFICATION_PREFS) {
    notifications[key] = typeof prefs[key] === "boolean" ? prefs[key] : true;
  }
  // I documenti hanno avuto il loro interruttore dopo: chi li aveva silenziati
  // con `notifyOnWallet` non se li ritrova riaccesi. Stessa scala di iOS.
  if (typeof prefs.notifyOnNewDocument !== "boolean" && typeof prefs.notifyOnWallet === "boolean") {
    notifications.notifyOnNewDocument = prefs.notifyOnWallet;
  }

  return {
    notifications,
    aiEnabled: prefs.aiEnabled === true,
    chatEnabled: d.appPrefs?.chatEnabled !== false,
    healthContextSendPreference:
      d.aiPrefs?.healthContextSendPreference || "ask_each_time",
    notificationLanguage: d.notificationLanguage || "",
  };
}

export function setNotificationPref(uid, key, enabled) {
  return setDoc(userRef(uid), { notificationPrefs: { [key]: enabled } }, { merge: true });
}

export function setAIEnabled(uid, enabled) {
  return setDoc(userRef(uid), { notificationPrefs: { aiEnabled: enabled } }, { merge: true });
}

export function setHealthContextSendPreference(uid, preference) {
  return setDoc(
    userRef(uid),
    {
      aiPrefs: {
        healthContextSendPreference: preference,
        healthContextSendPreferenceUpdatedAt: serverTimestamp(),
      },
    },
    { merge: true }
  );
}

/** Il server legge questo campo per tradurre le push: senza, restano in italiano. */
export function setNotificationLanguage(uid, code) {
  return setDoc(userRef(uid), { notificationLanguage: code }, { merge: true });
}

/** Ricorda che le notifiche dei messaggi le abbiamo spente noi con la chat. */
const PAUSED_KEY = "kidbox:chatNotificationsPausedByChatOff";

/**
 * Accende/spegne la chat e, con essa, le notifiche dei messaggi: spenta la
 * chat, una notifica porterebbe a una schermata che non si apre.
 *
 * Riaccendendo la chat le notifiche tornano **solo se le avevamo spente noi**:
 * chi le aveva già disattivate per conto suo se le ritrova disattivate.
 * Ritorna il nuovo valore di `notifyOnNewMessages`, che la pagina usa per
 * aggiornare l'interruttore corrispondente.
 */
export async function setChatEnabled(uid, enabled, notifyOnNewMessages) {
  await setDoc(userRef(uid), { appPrefs: { chatEnabled: enabled } }, { merge: true });

  if (!enabled) {
    if (!notifyOnNewMessages) return notifyOnNewMessages;
    localStorage.setItem(PAUSED_KEY, "1");
    await setNotificationPref(uid, "notifyOnNewMessages", false);
    return false;
  }

  if (localStorage.getItem(PAUSED_KEY) === "1") {
    localStorage.removeItem(PAUSED_KEY);
    await setNotificationPref(uid, "notifyOnNewMessages", true);
    return true;
  }
  return notifyOnNewMessages;
}
