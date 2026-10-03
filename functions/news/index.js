/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// NOTIZIE PER LA FAMIGLIA (Pro e Max)
//
// Ogni giorno, per chi apre la scheda Notizie:
//   - un'EDIZIONE NAZIONALE (paese + lingua): bonus, economia, scuola, salute,
//     crescita, società e tempo libero su scala nazionale;
//   - un'EDIZIONE LOCALE (paese + regione + città + lingua): notizie di regione
//     e comune ed eventi entro ~60 km, rigenerata ogni `localRefreshDays`;
//   - su richiesta, OFFERTE SU MISURA dalle bollette e dalla spesa, che il
//     telefono riassume (senza nomi, indirizzi né codici) e che qui non si salva.
// Le notizie le trova Claude con la ricerca web; ogni voce passa dal setaccio
// di `prompts.js` (URL fra i risultati veri, date, doppioni).
//
// Le edizioni sono CONDIVISE: tutte le famiglie della stessa città, nella
// stessa lingua, leggono la stessa. Si generano in coda (`news_jobs` →
// `buildNewsEdition`), non dentro la callable: una generazione dura 40-100 s e
// una richiesta mobile così lunga cade a ogni cambio di rete. Il client mostra
// quello che c'è e richiama finché lo stato non è «ready».
//
// IL COSTO SI PAGA IN MESSAGGI AI (richiesta dell'utente del 03/10/2026): il
// costo vero in dollari di ogni generazione, ricerche comprese, diventa
// messaggi al cambio `usdPerMessage` (0,02 $: un messaggio pieno, 50.000
// caratteri ad Haiku più la risposta) e si scala dalla quota della famiglia con
// lo stesso contatore dell'assistente. Un'edizione condivisa costa a ogni
// famiglia la sua parte: costo ÷ famiglie che hanno letto le edizioni di quella
// zona negli ultimi giorni (almeno 1), fissato quando l'edizione nasce. Ogni
// famiglia paga un'edizione una volta sola (`news_charges`), anche se la
// rileggono più membri o la stessa edizione locale vale due giorni. La parte di
// ciascuno ha un tetto (`maxUnitsPerEdition`, 6): con pochi lettori sarebbe
// quasi tutto il costo, e il primo giorno si mangerebbe la quota di un Pro.
//
// Collezioni, tutte solo-server (le rules non le aprono):
//   news_editions/{scopeKey}_{dateKey}  stato e contenuto di un'edizione
//   news_jobs/{editionId}_{n}           richiesta di generazione (trigger)
//   news_charges/{familyId}_{editionId} addebito di un'edizione a una famiglia
//   news_personal/{uid}                 le ultime offerte su misura dell'utente
//   news_usage/{dateKey}                spesa del giorno, per il tetto globale
// Disegno e numeri in internal/notizie.md.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const P = require("./prompts");
const {searchWithClaude, estimateCostUsd, MODEL_SONNET} = require("./search");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const REGION = "europe-west1";

const EDITIONS = "news_editions";
const JOBS = "news_jobs";
const CHARGES = "news_charges";
const PERSONAL = "news_personal";
const USAGE = "news_usage";

const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Notizie e eventi mostrati in un'edizione composta. «Se non ci sono notizie il numero cala.» */
const MAX_NEWS = 10;
const MAX_EVENTS = 6;
const MAX_OFFERS = 4;
/** Quante notizie chiedere al modello per edizione (il setaccio ne scarta qualcuna). */
const COUNTRY_MAX_ITEMS = 12;
const LOCAL_MAX_ITEMS = 8;
const LOCAL_MAX_EVENTS = 8;
/** Un'edizione «in preparazione» da più di così si considera persa e si rimette in coda. */
const STALE_MS = 9 * 60 * 1000;
/** Tentativi per edizione al giorno, poi si resta sull'ultima pronta. */
const MAX_ATTEMPTS = 3;
/** Fra un fallimento e il tentativo successivo. */
const RETRY_AFTER_MS = 5 * 60 * 1000;
/** Le offerte su misura non si rifanno più spesso di così (doppio tocco, due dispositivi). */
const OFFERS_MIN_INTERVAL_MS = 6 * 60 * 60 * 1000;
/** Quanto si guarda indietro per i titoli già usciti e per stimare i lettori. */
const HISTORY_DAYS = 10;

const DEFAULTS = {
  enabled: true,
  /** Dollari per messaggio AI: il cambio fra il costo vero e la quota della famiglia. */
  usdPerMessage: 0.02,
  /** Tetto di spesa globale al giorno per le generazioni: oltre, si servono le ultime edizioni pronte. */
  dailyBudgetUsd: 5,
  /** Giorni di vita di un'edizione locale: notizie di città ed eventi a 14 giorni cambiano piano. */
  localRefreshDays: 2,
  /** Effort e ricerche di CIASCUNO dei due gruppi dell'edizione nazionale (girano in parallelo). */
  countryEffort: "medium",
  countryMaxUses: 7,
  localEffort: "medium",
  localMaxUses: 10,
  offersEffort: "medium",
  offersMaxUses: 6,
  /** Stima del costo delle offerte su misura, prenotata prima di generarle e poi conguagliata. */
  offersEstimateUsd: 0.16,
  /**
   * Tetto per edizione, in messaggi. Con pochi lettori la parte di ciascuno è
   * quasi tutto il costo (18 messaggi per la nazionale, misurato il
   * 03/10/2026): senza tetto, il primo giorno le Notizie si mangerebbero la
   * quota di un Pro. Sopra il tetto il costo resta a KidBox.
   */
  maxUnitsPerEdition: 6,
  maxUnitsOffers: 8,
  /** Stima di un'edizione mai vista, per il messaggio «costa circa N messaggi». */
  editionEstimateUsd: 0.25,
};
const BOUNDS = {
  usdPerMessage: [0.002, 0.5],
  dailyBudgetUsd: [0, 200],
  localRefreshDays: [1, 7],
  countryMaxUses: [2, 20],
  localMaxUses: [2, 20],
  offersMaxUses: [2, 10],
  offersEstimateUsd: [0.01, 2],
  editionEstimateUsd: [0.01, 2],
  maxUnitsPerEdition: [1, 100],
  maxUnitsOffers: [1, 100],
};
const EFFORTS = ["low", "medium", "high"];
const CONFIG_TTL_MS = 60 * 1000;
let configCache = {at: 0, cfg: null};

/**
 * Parametri da `config/news`, con i default come rete di sicurezza: il
 * documento non serve per partire, serve per cambiare cambio, tetto e
 * frequenze senza deploy.
 * @return {Promise<typeof DEFAULTS>}
 */
async function loadNewsConfig() {
  const now = Date.now();
  if (configCache.cfg && now - configCache.at < CONFIG_TTL_MS) return configCache.cfg;
  const cfg = {...DEFAULTS};
  try {
    const snap = await admin.firestore().collection("config").doc("news").get();
    const d = snap.exists ? snap.data() || {} : {};
    if (d.enabled === false) cfg.enabled = false;
    for (const [key, [min, max]] of Object.entries(BOUNDS)) {
      const n = Number(d[key]);
      if (d[key] !== undefined && Number.isFinite(n)) cfg[key] = Math.min(max, Math.max(min, n));
    }
    for (const key of ["countryEffort", "localEffort", "offersEffort"]) {
      if (EFFORTS.includes(d[key])) cfg[key] = d[key];
    }
    cfg.localRefreshDays = Math.round(cfg.localRefreshDays);
    cfg.maxUnitsPerEdition = Math.round(cfg.maxUnitsPerEdition);
    cfg.maxUnitsOffers = Math.round(cfg.maxUnitsOffers);
  } catch (e) {
    logger.warn("news: lettura config/news fallita, uso i default", {error: e.message});
  }
  configCache = {at: now, cfg};
  return cfg;
}

// ── Lettura della richiesta ──────────────────────────────────────────────────

/**
 * Testo dell'utente pulito: niente caratteri di controllo, niente a capo.
 * @param {*} v
 * @param {number} max
 * @return {string}
 */
function cleanText(v, max) {
  if (typeof v !== "string") return "";
  // eslint-disable-next-line no-control-regex -- i caratteri di controllo sono proprio quelli da togliere
  return v.replace(/[\u0000-\u001f\u007f<>{}]+/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

/**
 * Il luogo scelto nelle impostazioni. Il paese basta per l'edizione
 * nazionale; senza città non c'è edizione locale.
 * @param {*} raw
 * @return {?{countryCode: string, country: string, region: string, province: string, city: string}}
 */
function parsePlace(raw) {
  if (!raw || typeof raw !== "object") return null;
  const countryCode = typeof raw.countryCode === "string" ? raw.countryCode.trim().toUpperCase() : "";
  if (!/^[A-Z]{2}$/.test(countryCode)) return null;
  const place = {
    countryCode,
    country: cleanText(raw.country, 60) || countryCode,
    region: cleanText(raw.region, 60),
    province: cleanText(raw.province, 60),
    city: cleanText(raw.city, 60),
  };
  // Senza regione la città resta ambigua (Paris, Texas): la si usa lo stesso,
  // ma il nome della regione nel prompt è la provincia o il paese.
  if (!place.region) place.region = place.province || place.country;
  return place;
}

/**
 * @param {*} raw
 * @return {string[]}
 */
function parseCategories(raw) {
  if (!Array.isArray(raw)) return [...P.CATEGORIES];
  const set = new Set(raw.filter((c) => P.CATEGORIES.includes(c)));
  return set.size ? P.CATEGORIES.filter((c) => set.has(c)) : [...P.CATEGORIES];
}

/**
 * @param {*} raw
 * @return {string}
 */
function parseLang(raw) {
  const l = typeof raw === "string" ? raw.slice(0, 2).toLowerCase() : "";
  return P.LANGUAGES[l] ? l : "it";
}

/**
 * Un fuso IANA vero, altrimenti quello di Roma.
 * @param {*} raw
 * @return {string}
 */
function parseTimeZone(raw) {
  if (typeof raw !== "string" || raw.length > 64) return "Europe/Rome";
  try {
    new Intl.DateTimeFormat("en", {timeZone: raw});
    return raw;
  } catch (_) {
    return "Europe/Rome";
  }
}

/**
 * Pezzo di chiave da un nome di luogo: senza accenti, minuscolo, a trattini.
 * @param {string} s
 * @return {string}
 */
function slug(s) {
  return String(s || "")
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
      .slice(0, 40) || "x";
}

/**
 * Le due edizioni che servono a questo luogo e a questa lingua.
 * @param {object} place
 * @param {string} lang
 * @param {string} timeZone
 * @return {{kind: string, key: string, place: object, lang: string, timeZone: string}[]}
 */
function scopesFor(place, lang, timeZone) {
  const scopes = [{
    kind: "country",
    key: `c-${place.countryCode}-${lang}`,
    place: {countryCode: place.countryCode, country: place.country},
    lang,
    timeZone,
  }];
  if (place.city) {
    scopes.push({
      kind: "local",
      key: `l-${place.countryCode}-${slug(place.region)}-${slug(place.city)}-${lang}`,
      place,
      lang,
      timeZone,
    });
  }
  return scopes;
}

/**
 * Il riassunto di bollette e spesa mandato dal telefono, ripulito e limitato.
 * @param {*} raw
 * @return {{bills: object[], grocery: string[]}}
 */
function parseBrief(raw) {
  const BILL_TYPES = ["luce", "gas", "acqua", "internet", "telefono"];
  const bills = [];
  for (const b of Array.isArray(raw?.bills) ? raw.bills.slice(0, 6) : []) {
    const type = typeof b?.type === "string" ? b.type.toLowerCase() : "";
    if (!BILL_TYPES.includes(type)) continue;
    const amount = Number(b.amountEur);
    const period = Number(b.periodMonths);
    bills.push({
      type,
      supplier: cleanText(b.supplier, 40) || null,
      amountEur: Number.isFinite(amount) && amount > 0 && amount < 10000 ? Math.round(amount * 100) / 100 : null,
      periodMonths: [1, 2, 3, 4, 6, 12].includes(period) ? period : null,
      contractEnd: typeof b.contractEnd === "string" && /^\d{4}-\d{2}-\d{2}$/.test(b.contractEnd) ? b.contractEnd : null,
      excerpt: cleanText(b.excerpt, 600) || null,
    });
  }
  const grocery = [];
  for (const g of Array.isArray(raw?.grocery) ? raw.grocery.slice(0, 40) : []) {
    const name = cleanText(g, 40);
    if (name && !grocery.includes(name)) grocery.push(name);
    if (grocery.length >= 30) break;
  }
  return {bills, grocery};
}

/**
 * Giorno YYYY-MM-DD spostato di n giorni.
 * @param {string} dateKey
 * @param {number} n
 * @return {string}
 */
function shiftDay(dateKey, n) {
  const d = new Date(`${dateKey}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/**
 * Messaggi AI per un costo in dollari: almeno uno, arrotondati, al massimo `cap`.
 * @param {number} usd
 * @param {typeof DEFAULTS} cfg
 * @param {number} [cap]
 * @return {number}
 */
function unitsFor(usd, cfg, cap = Infinity) {
  return Math.min(cap, Math.max(1, Math.round((Number(usd) || 0) / cfg.usdPerMessage)));
}

/**
 * Millisecondi da un Timestamp Firestore, o null.
 * @param {*} t
 * @return {?number}
 */
function millis(t) {
  return t && typeof t.toMillis === "function" ? t.toMillis() : null;
}

// ── Il modulo ────────────────────────────────────────────────────────────────

/**
 * Costruisce le function con gli helper di `index.js` (appartenenza, quota,
 * contatore AI), così quota e piano hanno una copia sola.
 * @param {{assertFamilyMember: Function, resolveAIQuota: Function, checkAndIncrementAIUsage: Function, refundAIUsage: Function}} deps
 * @return {object}
 */
function build(deps) {
  const db = () => admin.firestore();

  /**
   * Il cancello comune alle due callable: login, famiglia, piano, interruttore.
   * Il piano si legge dalla quota: `lifetime` è il Free, e il Free non ha le
   * Notizie (trappola di /gating-pro: `isAIAccessible` non è il piano).
   * @param {object} request
   * @return {Promise<{uid: string, familyId: string, quota: object, cfg: typeof DEFAULTS}>}
   */
  async function gate(request) {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
    const familyId = typeof request.data?.familyId === "string" ? request.data.familyId : "";
    if (!ID_RE.test(familyId)) throw new HttpsError("invalid-argument", "familyId non valido.");
    const cfg = await loadNewsConfig();
    if (!cfg.enabled) {
      throw new HttpsError("failed-precondition", "Le notizie sono sospese.", {reason: "news-disabled"});
    }
    await deps.assertFamilyMember(uid, familyId);
    const quota = await deps.resolveAIQuota(uid, familyId);
    if (quota.period === "lifetime") {
      throw new HttpsError(
          "permission-denied",
          "Le Notizie sono incluse nei piani Pro e Max. Passa a Pro per riceverle.",
          {reason: "plan"},
      );
    }
    return {uid, familyId, quota, cfg};
  }

  /**
   * Quanto si è speso oggi in generazioni, contro il tetto.
   * @param {string} dateKey
   * @param {typeof DEFAULTS} cfg
   * @return {Promise<boolean>}
   */
  async function overBudget(dateKey, cfg) {
    const snap = await db().collection(USAGE).doc(dateKey).get();
    return (snap.get("costUsd") || 0) >= cfg.dailyBudgetUsd;
  }

  /**
   * Somma una generazione alla spesa del giorno e ai costi AI del mese (la
   * console li legge da lì, insieme a quelli dell'assistente).
   * @param {string} dateKey
   * @param {string} kind
   * @param {number} costUsd
   * @param {number} searches
   * @return {Promise<void>}
   */
  async function recordSpend(dateKey, kind, costUsd, searches) {
    const inc = admin.firestore.FieldValue.increment;
    const monthKey = new Date().toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"}).slice(0, 7);
    await Promise.all([
      db().collection(USAGE).doc(dateKey).set({
        costUsd: inc(costUsd),
        searches: inc(searches),
        generations: inc(1),
        // Mappa annidata e non «byKind.x»: con set+merge il punto crea un campo
        // che si chiama davvero «byKind.x» (la trappola del contatore storage).
        byKind: {[kind]: inc(costUsd)},
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}),
      db().collection("ai_costs").doc(monthKey).set({
        calls: inc(1),
        costUsd: inc(costUsd),
        newsCostUsd: inc(costUsd),
        newsSearches: inc(searches),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]).catch((e) => logger.warn("news: registrazione spesa fallita", {error: e.message}));
  }

  /**
   * Le edizioni pronte della stessa zona nei giorni prima di `dateKey`.
   * @param {string} scopeKey
   * @param {string} dateKey
   * @param {number} days
   * @return {Promise<object[]>} dalla più recente
   */
  async function previousEditions(scopeKey, dateKey, days) {
    const refs = [];
    for (let n = 1; n <= days; n++) refs.push(db().collection(EDITIONS).doc(`${scopeKey}_${shiftDay(dateKey, -n)}`));
    const snaps = await db().getAll(...refs);
    return snaps.filter((s) => s.exists && s.get("status") === "ready").map((s) => ({id: s.id, ...s.data()}));
  }

  /**
   * Mette in coda l'edizione di oggi per una zona, se non c'è già. Edizione e
   * richiesta nascono nella stessa transazione: la generazione parte dal
   * trigger su `news_jobs`, mai dalla callable.
   * @param {object} scope
   * @param {{dateKey: string, label: string}} today
   * @param {string} reason
   * @return {Promise<boolean>} true se l'ha messa in coda questa chiamata
   */
  async function queueEdition(scope, today, reason) {
    const editionId = `${scope.key}_${today.dateKey}`;
    const ref = db().collection(EDITIONS).doc(editionId);
    return db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const status = snap.exists ? snap.get("status") : null;
      const attempts = snap.exists ? snap.get("attempts") || 0 : 0;
      if (status === "ready") return false;
      if (status === "queued" || status === "generating") {
        const since = millis(snap.get(status === "queued" ? "queuedAt" : "startedAt")) || 0;
        if (Date.now() - since < STALE_MS) return false;
      }
      if (status === "failed") {
        if (attempts >= MAX_ATTEMPTS) return false;
        if (Date.now() - (millis(snap.get("failedAt")) || 0) < RETRY_AFTER_MS) return false;
      }
      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.set(ref, {
        status: "queued",
        queuedAt: now,
        scope: scope.kind,
        scopeKey: scope.key,
        dateKey: today.dateKey,
        dateLabel: today.label,
        lang: scope.lang,
        timeZone: scope.timeZone,
        place: scope.place,
        attempts,
        readers: snap.exists ? snap.get("readers") || 0 : 0,
        expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + 120 * DAY_MS),
      }, {merge: true});
      tx.set(db().collection(JOBS).doc(`${editionId}_${attempts + 1}`), {
        editionId,
        reason,
        createdAt: now,
        expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + 7 * DAY_MS),
      });
      return true;
    });
  }

  /**
   * L'edizione da mostrare oggi per una zona: la più recente ancora valida, o
   * una messa in coda adesso.
   * @param {object} scope
   * @param {{dateKey: string, label: string}} today
   * @param {typeof DEFAULTS} cfg
   * @return {Promise<{status: "ready"|"preparing"|"missing", edition?: object, stale?: boolean, reason?: string}>}
   */
  async function resolveEdition(scope, today, cfg) {
    const days = scope.kind === "country" ? 1 : Math.max(1, cfg.localRefreshDays);
    const refs = [];
    for (let n = 0; n < days; n++) refs.push(db().collection(EDITIONS).doc(`${scope.key}_${shiftDay(today.dateKey, -n)}`));
    const snaps = await db().getAll(...refs);
    const ready = snaps.find((s) => s.exists && s.get("status") === "ready");
    if (ready) return {status: "ready", edition: {id: ready.id, ...ready.data()}};

    if (await overBudget(today.dateKey, cfg)) {
      // Oltre il tetto non si genera: si serve l'ultima edizione pronta, se c'è.
      const prev = await previousEditions(scope.key, today.dateKey, 7);
      logger.warn("news: tetto di spesa del giorno raggiunto", {scope: scope.key, dateKey: today.dateKey});
      return prev.length ? {status: "ready", edition: prev[0], stale: true, reason: "budget"} : {status: "missing", reason: "budget"};
    }

    await queueEdition(scope, today, "request");
    const todaySnap = await refs[0].get();
    const status = todaySnap.get("status");
    if (status === "queued" || status === "generating") return {status: "preparing"};
    // Tentativi finiti per oggi: resta l'ultima edizione pronta.
    const prev = await previousEditions(scope.key, today.dateKey, 7);
    return prev.length ? {status: "ready", edition: prev[0], stale: true, reason: "failed"} : {status: "missing", reason: "failed"};
  }

  /**
   * Scala dalla quota AI della famiglia le edizioni che non ha ancora pagato.
   * Prima la prenotazione (`create` fallisce se un altro dispositivo della
   * famiglia l'ha appena fatta), poi il contatore: se la quota non basta le
   * prenotazioni si tolgono e l'errore arriva al client con i numeri.
   * @param {string} uid
   * @param {string} familyId
   * @param {object} quota
   * @param {object[]} editions
   * @param {typeof DEFAULTS} cfg
   * @return {Promise<{chargedUnits: number, totalUnits: number}>}
   */
  async function chargeEditions(uid, familyId, quota, editions, cfg) {
    if (editions.length === 0) return {chargedUnits: 0, totalUnits: 0};
    const refs = editions.map((e) => db().collection(CHARGES).doc(`${familyId}_${e.id}`));
    const snaps = await db().getAll(...refs);
    let totalUnits = 0;
    const toPay = [];
    editions.forEach((e, i) => {
      if (snaps[i].exists) totalUnits += snaps[i].get("units") || 0;
      else toPay.push({edition: e, ref: refs[i], units: unitsFor(e.priceUsd, cfg, cfg.maxUnitsPerEdition)});
    });
    const claimed = [];
    for (const t of toPay) {
      try {
        await t.ref.create({
          familyId,
          editionId: t.edition.id,
          units: t.units,
          priceUsd: t.edition.priceUsd || 0,
          status: "pending",
          uid,
          at: admin.firestore.FieldValue.serverTimestamp(),
          expireAt: admin.firestore.Timestamp.fromMillis(Date.now() + 40 * DAY_MS),
        });
        claimed.push(t);
      } catch (e) {
        // 6 = ALREADY_EXISTS: l'ha pagata un'altra richiesta della famiglia.
        if (e.code === 6) totalUnits += t.units;
        else throw e;
      }
    }
    const units = claimed.reduce((s, t) => s + t.units, 0);
    if (units > 0) {
      try {
        await deps.checkAndIncrementAIUsage(familyId, uid, quota, units);
      } catch (e) {
        await Promise.all(claimed.map((t) => t.ref.delete().catch(() => {})));
        if (e instanceof HttpsError && e.code === "resource-exhausted") {
          throw new HttpsError("resource-exhausted", e.message, {...(e.details || {}), reason: e.details?.reason || "daily-limit", news: true, units});
        }
        throw e;
      }
      const batch = db().batch();
      const now = admin.firestore.FieldValue.serverTimestamp();
      for (const t of claimed) {
        batch.update(t.ref, {status: "paid"});
        batch.update(db().collection(EDITIONS).doc(t.edition.id), {
          readers: admin.firestore.FieldValue.increment(1),
          lastReadAt: now,
        });
      }
      await batch.commit().catch((e) => logger.warn("news: aggiornamento lettori fallito", {error: e.message}));
    }
    return {chargedUnits: units, totalUnits: totalUnits + units};
  }

  /**
   * Le notizie da mostrare a questo utente: le sue categorie, prima il paese,
   * poi la regione, poi la città; al massimo MAX_NEWS, con spazio garantito al
   * locale quando c'è.
   * @param {?object} countryEd
   * @param {?object} localEd
   * @param {string[]} categories
   * @param {string} todayKey
   * @return {{items: object[], events: object[]}}
   */
  function compose(countryEd, localEd, categories, todayKey) {
    const want = new Set(categories);
    const stillValid = (i) => !i.keyDate || P.daysBetween(todayKey, i.keyDate) >= 0;
    const country = (countryEd?.items || []).filter((i) => want.has(i.category));
    const local = (localEd?.items || []).filter((i) => want.has(i.category));
    let localQuota = Math.min(local.length, Math.ceil(MAX_NEWS / 2));
    const countryQuota = Math.min(country.length, MAX_NEWS - localQuota);
    localQuota = Math.min(local.length, MAX_NEWS - countryQuota);
    const pickedLocal = local.slice(0, localQuota);
    const items = [
      ...country.slice(0, countryQuota),
      ...pickedLocal.filter((i) => i.level === "region"),
      ...pickedLocal.filter((i) => i.level === "city"),
    ].map((i) => (stillValid(i) ? i : {...i, keyDate: null, keyDateKind: null}));
    const events = want.has("leisure") ?
      (localEd?.events || []).filter((e) => P.daysBetween(todayKey, e.endDate || e.startDate) >= 0).slice(0, MAX_EVENTS) :
      [];
    return {items, events};
  }

  /**
   * Le offerte salvate dell'utente, nella forma della risposta.
   * @param {string} uid
   * @return {Promise<?object>}
   */
  async function savedOffers(uid) {
    const snap = await db().collection(PERSONAL).doc(uid).get();
    if (!snap.exists) return null;
    return {
      offers: snap.get("offers") || [],
      generatedAt: millis(snap.get("generatedAt")),
      units: snap.get("units") || 0,
      lang: snap.get("lang") || null,
    };
  }

  // ── getFamilyNews ──────────────────────────────────────────────────────────

  const getFamilyNews = onCall(
      {region: REGION, maxInstances: 20, invoker: "public", timeoutSeconds: 60},
      async (request) => {
        const {uid, familyId, quota, cfg} = await gate(request);
        const d = request.data || {};
        const place = parsePlace(d.place);
        if (!place) throw new HttpsError("invalid-argument", "Manca il paese.", {reason: "no-place"});
        const lang = parseLang(d.lang);
        const timeZone = parseTimeZone(d.timeZone);
        const categories = parseCategories(d.categories);
        const today = P.todayInfo(timeZone);

        const scopes = scopesFor(place, lang, timeZone);
        const resolved = await Promise.all(scopes.map((s) => resolveEdition(s, today, cfg)));
        const byKind = {};
        scopes.forEach((s, i) => {
          byKind[s.kind] = resolved[i];
        });
        const readyEditions = resolved.filter((r) => r.status === "ready").map((r) => r.edition);
        const charge = await chargeEditions(uid, familyId, quota, readyEditions, cfg);

        const {items, events} = compose(byKind.country?.edition, byKind.local?.edition, categories, today.dateKey);
        const offers = await savedOffers(uid);
        const pending = scopes.filter((s, i) => resolved[i].status === "preparing").map((s) => s.kind);

        logger.info("getFamilyNews", {
          uid, familyId, place: place.city || place.countryCode, lang, pending,
          charged: charge.chargedUnits, items: items.length, events: events.length,
        });
        const editionInfo = (r) => (r ? {
          status: r.status,
          generatedAt: r.edition ? millis(r.edition.generatedAt) : null,
          stale: r.stale === true,
          reason: r.reason || null,
        } : null);
        return {
          status: pending.length ? "preparing" : "ready",
          pending,
          dateKey: today.dateKey,
          place: {city: place.city || null, region: place.city ? place.region : null, country: place.country},
          items,
          events,
          offers: offers && offers.lang === lang ? offers : null,
          editions: {country: editionInfo(byKind.country), local: editionInfo(byKind.local)},
          charge: {units: charge.chargedUnits, totalUnits: charge.totalUnits},
          maxUnitsPerEdition: cfg.maxUnitsPerEdition,
        };
      },
  );

  // ── buildNewsEdition (trigger) ─────────────────────────────────────────────

  /**
   * Genera un'edizione: prompt, ricerca, setaccio, doppioni dei giorni prima,
   * costo e prezzo per famiglia.
   * @param {object} ed il documento dell'edizione in coda
   * @param {typeof DEFAULTS} cfg
   * @return {Promise<object>} i campi da scrivere sull'edizione pronta
   */
  async function generateEdition(ed, cfg) {
    const history = await previousEditions(ed.scopeKey, ed.dateKey, HISTORY_DAYS);
    const already = [];
    const seen = new Set();
    for (const h of history) {
      for (const it of h.items || []) {
        if (already.length < 60) already.push(it.title);
        seen.add(P.normalizeUrl(it.url));
      }
    }
    const isCountry = ed.scope === "country";
    const place = ed.place || {};
    const today = {dateKey: ed.dateKey, label: ed.dateLabel || ed.dateKey};
    const userLocation = {type: "approximate", country: place.countryCode, timezone: ed.timeZone || "Europe/Rome"};
    if (!isCountry) {
      userLocation.city = place.city;
      if (place.region) userLocation.region = place.region;
    }
    // Il trigger ha 540 s: le riprese dopo `pause_turn` devono starci dentro.
    const deadline = Date.now() + 480000;

    // Una ricerca: risposta, URL ammessi, costo. Le richieste dell'edizione
    // nazionale sono due, in parallelo, una per gruppo di categorie.
    const run = async (prompt, maxUses, effort) => {
      const r = await searchWithClaude({
        apiKey: ANTHROPIC_API_KEY.value(), model: MODEL_SONNET, system: prompt.system, user: prompt.user,
        maxUses, effort, userLocation, timeoutMs: 240000, deadline,
      });
      const json = r.refusal ? null : P.extractTaggedJson(P.replyText(r.blocks));
      return {r, json, allowed: P.collectSearchUrls(r.blocks), costUsd: estimateCostUsd(r.usage, r.model)};
    };
    const prompts = isCountry ?
      P.COUNTRY_GROUPS.map((categories) => P.buildCountryPrompt({
        countryCode: place.countryCode, countryName: place.country, lang: ed.lang, today, already, categories,
      })) :
      [P.buildLocalPrompt({
        countryCode: place.countryCode, countryName: place.country, region: place.region, province: place.province,
        city: place.city, lang: ed.lang, today, already, maxItems: LOCAL_MAX_ITEMS, maxEvents: LOCAL_MAX_EVENTS, withEvents: true,
      })];
    const settled = await Promise.allSettled(prompts.map((pr) => run(
        pr, isCountry ? cfg.countryMaxUses : cfg.localMaxUses, isCountry ? cfg.countryEffort : cfg.localEffort,
    )));

    const spend = {costUsd: 0, searches: 0, ms: 0, calls: 0, model: MODEL_SONNET};
    const items = [];
    let events = [];
    const dropped = [];
    const failures = [];
    const urls = new Set();
    for (const out of settled) {
      if (out.status === "rejected") {
        failures.push(out.reason?.message || String(out.reason));
        continue;
      }
      const {r, json, allowed, costUsd} = out.value;
      spend.costUsd += costUsd;
      spend.searches += r.usage.web_search_requests;
      spend.ms = Math.max(spend.ms, r.ms);
      spend.calls += r.calls;
      spend.model = r.model;
      if (!json) {
        failures.push(r.refusal ? `rifiuto (${r.refusal.category || "?"})` : `senza blocco kidbox_news (stop ${r.stopReason})`);
        continue;
      }
      const s = P.sanitizeItems(json.items, {
        allowedUrls: allowed, todayKey: ed.dateKey, forcedLevel: isCountry ? "country" : undefined,
        max: isCountry ? COUNTRY_MAX_ITEMS : LOCAL_MAX_ITEMS,
      });
      dropped.push(...s.dropped);
      for (const it of s.items) {
        const key = P.normalizeUrl(it.url);
        if (seen.has(key)) {
          dropped.push({reason: "già uscita", title: it.title});
          continue;
        }
        if (urls.has(key)) continue;
        urls.add(key);
        items.push(it);
      }
      if (!isCountry) {
        const ev = P.sanitizeEvents(json.events, {allowedUrls: allowed, todayKey: ed.dateKey, max: LOCAL_MAX_EVENTS});
        events = ev.events;
        dropped.push(...ev.dropped);
      }
    }
    // Tutte le richieste fallite: l'edizione non c'è, ma le ricerche fatte si
    // sono pagate lo stesso.
    if (failures.length === settled.length) {
      const err = new Error(failures.join(" · "));
      err.spend = spend;
      throw err;
    }

    // Le famiglie che leggono questa zona: la media delle edizioni recenti
    // lette almeno una volta. Una zona nuova parte da 1 (paga chi la apre).
    const readers = history.map((h) => h.readers || 0).filter((n) => n > 0);
    const expectedReaders = readers.length ? Math.max(1, readers.reduce((a, b) => a + b, 0) / readers.length) : 1;
    return {
      ...spend,
      items: items.slice(0, isCountry ? COUNTRY_MAX_ITEMS : LOCAL_MAX_ITEMS),
      events,
      expectedReaders: Math.round(expectedReaders * 100) / 100,
      priceUsd: spend.costUsd / expectedReaders,
      droppedCount: dropped.length,
      droppedReasons: dropped.slice(0, 20).map((x) => x.reason),
      partialFailures: failures,
    };
  }

  const buildNewsEdition = onDocumentCreated(
      {
        document: `${JOBS}/{jobId}`,
        region: REGION,
        secrets: [ANTHROPIC_API_KEY],
        timeoutSeconds: 540,
        memory: "512MiB",
        maxInstances: 10,
      },
      async (event) => {
        const job = event.data?.data() || {};
        const editionId = typeof job.editionId === "string" ? job.editionId : "";
        if (!editionId) return;
        const ref = db().collection(EDITIONS).doc(editionId);
        const ed = await db().runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          if (!snap.exists || snap.get("status") !== "queued") return null;
          tx.update(ref, {
            status: "generating",
            startedAt: admin.firestore.FieldValue.serverTimestamp(),
            attempts: admin.firestore.FieldValue.increment(1),
          });
          return snap.data();
        });
        if (!ed) return;
        const cfg = await loadNewsConfig();
        try {
          const result = await generateEdition(ed, cfg);
          await ref.update({
            ...result,
            status: "ready",
            generatedAt: admin.firestore.FieldValue.serverTimestamp(),
            error: admin.firestore.FieldValue.delete(),
          });
          await recordSpend(ed.dateKey, ed.scope, result.costUsd, result.searches);
          logger.info("news: edizione pronta", {
            editionId, items: result.items.length, events: result.events.length, costUsd: result.costUsd.toFixed(4),
            searches: result.searches, ms: result.ms, expectedReaders: result.expectedReaders, dropped: result.droppedReasons,
          });
        } catch (e) {
          logger.error("news: generazione fallita", {editionId, error: e.message});
          await ref.update({
            status: "failed",
            failedAt: admin.firestore.FieldValue.serverTimestamp(),
            error: String(e.message || e).slice(0, 300),
          }).catch(() => {});
          // Una generazione fallita dopo le ricerche le ha pagate lo stesso.
          if (e.spend) await recordSpend(ed.dateKey, ed.scope, e.spend.costUsd, e.spend.searches);
        }
      },
  );

  // ── getNewsOffers ──────────────────────────────────────────────────────────

  const getNewsOffers = onCall(
      {region: REGION, maxInstances: 20, invoker: "public", timeoutSeconds: 180, secrets: [ANTHROPIC_API_KEY]},
      async (request) => {
        const {uid, familyId, quota, cfg} = await gate(request);
        const d = request.data || {};
        const lang = parseLang(d.lang);
        const saved = await savedOffers(uid);
        const estimateUnits = unitsFor(cfg.offersEstimateUsd, cfg, cfg.maxUnitsOffers);
        if (d.refresh !== true) {
          return {status: saved ? "saved" : "none", ...(saved || {offers: []}), estimateUnits};
        }
        if (saved?.generatedAt && Date.now() - saved.generatedAt < OFFERS_MIN_INTERVAL_MS && saved.lang === lang) {
          return {status: "recent", ...saved, estimateUnits};
        }
        const place = parsePlace(d.place);
        if (!place) throw new HttpsError("invalid-argument", "Manca il paese.", {reason: "no-place"});
        const brief = parseBrief(d.brief);
        if (brief.bills.length === 0 && brief.grocery.length === 0) {
          throw new HttpsError("invalid-argument", "Niente bollette né spesa da cui partire.", {reason: "empty-brief"});
        }
        const timeZone = parseTimeZone(d.timeZone);
        const today = P.todayInfo(timeZone);
        if (await overBudget(today.dateKey, cfg)) {
          throw new HttpsError("resource-exhausted", "Le ricerche di oggi sono finite: riprova domani.", {reason: "news-budget"});
        }

        // Si prenota la stima prima di spendere (come askAI: niente generazioni
        // che la famiglia non può pagare), poi si conguaglia sul costo vero.
        await deps.checkAndIncrementAIUsage(familyId, uid, quota, estimateUnits).catch((e) => {
          if (e instanceof HttpsError && e.code === "resource-exhausted") {
            throw new HttpsError("resource-exhausted", e.message, {...(e.details || {}), news: true, units: estimateUnits});
          }
          throw e;
        });
        let r;
        try {
          const prompt = P.buildPersonalPrompt({
            countryCode: place.countryCode, countryName: place.country, region: place.city ? place.region : "",
            city: place.city, lang, today, brief, maxOffers: MAX_OFFERS,
          });
          const userLocation = {type: "approximate", country: place.countryCode, timezone: timeZone};
          if (place.city) userLocation.city = place.city;
          r = await searchWithClaude({
            apiKey: ANTHROPIC_API_KEY.value(),
            model: MODEL_SONNET,
            system: prompt.system,
            user: prompt.user,
            maxUses: cfg.offersMaxUses,
            effort: cfg.offersEffort,
            userLocation,
            timeoutMs: 150000,
            deadline: Date.now() + 160000,
          });
        } catch (e) {
          await deps.refundAIUsage(familyId, uid, quota, estimateUnits);
          logger.error("news: offerte fallite", {uid, familyId, error: e.message});
          throw new HttpsError("unavailable", "La ricerca delle offerte non è riuscita. Riprova fra poco.");
        }
        const costUsd = estimateCostUsd(r.usage, r.model);
        await recordSpend(today.dateKey, "offers", costUsd, r.usage.web_search_requests);
        const json = r.refusal ? null : P.extractTaggedJson(P.replyText(r.blocks));
        if (!json) {
          await deps.refundAIUsage(familyId, uid, quota, estimateUnits);
          logger.error("news: offerte senza blocco", {uid, stop: r.stopReason, refusal: r.refusal});
          throw new HttpsError("unavailable", "La ricerca delle offerte non è riuscita. Riprova fra poco.");
        }
        const {offers, dropped} = P.sanitizeOffers(json.offers, {allowedUrls: P.collectSearchUrls(r.blocks), max: MAX_OFFERS});

        // Conguaglio: si restituisce quanto prenotato in più, si prova a
        // scalare quanto manca (se la quota non basta più, lo si regala).
        const units = unitsFor(costUsd, cfg, cfg.maxUnitsOffers);
        if (units < estimateUnits) {
          await deps.refundAIUsage(familyId, uid, quota, estimateUnits - units);
        } else if (units > estimateUnits) {
          await deps.checkAndIncrementAIUsage(familyId, uid, quota, units - estimateUnits).catch(() => {
            logger.warn("news: conguaglio offerte non scalato", {uid, familyId, units, estimateUnits});
          });
        }
        const briefHash = crypto.createHash("sha256").update(JSON.stringify(brief)).digest("hex").slice(0, 16);
        await db().collection(PERSONAL).doc(uid).set({
          offers,
          lang,
          units,
          costUsd,
          familyId,
          briefHash,
          generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        logger.info("news: offerte pronte", {
          uid, familyId, offers: offers.length, dropped: dropped.map((x) => x.reason), costUsd: costUsd.toFixed(4),
          units, searches: r.usage.web_search_requests, ms: r.ms, bills: brief.bills.length, grocery: brief.grocery.length,
        });
        return {status: "fresh", offers, generatedAt: Date.now(), units, lang, estimateUnits};
      },
  );

  // ── prepareNewsEditions (ogni mattina) ─────────────────────────────────────

  // Le edizioni delle zone lette negli ultimi giorni si preparano all'alba,
  // così chi apre la scheda trova tutto pronto. Le zone che nessuno legge da
  // tre giorni non si preparano più: si rigenerano alla prossima apertura.
  const prepareNewsEditions = onSchedule(
      {schedule: "every day 05:30", timeZone: "Europe/Rome", region: REGION, maxInstances: 1, timeoutSeconds: 300},
      async () => {
        const cfg = await loadNewsConfig();
        if (!cfg.enabled) return;
        const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - 3 * DAY_MS);
        const snap = await db().collection(EDITIONS).where("lastReadAt", ">=", cutoff).get();
        const scopes = new Map();
        for (const doc of snap.docs) {
          const d = doc.data();
          if (!d.scopeKey || scopes.has(d.scopeKey)) continue;
          scopes.set(d.scopeKey, {kind: d.scope, key: d.scopeKey, place: d.place, lang: d.lang, timeZone: d.timeZone || "Europe/Rome"});
        }
        let queued = 0;
        for (const scope of scopes.values()) {
          const today = P.todayInfo(scope.timeZone);
          if (await overBudget(today.dateKey, cfg)) break;
          // L'edizione locale ancora valida non si rifà.
          const days = scope.kind === "country" ? 1 : Math.max(1, cfg.localRefreshDays);
          const refs = [];
          for (let n = 0; n < days; n++) refs.push(db().collection(EDITIONS).doc(`${scope.key}_${shiftDay(today.dateKey, -n)}`));
          const snaps = await db().getAll(...refs);
          if (snaps.some((s) => s.exists && s.get("status") === "ready")) continue;
          if (await queueEdition(scope, today, "morning")) queued++;
        }
        logger.info("news: edizioni del mattino in coda", {scopes: scopes.size, queued});
      },
  );

  return {getFamilyNews, getNewsOffers, buildNewsEdition, prepareNewsEditions};
}

module.exports = {build, PERSONAL, _test: {parsePlace, parseBrief, parseCategories, scopesFor, slug, unitsFor, shiftDay}};
