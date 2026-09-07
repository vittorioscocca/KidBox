import { initializeApp } from "firebase/app";
import { initializeAppCheck, ReCaptchaEnterpriseProvider } from "firebase/app-check";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";
import { getFunctions } from "firebase/functions";
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

if (recaptchaSiteKey) {
  // In sviluppo il provider reale fallirebbe su localhost. Questo flag fa
  // stampare in console un token di debug da registrare una volta in
  // Firebase Console → App Check → Gestisci token di debug.
  if (import.meta.env.DEV) {
    self.FIREBASE_APPCHECK_DEBUG_TOKEN = true;
  }

  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(recaptchaSiteKey),
    isTokenAutoRefreshEnabled: true,
  });
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
