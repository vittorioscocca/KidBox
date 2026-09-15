/**
 * Google Analytics (GA4) per il client web, allineato a `AppAnalytics.swift` e
 * `AppAnalytics.kt`.
 *
 * **I nomi degli eventi e dei parametri devono restare identici a quelli dei
 * client nativi**: finiscono nella stessa proprietà GA4 (lo stream web è quello
 * di `measurementId` in `firebase.js`), e un nome diverso significa una serie
 * separata che nessun rapporto somma. Se aggiungi un evento qui, aggiungilo
 * anche di là — e viceversa.
 *
 * Ogni chiamata è **silenziosamente inerte** quando Analytics non è disponibile:
 * `isSupported()` è falso in alcuni browser, e le estensioni che bloccano i
 * tracker fanno fallire il caricamento. Un errore di analytics non deve mai
 * rompere una schermata.
 */
import { app } from "../firebase";

let analyticsPromise = null;

/**
 * Consenso. Tre stati, non due: `null` significa **non ancora deciso**, ed è la
 * condizione in cui non parte niente. Con un default «acceso» il banner
 * arriverebbe dopo i primi eventi, cioè troppo tardi per servire a qualcosa.
 *
 * La scelta vive nel browser: è per dispositivo, e il dominio della landing —
 * altra origine — ha la sua.
 */
const CONSENT_KEY = "kidbox:analyticsConsent";

export const CONSENT_GRANTED = "granted";
export const CONSENT_DENIED = "denied";

/** `"granted"`, `"denied"` oppure `null` se non ha ancora scelto. */
export function analyticsConsent() {
  try {
    const v = localStorage.getItem(CONSENT_KEY);
    return v === CONSENT_GRANTED || v === CONSENT_DENIED ? v : null;
  } catch {
    // Senza storage non si può ricordare una scelta: si resta sul rifiuto.
    return CONSENT_DENIED;
  }
}

export function setAnalyticsConsent(value) {
  try {
    localStorage.setItem(CONSENT_KEY, value);
  } catch {
    // Niente da fare: la sessione resta senza analytics.
  }
}

export const isAnalyticsEnabled = () => analyticsConsent() === CONSENT_GRANTED;

/** Carica il modulo solo quando serve: pesa, e a molti utenti è bloccato. */
async function analytics() {
  if (!isAnalyticsEnabled()) return null;
  if (!analyticsPromise) {
    analyticsPromise = (async () => {
      try {
        const mod = await import("firebase/analytics");
        if (!(await mod.isSupported())) return null;
        const instance = mod.getAnalytics(app);
        // Se il login è arrivato prima che Analytics fosse caricato (consenso
        // dato dopo), il parametro va messo adesso.
        if (internalUser) mod.setDefaultEventParameters({ traffic_type: "internal" });
        return { instance, logEvent: mod.logEvent, setDefaultEventParameters: mod.setDefaultEventParameters };
      } catch {
        return null;
      }
    })();
  }
  return analyticsPromise;
}

/* ── Traffico interno ─────────────────────────────────────────────────────── */

/**
 * Account di test dello sviluppatore: gli eventi partono con
 * `traffic_type = internal`, che il filtro «Traffico interno» di GA4 tiene
 * fuori dai report. Stesso elenco di hash SHA-256 di `InternalTraffic.swift`
 * e `InternalTraffic.kt`; mai l'email in chiaro nel bundle. Lo stesso elenco,
 * come uid, sta in `config/internalUsers` su Firestore per rollup e report.
 */
const INTERNAL_EMAIL_HASHES = new Set([
  "2932b8f0e073118c0ca7484c73ae1e33ba8b9e3011e4b78ae17da4dfb7c74f21",
  "ef18139763e351755d752d5ea05e5efc6aaf7a7dd666a9c559cda03236f540d3",
  "0b45a4dc93984656b8eec293859533018cc6d5dc3bac24d5c554d92bc8fb0486",
  "09ea5430711b0dc611c7eadf90e20a2072af2fc5224f0318ad82501e59d069d9",
  "e4876522f848d46ce31670b18e6e90486e6c90b41107670a199f98d46cff8aa3",
]);

let internalUser = false;

async function sha256Hex(text) {
  const data = new TextEncoder().encode(text.trim().toLowerCase());
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** Da chiamare a ogni cambio di stato di autenticazione (`user` o `null`). */
export async function setInternalTraffic(user) {
  let internal = false;
  if (user) {
    const emails = [...(user.providerData || []).map((p) => p.email), user.email].filter(Boolean);
    for (const e of emails) {
      // `crypto.subtle` manca solo su origini non sicure: lì non si marca nulla.
      if (!globalThis.crypto?.subtle) break;
      if (INTERNAL_EMAIL_HASHES.has(await sha256Hex(e))) { internal = true; break; }
    }
  }
  internalUser = internal;
  analytics()
    .then((a) => {
      if (a) a.setDefaultEventParameters(internal ? { traffic_type: "internal" } : {});
    })
    .catch(() => {});
}

/** Non restituisce una Promise di proposito: nessun call site deve attenderla. */
function log(name, params) {
  analytics()
    .then((a) => {
      if (a) a.logEvent(a.instance, name, params);
    })
    .catch(() => {});
}

/* ── Registrazione e accesso ──────────────────────────────────────────────── */

export const signupStarted = (method) => log("signup_started", { method });
export const signupCompleted = (method) => log("signup_completed", { method });
export const signupMethodSelected = (method) => log("signup_method_selected", { method });
/** L'evento che misura davvero il tap: gli altri tre, sul social, sono emessi
 *  dopo il successo del login e non hanno un intervallo reale. */
export const loginAttempted = (method) => log("login_attempted", { method });
export const preSignupScreenShown = (screenName) =>
  log("pre_signup_screen_shown", { screen_name: screenName });
export const preSignupScreenDismissed = (screenName) =>
  log("pre_signup_screen_dismissed", { screen_name: screenName });

/* ── Onboarding e famiglia ────────────────────────────────────────────────── */

export const onboardingStepShown = (stepName, stepNumber) =>
  log("onboarding_step_shown", { step_name: stepName, step_number: stepNumber });
export const onboardingStepCompleted = (stepName) =>
  log("onboarding_step_completed", { step_name: stepName });
export const onboardingCompleted = (totalDurationSeconds) =>
  log("onboarding_completed", { total_duration_seconds: totalDurationSeconds });
export const onboardingAbandoned = (lastStepSeen) =>
  log("onboarding_abandoned", { last_step_seen: lastStepSeen });
export const familyCreated = () => log("family_created");
export const onboardingInviteStepShown = () => log("onboarding_invite_step_shown");
export const onboardingInviteStepSkipped = () => log("onboarding_invite_step_skipped");
export const inviteGenerated = () => log("invite_generated");
export const inviteShared = (channel) => log("invite_shared", { channel });
export const familyJoinAttempted = () => log("family_join_attempted");
export const familyJoined = (vaultKeyAvailable) =>
  log("family_joined", { vault_key_available: vaultKeyAvailable });
export const familyJoinFailed = (reason) => log("family_join_failed", { reason });

/* ── Uso ──────────────────────────────────────────────────────────────────── */

export const screenView = (name) => log("screen_view", { screen_name: name });
export const contentCreated = (type) => log("content_created", { content_type: type });
export const contentSharedRead = (type) => log("content_shared_read", { content_type: type });

/* ── AI e abbonamenti ─────────────────────────────────────────────────────── */

export const aiPaywallShown = (context) => log("ai_paywall_shown", { context });
export const aiMessageSent = (agentType, plan) =>
  log("ai_message_sent", { agent_type: agentType, plan });
export const aiBriefingReceived = () => log("ai_briefing_received");
export const paywallShown = (triggerFeature, planShown) =>
  log("paywall_shown", { trigger_feature: triggerFeature, plan_shown: planShown });
export const subscriptionStarted = (plan, trial) =>
  log("subscription_started", { plan, trial });

/* ── Prima volta su una feature ───────────────────────────────────────────── */

const FIRST_USE_KEY = "kidbox:featuresSeen";

/**
 * `feature_first_use` una volta sola per feature e per browser, come i nativi
 * fanno con UserDefaults e SharedPreferences.
 */
export function featureFirstUse(feature) {
  try {
    const seen = new Set(JSON.parse(localStorage.getItem(FIRST_USE_KEY) || "[]"));
    if (seen.has(feature)) return;
    seen.add(feature);
    localStorage.setItem(FIRST_USE_KEY, JSON.stringify([...seen]));
  } catch {
    // Senza storage l'evento partirebbe a ogni visita: meglio non mandarlo.
    return;
  }
  log("feature_first_use", { feature });
}

/* ── Apertura ─────────────────────────────────────────────────────────────── */

const INSTALL_KEY = "kidbox:analyticsInstallDate";
const LAST_OPEN_KEY = "kidbox:analyticsLastOpenDate";
const DAY_MS = 24 * 60 * 60 * 1000;

/** `app_open` con i giorni dall'installazione e dall'ultima apertura, come i nativi. */
export function trackAppOpen() {
  let installDate;
  let lastOpenDate;
  const now = Date.now();
  try {
    installDate = Number(localStorage.getItem(INSTALL_KEY)) || now;
    if (!localStorage.getItem(INSTALL_KEY)) localStorage.setItem(INSTALL_KEY, String(now));
    lastOpenDate = Number(localStorage.getItem(LAST_OPEN_KEY)) || installDate;
    localStorage.setItem(LAST_OPEN_KEY, String(now));
  } catch {
    installDate = now;
    lastOpenDate = now;
  }
  log("app_open", {
    days_since_install: Math.floor((now - installDate) / DAY_MS),
    days_since_last_open: Math.floor((now - lastOpenDate) / DAY_MS),
  });
}
