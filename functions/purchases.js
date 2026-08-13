/* eslint-disable max-len */
/**
 * Validazione lato server delle ricevute di acquisto (App Store e Google Play).
 *
 * Perché esiste: prima il client scriveva da solo `families/{id}.plan` su
 * Firestore dopo l'acquisto, e le rules glielo permettevano. Chiunque poteva
 * quindi assegnarsi Pro/Max con una singola scrittura, senza pagare nulla.
 * Qui la prova d'acquisto viene verificata crittograficamente e solo l'Admin
 * SDK scrive il piano.
 */

const fs = require("fs");
const path = require("path");
const logger = require("firebase-functions/logger");
const {SignedDataVerifier, Environment, VerificationStatus} = require("@apple/app-store-server-library");

/**
 * Nome leggibile dello stato di verifica Apple: l'eccezione della libreria
 * porta solo un codice numerico, inutile da leggere nei log.
 * @param {unknown} error
 * @return {string}
 */
function appleVerificationErrorLabel(error) {
  const status = error && typeof error === "object" ? error.status : undefined;
  if (status === undefined) return error?.message || "sconosciuto";
  const name = Object.keys(VerificationStatus).find((k) => VerificationStatus[k] === status);
  return name || `status-${status}`;
}

/** Bundle id dell'app iOS (target principale). */
const IOS_BUNDLE_ID = "it.vittorioscocca.KidBox";
/** App Store id numerico: richiesto dalla verifica in ambiente Production. */
const IOS_APP_APPLE_ID = 6761055375;
/** Package name dell'app Android. */
const ANDROID_PACKAGE_NAME = "it.vittorioscocca.kidbox";

/** Product id → piano. Unica mappa autorevole: un product id sconosciuto non concede nulla. */
const PRODUCT_TO_PLAN = {
  "it.vittorioscocca.kidbox.pro.monthly": "pro",
  "it.vittorioscocca.kidbox.max.monthly": "max",
};

/**
 * Piano corrispondente a un product id, o null se non riconosciuto.
 * @param {string|undefined|null} productId
 * @return {string|null}
 */
function planForProductId(productId) {
  if (!productId || typeof productId !== "string") return null;
  return PRODUCT_TO_PLAN[productId] || null;
}

let cachedRootCerts = null;

/**
 * Certificati root Apple usati per validare la catena della firma.
 * Sono pubblici (scaricati da apple.com/certificateauthority) e versionati
 * insieme alle functions: la verifica del JWS è quindi offline.
 * @return {Array<Buffer>}
 */
function appleRootCerts() {
  if (cachedRootCerts) return cachedRootCerts;
  const dir = path.join(__dirname, "certs");
  const files = ["AppleRootCA-G3.cer", "AppleRootCA-G2.cer", "AppleIncRootCertificate.cer"];
  cachedRootCerts = files
      .map((f) => path.join(dir, f))
      .filter((p) => fs.existsSync(p))
      .map((p) => fs.readFileSync(p));
  if (cachedRootCerts.length === 0) {
    throw new Error("Certificati root Apple mancanti in functions/certs");
  }
  return cachedRootCerts;
}

const verifierCache = new Map();

/**
 * @param {Environment} environment
 * @return {SignedDataVerifier}
 */
function appleVerifier(environment) {
  if (verifierCache.has(environment)) return verifierCache.get(environment);
  const verifier = new SignedDataVerifier(
      appleRootCerts(),
      // Controllo online della revoca dei certificati: è un flusso di acquisto,
      // non un percorso caldo, quindi la latenza in più vale la sicurezza.
      true,
      environment,
      IOS_BUNDLE_ID,
      IOS_APP_APPLE_ID,
  );
  verifierCache.set(environment, verifier);
  return verifier;
}

/**
 * Verifica un JWS StoreKit 2 (`Transaction.jwsRepresentation`).
 *
 * Prova prima Production e poi Sandbox: le build TestFlight e i test in
 * sandbox producono transazioni che Production rifiuta, e il client non può
 * dirci in modo affidabile in quale ambiente si trova.
 * @param {string} signedTransaction
 * @return {Promise<object>} payload decodificato e verificato
 */
async function verifyAppleTransaction(signedTransaction) {
  if (!signedTransaction || typeof signedTransaction !== "string") {
    throw new Error("signedTransaction mancante");
  }
  const environments = [Environment.PRODUCTION, Environment.SANDBOX];
  const failures = [];
  for (const env of environments) {
    try {
      const payload = await appleVerifier(env).verifyAndDecodeTransaction(signedTransaction);
      return {...payload, verifiedEnvironment: env};
    } catch (e) {
      failures.push(`${env}=${appleVerificationErrorLabel(e)}`);
    }
  }
  throw new Error(`Verifica ricevuta Apple fallita (${failures.join(", ")})`);
}

/**
 * Traduce una transazione Apple verificata in un esito di abbonamento.
 * @param {object} payload
 * @return {{plan: string|null, isActive: boolean, expiresAtMs: number|null, reason: string}}
 */
function subscriptionFromAppleTransaction(payload) {
  const plan = planForProductId(payload.productId);
  if (!plan) {
    return {plan: null, isActive: false, expiresAtMs: null, reason: "product-id-sconosciuto"};
  }
  if (payload.bundleId && payload.bundleId !== IOS_BUNDLE_ID) {
    return {plan: null, isActive: false, expiresAtMs: null, reason: "bundle-id-non-corrispondente"};
  }
  if (payload.revocationDate) {
    return {plan, isActive: false, expiresAtMs: null, reason: "rimborsata-o-revocata"};
  }
  const expiresAtMs = payload.expiresDate || null;
  if (expiresAtMs && expiresAtMs <= Date.now()) {
    return {plan, isActive: false, expiresAtMs, reason: "scaduta"};
  }
  return {plan, isActive: true, expiresAtMs, reason: "attiva"};
}

let cachedGoogleAuth = null;

/**
 * Client Google Auth per la Play Developer API.
 *
 * Nessuna chiave JSON: l'organizzazione blocca la creazione di chiavi per gli
 * account di servizio (constraints/iam.disableServiceAccountKeyCreation), e va
 * bene così — sono comunque la pratica meno sicura. La Cloud Function
 * `validatePurchase` gira già con l'identità dedicata
 * `play-purchase-validator@kidbox-42cd7.iam.gserviceaccount.com` (assegnata in
 * fase di deploy via `serviceAccount` nelle options di `onCall`), quindi le
 * Application Default Credentials la usano automaticamente: zero segreti da
 * gestire o far scadere. Quell'identità va autorizzata in Play Console
 * (Utenti e autorizzazioni → invita l'email del service account → permesso
 * "Visualizza dati finanziari, ordini e risposte ai sondaggi di annullamento").
 * @return {import("google-auth-library").GoogleAuth}
 */
function googleAuth() {
  if (!cachedGoogleAuth) {
    const {GoogleAuth} = require("google-auth-library");
    cachedGoogleAuth = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });
  }
  return cachedGoogleAuth;
}

/**
 * Verifica un acquisto Google Play tramite Play Developer API.
 * @param {string} purchaseToken
 * @param {string} productId
 * @return {Promise<{plan: string|null, isActive: boolean, expiresAtMs: number|null, reason: string}>}
 */
async function verifyGooglePurchase(purchaseToken, productId) {
  const plan = planForProductId(productId);
  if (!plan) {
    return {plan: null, isActive: false, expiresAtMs: null, reason: "product-id-sconosciuto"};
  }

  const client = await googleAuth().getClient();
  const url = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/" +
    `${encodeURIComponent(ANDROID_PACKAGE_NAME)}/purchases/subscriptionsv2/tokens/` +
    `${encodeURIComponent(purchaseToken)}`;

  const res = await client.request({url});
  const data = res.data || {};

  // subscriptionsv2: SUBSCRIPTION_STATE_ACTIVE / _IN_GRACE_PERIOD valgono come attivo.
  const state = data.subscriptionState;
  const activeStates = ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"];
  const lineItem = Array.isArray(data.lineItems) ? data.lineItems[0] : null;
  const expiryTime = lineItem?.expiryTime ? Date.parse(lineItem.expiryTime) : null;

  if (!activeStates.includes(state)) {
    return {plan, isActive: false, expiresAtMs: expiryTime, reason: `stato-${state || "sconosciuto"}`};
  }
  if (expiryTime && expiryTime <= Date.now()) {
    return {plan, isActive: false, expiresAtMs: expiryTime, reason: "scaduta"};
  }
  return {plan, isActive: true, expiresAtMs: expiryTime, reason: "attiva"};
}

module.exports = {
  IOS_BUNDLE_ID,
  ANDROID_PACKAGE_NAME,
  planForProductId,
  verifyAppleTransaction,
  subscriptionFromAppleTransaction,
  verifyGooglePurchase,
  logger,
};
