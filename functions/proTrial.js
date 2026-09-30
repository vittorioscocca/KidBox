/* eslint-disable max-len */
/**
 * Prova Pro senza carta: il proprietario la attiva dal pulsante «Prova Pro per
 * 14 giorni» (callable `startProTrial`), e la famiglia torna al Free da sola.
 * Finché `config/trial.autoGrant` non è false parte anche da sola alla
 * creazione della famiglia, per le app pubblicate prima del pulsante.
 *
 * Perché lato server: il piano dei client arriva da `families/{id}.plan`, quindi
 * scrivere lì `pro` sblocca la prova anche sulle app già pubblicate, senza
 * aspettare una release. La prova usa gli stessi campi protetti dalle rules di
 * un abbonamento vero (`plan`, `planSource`, `planExpiresAt`): nessun campo
 * nuovo sulla famiglia che un client potrebbe scrivere per allungarsi la prova.
 *
 * Una volta per PERSONA, non per famiglia: chiunque può creare famiglie
 * illimitate, e il registro `trials/{uid}` (solo server, nessuna rule lo apre)
 * impedisce di rigenerare la prova aprendone una nuova.
 *
 * L'AI della prova ha una quota sua, più bassa del Pro: un totale per tutta la
 * durata (`period: "trial"`, contatore `ai_usage/family_{id}/lifetime/trial`).
 * Il resto del Pro (spazio, pianificatori) è sbloccato per intero.
 *
 * Interruttore e parametri in `config/trial` (vedi DEFAULTS). Spento finché
 * `enabled` non è true: così il codice può stare in produzione prima che i
 * client che spiegano la prova siano pubblicati.
 */

const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const DEFAULTS = {
  enabled: false,
  /** Concessione automatica alla creazione della famiglia (app senza pulsante). */
  autoGrant: true,
  days: 14,
  plan: "pro",
  /** Messaggi AI in tutto, per l'intera prova (non al giorno). */
  aiLimit: 50,
  /** Giorni prima della fine in cui arriva il promemoria push. */
  reminderDaysBefore: 2,
};

const BOUNDS = {
  days: [1, 30],
  aiLimit: [0, 200],
  reminderDaysBefore: [0, 7],
};

const DAY_MS = 24 * 60 * 60 * 1000;
const CACHE_TTL_MS = 60 * 1000;
let cache = {at: 0, cfg: null};

/**
 * Riporta un numero dentro i limiti, o il default se non è un intero valido.
 * @param {*} value
 * @param {string} key
 * @return {number}
 */
function clampInt(value, key) {
  const n = Number(value);
  const [min, max] = BOUNDS[key];
  if (!Number.isInteger(n)) return DEFAULTS[key];
  return Math.min(max, Math.max(min, n));
}

/**
 * Parametri della prova da `config/trial`, con i default come rete di sicurezza.
 * Un documento assente o illeggibile vale «prova spenta».
 * @return {Promise<typeof DEFAULTS>}
 */
async function loadTrialConfig() {
  const now = Date.now();
  if (cache.cfg && now - cache.at < CACHE_TTL_MS) return cache.cfg;
  let cfg = {...DEFAULTS};
  try {
    const snap = await admin.firestore().collection("config").doc("trial").get();
    const d = snap.exists ? snap.data() || {} : {};
    cfg = {
      enabled: d.enabled === true,
      autoGrant: d.autoGrant !== false,
      days: clampInt(d.days ?? DEFAULTS.days, "days"),
      // La prova non concede mai il Max: il suo costo AI non è coperto.
      plan: "pro",
      aiLimit: clampInt(d.aiLimit ?? DEFAULTS.aiLimit, "aiLimit"),
      reminderDaysBefore: clampInt(d.reminderDaysBefore ?? DEFAULTS.reminderDaysBefore, "reminderDaysBefore"),
    };
  } catch (e) {
    logger.warn("proTrial: lettura config/trial fallita, prova spenta", {error: e.message});
    cfg = {...DEFAULTS, enabled: false};
  }
  cache = {at: now, cfg};
  return cfg;
}

/**
 * Quota AI della prova, nella stessa forma di `plansConfig.aiQuotaForPlan`.
 * @return {Promise<{period: string, limit: number}>}
 */
async function trialAIQuota() {
  const cfg = await loadTrialConfig();
  return {period: "trial", limit: cfg.aiLimit};
}

/**
 * Perché la prova non si può concedere, o null se si può.
 * Il proprietario è `ownerUid` della famiglia o il membro con `role: "owner"`,
 * come `isFamilyOwner` dei client: la prova è sua, e a lui vanno le push.
 * @param {FirebaseFirestore.DocumentSnapshot} familySnap
 * @param {FirebaseFirestore.DocumentSnapshot} trialSnap
 * @param {?FirebaseFirestore.DocumentSnapshot} memberSnap null = non controllare il ruolo
 * @param {string} uid
 * @return {?string}
 */
function ineligibleReason(familySnap, trialSnap, memberSnap, uid) {
  if (!familySnap.exists) return "no-family";
  if (trialSnap.exists) return "already-used";
  const d = familySnap.data() || {};
  if (memberSnap) {
    const isOwner = d.ownerUid === uid || (memberSnap.exists && memberSnap.get("role") === "owner");
    if (!isOwner) return "not-owner";
  }
  const override = d.planOverride;
  if (override === "pro" || override === "max") return "override";
  if (d.plan && d.plan !== "free") return "has-plan";
  return null;
}

/** Pausa fra due richieste della prova dello stesso membro al proprietario. */
const REQUEST_COOLDOWN_MS = DAY_MS;

/**
 * Se il pulsante della prova va mostrato a `uid` per questa famiglia.
 * Solo letture: la chiamano i client all'apertura di piani e spazio.
 *
 * A chi non è proprietario dice anche se il proprietario potrebbe attivarla
 * (`ownerCanStart`) e se gliel'ha già chiesto da poco (`askedOwner`): il
 * client mostra allora «Chiedi di attivarla» invece del pulsante.
 * @param {string} familyId
 * @param {string} uid
 * @return {Promise<{eligible: boolean, reason: string, days: number, aiLimit: number,
 *     ownerCanStart: boolean, askedOwner: boolean}>}
 */
async function trialEligibility(familyId, uid) {
  const cfg = await loadTrialConfig();
  const base = {days: cfg.days, aiLimit: cfg.aiLimit, ownerCanStart: false, askedOwner: false};
  if (!cfg.enabled) return {eligible: false, reason: "disabled", ...base};
  const db = admin.firestore();
  const familyRef = db.collection("families").doc(familyId);
  const [familySnap, trialSnap, memberSnap] = await Promise.all([
    familyRef.get(),
    db.collection("trials").doc(uid).get(),
    familyRef.collection("members").doc(uid).get(),
  ]);
  const reason = ineligibleReason(familySnap, trialSnap, memberSnap, uid);
  if (reason !== "not-owner") return {eligible: reason === null, reason: reason || "ok", ...base};

  const ownerUid = familySnap.get("ownerUid");
  if (!ownerUid) return {eligible: false, reason, ...base};
  const [ownerTrialSnap, requestSnap] = await Promise.all([
    db.collection("trials").doc(ownerUid).get(),
    trialRequestRef(familyId, uid).get(),
  ]);
  const ownerCanStart = ineligibleReason(familySnap, ownerTrialSnap, null, ownerUid) === null;
  const askedAtMs = requestSnap.get("requestedAt")?.toMillis?.() ?? 0;
  return {
    eligible: false,
    reason,
    ...base,
    ownerCanStart,
    askedOwner: Date.now() - askedAtMs < REQUEST_COOLDOWN_MS,
  };
}

/**
 * Registro delle richieste «chiedi di attivare la prova» (solo server): una
 * per membro e famiglia, per non far arrivare al proprietario una push a tocco.
 * @param {string} familyId
 * @param {string} uid chi chiede
 * @return {FirebaseFirestore.DocumentReference}
 */
function trialRequestRef(familyId, uid) {
  return admin.firestore().collection("trialRequests").doc(`${familyId}_${uid}`);
}

/**
 * Concede la prova alla famiglia, se `uid` non l'ha mai avuta.
 *
 * Non tocca nulla se la famiglia ha già un piano (abbonamento o override della
 * console): la prova non deve mai sovrascrivere qualcosa che vale di più.
 * @param {string} familyId
 * @param {string} uid chi riceve la prova (il proprietario della famiglia)
 * @param {{source?: string, force?: boolean, requireOwner?: boolean}} opts
 *     `force` salta l'interruttore (solo per gli script amministrativi, mai
 *     dai trigger); `requireOwner` rifiuta chi non è proprietario (callable)
 * @return {Promise<{granted: boolean, reason: string, expiresAtMs?: number}>}
 */
async function grantTrial(familyId, uid, opts = {}) {
  if (!familyId || !uid) return {granted: false, reason: "missing-ids"};
  const cfg = await loadTrialConfig();
  if (!cfg.enabled && opts.force !== true) return {granted: false, reason: "disabled"};

  const db = admin.firestore();
  const familyRef = db.collection("families").doc(familyId);
  const trialRef = db.collection("trials").doc(uid);
  const memberRef = familyRef.collection("members").doc(uid);

  return db.runTransaction(async (tx) => {
    const [familySnap, trialSnap, memberSnap] = await Promise.all([
      tx.get(familyRef),
      tx.get(trialRef),
      opts.requireOwner ? tx.get(memberRef) : Promise.resolve(null),
    ]);
    const reason = ineligibleReason(familySnap, trialSnap, memberSnap, uid);
    if (reason) return {granted: false, reason};

    const nowMs = Date.now();
    const expiresAtMs = nowMs + cfg.days * DAY_MS;
    const expiresAt = admin.firestore.Timestamp.fromMillis(expiresAtMs);

    tx.set(familyRef, {
      plan: cfg.plan,
      planSource: "trial",
      planUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      planExpiresAt: expiresAt,
    }, {merge: true});
    tx.set(trialRef, {
      familyId,
      plan: cfg.plan,
      days: cfg.days,
      aiLimit: cfg.aiLimit,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
      source: opts.source || "family_created",
    });
    return {granted: true, reason: "ok", expiresAtMs};
  });
}

/**
 * Riferimenti ai contatori AI per un periodo di quota.
 * `lifetime` (Free) scala anche per utente; `trial` solo per famiglia, perché
 * la prova è già una per persona alla concessione; `daily` per famiglia e giorno.
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} familyId
 * @param {string} uid
 * @param {string} period
 * @param {string} todayKey chiave del giorno per il periodo `daily`
 * @return {{familyRef: FirebaseFirestore.DocumentReference, userRef: ?FirebaseFirestore.DocumentReference}}
 */
function aiUsageRefs(db, familyId, uid, period, todayKey) {
  const familyDoc = db.collection("ai_usage").doc(`family_${familyId}`);
  if (period === "trial") {
    return {familyRef: familyDoc.collection("lifetime").doc("trial"), userRef: null};
  }
  if (period === "lifetime") {
    return {
      familyRef: familyDoc.collection("lifetime").doc("free"),
      userRef: uid ? db.collection("ai_usage").doc(`user_${uid}`).collection("lifetime").doc("free") : null,
    };
  }
  return {familyRef: familyDoc.collection("daily").doc(todayKey), userRef: null};
}

module.exports = {
  DEFAULTS,
  DAY_MS,
  REQUEST_COOLDOWN_MS,
  loadTrialConfig,
  trialAIQuota,
  trialEligibility,
  trialRequestRef,
  grantTrial,
  aiUsageRefs,
  _resetCacheForTests: () => {
    cache = {at: 0, cfg: null};
  },
};
