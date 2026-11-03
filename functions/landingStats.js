/**
 * getLandingStats — i numeri della landing per la console admin: Google
 * Search (Search Console) e GA4 filtrato sugli host della landing.
 *
 * Gira con l'identità di `ga4-reader@kidbox-42cd7.iam.gserviceaccount.com`
 * (`serviceAccount` qui sotto), lo stesso service account che i report
 * impersonano: è già utente della property GA4 e di Search Console, quindi
 * nessun permesso nuovo. Il token arriva dal metadata server, senza librerie.
 * Il contatore `landingTraffic` lo legge la console da sola (lettura admin).
 *
 * Solo admin (`ADMIN_UIDS` di index.js). Risultato tenuto 30 minuti in memoria
 * dell'istanza: la console può riaprire la pagina senza rifare 11 chiamate.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");

const SA = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";
const SITE = "sc-domain:kidboxapp.com";
const GA4_PROPERTY = "523225071";
// Landing e i suoi alias; la web app (app.kidboxapp.com) resta fuori.
const LANDING_HOSTS = [
  "kidboxapp.com",
  "www.kidboxapp.com",
  "kidbox-landing.web.app",
  "kidbox-landing.firebaseapp.com",
];
const CACHE_MS = 30 * 60 * 1000;
const METADATA_TOKEN = "http://metadata.google.internal/computeMetadata/v1/" +
  "instance/service-accounts/default/token";

let cache = null;

/**
 * Token OAuth del service account di runtime, con gli scope chiesti.
 * @return {Promise<string>}
 */
async function accessToken() {
  const scopes = [
    "https://www.googleapis.com/auth/webmasters.readonly",
    "https://www.googleapis.com/auth/analytics.readonly",
  ].join(",");
  const res = await fetch(`${METADATA_TOKEN}?scopes=${scopes}`,
      {headers: {"Metadata-Flavor": "Google"}});
  if (!res.ok) throw new Error(`metadata token ${res.status}`);
  return (await res.json()).access_token;
}

/**
 * YYYY-MM-DD di n giorni fa, nel fuso di Roma.
 * @param {number} n
 * @return {string}
 */
function dayAgo(n) {
  const d = new Date(Date.now() - n * 864e5);
  return d.toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"});
}

/**
 * POST JSON con token; errore leggibile se la risposta non è 2xx.
 * @param {string} url
 * @param {string} tok
 * @param {object} body
 * @return {Promise<object>}
 */
async function postJson(url, tok, body) {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${tok}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(j.error?.message || `HTTP ${res.status}`);
  return j;
}

/**
 * Search Console: serie di 92 giorni e spaccati degli ultimi 28.
 * @param {string} tok
 * @return {Promise<object>}
 */
async function searchConsole(tok) {
  const url = "https://www.googleapis.com/webmasters/v3/sites/" +
    `${encodeURIComponent(SITE)}/searchAnalytics/query`;
  const q = (dimensions, days, rowLimit) => postJson(url, tok, {
    startDate: dayAgo(days), endDate: dayAgo(0), dimensions, rowLimit,
  }).then((j) => (j.rows || []).map((r) => ({
    keys: r.keys || [],
    clicks: r.clicks,
    impressions: r.impressions,
    ctr: r.ctr,
    position: r.position,
  })));
  const [daily, queries, pages, countries, devices] = await Promise.all([
    q(["date"], 92, 200),
    q(["query"], 28, 30),
    q(["page"], 28, 30),
    q(["country"], 28, 12),
    q(["device"], 28, 5),
  ]);
  return {daily, queries, pages, countries, devices};
}

/**
 * GA4 sui soli host della landing. Conta solo chi ha dato il consenso.
 * @param {string} tok
 * @return {Promise<object>}
 */
async function ga4(tok) {
  const url = "https://analyticsdata.googleapis.com/v1beta/properties/" +
    `${GA4_PROPERTY}:runReport`;
  const hostFilter = {
    filter: {fieldName: "hostName", inListFilter: {values: LANDING_HOSTS}},
  };
  const run = (dimensions, metrics, days, limit, orderBys) =>
    postJson(url, tok, {
      dateRanges: [{startDate: `${days}daysAgo`, endDate: "today"}],
      dimensions: dimensions.map((name) => ({name})),
      metrics: metrics.map((name) => ({name})),
      dimensionFilter: hostFilter,
      orderBys: orderBys || [{metric: {metricName: metrics[0]}, desc: true}],
      limit,
    }).then((j) => (j.rows || []).map((r) => ({
      keys: (r.dimensionValues || []).map((v) => v.value),
      values: (r.metricValues || []).map((v) => Number(v.value) || 0),
    })));
  const byDate = [{dimension: {dimensionName: "date"}}];
  const [daily, pages, channels, countries, devices, events] =
    await Promise.all([
      run(["date"],
          ["activeUsers", "sessions", "screenPageViews", "engagedSessions"],
          90, 100, byDate),
      run(["pagePath"], ["screenPageViews", "activeUsers"], 28, 30),
      run(["sessionDefaultChannelGroup", "sessionSource"],
          ["sessions", "engagedSessions"], 28, 20),
      run(["country"], ["activeUsers"], 28, 12),
      run(["deviceCategory"], ["activeUsers"], 28, 5),
      run(["eventName"], ["eventCount", "totalUsers"], 28, 25),
    ]);
  return {daily, pages, channels, countries, devices, events};
}

/**
 * La callable, con la lista degli admin presa da index.js.
 * @param {{ADMIN_UIDS: string[]}} deps
 * @return {object}
 */
exports.build = ({ADMIN_UIDS}) => onCall(
    {
      region: "europe-west1",
      maxInstances: 2,
      serviceAccount: SA,
      timeoutSeconds: 60,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      }
      if (!ADMIN_UIDS.includes(uid)) {
        throw new HttpsError("permission-denied", "Non autorizzato.");
      }
      const fresh = cache && Date.now() - cache.at < CACHE_MS;
      if (fresh && !request.data?.force) return cache.data;

      const tok = await accessToken();
      // Una fonte che fallisce non ferma l'altra: la console mostra l'errore
      // solo in quella sezione.
      const [sc, ga] = await Promise.allSettled([searchConsole(tok), ga4(tok)]);
      const err = (r) => ({error: String(r.reason?.message || r.reason)});
      const data = {
        computedAt: Date.now(),
        searchConsole: sc.status === "fulfilled" ? sc.value : err(sc),
        ga4: ga.status === "fulfilled" ? ga.value : err(ga),
      };
      if (sc.status === "rejected") {
        logger.warn("getLandingStats: Search Console", data.searchConsole);
      }
      if (ga.status === "rejected") {
        logger.warn("getLandingStats: GA4", data.ga4);
      }
      if (sc.status === "fulfilled" && ga.status === "fulfilled") {
        cache = {at: Date.now(), data};
      }
      return data;
    });
