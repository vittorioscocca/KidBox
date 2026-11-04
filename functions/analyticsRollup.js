// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS — rollup giornalieri
//
// Design: internal/analytics-active-users.md
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
 * Uid degli account di test dello sviluppatore (`config/internalUsers.uids`),
 * esclusi da ogni conteggio: con qualche decina di utenti attivi al giorno,
 * un pomeriggio di prove vale una settimana di utenti veri. Lo stesso elenco
 * lo usano `scripts/console-daily-report.js` (Auth) e, via hash delle email,
 * i client per marcare `traffic_type=internal` su GA4.
 * Documento assente o illeggibile = nessuna esclusione, il rollup non si ferma.
 * @return {Promise<Set<string>>}
 */
async function internalUids() {
  try {
    const snap = await admin.firestore()
        .collection("config").doc("internalUsers").get();
    const uids = (snap.exists && snap.data().uids) || [];
    const clean = Array.isArray(uids) ?
      uids.filter((u) => typeof u === "string") : [];
    return new Set(clean);
  } catch (e) {
    logger.warn("analyticsRollup: config/internalUsers non leggibile", {
      error: e.message,
    });
    return new Set();
  }
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

  const [snap, internal] = await Promise.all([
    db.collection(EVENTS_COLLECTION)
        .where("ts", ">=", admin.firestore.Timestamp.fromDate(start))
        .where("ts", "<", admin.firestore.Timestamp.fromDate(end))
        .get(),
    internalUids(),
  ]);

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
  // Join famiglia del giorno (evento persistente, fuori dal DAU).
  let membersJoined = 0;
  const grownFamilies = new Set();
  // Coppie "familyId:uid" che hanno CREATO contenuto nel giorno. Servono al
  // funnel: una famiglia con 2 membri dove ha creato solo uno non è ancora
  // condivisa davvero. Stesso ruolo di `uids`: unire le finestre senza
  // riscansionare i grezzi, che scadono a 90gg.
  const creatorPairs = new Set();

  let internalSkipped = 0;
  for (const doc of snap.docs) {
    const e = doc.data();
    const props = e.props || {};

    if (e.uid && internal.has(e.uid)) {
      internalSkipped += 1;
      continue;
    }

    if (e.name === "session_start") {
      if (e.uid) openedUids.add(e.uid);
      sessionsTotal += 1;
      continue;
    }
    // Evento di crescita, non di attività: entrare in una famiglia non conta
    // per il DAU, ma segnala l'intento di condivisione — chi invita ha già
    // deciso che l'app vale per la famiglia.
    if (e.name === "family_member_joined") {
      membersJoined += 1;
      if (e.familyId) grownFamilies.add(e.familyId);
      continue;
    }
    if (!VALUE_EVENTS.includes(e.name)) continue;

    if (e.uid) activeUids.add(e.uid);
    if (e.familyId) activeFamilies.add(e.familyId);
    if (e.name === "content_created" && e.uid && e.familyId) {
      creatorPairs.add(`${e.familyId}:${e.uid}`);
    }
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
    membersJoined,
    familiesGrown: grownFamilies.size,
    byFeature,
    retrievedTotal,
    crossMemberReadRate: retrievedTotal ?
      +(retrievedCrossMember / retrievedTotal).toFixed(3) : 0,
    eventsScanned: snap.size,
    // Eventi degli account di test, tolti dai conteggi qui sopra.
    internalSkipped,
    // Servono a unire le finestre rolling senza riscansionare i grezzi — che a
    // 90gg scadono. Sono la ragione per cui WAU/MAU restano calcolabili.
    uids: Array.from(activeUids),
    familyIds: Array.from(activeFamilies),
    creators: Array.from(creatorPairs),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

/**
 * Rollup dei 27 giorni precedenti (idx 0 = ieri), una sola lettura per giorno.
 * @param {string} dateStr ultimo giorno della finestra
 * @return {Promise<Array>} snapshot, anche di documenti assenti
 */
async function previousRollups(dateStr) {
  const db = admin.firestore();
  const refs = [];
  for (let i = 1; i < MAU_DAYS; i++) {
    refs.push(db.collection(METRICS_COLLECTION).doc(addDays(dateStr, -i)));
  }
  return refs.length ? db.getAll(...refs) : [];
}

/**
 * Unisce le finestre rolling leggendo i rollup già scritti.
 * @param {Object} daily rollup del giorno appena calcolato
 * @param {Array} snaps rollup precedenti (vedi previousRollups)
 * @return {Object} wau/mau/waf/maf
 */
function buildWindows(daily, snaps) {
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
 * Funnel delle famiglie: foto del momento in cui gira, non del giorno scelto.
 * Una famiglia è «condivisa davvero» quando ha 2+ membri E almeno 2 membri
 * diversi hanno creato contenuto negli ultimi 28 giorni. Gli account di test
 * non contano come membri. Costo: una lettura per famiglia e per membro,
 * perciò si calcola solo per l'ultimo giorno di un giro, non a ogni backfill.
 * `creatorDays` dice quanti giorni della finestra hanno il dato `creators`:
 * prima del primo rollup nuovo lo zero è «non misurato», non «nessuno crea».
 * @param {Object} daily rollup del giorno
 * @param {Array} snaps rollup precedenti
 * @param {Set<string>} internal uid di test
 * @return {Promise<Object>} funnel
 */
async function buildFamilyFunnel(daily, snaps, internal) {
  const db = admin.firestore();
  const [famSnap, memSnap] = await Promise.all([
    db.collection("families").select().get(),
    db.collectionGroup("members").select().get(),
  ]);

  // familyId → [{uid, joined}] ; createTime del documento membro = ingresso.
  const members = new Map();
  for (const m of memSnap.docs) {
    const fam = m.ref.parent.parent;
    if (!fam || fam.parent.id !== "families") continue;
    if (internal.has(m.id)) continue;
    if (!members.has(fam.id)) members.set(fam.id, []);
    members.get(fam.id).push({uid: m.id, joined: m.createTime.toMillis()});
  }

  const creators = new Map(); // familyId → Set<uid>
  let creatorDays = 0;
  const addPairs = (pairs) => {
    for (const p of pairs || []) {
      const i = p.indexOf(":");
      const f = p.slice(0, i);
      if (!creators.has(f)) creators.set(f, new Set());
      creators.get(f).add(p.slice(i + 1));
    }
  };
  if (daily.creators) creatorDays += 1;
  addPairs(daily.creators);
  for (const snap of snaps) {
    if (!snap.exists || !snap.data().creators) continue;
    creatorDays += 1;
    addPairs(snap.data().creators);
  }

  const out = {
    families: 0, withMembers: 0, multi: 0,
    multiCreators0: 0, multiCreators1: 0, multiCreators2: 0,
    toSecond: {sameDay: 0, within7d: 0, over7d: 0}, medianDaysToSecond: null,
    creatorDays, computedAt: new Date().toISOString(),
  };
  const gaps = [];
  for (const f of famSnap.docs) {
    // ZZZ-TEST-…: prove lato server, con membri finti che non sono account
    // di test e quindi non escono dal filtro `internal`.
    if (f.id.startsWith("ZZZ-TEST")) continue;
    const list = members.get(f.id) || [];
    out.families += 1;
    if (list.length >= 1) out.withMembers += 1;
    if (list.length < 2) continue;
    out.multi += 1;
    const uids = new Set(list.map((m) => m.uid));
    let n = 0;
    for (const u of creators.get(f.id) || []) if (uids.has(u)) n += 1;
    out[`multiCreators${Math.min(n, 2)}`] += 1;

    const joined = list.map((m) => m.joined).sort((a, b) => a - b);
    const days = (joined[1] - joined[0]) / 86400000;
    gaps.push(days);
    if (days < 1) out.toSecond.sameDay += 1;
    else if (days <= 7) out.toSecond.within7d += 1;
    else out.toSecond.over7d += 1;
  }
  if (gaps.length) {
    gaps.sort((a, b) => a - b);
    const mid = Math.floor(gaps.length / 2);
    const med = gaps.length % 2 ? gaps[mid] : (gaps[mid - 1] + gaps[mid]) / 2;
    out.medianDaysToSecond = +med.toFixed(1);
  }
  return out;
}

/**
 * Calcola e scrive il rollup di un giorno.
 * @param {string} dateStr giorno locale "YYYY-MM-DD"
 * @param {{funnel: ?boolean}} [opts] funnel: calcola anche il funnel famiglie
 * @return {Promise<Object>} il rollup scritto
 */
async function rollupDay(dateStr, opts = {}) {
  const daily = await buildDaily(dateStr);
  const snaps = await previousRollups(dateStr);
  const windows = buildWindows(daily, snaps);
  const out = {...daily, ...windows};
  if (opts.funnel) {
    try {
      out.funnel = await buildFamilyFunnel(daily, snaps, await internalUids());
    } catch (e) {
      logger.error("analyticsRollup: funnel famiglie fallito", {
        error: e.message,
      });
    }
  }

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
      maxInstances: 1,
    },
    async () => {
      const yesterday = addDays(localDateStr(new Date()), -1);
      await rollupDay(yesterday, {funnel: true});
    },
);

// Esecuzione manuale: ricalcola uno o più giorni senza aspettare le 03:15.
// Serve per il primo giorno, per i backfill dopo un cambio di definizione, e
// per vedere i numeri di oggi dalla console. Idempotente: riscrive il doc.
exports.runAnalyticsRollup = onCall(
    {region: REGION, invoker: "public", maxInstances: 1},
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
        const out = await rollupDay(d, {funnel: i === 0});
        results.push({date: d, dau: out.dau, daf: out.daf, wau: out.wau,
          mau: out.mau, eventsScanned: out.eventsScanned});
      }
      return {ok: true, days: results};
    },
);

module.exports.rollupDay = rollupDay;
module.exports.buildFamilyFunnel = buildFamilyFunnel;
module.exports.addDays = addDays;
module.exports.localDateStr = localDateStr;
module.exports.localMidnight = localMidnight;
