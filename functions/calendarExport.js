/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// CALENDARIO DI KIDBOX IN GOOGLE, OUTLOOK E APPLE (link iCal in uscita)
//
// Il contrario di calendarFeeds.js: lì KidBox si iscrive ai calendari degli
// altri, qui Google Calendar, Outlook o il Calendario di Apple si iscrivono a
// quello di KidBox. Ognuno ha il SUO link segreto, non uno di famiglia: gli
// eventi hanno una visibilità (tutta la famiglia, alcuni membri, solo io) e il
// link mostra solo quelli che la persona vede nell'app.
//
// Documento `calendarExports/{uid}_{familyId}`, scritto e letto SOLO da qui (in
// cima alle rules nessuno scrive fuori da quanto elencato, e la lettura è degli
// admin):
//   uid, familyId, token, tz, createdAt, lastFetchAt
//
// Il link è `https://kidboxapp.com/cal/{token}.ics` (rewrite dell'hosting della
// landing verso `calendarExportFeed`). Chi lo conosce legge il calendario,
// nomi dei figli compresi: per questo si rigenera (il vecchio smette subito di
// funzionare) e smette da solo quando la persona non è più membro della
// famiglia, e la risposta non passa dalla cache della CDN.
//
// Sola lettura e aggiornamento lento: Google rilegge un calendario iscritto
// quando vuole lui, in genere ogni 12-24 ore, e non si può forzare. I client
// lo dicono vicino al pulsante.
//
// Gli orari escono nel fuso di chi ha creato il link (`tz`, mandato dal
// telefono o dal browser) con il suo VTIMEZONE: una ripetizione settimanale
// delle 17 resta alle 17 anche dopo il cambio dell'ora legale, come nell'app.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {logger} = require("firebase-functions");

const REGION = "europe-west1";
const PUBLIC_BASE = "https://kidboxapp.com/cal/";
const DEFAULT_TZ = "Europe/Rome";
/** Gli eventi singoli finiti da più di così restano fuori dal file. */
const PAST_DAYS = 120;
/** `lastFetchAt` si scrive al massimo una volta all'ora, non a ogni lettura. */
const FETCH_STAMP_MS = 60 * 60 * 1000;
const TOKEN_RE = /^[A-Za-z0-9_-]{32}$/;

const db = () => admin.firestore();
const exportRef = (uid, familyId) => db().collection("calendarExports").doc(`${uid}_${familyId}`);

/**
 * @param {string} tz nome IANA
 * @return {boolean} true se Intl lo conosce
 */
function validTz(tz) {
  if (typeof tz !== "string" || !tz || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-US", {timeZone: tz});
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * @param {object|null} d documento membro
 * @return {boolean} stesso criterio di `isActiveMember` in index.js e di `isMember` nelle rules
 */
function isActiveMember(d) {
  return !!d && d.isDeleted !== true && typeof d.role === "string" && d.role.trim() !== "";
}

/**
 * Specchio di `isVisibleTo` della web app e di `KBVisibilityScope` su iOS.
 * @param {object} e evento
 * @param {string} uid lettore
 * @return {boolean} true se il lettore vede l'evento
 */
function isVisibleTo(e, uid) {
  const scope = e.visibilityScope;
  if (scope === "members") return e.createdBy === uid || (e.visibilityMemberIds || []).includes(uid);
  if (scope === "private") return e.createdBy === uid;
  return true;
}

// ── Date nel fuso ───────────────────────────────────────────────────────────

/**
 * Ora da orologio di un istante in un fuso.
 * @param {number} ms istante
 * @param {string} tz fuso
 * @return {{y:number,m:number,d:number,h:number,mi:number,s:number}} componenti locali
 */
function localParts(ms, tz) {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const p = {};
  for (const x of f.formatToParts(new Date(ms))) p[x.type] = x.value;
  return {y: +p.year, m: +p.month, d: +p.day, h: +p.hour, mi: +p.minute, s: +p.second};
}

/**
 * @param {number} ms istante
 * @param {string} tz fuso
 * @return {number} scarto in minuti del fuso in quell'istante (Roma d'estate: 120)
 */
function offsetMinutes(ms, tz) {
  const p = localParts(ms, tz);
  return Math.round((Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s) - Math.floor(ms / 1000) * 1000) / 60000);
}

const pad = (n, w = 2) => String(n).padStart(w, "0");
const fmtDate = (p) => `${pad(p.y, 4)}${pad(p.m)}${pad(p.d)}`;
const fmtLocal = (p) => `${fmtDate(p)}T${pad(p.h)}${pad(p.mi)}${pad(p.s)}`;
const fmtUtc = (ms) => new Date(ms).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");

/**
 * Giorno di calendario + n giorni.
 * @param {{y:number,m:number,d:number}} p data
 * @param {number} n giorni
 * @return {{y:number,m:number,d:number}} data spostata
 */
function addDays(p, n) {
  const t = new Date(Date.UTC(p.y, p.m - 1, p.d + n));
  return {y: t.getUTCFullYear(), m: t.getUTCMonth() + 1, d: t.getUTCDate()};
}

/**
 * VTIMEZONE del fuso, dalle due transizioni dell'anno corrente (bastano a
 * Google, Outlook e Apple: la regola si ripete). Il giorno della transizione
 * diventa una regola «n-esima / ultima domenica del mese».
 * @param {string} tz fuso
 * @param {number} nowMs adesso
 * @return {string[]} righe del blocco
 */
function vtimezone(tz, nowMs) {
  const year = new Date(nowMs).getUTCFullYear();
  const start = Date.UTC(year, 0, 1);
  const end = Date.UTC(year + 1, 0, 1);
  const hour = 3600 * 1000;
  const transitions = [];
  let prev = offsetMinutes(start, tz);
  for (let t = start + hour; t <= end; t += hour) {
    const cur = offsetMinutes(t, tz);
    if (cur !== prev) {
      transitions.push({at: t, from: prev, to: cur});
      prev = cur;
    }
  }
  const fmtOff = (m) => `${m < 0 ? "-" : "+"}${pad(Math.floor(Math.abs(m) / 60))}${pad(Math.abs(m) % 60)}`;
  const lines = ["BEGIN:VTIMEZONE", `TZID:${tz}`];
  if (transitions.length < 2) {
    const off = fmtOff(offsetMinutes(nowMs, tz));
    lines.push("BEGIN:STANDARD", "DTSTART:19700101T000000", `TZOFFSETFROM:${off}`, `TZOFFSETTO:${off}`, "END:STANDARD");
  } else {
    const days = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];
    for (const tr of transitions.slice(0, 2)) {
      // Ora da orologio PRIMA del salto, con lo scarto vecchio (02:00 a marzo,
      // 03:00 a ottobre in Europa).
      const w = new Date(tr.at + tr.from * 60000);
      const p = {y: w.getUTCFullYear(), m: w.getUTCMonth() + 1, d: w.getUTCDate()};
      const local = {...p, h: w.getUTCHours(), mi: w.getUTCMinutes(), s: 0};
      const dow = new Date(Date.UTC(p.y, p.m - 1, p.d)).getUTCDay();
      const lastOfMonth = new Date(Date.UTC(p.y, p.m, 0)).getUTCDate();
      const nth = p.d + 7 > lastOfMonth ? -1 : Math.ceil(p.d / 7);
      const kind = tr.to > tr.from ? "DAYLIGHT" : "STANDARD";
      lines.push(`BEGIN:${kind}`, `DTSTART:${fmtLocal({...local, y: 1970})}`,
          `TZOFFSETFROM:${fmtOff(tr.from)}`, `TZOFFSETTO:${fmtOff(tr.to)}`,
          `RRULE:FREQ=YEARLY;BYMONTH=${p.m};BYDAY=${nth}${days[dow]}`, `END:${kind}`);
    }
  }
  lines.push("END:VTIMEZONE");
  return lines;
}

// ── Testo iCal ──────────────────────────────────────────────────────────────

/**
 * @param {*} s testo libero
 * @return {string} testo con le sequenze di escape del formato
 */
function esc(s) {
  return String(s ?? "").replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
}

/**
 * Piega una riga a 75 byte UTF-8, senza spezzare un carattere.
 * @param {string} line riga
 * @return {string} riga piegata con CRLF + spazio
 */
function fold(line) {
  const out = [];
  let cur = "";
  let bytes = 0;
  for (const ch of line) {
    const b = Buffer.byteLength(ch);
    if (bytes + b > (out.length ? 74 : 75)) {
      out.push(cur);
      cur = "";
      bytes = 0;
    }
    cur += ch;
    bytes += b;
  }
  out.push(cur);
  return out.join("\r\n ");
}

/**
 * Le cinque ricorrenze di KidBox in RRULE. Nei client il 31 cade l'ultimo
 * giorno dei mesi corti e il 29 febbraio il 28: il 31 diventa «ultimo giorno
 * del mese» (BYMONTHDAY=-1), il 29 febbraio «ultimo giorno di febbraio». Il
 * 29 e il 30 del mese restano senza il giro di febbraio: la forma esatta
 * (BYSETPOS) non la leggono bene tutti i calendari, ical.js compreso.
 * @param {string} raw recurrenceRaw
 * @param {{m:number,d:number}} p giorno d'inizio, locale
 * @return {string|null} riga RRULE o null
 */
function rrule(raw, p) {
  switch (raw) {
    case "daily": return "RRULE:FREQ=DAILY";
    case "weekly": return "RRULE:FREQ=WEEKLY";
    case "monthly":
      return p.d === 31 ? "RRULE:FREQ=MONTHLY;BYMONTHDAY=-1" : "RRULE:FREQ=MONTHLY";
    case "yearly":
      if (p.m === 2 && p.d === 29) return "RRULE:FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=-1";
      return "RRULE:FREQ=YEARLY";
    default: return null;
  }
}

const toMs = (v) => (v && typeof v.toMillis === "function" ? v.toMillis() : typeof v === "number" ? v : null);

/**
 * Il file .ics con gli eventi che il lettore vede.
 * @param {{familyName:string, tz:string, events:Array<{id:string, data:object}>, uid:string, nowMs:number}} o dati
 * @return {string} testo iCal
 */
function buildIcs({familyName, tz, events, uid, nowMs}) {
  const name = familyName ? `KidBox · ${familyName}` : "KidBox";
  const lines = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//KidBox//Calendario di famiglia//IT",
    "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    `X-WR-CALNAME:${esc(name)}`, `X-WR-TIMEZONE:${tz}`,
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H",
    ...vtimezone(tz, nowMs),
  ];
  const cutoff = nowMs - PAST_DAYS * 86400000;
  for (const {id, data: e} of events) {
    if (e.isDeleted === true || !isVisibleTo(e, uid)) continue;
    const s = toMs(e.startDate);
    let en = toMs(e.endDate);
    if (s == null) continue;
    if (en == null || en < s) en = s;
    const rec = ["daily", "weekly", "monthly", "yearly"].includes(e.recurrenceRaw) ? e.recurrenceRaw : "none";
    if (rec === "none" && en < cutoff) continue;
    const ps = localParts(s, tz);
    const ev = ["BEGIN:VEVENT", `UID:${id}@kidboxapp.com`, `DTSTAMP:${fmtUtc(toMs(e.updatedAt) || nowMs)}`];
    if (e.isAllDay === true) {
      // Fine esclusa. Le app salvano la fine come mezzanotte del giorno dopo
      // oppure come un orario dentro l'ultimo giorno: entrambe valgono.
      const pe = localParts(en, tz);
      const endIsMidnight = pe.h === 0 && pe.mi === 0 && en > s;
      const endDay = endIsMidnight ? pe : addDays(pe, 1);
      ev.push(`DTSTART;VALUE=DATE:${fmtDate(ps)}`, `DTEND;VALUE=DATE:${fmtDate(endDay)}`);
    } else {
      ev.push(`DTSTART;TZID=${tz}:${fmtLocal(ps)}`, `DTEND;TZID=${tz}:${fmtLocal(localParts(en, tz))}`);
    }
    const rr = rrule(rec, ps);
    if (rr) ev.push(rr);
    ev.push(`SUMMARY:${esc(e.title || "")}`);
    if (e.location) ev.push(`LOCATION:${esc(e.location)}`);
    if (e.notes) ev.push(`DESCRIPTION:${esc(e.notes)}`);
    ev.push("END:VEVENT");
    lines.push(...ev);
  }
  lines.push("END:VCALENDAR");
  return lines.map(fold).join("\r\n") + "\r\n";
}

// ── Callable: crea, mostra, rigenera, spegne ────────────────────────────────

/**
 * `{familyId, action: "get" | "enable" | "rotate" | "disable", tz?}` →
 * `{url: string|null}`. «get» non crea niente; «enable» crea se manca;
 * «rotate» sostituisce il token (il vecchio link muore subito).
 */
exports.calendarExportLink = onCall(
    {region: REGION, maxInstances: 10, invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      const {familyId, action, tz} = request.data || {};
      if (!familyId || typeof familyId !== "string" || familyId.includes("/")) {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }
      if (!["get", "enable", "rotate", "disable"].includes(action)) {
        throw new HttpsError("invalid-argument", "Azione non valida.");
      }
      const member = await db().collection("families").doc(familyId).collection("members").doc(uid).get();
      if (!isActiveMember(member.exists ? member.data() : null)) {
        throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.");
      }
      const ref = exportRef(uid, familyId);
      const snap = await ref.get();
      const urlOf = (token) => `${PUBLIC_BASE}${token}.ics`;

      if (action === "disable") {
        if (snap.exists) await ref.delete();
        return {url: null};
      }
      if (action === "get") {
        return {url: snap.exists ? urlOf(snap.data().token) : null};
      }
      if (action === "enable" && snap.exists) {
        if (validTz(tz) && tz !== snap.data().tz) await ref.update({tz});
        return {url: urlOf(snap.data().token)};
      }
      const token = crypto.randomBytes(24).toString("base64url");
      await ref.set({
        uid, familyId, token,
        tz: validTz(tz) ? tz : (snap.exists && snap.data().tz) || DEFAULT_TZ,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastFetchAt: null,
      });
      logger.info("calendarExport link", {uid, familyId, action});
      return {url: urlOf(token)};
    },
);

// ── HTTP: il file che leggono Google, Outlook e Apple ───────────────────────

exports.calendarExportFeed = onRequest(
    // Non 128MiB: il processo carica tutto index.js (vedi inviteLanding).
    {region: REGION, maxInstances: 5, memory: "256MiB", invoker: "public"},
    async (req, res) => {
      if (req.method !== "GET" && req.method !== "HEAD") {
        res.status(405).send("method");
        return;
      }
      res.set("Cache-Control", "private, no-store");
      const m = /\/cal\/([^/.]+)(?:\.ics)?$/.exec(req.path || "");
      const token = m ? m[1] : "";
      if (!TOKEN_RE.test(token)) {
        res.status(404).send("not found");
        return;
      }
      const found = await db().collection("calendarExports").where("token", "==", token).limit(1).get();
      if (found.empty) {
        res.status(404).send("not found");
        return;
      }
      const doc = found.docs[0];
      const {uid, familyId, tz: savedTz, lastFetchAt} = doc.data();
      const famRef = db().collection("families").doc(familyId);
      const [member, fam] = await Promise.all([famRef.collection("members").doc(uid).get(), famRef.get()]);
      if (!fam.exists || !isActiveMember(member.exists ? member.data() : null)) {
        // Uscito dalla famiglia, o famiglia cancellata: il link si spegne da solo.
        await doc.ref.delete().catch(() => {});
        res.status(404).send("not found");
        return;
      }
      const nowMs = Date.now();
      const tz = validTz(savedTz) ? savedTz : DEFAULT_TZ;
      const evSnap = await famRef.collection("calendarEvents").get();
      const ics = buildIcs({
        familyName: fam.data().name || "",
        tz, uid, nowMs,
        events: evSnap.docs.map((d) => ({id: d.id, data: d.data()})),
      });
      if (!lastFetchAt || nowMs - toMs(lastFetchAt) > FETCH_STAMP_MS) {
        await doc.ref.update({lastFetchAt: admin.firestore.FieldValue.serverTimestamp()}).catch(() => {});
      }
      res.set("Content-Type", "text/calendar; charset=utf-8");
      res.set("Content-Disposition", "inline; filename=\"kidbox.ics\"");
      res.status(200).send(req.method === "HEAD" ? "" : ics);
    },
);

// Per i test.
exports._test = {buildIcs, vtimezone, rrule, fold, esc, localParts};
