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

const TEXT_TYPES = /^(text\/|application\/(json|xml|xhtml\+xml|.*\+json|.*\+xml))/i;

/**
 * Scarica un documento di testo, seguendo a mano i redirect.
 * @param {string} rawUrl
 * @param {{maxBytes?: number, accept?: string}} [opts]
 * @return {Promise<{text: string, finalUrl: string, contentType: string}>}
 */
async function download(rawUrl, opts = {}) {
  const maxBytes = opts.maxBytes || MAX_BYTES;
  let url = parseUrl(rawUrl);
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublicHost(url);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
    let res;
    try {
      res = await fetch(url, {
        redirect: "manual",
        signal: controller.signal,
        headers: {
          "User-Agent": USER_AGENT,
          "Accept": opts.accept || "text/html, application/json;q=0.9, application/xml;q=0.8, */*;q=0.1",
          "Accept-Language": "it-IT,it;q=0.9",
        },
      });
    } catch (e) {
      throw new FetchError(ERR.UNREACHABLE, e.name === "AbortError" ? "timeout" : String(e.message || e));
    } finally {
      clearTimeout(timer);
    }
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      url = parseUrl(new URL(res.headers.get("location"), url).toString());
      continue;
    }
    if (res.status === 429 || res.status >= 500) throw new FetchError(ERR.UNREACHABLE, `HTTP ${res.status}`);
    if (!res.ok) throw new FetchError(ERR.HTTP, `HTTP ${res.status}`);
    const contentType = res.headers.get("content-type") || "";
    if (contentType && !TEXT_TYPES.test(contentType)) throw new FetchError(ERR.NOT_TEXT, contentType);
    const declared = Number(res.headers.get("content-length") || 0);
    if (declared > maxBytes) throw new FetchError(ERR.TOO_LARGE, `${declared} byte`);

    const reader = res.body.getReader();
    const chunks = [];
    let total = 0;
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      total += value.length;
      if (total > maxBytes) {
        reader.cancel().catch(() => {});
        throw new FetchError(ERR.TOO_LARGE, `oltre ${maxBytes} byte`);
      }
      chunks.push(value);
    }
    return {text: Buffer.concat(chunks).toString("utf8"), finalUrl: url.toString(), contentType};
  }
  throw new FetchError(ERR.UNREACHABLE, "troppi redirect");
}

module.exports = {download, parseUrl, FetchError, ERR};
