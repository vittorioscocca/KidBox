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
const {accessToken, postJson, dayAgo} = require("./landingStats")._helpers;

const SA = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";
const SITE = "sc-domain:kidboxapp.com";
const GA4_PROPERTY = "523225071";
const COLLECTION = "reportSnapshots";
const KEY_EVENTS = [
  "first_open", "app_open", "pre_signup_screen_shown", "login_attempted",
  "signup_completed", "onboarding_completed", "family_created",
  "invite_prompt_shown", "invite_prompt_accepted", "invite_generated",
  "invite_shared", "family_join_attempted", "family_joined",
  "family_join_failed", "content_created", "content_shared_read",
  "ai_message_sent", "paywall_shown", "purchase_started",
  "subscription_started", "store_click", "invite_landing_shown",
  "invite_store_click", "landing_chat_open", "landing_chat_question",
];

/**
 * GET JSON con token.
 * @param {string} url
 * @param {string} tok
 * @return {Promise<object>}
 */
async function getJson(url, tok) {
  const res = await fetch(url, {headers: {Authorization: `Bearer ${tok}`}});
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(j.error?.message || `HTTP ${res.status}`);
  return j;
}

/**
 * Search Console: serie 28 giorni, finestre 1/7/28 con il periodo prima,
 * query, pagine, paesi, dispositivi, sitemap.
 * @param {string} tok
 * @return {Promise<{dataThrough: string, payload: object}>}
 */
async function searchConsoleSnapshot(tok) {
  const base = "https://www.googleapis.com/webmasters/v3/sites/" +
    encodeURIComponent(SITE);
  const q = (startDate, endDate, dimensions, rowLimit) =>
    postJson(`${base}/searchAnalytics/query`, tok,
        {startDate, endDate, dimensions, rowLimit})
        .then((j) => (j.rows || []).map((r) => ({
          keys: r.keys || [],
          clicks: r.clicks,
          impressions: r.impressions,
          ctr: r.ctr,
          position: r.position,
        })));
  // Ultimo giorno che Search Console ha davvero: serie su 40 giorni.
  const daily = await q(dayAgo(40), dayAgo(0), ["date"], 60);
  const days = daily.map((r) => r.keys[0]).sort();
  const through = days[days.length - 1] || dayAgo(3);
  const shift = (d, n) => new Date(Date.parse(d) + n * 864e5)
      .toISOString().slice(0, 10);
  const win = (n) => ({from: shift(through, -(n - 1)), to: through});
  const windows = {};
  for (const n of [1, 7, 28]) {
    const cur = win(n);
    const prev = {from: shift(cur.from, -n), to: shift(cur.from, -1)};
    const [c, p] = await Promise.all([
      q(cur.from, cur.to, [], 1), q(prev.from, prev.to, [], 1),
    ]);
    windows[`d${n}`] = {range: cur, current: c[0] || null,
      previous: p[0] || null};
  }
  const w28 = win(28);
  const [queries, pages, countries, devices] = await Promise.all([
    q(w28.from, w28.to, ["query"], 100),
    q(w28.from, w28.to, ["page"], 100),
    q(w28.from, w28.to, ["country"], 20),
    q(w28.from, w28.to, ["device"], 5),
  ]);
  const sm = await getJson(`${base}/sitemaps`, tok).catch((e) =>
    ({error: String(e.message || e)}));
  const sitemaps = (sm.sitemap || []).map((s) => ({
    path: s.path,
    lastDownloaded: s.lastDownloaded || null,
    isPending: !!s.isPending,
    errors: Number(s.errors) || 0,
    warnings: Number(s.warnings) || 0,
  }));
  return {
    dataThrough: through,
    payload: {daily, windows, queries, pages, countries, devices, sitemaps,
      sitemapsError: sm.error || null},
  };
}

/**
 * GA4: serie per piattaforma (14 giorni), eventi chiave per giorno (3 giorni),
 * pagine, sorgenti e paesi del web (28 giorni).
 * @param {string} tok
 * @return {Promise<{dataThrough: string, payload: object}>}
 */
async function ga4Snapshot(tok) {
  const url = "https://analyticsdata.googleapis.com/v1beta/properties/" +
    `${GA4_PROPERTY}:runReport`;
  const run = (from, to, dimensions, metrics, limit, filter) =>
    postJson(url, tok, {
      dateRanges: [{startDate: from, endDate: to}],
      dimensions: dimensions.map((name) => ({name})),
      metrics: metrics.map((name) => ({name})),
      dimensionFilter: filter,
      limit,
    }).then((j) => (j.rows || []).map((r) => ({
      keys: (r.dimensionValues || []).map((v) => v.value),
      values: (r.metricValues || []).map((v) => Number(v.value) || 0),
    })));
  const evFilter = {filter: {fieldName: "eventName",
    inListFilter: {values: KEY_EVENTS}}};
  const [platforms, events, pages, sources, countries] = await Promise.all([
    run(dayAgo(14), dayAgo(0), ["date", "platform"],
        ["activeUsers", "newUsers", "sessions"], 200),
    run(dayAgo(3), dayAgo(0), ["date", "eventName"],
        ["eventCount", "totalUsers"], 500, evFilter),
    run(dayAgo(28), dayAgo(0), ["hostName", "pagePath"],
        ["screenPageViews", "activeUsers"], 60),
    run(dayAgo(28), dayAgo(0),
        ["hostName", "sessionSource", "sessionMedium"],
        ["sessions", "engagedSessions"], 60),
    run(dayAgo(28), dayAgo(0), ["country"], ["activeUsers", "newUsers"], 25),
  ]);
  const dates = platforms.map((r) => r.keys[0]).sort();
  const last = dates[dates.length - 1] || dayAgo(0);
  const through = `${last.slice(0, 4)}-${last.slice(4, 6)}-${last.slice(6)}`;
  return {dataThrough: through,
    payload: {platforms, events, pages, sources, countries}};
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
    await ref.set({source, day: today, ok: true, dataThrough,
      computedAt: admin.firestore.FieldValue.serverTimestamp(), payload});
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
      await snapshot("searchConsole", today, searchConsoleSnapshot, tok);
      await snapshot("ga4", today, ga4Snapshot, tok);
    },
);
