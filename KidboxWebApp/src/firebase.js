import { initializeApp } from "firebase/app";
import { initializeAppCheck, ReCaptchaEnterpriseProvider } from "firebase/app-check";
import { connectAuthEmulator, getAuth } from "firebase/auth";
import { connectFirestoreEmulator, getFirestore } from "firebase/firestore";
import { connectFunctionsEmulator, getFunctions } from "firebase/functions";
import { getStorage } from "firebase/storage";

const firebaseConfig = {
  apiKey: "AIzaSyC7mDpJ1LadjvhhcoospAp2f0xuawCOOFk",
  authDomain: "kidbox-42cd7.firebaseapp.com",
  projectId: "kidbox-42cd7",
  // Bucket UE, lo stesso hardcoded nei client nativi (GoogleService-Info.plist /
  // google-services.json) e nelle Cloud Functions. NON è il bucket di default del
  // progetto: usare quello farebbe scrivere le foto in un posto che gli altri
  // client non guardano mai.
  storageBucket: "kidbox-42cd7-eu",
  messagingSenderId: "52613538008",
  appId: "1:52613538008:web:c5417674e80de0303df7ad",
  measurementId: "G-0PG65CW2VF",
};

export const app = initializeApp(firebaseConfig);

// ── App Check ────────────────────────────────────────────────────────────────
// Va inizializzato SUBITO dopo initializeApp e PRIMA di getAuth/getFirestore/…:
// i token vengono allegati alle richieste dei servizi creati dopo, quindi
// invertire l'ordine lascerebbe scoperte proprio le prime chiamate.
//
// Nel browser non esistono App Attest o Play Integrity: l'unico provider è
// reCAPTCHA Enterprise, che dà un punteggio comportamentale invece di una prova
// hardware. Garanzia più debole di quella mobile per costruzione, ma sufficiente
// contro l'abuso automatizzato (script/bot che chiamano askAI fuori da un browser),
// che è il vettore che ci interessa.
//
// La chiave del sito è PUBBLICA per definizione (finisce nel bundle): la
// sicurezza sta nella validazione lato server, non nel tenerla nascosta.
// Sta in .env.local come la VAPID per la stessa ragione: cambia da progetto a progetto.
const recaptchaSiteKey = import.meta.env.VITE_RECAPTCHA_SITE_KEY || "";

// In locale App Check NON si inizializza affatto.
//
// Prima qui si impostava `FIREBASE_APPCHECK_DEBUG_TOKEN = true`, che fa
// generare al volo un token di debug: non essendo registrato (l'app web ha
// zero token di debug, e registrarne uno sarebbe un bypass valido per
// l'intero progetto, askAI compreso) ogni scambio tornava 403. Peggio: a
// scambio fallito l'SDK non parte senza token, ne allega uno segnaposto che
// viene respinto, quindi ogni richiesta della sessione risultava INVALID e
// sporcava la soglia da cui dipende l'accensione dell'enforcement.
//
// Il dominio `localhost` non è fra quelli autorizzati sulla chiave reCAPTCHA
// e non va aggiunto: chiunque può servire una pagina su localhost, quindi
// quel permesso varrebbe come chiave per farsi rilasciare token App Check
// validi per tutto il progetto.
//
// Conseguenza da sapere: quando l'enforcement sarà acceso, questa app in
// locale non potrà più parlare con il Firebase di produzione. Si sviluppa
// contro gli emulatori (VITE_USE_EMULATORS=1) o si prova sul deployato.
const appCheckDisabledInDev = import.meta.env.DEV;

if (appCheckDisabledInDev) {
  console.info(
    "[AppCheck] sviluppo locale: App Check non inizializzato di proposito. " +
    "Con l'enforcement acceso usa gli emulatori (VITE_USE_EMULATORS=1).",
  );
} else if (recaptchaSiteKey) {
  // try/catch obbligatorio: App Check è infrastruttura OPZIONALE finché
  // l'enforcement è spento, quindi non deve mai poter spegnere l'app.
  // Senza, un'eccezione qui salterebbe gli export getAuth/getFirestore/… qui
  // sotto. Cause plausibili: chiave revocata, dominio non più autorizzato,
  // o un adblocker che blocca google.com/recaptcha.
  try {
    initializeAppCheck(app, {
      provider: new ReCaptchaEnterpriseProvider(recaptchaSiteKey),
      isTokenAutoRefreshEnabled: true,
    });
  } catch (e) {
    console.warn("[AppCheck] inizializzazione fallita, si prosegue senza token:", e);
  }
} else {
  // Nessuna chiave configurata: si prosegue senza App Check. Finché
  // l'enforcement è spento lato server l'app funziona identica; quando verrà
  // acceso, senza chiave qui le richieste verrebbero rifiutate.
  console.warn(
    "[AppCheck] VITE_RECAPTCHA_SITE_KEY non configurata: App Check non attivo. " +
    "Obbligatoria prima di abilitare l'enforcement lato server.",
  );
}

export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, "europe-west1");
export const storage = getStorage(app);

// Solo in sviluppo e solo se chiesto (`VITE_USE_EMULATORS=1 npm run dev`): Auth,
// Firestore e Functions degli emulatori locali, con le regole del repo. Serve a
// provare flussi come la cassaforte della chiave in un browser pulito, con
// account usa e getta, senza toccare i dati veri.
if (import.meta.env.DEV && import.meta.env.VITE_USE_EMULATORS === "1") {
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  connectFirestoreEmulator(db, "127.0.0.1", 8080);
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  console.warn("[Firebase] emulatori locali attivi");
}
