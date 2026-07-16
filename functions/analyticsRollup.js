// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS — rollup giornalieri
//
// Design: docs/analytics-active-users.md
//
// Ogni notte aggrega gli eventi grezzi del giorno in `metrics/{YYYY-MM-DD}`.
// La console legge SOLO questi documenti: il costo di lettura resta costante
// mentre `analyticsEvents` cresce, e i grezzi possono scadere a 90gg (TTL)
// senza perdere lo storico.
//
// Fuso: Europe/Rome per tutti. Il design chiedeva "il giorno solare nel fuso
// dell'utente", ma gli eventi non portano il fuso e il server non lo conosce.
// Per una base utenti italiana è una buona approssimazione — e comunque meglio
// di UTC, che spezzerebbe la serata a mezzanotte spostando eventi al giorno
// dopo.
// Se un giorno la base diventa multi-fuso, va aggiunto `tz` all'evento.
// ─────────────────────────────────────────────────────────────────────────────

const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// Duplicato da index.js:3729 — analyticsRollup non può richiedere index.js
// (index.js richiede questo modulo: sarebbe circolare). Tenere allineati.
const ADMIN_UIDS = ["efw85HN41nb1rmslevC3wkFpVUo1"];

const REGION = "europe-west1";
const TZ = "Europe/Rome";
const EVENTS_COLLECTION = "analyticsEvents";
const METRICS_COLLECTION = "metrics";

// Azioni di valore: definiscono l'utente attivo. `session_start` è
// deliberatamente ESCLUSO — aprire l'app non è essere attivi. Si conta a parte,
// come denominatore per sapere quanti aprono senza fare nulla.
const VALUE_EVENTS = [
  "content_created",
  "content_updated",
  "content_completed",
  "content_retrieved",
  "ai_interaction",
];

const WAU_DAYS = 7;
const MAU_DAYS = 28; // non "un mese": 28gg contengono sempre 4 weekend

/**
 * Offset del fuso, in minuti, per un dato istante.
 * @param {Date} date istante
 * @param {string} tz nome IANA del fuso
 * @return {number} minuti di offset rispetto a UTC
 */
function tzOffsetMinutes(date, tz) {
  const dtf = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const p = {};
  for (const part of dtf.formatToParts(date)) p[part.type] = part.value;
  const asUTC = Date.UTC(
      +p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  return (asUTC - date.getTime()) / 60000;
}

/**
 * Istante UTC della mezzanotte locale di una data.
 * @param {string} dateStr data "YYYY-MM-DD"
 * @return {Date} istante UTC
 */
function localMidnight(dateStr) {
  const guess = new Date(`${dateStr}T00:00:00Z`);
  return new Date(guess.getTime() - tzOffsetMinutes(guess, TZ) * 60000);
}

/**
 * Data locale "YYYY-MM-DD" di un istante.
 * @param {Date} date istante
 * @return {string} data locale
 */
function localDateStr(date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit",
  }).format(date);
}

/**
 * Somma i giorni a una data "YYYY-MM-DD".
 * @param {string} dateStr data di partenza
 * @param {number} days giorni da sommare (può essere negativo)
 * @return {string} data risultante
 */
function addDays(dateStr, days) {
  const d = new Date(`${dateStr}T12:00:00Z`); // mezzogiorno: immune alla DST
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/**
 * Aggrega gli eventi di un giorno.
 * @param {string} dateStr giorno locale "YYYY-MM-DD"
 * @return {Promise<Object>} rollup del giorno
 */
async function buildDaily(dateStr) {
  const db = admin.firestore();
  const start = localMidnight(dateStr);
  const end = localMidnight(addDays(dateStr, 1));

  const snap = await db.collection(EVENTS_COLLECTION)
      .where("ts", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("ts", "<", admin.firestore.Timestamp.fromDate(end))
      .get();

  const activeUids = new Set();
  const activeFamilies = new Set();
  // familyId → uid attivi in QUELLA famiglia. Non basta `dau / daf`: un utente
  // che appartiene a due famiglie conta 1 nel numeratore e 2 nel denominatore,
  // producendo medie impossibili (es. 0.5 membri attivi per famiglia).
  const membersByFamily = new Map();
  const openedUids = new Set(); // ha aperto l'app (session_start)
  const byFeature = {};
  let retrievedTotal = 0;
  let retrievedCrossMember = 0;
  // `sessionsTotal` e `retrievedTotal` a 0 significano "non misurato" finché il
  // logger client (fase 5) non è in produzione — non "nessuno legge". La
  // console deve poter distinguere lo zero dal non-misurato, altrimenti mostra
  // un fallimento inesistente.
  let sessionsTotal = 0;

  for (const doc of snap.docs) {
    const e = doc.data();
    const props = e.props || {};

    if (e.name === "session_start") {
      if (e.uid) openedUids.add(e.uid);
      sessionsTotal += 1;
      continue;
    }
    if (!VALUE_EVENTS.includes(e.name)) continue;

    if (e.uid) activeUids.add(e.uid);
    if (e.familyId) activeFamilies.add(e.familyId);
    if (e.uid && e.familyId) {
      if (!membersByFamily.has(e.familyId)) {
        membersByFamily.set(e.familyId, new Set());
      }
      membersByFamily.get(e.familyId).add(e.uid);
    }

    const feature = e.feature || "unknown";
    if (!byFeature[feature]) {
      byFeature[feature] = {
        created: 0, updated: 0, completed: 0, retrieved: 0, ai: 0,
      };
    }

    // `content_retrieved` arriva batchato dal client: `count` è il numero di
    // letture aggregate nella sessione, non 1.
    const validCount =
      typeof props.count === "number" && props.count > 0;
    const n = e.name === "content_retrieved" && validCount ? props.count : 1;

    if (e.name === "content_created") byFeature[feature].created += 1;
    else if (e.name === "content_updated") byFeature[feature].updated += 1;
    else if (e.name === "content_completed") byFeature[feature].completed += 1;
    else if (e.name === "ai_interaction") byFeature[feature].ai += 1;
    else if (e.name === "content_retrieved") {
      byFeature[feature].retrieved += n;
      retrievedTotal += n;
      // La metrica che prova la tesi di prodotto: leggo ciò che ha caricato un
      // altro membro, senza doverglielo chiedere.
      if (props.uploaderIsSelf === false) retrievedCrossMember += n;
    }
  }

  // Aperture senza alcuna azione di valore.
  let sessionsNoAction = 0;
  for (const uid of openedUids) if (!activeUids.has(uid)) sessionsNoAction += 1;

  // Media dei membri attivi PER famiglia, non `dau / daf`.
  let membersPerFamily = 0;
  if (membersByFamily.size) {
    let tot = 0;
    for (const uids of membersByFamily.values()) tot += uids.size;
    membersPerFamily = +(tot / membersByFamily.size).toFixed(2);
  }

  return {
    date: dateStr,
    tz: TZ,
    dau: activeUids.size,
    daf: activeFamilies.size,
    activeMembersPerActiveFamily: membersPerFamily,
    sessionsNoAction,
    sessionsTotal,
    byFeature,
    retrievedTotal,
    crossMemberReadRate: retrievedTotal ?
      +(retrievedCrossMember / retrievedTotal).toFixed(3) : 0,
    eventsScanned: snap.size,
    // Servono a unire le finestre rolling senza riscansionare i grezzi — che a
    // 90gg scadono. Sono la ragione per cui WAU/MAU restano calcolabili.
    uids: Array.from(activeUids),
    familyIds: Array.from(activeFamilies),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Unisce le finestre rolling leggendo i rollup già scritti.
 * @param {string} dateStr ultimo giorno della finestra
 * @param {Object} daily rollup del giorno appena calcolato
 * @return {Promise<Object>} wau/mau/waf/maf
 */
async function buildWindows(dateStr, daily) {
  const db = admin.firestore();
  const ids = [];
  for (let i = 1; i < MAU_DAYS; i++) ids.push(addDays(dateStr, -i));

  const refs = ids.map((d) => db.collection(METRICS_COLLECTION).doc(d));
  const snaps = refs.length ? await db.getAll(...refs) : [];

  const wauU = new Set(daily.uids);
  const wauF = new Set(daily.familyIds);
  const mauU = new Set(daily.uids);
  const mauF = new Set(daily.familyIds);

  snaps.forEach((snap, idx) => {
    if (!snap.exists) return;
    const d = snap.data();
    const inWau = idx < WAU_DAYS - 1; // idx 0 = ieri
    for (const u of d.uids || []) {
      mauU.add(u);
      if (inWau) wauU.add(u);
    }
    for (const f of d.familyIds || []) {
      mauF.add(f);
      if (inWau) wauF.add(f);
    }
  });

  return {
    wau: wauU.size, waf: wauF.size,
    mau: mauU.size, maf: mauF.size,
    // I rapporti che contano. Per KidBox un DAU/MAU basso non è un fallimento:
    // documenti e veicoli hanno cadenza mensile o annuale. Il benchmark è
    // WAU/MAU, target > 50%.
    stickinessDauMau: mauU.size ? +(daily.dau / mauU.size).toFixed(3) : 0,
    stickinessWauMau: mauU.size ? +(wauU.size / mauU.size).toFixed(3) : 0,
  };
}

/**
 * Calcola e scrive il rollup di un giorno.
 * @param {string} dateStr giorno locale "YYYY-MM-DD"
 * @return {Promise<Object>} il rollup scritto
 */
async function rollupDay(dateStr) {
  const daily = await buildDaily(dateStr);
  const windows = await buildWindows(dateStr, daily);
  const out = {...daily, ...windows};

  await admin.firestore()
      .collection(METRICS_COLLECTION).doc(dateStr)
      .set(out, {merge: true});

  logger.info("rollup scritto", {
    date: dateStr, dau: out.dau, daf: out.daf,
    wau: out.wau, mau: out.mau, eventsScanned: out.eventsScanned,
  });
  return out;
}

// 03:15 locali: dopo la mezzanotte del giorno da chiudere, con margine per gli
// eventi in coda.
exports.analyticsRollupDaily = onSchedule(
    {
      schedule: "15 3 * * *",
      timeZone: TZ,
      region: REGION,
    },
    async () => {
      const yesterday = addDays(localDateStr(new Date()), -1);
      await rollupDay(yesterday);
    },
);

// Esecuzione manuale: ricalcola uno o più giorni senza aspettare le 03:15.
// Serve per il primo giorno, per i backfill dopo un cambio di definizione, e
// per vedere i numeri di oggi dalla console. Idempotente: riscrive il doc.
exports.runAnalyticsRollup = onCall(
    {region: REGION, invoker: "public"},
    async (request) => {
      const uid = request.auth && request.auth.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Login richiesto.");
      if (!ADMIN_UIDS.includes(uid)) {
        throw new HttpsError("permission-denied", "Non autorizzato.");
      }

      const data = request.data || {};
      const days =
        Math.min(Math.max(parseInt(data.days || 1, 10), 1), MAU_DAYS);
      const from = data.date || localDateStr(new Date());

      if (!/^\d{4}-\d{2}-\d{2}$/.test(from)) {
        throw new HttpsError("invalid-argument", "date: usa YYYY-MM-DD.");
      }

      // Dal più vecchio al più recente: le finestre rolling di un giorno
      // leggono i rollup dei precedenti, che devono quindi esistere già.
      const results = [];
      for (let i = days - 1; i >= 0; i--) {
        const d = addDays(from, -i);
        const out = await rollupDay(d);
        results.push({date: d, dau: out.dau, daf: out.daf, wau: out.wau,
          mau: out.mau, eventsScanned: out.eventsScanned});
      }
      return {ok: true, days: results};
    },
);

module.exports.rollupDay = rollupDay;
module.exports.addDays = addDays;
module.exports.localDateStr = localDateStr;
module.exports.localMidnight = localMidnight;
