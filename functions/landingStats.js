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
 * Solo admin (`ADMIN_UIDS` di index.js). La console passa il periodo scelto
 * (`from`, `to`, oppure `all`): le serie per giorno arrivano sempre intere, gli
 * spaccati sono del periodo. Risultato tenuto 30 minuti in memoria
 * dell'istanza, per periodo: cambiando filtro non si rifanno 11 chiamate.
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
const CACHE_MAX = 12;
// Search Console tiene 16 mesi: «Tutto» arriva fin lì.
const MAX_DAYS = 480;
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const METADATA_TOKEN = "http://metadata.google.internal/computeMetadata/v1/" +
  "instance/service-accounts/default/token";

const cache = new Map();

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
 * Il periodo chiesto dalla console, in date valide e dentro lo storico.
 * @param {object} d i dati della chiamata
 * @return {{from: string, to: string}}
 */
function parseRange(d) {
  const oldest = dayAgo(MAX_DAYS);
  const to = DAY_RE.test(d?.to) ? d.to : dayAgo(0);
  let from = DAY_RE.test(d?.from) ? d.from : dayAgo(28);
  if (d?.all || from < oldest) from = oldest;
  if (from > to) from = to;
  return {from, to};
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
 * Search Console: serie per giorno intera e spaccati del periodo.
 * @param {string} tok
 * @param {{from: string, to: string}} range
 * @return {Promise<object>}
 */
async function searchConsole(tok, range) {
  const url = "https://www.googleapis.com/webmasters/v3/sites/" +
    `${encodeURIComponent(SITE)}/searchAnalytics/query`;
  const query = (dimensions, startDate, endDate, rowLimit) =>
    postJson(url, tok, {startDate, endDate, dimensions, rowLimit})
        .then((j) => (j.rows || []).map((r) => ({
          keys: r.keys || [],
          clicks: r.clicks,
          impressions: r.impressions,
          ctr: r.ctr,
          position: r.position,
        })));
  const q = (dimensions, limit) =>
    query(dimensions, range.from, range.to, limit);
  const [daily, queries, pages, countries, devices] = await Promise.all([
    query(["date"], dayAgo(MAX_DAYS), dayAgo(0), MAX_DAYS + 20),
    q(["query"], 30),
    q(["page"], 30),
    q(["country"], 12),
    q(["device"], 5),
  ]);
  return {daily, queries, pages, countries, devices};
}

/**
 * GA4 sui soli host della landing: serie per giorno intera e spaccati del
 * periodo. Conta solo chi ha dato il consenso.
 * @param {string} tok
 * @param {{from: string, to: string}} range
 * @return {Promise<object>}
 */
async function ga4(tok, range) {
  const url = "https://analyticsdata.googleapis.com/v1beta/properties/" +
    `${GA4_PROPERTY}:runReport`;
  const hostFilter = {
    filter: {fieldName: "hostName", inListFilter: {values: LANDING_HOSTS}},
  };
  const run = (dimensions, metrics, limit, orderBys, dates = range) =>
    postJson(url, tok, {
      dateRanges: [{startDate: dates.from, endDate: dates.to}],
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
  const history = {from: dayAgo(MAX_DAYS), to: dayAgo(0)};
  const [daily, pages, channels, countries, devices, events] =
    await Promise.all([
      run(["date"],
          ["activeUsers", "sessions", "screenPageViews", "engagedSessions"],
          MAX_DAYS + 20, byDate, history),
      run(["pagePath"], ["screenPageViews", "activeUsers"], 30),
      run(["sessionDefaultChannelGroup", "sessionSource"],
          ["sessions", "engagedSessions"], 20),
      run(["country"], ["activeUsers"], 12),
      run(["deviceCategory"], ["activeUsers"], 5),
      run(["eventName"], ["eventCount", "totalUsers"], 25),
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
      const range = parseRange(request.data);
      const key = `${range.from}|${range.to}`;
      const hit = cache.get(key);
      const fresh = hit && Date.now() - hit.at < CACHE_MS;
      if (fresh && !request.data?.force) return hit.data;

      const tok = await accessToken();
      // Una fonte che fallisce non ferma l'altra: la console mostra l'errore
      // solo in quella sezione.
      const [sc, ga] = await Promise.allSettled([
        searchConsole(tok, range),
        ga4(tok, range),
      ]);
      const err = (r) => ({error: String(r.reason?.message || r.reason)});
      const data = {
        computedAt: Date.now(),
        range,
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
        cache.set(key, {at: Date.now(), data});
        if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
      }
      return data;
    });
