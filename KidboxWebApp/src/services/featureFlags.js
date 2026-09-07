/**
 * Interruttori remoti, porting di `KBFeatureFlags` (iOS) e `KBFeatureFlags.kt`
 * (Android).
 *
 * Nasce per il pulsante «Accedi con Facebook»: l'app Meta di KidBox è in
 * modalità sviluppo, quindi chi non ha un ruolo su di essa riceve «questa app
 * non funziona e lo sviluppatore ne è a conoscenza», che si legge come un
 * guasto di KidBox. Il pulsante va tolto, ma deve poter tornare il giorno in
 * cui Meta pubblica l'app, senza un nuovo rilascio: da qui l'interruttore.
 *
 * Perché Remote Config e non Firestore: la schermata di login sta **prima**
 * dell'autenticazione, e ogni documento sotto `config/` richiede `isSignedIn()`
 * (`firestore.rules:41-42`). Remote Config si legge senza account.
 *
 * Il valore vive in tre posti, dal più pronto al più autorevole: il default
 * compilato qui sotto, `localStorage` con l'ultimo valore visto, e Remote
 * Config. La stessa chiave dei client nativi — un solo parametro in console
 * governa iPhone, Android e browser.
 */
import { app } from "../firebase";

export const FACEBOOK_LOGIN_REMOTE_KEY = "facebook_login_enabled";

/** Cache locale: stesso nome della chiave usata da iOS e Android. */
const FACEBOOK_LOGIN_CACHE_KEY = "kb_facebookLoginEnabled";

/** Spento finché Meta non pubblica l'app. */
const FACEBOOK_LOGIN_FALLBACK = false;

/**
 * Lettura immediata, senza rete: è quella con cui parte la schermata di login.
 * `null` in cache significa «mai scritta», che non è `false`: la differenza
 * conterà il giorno in cui il default compilato tornerà `true`.
 */
export function facebookLoginEnabled() {
  try {
    const cached = localStorage.getItem(FACEBOOK_LOGIN_CACHE_KEY);
    return cached === null ? FACEBOOK_LOGIN_FALLBACK : cached === "true";
  } catch {
    return FACEBOOK_LOGIN_FALLBACK;
  }
}

/**
 * Allinea la cache al valore remoto e restituisce quello valido ora.
 *
 * Non va attesa per disegnare: la schermata parte dalla cache e si aggiorna
 * quando la risposta arriva. Se la rete manca resta l'ultimo valore noto, che
 * è già la scelta giusta dell'ultima volta — nessun fallback che riaccenda un
 * pulsante spento apposta.
 */
export async function refreshFeatureFlags() {
  try {
    const { getRemoteConfig, fetchAndActivate, getValue, isSupported } = await import(
      "firebase/remote-config"
    );
    // Remote Config sul web vuole IndexedDB: in navigazione privata o con i
    // dati di sito bloccati non è disponibile, e lì vale la cache.
    if (!(await isSupported())) return facebookLoginEnabled();

    const remoteConfig = getRemoteConfig(app);
    remoteConfig.defaultConfig = { [FACEBOOK_LOGIN_REMOTE_KEY]: FACEBOOK_LOGIN_FALLBACK };
    // In sviluppo si rilegge a ogni avvio, così una modifica in console si
    // verifica subito; in produzione un'ora, come sui client nativi: il flag
    // cambia una volta all'anno, non vale una chiamata a ogni apertura.
    remoteConfig.settings.minimumFetchIntervalMillis = import.meta.env.DEV ? 0 : 3600 * 1000;

    await fetchAndActivate(remoteConfig);
    const enabled = getValue(remoteConfig, FACEBOOK_LOGIN_REMOTE_KEY).asBoolean();
    try {
      localStorage.setItem(FACEBOOK_LOGIN_CACHE_KEY, String(enabled));
    } catch {
      // Storage negato: il valore vale per questa sessione e basta.
    }
    return enabled;
  } catch {
    return facebookLoginEnabled();
  }
}
