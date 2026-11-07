/**
 * reportSnapshotDaily — fotografa ogni mattina le fonti esterne che la
 * routine di report legge (Search Console e GA4) e le scrive su Firestore,
 * in `reportSnapshots/{fonte}_{YYYY-MM-DD}`.
 *
 * Perché: console e report leggono lo STESSO documento invece di richiamare
 * le API ognuno per conto suo, e si tiene uno storico che le API non
 * conservano (GA4 e Search Console hanno finestre limitate).
 *
 * Identità: `ga4-reader` (già utente della property GA4 e di Search Console).
 * Per scrivere su Firestore ha `roles/datastore.user` (concesso il
 * 07/11/2026). Solo aggregati, nessun dato personale.
 *
 * Ogni documento dichiara `computedAt`, `dataThrough` (ultimo giorno che la
 * fonte ha davvero) e `ok`/`error`: chi legge deve poter dire «dati del …».
 * Una fonte che fallisce non ferma l'altra e non sovrascrive uno snapshot
 * buono con uno rotto: scrive comunque il documento del giorno, con `ok:false`.
 *
 * Rules: `reportSnapshots` lettura admin, scrittura solo da qui.
 */

const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {accessToken, dayAgo} = require("./landingStats")._helpers;

const SA = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";
const COLLECTION = "reportSnapshots";
const ga4 = require("./reportCollectors/ga4");
const searchConsole = require("./reportCollectors/searchConsole");
const billing = require("./reportCollectors/billing");
const play = require("./reportCollectors/play");

const SA_STORE = "report-snapshotter@kidbox-42cd7.iam.gserviceaccount.com";
const PLAY_SA = "play-purchase-validator@kidbox-42cd7.iam.gserviceaccount.com";
const METADATA_TOKEN = "http://metadata.google.internal/computeMetadata/v1/" +
  "instance/service-accounts/default/token";

/**
 * Token del service account di runtime (cloud-platform, quindi anche BigQuery
 * e IAM Credentials).
 * @return {Promise<string>}
 */
async function runtimeToken() {
  const res = await fetch(METADATA_TOKEN,
      {headers: {"Metadata-Flavor": "Google"}});
  if (!res.ok) throw new Error(`metadata token ${res.status}`);
  return (await res.json()).access_token;
}

/**
 * Header JSON con token.
 * @param {string} t
 * @return {object}
 */
function jsonHeaders(t) {
  return {"Authorization": `Bearer ${t}`, "Content-Type": "application/json"};
}

/**
 * Token di un altro service account, impersonato (serve tokenCreator su di lui
 * per il runtime).
 * @param {string} rt token di runtime
 * @param {string} sa
 * @param {string} scope
 * @return {Promise<string>}
 */
async function impersonate(rt, sa, scope) {
  const url = "https://iamcredentials.googleapis.com/v1/projects/-/" +
    `serviceAccounts/${sa}:generateAccessToken`;
  const res = await fetch(url, {
    method: "POST",
    headers: jsonHeaders(rt),
    body: JSON.stringify(
        {scope: [`https://www.googleapis.com/auth/${scope}`]}),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`impersona ${scope}: ${j.error?.message || res.status}`);
  }
  return j.accessToken;
}

/**
 * Query BigQuery (REST, SQL standard) → righe come oggetti. Tabella assente →
 * errore con `notYet`.
 * @param {string} rt
 * @param {string} sql
 * @return {Promise<object[]>}
 */
async function bigQuery(rt, sql) {
  const url = "https://bigquery.googleapis.com/bigquery/v2/projects/" +
    `${billing.PROJECT}/queries`;
  const res = await fetch(url, {
    method: "POST",
    headers: jsonHeaders(rt),
    body: JSON.stringify({query: sql, useLegacySql: false,
      maxResults: 10000, timeoutMs: 60000, location: "EU"}),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) {
    const err = new Error(j.error?.message || `HTTP ${res.status}`);
    if (res.status === 404 || /Not found: Table/i.test(err.message)) {
      err.notYet = true;
    }
    throw err;
  }
  if (j.jobComplete === false) {
    throw new Error("query BigQuery non completata in tempo");
  }
  const cols = (j.schema?.fields || []).map((f) => f.name);
  return (j.rows || []).map((r) => Object.fromEntries(
      cols.map((c, i) => [c, r.f[i].v])));
}

/**
 * Scrive lo snapshot di una fonte, anche se fallita (ok:false).
 * @param {string} source
 * @param {string} today YYYY-MM-DD
 * @param {Function} fn
 * @param {string} tok
 */
async function snapshot(source, today, fn, tok) {
  const ref = admin.firestore().collection(COLLECTION)
      .doc(`${source}_${today}`);
  try {
    const {dataThrough, payload} = await fn(tok);
    // Il payload è lo STESSO oggetto che lo script stampa con `--json`: lo si
    // salva come stringa JSON (niente limiti sui nomi dei campi, niente
    // `undefined`, un solo campo da leggere).
    const payloadJson = JSON.stringify(payload);
    if (payloadJson.length > 900000) {
      throw new Error(`payload troppo grande (${payloadJson.length} B)`);
    }
    await ref.set({source, day: today, ok: true, dataThrough,
      computedAt: admin.firestore.FieldValue.serverTimestamp(), payloadJson});
    logger.info(`reportSnapshot ${source} ok`, {dataThrough});
  } catch (e) {
    logger.error(`reportSnapshot ${source} fallito`, e);
    await ref.set({source, day: today, ok: false,
      error: String(e.message || e),
      computedAt: admin.firestore.FieldValue.serverTimestamp()});
  }
}

exports.reportSnapshotDaily = onSchedule(
    {
      // Dopo la riga del billing (che arriva tardi) non serve: queste due
      // fonti non dipendono da lei. Search Console ha comunque 2-3 giorni di
      // ritardo, `dataThrough` lo dice.
      schedule: "30 7 * * *",
      timeZone: "Europe/Rome",
      region: "europe-west1",
      serviceAccount: SA,
      maxInstances: 1,
      timeoutSeconds: 300,
    },
    async () => {
      const today = dayAgo(0);
      const tok = await accessToken();
      await snapshot("searchConsole", today, async (t) => {
        const o = await searchConsole.collect(t);
        return {dataThrough: o.lastDay || null, payload: o};
      }, tok);
      await snapshot("ga4", today, async (t) => {
        const o = await ga4.collect(t);
        return {dataThrough: o.yesterday, payload: o};
      }, tok);
    },
);

exports.reportSnapshotStoreDaily = onSchedule(
    {
      // Le righe del billing di ieri arrivano nel corso della mattina
      // (l'ultima volta alle 06:57): alle 11:00 ci sono quasi sempre.
      schedule: "0 11 * * *",
      timeZone: "Europe/Rome",
      region: "europe-west1",
      serviceAccount: SA_STORE,
      maxInstances: 1,
      timeoutSeconds: 300,
    },
    async () => {
      const today = dayAgo(0);
      const rt = await runtimeToken();
      await snapshot("billing", today, async () => {
        const o = await billing.collect((sql) => bigQuery(rt, sql));
        return {dataThrough: o.totals?.yesterday?.present ? o.yesterday : null,
          payload: o};
      }, rt);
      await snapshot("play", today, async () => {
        const [reporting, publisher] = await Promise.all([
          impersonate(rt, PLAY_SA, "playdeveloperreporting"),
          impersonate(rt, PLAY_SA, "androidpublisher"),
        ]);
        const o = await play.collect({reporting, publisher});
        return {dataThrough: o.yesterday, payload: o};
      }, rt);
    },
);
