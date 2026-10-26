/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// FARMACIE DI TURNO — download di una pagina scelta da un utente (o dall'AI).
//
// Stesse garanzie di `calendarFeeds.js` (che scarica link degli utenti): solo
// http/https, niente indirizzi interni (metadata di Google Cloud, reti
// private), redirect ricontrollati uno per uno, dimensione e tempo limitati.
// Qui in più: solo testo (HTML, JSON, XML). I PDF e le immagini non si leggono.
// ─────────────────────────────────────────────────────────────────────────────

const dns = require("node:dns").promises;
const net = require("node:net");
const tls = require("node:tls");
const https = require("node:https");
const http = require("node:http");
const crypto = require("node:crypto");
const {_internal} = require("../calendarFeeds");

const MAX_BYTES = 6 * 1024 * 1024;
const TIMEOUT_MS = 15_000;
const MAX_REDIRECTS = 3;
const USER_AGENT = "KidBox-Farmacie/1.0 (+https://kidboxapp.com)";

/** Un errore di rete con un motivo stabile da mostrare all'utente. */
class FetchError extends Error {
  /**
   * @param {string} code motivo stabile, da mostrare all'utente
   * @param {string} detail dettaglio per i log
   */
  constructor(code, detail) {
    super(detail || code);
    this.code = code;
  }
}

const ERR = {
  INVALID_URL: "invalid-url",
  PRIVATE: "private-address",
  UNREACHABLE: "unreachable",
  HTTP: "http-error",
  TOO_LARGE: "too-large",
  NOT_TEXT: "not-text",
};

/**
 * @param {string} raw
 * @return {URL} l'URL, solo http/https e senza credenziali
 */
function parseUrl(raw) {
  let url;
  try {
    url = _internal.normalizeUrl(raw);
  } catch (e) {
    throw new FetchError(ERR.INVALID_URL, String(e.message || e));
  }
  return url;
}

/**
 * @param {URL} url
 * @return {Promise<void>} rifiuta se l'host risolve su un indirizzo vietato
 */
async function assertPublicHost(url) {
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".internal") || host.endsWith(".local")) {
    throw new FetchError(ERR.PRIVATE, host);
  }
  let addresses;
  if (net.isIP(host)) {
    addresses = [host];
  } else {
    try {
      addresses = (await dns.lookup(host, {all: true})).map((a) => a.address);
    } catch (e) {
      throw new FetchError(ERR.UNREACHABLE, `dns ${host}: ${e.code || e.message}`);
    }
  }
  if (!addresses.length || addresses.some(_internal.isForbiddenIp)) {
    throw new FetchError(ERR.PRIVATE, `${host} → ${addresses.join(",")}`);
  }
}


// ── Certificati intermedi mancanti ───────────────────────────────────────────
// Molti siti della pubblica amministrazione inviano solo il certificato del
// sito e non l'intermedio: i browser lo recuperano dall'indirizzo «CA Issuers»
// scritto nel certificato (AIA), Node no ("unable to verify the first
// certificate"). Facciamo come i browser, senza abbassare la guardia: l'intermedio
// si aggiunge ai certificati fidati, ma la catena deve comunque arrivare a una
// radice del sistema. La verifica TLS non si disattiva mai.

const TLS_CHAIN_ERRORS = new Set(["UNABLE_TO_VERIFY_LEAF_SIGNATURE", "UNABLE_TO_GET_ISSUER_CERT_LOCALLY"]);
/** host → certificati intermedi (PEM) già recuperati. */
const intermediates = new Map();

/**
 * @param {string} host
 * @param {number} port
 * @return {Promise<object>} il certificato che il server presenta, con le informazioni AIA
 */
function peerCertificate(host, port) {
  return new Promise((resolve, reject) => {
    const socket = tls.connect({host, port, servername: host, rejectUnauthorized: false, timeout: TIMEOUT_MS}, () => {
      const cert = socket.getPeerCertificate(true);
      socket.end();
      resolve(cert);
    });
    socket.on("error", reject);
    socket.on("timeout", () => {
      socket.destroy();
      reject(new Error("timeout"));
    });
  });
}

/**
 * @param {URL} url
 * @return {Promise<string[]>} gli intermedi in PEM, vuoto se non si trovano
 */
async function fetchIntermediates(url) {
  const host = url.hostname;
  if (intermediates.has(host)) return intermediates.get(host);
  const pems = [];
  try {
    const cert = await peerCertificate(host, Number(url.port) || 443);
    const raw = cert?.infoAccess?.["CA Issuers - URI"] || [];
    for (const uri of raw.slice(0, 2)) {
      const target = parseUrl(uri);
      await assertPublicHost(target);
      const res = await fetch(target, {signal: AbortSignal.timeout(TIMEOUT_MS), headers: {"User-Agent": USER_AGENT}});
      if (!res.ok) continue;
      const der = Buffer.from(await res.arrayBuffer());
      if (der.length > 64 * 1024) continue;
      try {
        pems.push(new crypto.X509Certificate(der).toString());
      } catch (_) {/* non è un certificato X.509 singolo */}
    }
  } catch (_) {/* senza intermedio si resta nell'errore originale */}
  intermediates.set(host, pems);
  return pems;
}

/**
 * @param {URL} url
 * @return {https.Agent|http.Agent}
 */
function agentFor(url) {
  if (url.protocol !== "https:") return new http.Agent();
  const extra = intermediates.get(url.hostname) || [];
  return new https.Agent(extra.length ? {ca: [...tls.rootCertificates, ...extra]} : {});
}

const TEXT_TYPES = /^(text\/|application\/(json|xml|xhtml\+xml|.*\+json|.*\+xml))/i;

/**
 * Scarica un documento di testo, seguendo a mano i redirect.
 * @param {string} rawUrl
 * @param {{maxBytes?: number, accept?: string}} [opts]
 * @return {Promise<{text: string, finalUrl: string, contentType: string}>}
 */
async function download(rawUrl, opts = {}) {
  const fetchNode = (await import("node-fetch")).default;
  const maxBytes = opts.maxBytes || MAX_BYTES;
  let url = parseUrl(rawUrl);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublicHost(url);
    let res;
    for (let attempt = 0; attempt < 2; attempt++) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
      try {
        res = await fetchNode(url, {
          redirect: "manual",
          signal: controller.signal,
          agent: () => agentFor(url),
          headers: {
            "User-Agent": USER_AGENT,
            "Accept": opts.accept || (opts.binary ? "image/png, image/jpeg, image/webp, image/gif" : "text/html, application/json;q=0.9, application/xml;q=0.8, */*;q=0.1"),
            "Accept-Language": "it-IT,it;q=0.9",
          },
        });
        break;
      } catch (e) {
        // Intermedio mancante: una volta sola si prova a recuperarlo.
        if (attempt === 0 && url.protocol === "https:" && TLS_CHAIN_ERRORS.has(e.code) && !intermediates.has(url.hostname)) {
          const found = await fetchIntermediates(url);
          if (found.length) continue;
        }
        throw new FetchError(ERR.UNREACHABLE, e.name === "AbortError" ? "timeout" : `${e.code || ""} ${e.message || e}`.trim());
      } finally {
        clearTimeout(timer);
      }
    }
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      url = parseUrl(new URL(res.headers.get("location"), url).toString());
      continue;
    }
    if (res.status === 429 || res.status >= 500) throw new FetchError(ERR.UNREACHABLE, `HTTP ${res.status}`);
    if (!res.ok) throw new FetchError(ERR.HTTP, `HTTP ${res.status}`);
    const contentType = res.headers.get("content-type") || "";
    if (opts.binary) {
      // Immagini dei turni (solo i formati che l'AI sa leggere).
      if (!/^image\/(png|jpe?g|webp|gif)/i.test(contentType)) throw new FetchError(ERR.NOT_TEXT, contentType);
    } else if (contentType && !TEXT_TYPES.test(contentType)) {
      throw new FetchError(ERR.NOT_TEXT, contentType);
    }
    const declared = Number(res.headers.get("content-length") || 0);
    if (declared > maxBytes) throw new FetchError(ERR.TOO_LARGE, `${declared} byte`);

    const chunks = [];
    let total = 0;
    for await (const chunk of res.body) {
      total += chunk.length;
      if (total > maxBytes) {
        res.body.destroy();
        throw new FetchError(ERR.TOO_LARGE, `oltre ${maxBytes} byte`);
      }
      chunks.push(chunk);
    }
    const buffer = Buffer.concat(chunks);
    return {text: opts.binary ? "" : buffer.toString("utf8"), buffer, finalUrl: url.toString(), contentType};
  }
  throw new FetchError(ERR.UNREACHABLE, "troppi redirect");
}

module.exports = {download, parseUrl, FetchError, ERR};
