/* eslint-disable max-len */
/**
 * Catalogo piani — FONTE DI VERITÀ: il documento Firestore `config/plans`.
 *
 * Quote, prezzi e feature dei piani Free/Pro/Max si modificano dalla console
 * admin, senza deploy e senza release delle app. Da `config/plans` escono:
 *
 *   - le quote applicate davvero (questo modulo, letto da askAI e dallo storage);
 *   - ciò che iOS e Android mostrano (leggono lo stesso documento);
 *   - le card della landing (`scripts/render-landing-plans.js`, che però lavora
 *     sul JSON nel repo: dopo una modifica da console va riallineato — vedi
 *     `internal/plans-source-of-truth.md`).
 *
 * `plans.json` impacchettato col deploy resta la RETE DI SICUREZZA: si usa
 * quando il documento manca, non è leggibile o non supera la validazione.
 *
 * PERCHÉ LA VALIDAZIONE È QUI E NON SOLO NEL FORM: un documento modificabile da
 * browser governa spesa vera (messaggi AI, byte su Storage). I limiti di
 * [LIMITS] sono l'ultima parola e valgono sia in scrittura sia in lettura: un
 * documento fuori scala non viene applicato nemmeno se qualcuno lo scrive a
 * mano dalla console Firebase, scavalcando le rules con l'Admin SDK.
 */

const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const BUNDLED = require("./plans.json");

const GIB = 1024 * 1024 * 1024;

/** Tetti invalicabili: oltre questi il listino non viene applicato. */
const LIMITS = {
  /** Messaggi AI per finestra di quota, su qualunque piano a pagamento. */
  aiLimitMax: 500,
  /** Sul piano Free il bonus è una tantum: un errore qui è spesa API regalata. */
  aiLimitFreeMax: 20,
  storageBytesMax: 100 * GIB,
  storageBytesFreeMax: 2 * GIB,
  priceMonthlyMax: 99.99,
  maxFeatures: 20,
  maxTextLength: 200,
  langs: ["it", "en", "fr", "es"],
};

/** Campi che la console NON può toccare: cambiarli romperebbe gli acquisti. */
const CAMPI_IMMUTABILI = ["id", "order", "displayName", "productId", "currency"];

/** Piani ammessi, nell'ordine di presentazione. */
const PLAN_IDS = Object.values(BUNDLED.plans)
    .sort((a, b) => (a.order || 0) - (b.order || 0))
    .map((p) => p.id);

// ─────────────────────────────────────────────────────────────────────────────
// Validazione
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Mappa localizzata ripulita: solo lingue note, solo stringhe, testi accorciati.
 * @param {*} value
 * @return {Object<string, string>}
 */
function sanitizeLocalized(value) {
  const out = {};
  if (!value || typeof value !== "object") return out;
  for (const lang of LIMITS.langs) {
    const text = value[lang];
    if (typeof text === "string") out[lang] = text.slice(0, LIMITS.maxTextLength);
  }
  return out;
}

/**
 * Elenco feature ripulito per lingua.
 * @param {*} value
 * @return {Object<string, Array<object>>}
 */
function sanitizeFeatures(value) {
  const out = {};
  if (!value || typeof value !== "object") return out;
  for (const lang of LIMITS.langs) {
    const list = value[lang];
    if (!Array.isArray(list)) continue;
    out[lang] = list.slice(0, LIMITS.maxFeatures).map((f) => ({
      icon: String(f?.icon ?? "").slice(0, 8),
      text: String(f?.text ?? "").slice(0, LIMITS.maxTextLength),
      strong: f?.strong === true,
    })).filter((f) => f.text.length > 0);
  }
  return out;
}

/**
 * Valida e normalizza un listino completo.
 *
 * Non corregge in silenzio i numeri fuori scala: li rifiuta. Un limite tagliato
 * di nascosto sarebbe peggio di un errore, perché nessuno si accorgerebbe che
 * il valore applicato non è quello scritto nel form.
 *
 * @param {*} plans - Mappa {planId: spec} da validare.
 * @return {{ok: boolean, errors: string[], plans: object|null}}
 */
function validatePlans(plans) {
  const errors = [];
  if (!plans || typeof plans !== "object") {
    return {ok: false, errors: ["listino assente o non è un oggetto"], plans: null};
  }

  const out = {};
  for (const id of PLAN_IDS) {
    const base = BUNDLED.plans[id];
    const p = plans[id];
    if (!p || typeof p !== "object") {
      errors.push(`piano "${id}" mancante`);
      continue;
    }

    const storageBytes = Number(p.storageBytes);
    const aiLimit = Number(p.aiLimit);
    const aiPeriod = String(p.aiPeriod || "");
    const priceMonthly = Number(p.priceMonthly);
    const tettoStorage = id === "free" ? LIMITS.storageBytesFreeMax : LIMITS.storageBytesMax;
    const tettoAI = id === "free" ? LIMITS.aiLimitFreeMax : LIMITS.aiLimitMax;

    if (!Number.isFinite(storageBytes) || !Number.isInteger(storageBytes) || storageBytes < 0 || storageBytes > tettoStorage) {
      errors.push(`${id}: storageBytes deve essere un intero tra 0 e ${tettoStorage}`);
    }
    if (!Number.isInteger(aiLimit) || aiLimit < 0 || aiLimit > tettoAI) {
      errors.push(`${id}: aiLimit deve essere un intero tra 0 e ${tettoAI}`);
    }
    if (aiPeriod !== "daily" && aiPeriod !== "lifetime") {
      errors.push(`${id}: aiPeriod deve essere "daily" o "lifetime"`);
    }
    // Solo il Free può avere una quota una tantum: su un piano a pagamento
    // "lifetime" significherebbe abbonamento che smette di funzionare.
    if (id === "free" && aiPeriod !== "lifetime") {
      errors.push("free: aiPeriod deve restare \"lifetime\"");
    }
    if (id !== "free" && aiPeriod !== "daily") {
      errors.push(`${id}: aiPeriod deve restare "daily"`);
    }
    if (!Number.isFinite(priceMonthly) || priceMonthly < 0 || priceMonthly > LIMITS.priceMonthlyMax) {
      errors.push(`${id}: priceMonthly deve essere tra 0 e ${LIMITS.priceMonthlyMax}`);
    }

    out[id] = {
      storageBytes,
      aiLimit,
      aiPeriod,
      priceMonthly,
      highlighted: p.highlighted === true,
      priceLabel: sanitizeLocalized(p.priceLabel),
      tagline: sanitizeLocalized(p.tagline),
      badge: sanitizeLocalized(p.badge),
      features: sanitizeFeatures(p.features),
    };
    // I campi che identificano il piano e il prodotto sullo store vengono
    // sempre dal bundle: la console non li vede nemmeno.
    for (const campo of CAMPI_IMMUTABILI) out[id][campo] = base[campo];
  }

  return errors.length ? {ok: false, errors, plans: null} : {ok: true, errors: [], plans: out};
}

// ─────────────────────────────────────────────────────────────────────────────
// Lettura con cache
// ─────────────────────────────────────────────────────────────────────────────

/** Il documento cambia a mano, di rado: 60 s bastano a non rileggerlo a ogni chiamata. */
const CACHE_TTL_MS = 60 * 1000;
let cache = {at: 0, plans: null, source: "bundle"};

/**
 * Listino effettivo: `config/plans` se valido, altrimenti il JSON deployato.
 * @return {Promise<{plans: object, source: string}>}
 */
async function loadPlans() {
  const now = Date.now();
  if (cache.plans && now - cache.at < CACHE_TTL_MS) return cache;

  try {
    const snap = await admin.firestore().collection("config").doc("plans").get();
    const {ok, errors, plans} = validatePlans(snap.data()?.plans);
    if (ok) {
      cache = {at: now, plans, source: "firestore"};
      return cache;
    }
    if (snap.exists) {
      logger.warn("plansConfig: documento config/plans non valido, uso il bundle", {errors});
    }
  } catch (e) {
    logger.warn("plansConfig: lettura config/plans fallita, uso il bundle", {error: e.message});
  }

  cache = {at: now, plans: BUNDLED.plans, source: "bundle"};
  return cache;
}

/** Svuota la cache: da chiamare subito dopo una scrittura del listino. */
function invalidateCache() {
  cache = {at: 0, plans: null, source: "bundle"};
}

/**
 * Spec di un piano, con fallback su `free` per input sconosciuti/assenti.
 * @param {object} plans
 * @param {string|null|undefined} plan
 * @return {object}
 */
function planSpec(plans, plan) {
  const key = String(plan || "").trim().toLowerCase();
  return plans[key] || plans.free || BUNDLED.plans.free;
}

/**
 * Quota storage in byte del piano.
 * @param {string|null|undefined} plan
 * @return {Promise<number>}
 */
async function storageQuotaBytesForPlan(plan) {
  const {plans} = await loadPlans();
  return planSpec(plans, plan).storageBytes;
}

/**
 * Quota messaggi AI per famiglia: su `free` è un bonus UNA TANTUM che non si
 * resetta mai (`lifetime`), su Pro/Max è la quota giornaliera (`daily`).
 * @param {string|null|undefined} plan
 * @return {Promise<{period: string, limit: number}>}
 */
async function aiQuotaForPlan(plan) {
  const {plans} = await loadPlans();
  const spec = planSpec(plans, plan);
  return {period: spec.aiPeriod, limit: spec.aiLimit};
}

/**
 * Listino da mostrare/modificare in console, con l'indicazione della provenienza.
 * @return {Promise<{plans: object, source: string, bundled: object, limits: object}>}
 */
async function currentCatalog() {
  const {plans, source} = await loadPlans();
  return {plans, source, bundled: BUNDLED.plans, limits: LIMITS};
}

module.exports = {
  LIMITS,
  PLAN_IDS,
  BUNDLED_VERSION: BUNDLED.version,
  bundledPlans: () => BUNDLED.plans,
  validatePlans,
  loadPlans,
  invalidateCache,
  storageQuotaBytesForPlan,
  aiQuotaForPlan,
  currentCatalog,
  AI_FREE_LIFETIME_LIMIT: BUNDLED.plans.free.aiLimit,
};
