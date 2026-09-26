/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// CALENDARI ISCRITTI (feed ICS da URL)
//
// Un membro incolla il link di un calendario pubblicato da altri (scuola,
// squadra, festività, l'«indirizzo segreto iCal» di un Google Calendar) e gli
// eventi compaiono nel calendario di TUTTA la famiglia, in sola lettura, su
// iOS, Android e web. È l'unica strada per il web: il browser non vede i
// calendari del telefono.
//
// Documento `families/{familyId}/calendarFeeds/{feedId}`, scritto SOLO da qui
// (le rules lo lasciano solo leggere ai membri):
//   name, url, colorHex, createdBy, createdAt, updatedAt,
//   lastFetchAt, lastError (codice | null), etag, lastModified,
//   eventCount, truncated, events: [ {id, t, s, e, a, l, n} ]
//
// Gli eventi stanno DENTRO il documento, non in una sottocollezione: un feed
// della scuola sono qualche centinaio di occorrenze, e così ogni client le
// riceve con una lettura sola invece che con una per evento. Le ripetizioni le
// espande il server (RRULE, EXDATE, eccezioni, fusi: il formato ICS è molto più
// ricco delle cinque ricorrenze di KidBox), i client ricevono date e basta.
//
// Formato di un evento:
//   t titolo, l luogo, n note (accorciate), id stabile (UID + inizio);
//   a = true  → tutto il giorno: s/e sono DATE "YYYY-MM-DD", e esclusa. Così
//               il 25 dicembre resta il 25 dicembre in ogni fuso;
//   a = false → s/e in millisecondi epoch.
//
// Il server scarica URL scelti dagli utenti: niente indirizzi interni
// (metadata di Google Cloud, reti private), solo http/https, redirect
// ricontrollati uno per uno, 5 MB e 15 secondi al massimo.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const dns = require("node:dns").promises;
const net = require("node:net");
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {logger} = require("firebase-functions");
const ICAL = require("ical.js");

const REGION = "europe-west1";
const MAX_FEEDS_PER_FAMILY = 10;
const MAX_BYTES = 5 * 1024 * 1024;
const FETCH_TIMEOUT_MS = 15_000;
const MAX_REDIRECTS = 3;
/** Finestra delle occorrenze salvate: un po' di passato, più di un anno avanti. */
const PAST_DAYS = 60;
const FUTURE_DAYS = 400;
const MAX_OCCURRENCES = 1500;
/** Sotto il limite di 1 MiB del documento, con margine per gli altri campi. */
const MAX_EVENTS_BYTES = 850 * 1024;
const NOTES_MAX = 400;
const DEFAULT_TZ = "Europe/Rome";
const COLOR_RE = /^#[0-9A-Fa-f]{6}$/;

/** Codici d'errore letti dai client (tradotti lì). */
const ERR = {
  INVALID_URL: "invalid_url",
  PRIVATE_ADDRESS: "private_address",
  UNREACHABLE: "unreachable",
  HTTP_ERROR: "http_error",
  TOO_LARGE: "too_large",
  NOT_ICS: "not_ics",
  TOO_MANY: "too_many_feeds",
};

/** Errore di un feed, con un codice di `ERR` che il client sa tradurre. */
class FeedError extends Error {
  /**
   * @param {string} code codice di `ERR`
   * @param {string} message dettaglio per i log
   */
  constructor(code, message) {
    super(message || code);
    this.code = code;
  }
}

// ── Rete ─────────────────────────────────────────────────────────────────────

/**
 * `webcal://` è solo un modo per dire «aprilo in un'app calendario»: sotto è
 * https. Si accettano anche gli URL incollati con spazi o senza schema.
 * @param {string} raw testo incollato
 * @return {URL} URL normalizzato
 */
function normalizeUrl(raw) {
  let s = String(raw || "").trim();
  if (!s) throw new FeedError(ERR.INVALID_URL, "vuoto");
  if (/^webcals?:\/\//i.test(s)) s = s.replace(/^webcals?:\/\//i, "https://");
  if (!/^[a-z]+:\/\//i.test(s)) s = `https://${s}`;
  let url;
  try {
    url = new URL(s);
  } catch (_) {
    throw new FeedError(ERR.INVALID_URL, "non è un URL");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new FeedError(ERR.INVALID_URL, `schema ${url.protocol}`);
  }
  if (url.username || url.password) throw new FeedError(ERR.INVALID_URL, "credenziali nell'URL");
  return url;
}

/**
 * Vero per gli indirizzi che il server non deve mai contattare per conto di
 * un utente: loopback, reti private, link-local (dove vive il metadata server
 * di Google Cloud), CGNAT, multicast.
 * @param {string} ip indirizzo IPv4 o IPv6
 * @return {boolean} true se vietato
 */
function isForbiddenIp(ip) {
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split(".").map(Number);
    return a === 0 || a === 10 || a === 127 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      (a === 198 && (b === 18 || b === 19)) ||
      a >= 224;
  }
  const v = ip.toLowerCase();
  if (v.startsWith("::ffff:")) return isForbiddenIp(v.slice(7));
  return v === "::" || v === "::1" || v.startsWith("fc") || v.startsWith("fd") ||
    v.startsWith("fe8") || v.startsWith("fe9") || v.startsWith("fea") ||
    v.startsWith("feb") || v.startsWith("ff");
}

/**
 * @param {URL} url destinazione
 * @return {Promise<void>} rifiuta se l'host risolve su un indirizzo vietato
 */
async function assertPublicHost(url) {
  const host = url.hostname.replace(/^\[|\]$/g, "");
  if (host === "localhost" || host.endsWith(".internal") || host.endsWith(".local")) {
    throw new FeedError(ERR.PRIVATE_ADDRESS, host);
  }
  let addresses;
  if (net.isIP(host)) {
    addresses = [host];
  } else {
    try {
      addresses = (await dns.lookup(host, {all: true})).map((a) => a.address);
    } catch (e) {
      throw new FeedError(ERR.UNREACHABLE, `dns ${host}: ${e.code || e.message}`);
    }
  }
  if (!addresses.length || addresses.some(isForbiddenIp)) {
    throw new FeedError(ERR.PRIVATE_ADDRESS, `${host} → ${addresses.join(",")}`);
  }
}

/**
 * Scarica il feed seguendo a mano i redirect, per ricontrollare ogni tappa.
 * @param {URL} startUrl primo URL
 * @param {{etag?: string, lastModified?: string}} cache validatori HTTP
 * @return {Promise<{notModified: boolean, text?: string, etag?: string,
 *   lastModified?: string}>} contenuto o «non cambiato»
 */
async function download(startUrl, cache = {}) {
  let url = startUrl;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    await assertPublicHost(url);
    const headers = {
      "User-Agent": "KidBox-Calendar/1.0 (+https://kidboxapp.com)",
      "Accept": "text/calendar, text/plain;q=0.9, */*;q=0.5",
    };
    if (cache.etag) headers["If-None-Match"] = cache.etag;
    if (cache.lastModified) headers["If-Modified-Since"] = cache.lastModified;
    let res;
    try {
      res = await fetch(url, {
        headers,
        redirect: "manual",
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      });
    } catch (e) {
      throw new FeedError(ERR.UNREACHABLE, e.message);
    }
    if (res.status >= 300 && res.status < 400 && res.headers.get("location")) {
      url = normalizeUrl(new URL(res.headers.get("location"), url).toString());
      continue;
    }
    if (res.status === 304) return {notModified: true};
    if (!res.ok) throw new FeedError(ERR.HTTP_ERROR, `HTTP ${res.status}`);
    const declared = Number(res.headers.get("content-length") || 0);
    if (declared > MAX_BYTES) throw new FeedError(ERR.TOO_LARGE, `${declared} byte`);

    const reader = res.body.getReader();
    const chunks = [];
    let total = 0;
    for (;;) {
      const {done, value} = await reader.read();
      if (done) break;
      total += value.length;
      if (total > MAX_BYTES) {
        reader.cancel().catch(() => {});
        throw new FeedError(ERR.TOO_LARGE, `oltre ${MAX_BYTES} byte`);
      }
      chunks.push(value);
    }
    return {
      notModified: false,
      text: Buffer.concat(chunks).toString("utf8"),
      etag: res.headers.get("etag") || undefined,
      lastModified: res.headers.get("last-modified") || undefined,
    };
  }
  throw new FeedError(ERR.UNREACHABLE, "troppi redirect");
}

// ── Parsing ──────────────────────────────────────────────────────────────────

/**
 * Millisecondi epoch di un orario «da orologio» in un fuso con nome, senza
 * librerie: si parte dall'ora come se fosse UTC e si corregge con l'offset
 * che quel fuso ha in quell'istante (due passi coprono il cambio dell'ora).
 * @param {object} p {year, month (1-12), day, hour, minute, second}
 * @param {string} tz fuso IANA
 * @return {number} epoch ms
 */
function wallClockToEpoch(p, tz) {
  const guess = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second);
  const offsetAt = (ms) => {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hourCycle: "h23",
      year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
    }).formatToParts(new Date(ms));
    const g = (type) => Number(parts.find((x) => x.type === type).value);
    return Date.UTC(g("year"), g("month") - 1, g("day"), g("hour"), g("minute"), g("second")) - ms;
  };
  let ms = guess - offsetAt(guess);
  ms = guess - offsetAt(ms);
  return ms;
}

/**
 * @param {ICAL.Time} time orario ical.js
 * @param {string} fallbackTz fuso per gli orari «floating» (senza fuso)
 * @return {number} epoch ms
 */
function timeToEpoch(time, fallbackTz) {
  const wall = {
    year: time.year, month: time.month, day: time.day,
    hour: time.hour, minute: time.minute, second: time.second,
  };
  const zone = time.zone;
  // Con un TZID che il file non definisce (niente VTIMEZONE) ical.js lascia
  // l'orario «floating» e il nome del fuso solo in `timezone`: trattarlo da
  // floating spostava una riunione delle 9 a New York alle 9 italiane.
  const tzid = (zone && zone.tzid && zone.tzid !== "floating" && zone !== ICAL.Timezone.localTimezone) ?
    zone.tzid : time.timezone;
  if (tzid === "UTC" || tzid === "Z" || zone === ICAL.Timezone.utcTimezone) {
    return time.toJSDate().getTime();
  }
  if (zone && zone.component) {
    // Fuso definito nel file: lo converte ical.js con le sue regole.
    return time.toJSDate().getTime();
  }
  if (tzid) {
    try {
      return wallClockToEpoch(wall, tzid);
    } catch (_) {
      // tzid non IANA (es. nomi Windows): si ripiega sul fuso del calendario.
    }
  }
  return wallClockToEpoch(wall, fallbackTz);
}

/**
 * @param {ICAL.Time} t data senza ora
 * @return {string} "YYYY-MM-DD"
 */
function dateString(t) {
  const p = (n) => String(n).padStart(2, "0");
  return `${t.year}-${p(t.month)}-${p(t.day)}`;
}

/**
 * Legge il file ICS e restituisce le occorrenze dentro la finestra.
 * @param {string} text contenuto del feed
 * @param {number} nowMs istante di riferimento
 * @return {{events: object[], truncated: boolean, calendarName: ?string}}
 */
function parseIcs(text, nowMs = Date.now()) {
  if (!/BEGIN:VCALENDAR/i.test(text)) throw new FeedError(ERR.NOT_ICS, "manca VCALENDAR");
  let comp;
  try {
    comp = new ICAL.Component(ICAL.parse(text));
  } catch (e) {
    throw new FeedError(ERR.NOT_ICS, e.message);
  }
  for (const tz of comp.getAllSubcomponents("vtimezone")) {
    try {
      ICAL.TimezoneService.register(new ICAL.Timezone(tz));
    } catch (_) {
      // Un VTIMEZONE rotto non deve far cadere tutto il feed.
    }
  }
  const calTz = comp.getFirstPropertyValue("x-wr-timezone") || DEFAULT_TZ;
  const calendarName = comp.getFirstPropertyValue("x-wr-calname") || null;

  const windowStart = nowMs - PAST_DAYS * 86_400_000;
  const windowEnd = nowMs + FUTURE_DAYS * 86_400_000;
  const vevents = comp.getAllSubcomponents("vevent");

  // Le eccezioni (RECURRENCE-ID) si agganciano alla loro serie.
  const masters = new Map();
  const exceptions = [];
  for (const ve of vevents) {
    const ev = new ICAL.Event(ve);
    if (ev.isRecurrenceException()) exceptions.push(ev);
    else masters.set(ev.uid || crypto.randomUUID(), ev);
  }
  for (const ex of exceptions) {
    const master = masters.get(ex.uid);
    if (master) master.relateException(ex);
    else masters.set(`${ex.uid}#${ex.recurrenceId}`, ex);
  }

  const out = [];
  const pushOccurrence = (ev, startTime, endTime, keyUid) => {
    if (!startTime) return;
    const status = String(ev.component.getFirstPropertyValue("status") || "").toUpperCase();
    if (status === "CANCELLED") return;
    const isAllDay = startTime.isDate;
    let s;
    let e;
    let sortKey;
    let endKey;
    if (isAllDay) {
      const end = endTime && endTime.compare(startTime) > 0 ? endTime :
        (() => {
          const x = startTime.clone(); x.adjust(1, 0, 0, 0); return x;
        })();
      s = dateString(startTime);
      e = dateString(end);
      sortKey = Date.UTC(startTime.year, startTime.month - 1, startTime.day);
      endKey = Date.UTC(end.year, end.month - 1, end.day);
    } else {
      s = timeToEpoch(startTime, calTz);
      e = endTime ? timeToEpoch(endTime, calTz) : s;
      if (e < s) e = s;
      sortKey = s;
      endKey = e;
    }
    if (endKey < windowStart || sortKey > windowEnd) return;
    const notes = (ev.description || "").trim();
    out.push({
      id: `${keyUid}|${isAllDay ? s : String(s)}`.slice(0, 300),
      t: (ev.summary || "").trim().slice(0, 200),
      s,
      e,
      a: isAllDay,
      l: (ev.location || "").trim().slice(0, 200) || null,
      n: notes ? notes.slice(0, NOTES_MAX) : null,
      _k: sortKey,
    });
  };

  for (const [key, ev] of masters) {
    try {
      if (!ev.isRecurring()) {
        pushOccurrence(ev, ev.startDate, ev.endDate, key);
        continue;
      }
      const it = ev.iterator();
      let next;
      let guard = 0;
      while ((next = it.next()) && guard++ < 5000) {
        const startMs = next.isDate ?
          Date.UTC(next.year, next.month - 1, next.day) :
          timeToEpoch(next, calTz);
        if (startMs > windowEnd) break;
        const det = ev.getOccurrenceDetails(next);
        // Occorrenze lontane nel passato: si salta il lavoro di dettaglio ma
        // si continua a iterare verso la finestra.
        if (startMs < windowStart - 400 * 86_400_000) continue;
        pushOccurrence(det.item, det.startDate, det.endDate, key);
      }
    } catch (e) {
      logger.warn("calendarFeeds: evento non leggibile", {uid: key, err: e.message});
    }
  }

  out.sort((x, y) => x._k - y._k);
  let events = out.slice(0, MAX_OCCURRENCES);
  let truncated = out.length > events.length;
  events.forEach((x) => delete x._k);

  // Sotto il limite del documento: prima si tolgono le note, poi si accorcia
  // la coda più lontana nel futuro.
  const size = () => Buffer.byteLength(JSON.stringify(events));
  if (size() > MAX_EVENTS_BYTES) {
    events = events.map((x) => ({...x, n: null}));
    truncated = true;
  }
  while (events.length && size() > MAX_EVENTS_BYTES) {
    events = events.slice(0, Math.floor(events.length * 0.9));
  }
  return {events, truncated, calendarName};
}

// ── Firestore ────────────────────────────────────────────────────────────────

/**
 * @param {string} familyId famiglia
 * @param {string} uid utente
 * @return {Promise<void>} rifiuta se non è un membro attivo
 */
async function assertMember(familyId, uid) {
  const snap = await admin.firestore()
      .collection("families").doc(familyId).collection("members").doc(uid).get();
  const d = snap.exists ? snap.data() : null;
  if (!d || d.isDeleted === true || typeof d.role !== "string" || !d.role.trim()) {
    throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.");
  }
}

/**
 * Scarica, legge e salva un feed. Gli errori di rete finiscono in
 * `lastError` senza toccare gli eventi già salvati: una scuola col sito giù
 * per un pomeriggio non deve svuotare il calendario di nessuno.
 * @param {FirebaseFirestore.DocumentReference} ref documento del feed
 * @param {object} data dati attuali
 * @return {Promise<{ok: boolean, code?: string, eventCount?: number}>}
 */
async function refreshFeed(ref, data) {
  const now = Date.now();
  try {
    const url = normalizeUrl(data.url);
    const res = await download(url, {etag: data.etag, lastModified: data.lastModified});
    if (res.notModified) {
      await ref.update({lastFetchAt: admin.firestore.FieldValue.serverTimestamp(), lastError: null});
      return {ok: true, eventCount: data.eventCount || 0};
    }
    const parsed = parseIcs(res.text, now);
    await ref.update({
      events: parsed.events,
      eventCount: parsed.events.length,
      truncated: parsed.truncated,
      etag: res.etag || null,
      lastModified: res.lastModified || null,
      lastFetchAt: admin.firestore.FieldValue.serverTimestamp(),
      lastError: null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {ok: true, eventCount: parsed.events.length};
  } catch (e) {
    const code = e instanceof FeedError ? e.code : ERR.UNREACHABLE;
    logger.warn("calendarFeeds: aggiornamento fallito", {path: ref.path, code, err: e.message});
    await ref.update({
      lastFetchAt: admin.firestore.FieldValue.serverTimestamp(),
      lastError: code,
    }).catch(() => {});
    return {ok: false, code};
  }
}

/**
 * Aggiunge o modifica un calendario iscritto. In creazione il feed si scarica
 * subito, così chi incolla un link sbagliato lo sa adesso e non tra sei ore.
 * data: {familyId, feedId?, name, url?, colorHex?}
 */
exports.saveCalendarFeed = onCall(
    {region: REGION, maxInstances: 10, invoker: "public", timeoutSeconds: 60, memory: "512MiB"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      const {familyId, feedId, name, url, colorHex} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }
      await assertMember(familyId, uid);

      const cleanName = String(name || "").trim().slice(0, 60);
      const color = COLOR_RE.test(String(colorHex || "")) ? colorHex : "#5B8DEF";
      const feeds = admin.firestore().collection("families").doc(familyId).collection("calendarFeeds");

      // Modifica di nome e colore: niente download.
      if (feedId) {
        if (typeof feedId !== "string") throw new HttpsError("invalid-argument", "feedId non valido.");
        const ref = feeds.doc(feedId);
        const snap = await ref.get();
        if (!snap.exists) throw new HttpsError("not-found", "Calendario non trovato.");
        const update = {colorHex: color, updatedAt: admin.firestore.FieldValue.serverTimestamp()};
        if (cleanName) update.name = cleanName;
        await ref.update(update);
        return {feedId, eventCount: snap.data().eventCount || 0};
      }

      let normalized;
      try {
        normalized = normalizeUrl(url);
      } catch (e) {
        throw new HttpsError("invalid-argument", "URL non valido.", {reason: ERR.INVALID_URL});
      }
      const count = (await feeds.count().get()).data().count;
      if (count >= MAX_FEEDS_PER_FAMILY) {
        throw new HttpsError("resource-exhausted", "Troppi calendari.", {reason: ERR.TOO_MANY});
      }

      let res;
      let parsed;
      try {
        res = await download(normalized);
        parsed = parseIcs(res.text);
      } catch (e) {
        const reason = e instanceof FeedError ? e.code : ERR.UNREACHABLE;
        logger.info("saveCalendarFeed: feed rifiutato", {familyId, reason, err: e.message});
        throw new HttpsError("failed-precondition", "Calendario non leggibile.", {reason});
      }

      const ref = feeds.doc();
      await ref.set({
        name: cleanName || parsed.calendarName || normalized.hostname,
        url: normalized.toString(),
        colorHex: color,
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastFetchAt: admin.firestore.FieldValue.serverTimestamp(),
        lastError: null,
        etag: res.etag || null,
        lastModified: res.lastModified || null,
        events: parsed.events,
        eventCount: parsed.events.length,
        truncated: parsed.truncated,
      });
      logger.info("saveCalendarFeed: iscritto", {familyId, feedId: ref.id, events: parsed.events.length});
      return {feedId: ref.id, eventCount: parsed.events.length};
    },
);

/** Toglie un calendario iscritto per tutta la famiglia. data: {familyId, feedId} */
exports.deleteCalendarFeed = onCall(
    {region: REGION, maxInstances: 10, invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      const {familyId, feedId} = request.data || {};
      if (!familyId || !feedId || typeof familyId !== "string" || typeof feedId !== "string") {
        throw new HttpsError("invalid-argument", "familyId e feedId richiesti.");
      }
      await assertMember(familyId, uid);
      await admin.firestore().collection("families").doc(familyId)
          .collection("calendarFeeds").doc(feedId).delete();
      return {ok: true};
    },
);

/**
 * Rilegge tutti i feed ogni sei ore. Con ETag/Last-Modified un feed che non
 * è cambiato costa una richiesta HTTP e un aggiornamento di `lastFetchAt`.
 */
exports.refreshCalendarFeeds = onSchedule(
    {schedule: "every 6 hours", region: REGION, timeoutSeconds: 540, memory: "512MiB"},
    async () => {
      const snap = await admin.firestore().collectionGroup("calendarFeeds").get();
      let ok = 0;
      let failed = 0;
      // Pochi alla volta: sono richieste verso siti di scuole e società
      // sportive, non serve martellarli.
      const docs = snap.docs;
      for (let i = 0; i < docs.length; i += 5) {
        const results = await Promise.all(
            docs.slice(i, i + 5).map((d) => refreshFeed(d.ref, d.data())));
        results.forEach((r) => (r.ok ? ok++ : failed++));
      }
      logger.info("refreshCalendarFeeds", {feeds: docs.length, ok, failed});
    },
);

// Per i test.
exports._internal = {normalizeUrl, isForbiddenIp, parseIcs, wallClockToEpoch, ERR};
