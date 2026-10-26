/* eslint-disable max-len, no-control-regex */
// ─────────────────────────────────────────────────────────────────────────────
// FARMACIE DI TURNO — le regole di estrazione.
//
// Una «regola» è un piccolo documento JSON che dice al codice come leggere i
// turni da una pagina: dove sono le righe, dove stanno nome, indirizzo,
// telefono, e da dove prendere la data. La scrive a mano chi aggiunge una fonte
// verificata (Lombardia, Torino) oppure la genera una volta l'AI guardando la
// pagina; da lì in poi la applica il codice, ogni giorno, senza costi.
//
// Una regola dell'AI NON si fida: `sanitizeRule` tiene solo i campi noti, e il
// risultato di `applyRule` passa da `plausible` prima di essere mostrato.
//
// Due forme:
//   json  { type, itemsPath, where?, dateField?, fields }
//         itemsPath = percorso a punti verso un array (o un oggetto di oggetti);
//         fields    = nome campo → percorso a punti dentro la riga.
//   html  { type, dayContainerSelector?, dayHeaderSelector?, itemSelector,
//           fields, detailSelector?, detailSeparator?, detailFields? }
//         fields    = nome campo → selettore CSS relativo alla riga, oppure
//                     ":self" (il testo diretto della riga);
//         il dettaglio («Comune — Via X, 4 — 011…») si spezza in campi.
// ─────────────────────────────────────────────────────────────────────────────

const {parse} = require("node-html-parser");

const FIELDS = ["name", "address", "comune", "phone", "lat", "lng"];
const MAX_ENTRIES = 3000;
const MAX_TEXT = 160;

const MONTHS = {
  gen: 1, feb: 2, mar: 3, apr: 4, mag: 5, giu: 6, lug: 7, ago: 8, set: 9, ott: 10, nov: 11, dic: 12,
};

/**
 * @param {*} v
 * @param {number} max
 * @return {string}
 */
function clean(v, max = MAX_TEXT) {
  if (v === null || v === undefined) return "";
  return String(v).replace(/[\u0000-\u001f<>]/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

/**
 * @param {string} key YYYY-MM-DD
 * @param {number} days
 * @return {string} YYYY-MM-DD
 */
function addDays(key, days) {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/**
 * «Lunedi 26 ott — OGGI», «26/10/2026», «lunedì 26 ottobre» → YYYY-MM-DD.
 * Senza anno si prende quello di oggi, o il successivo se la data sarebbe
 * passata da più di 40 giorni (a dicembre un «3 gennaio» è l'anno dopo).
 * @param {string} text
 * @param {string} todayKey YYYY-MM-DD
 * @return {?string}
 */
function parseItalianDate(text, todayKey) {
  const s = String(text || "").toLowerCase();
  let day;
  let month;
  let year = null;
  let m = s.match(/(\d{1,2})[/.-](\d{1,2})(?:[/.-](\d{2,4}))?/);
  if (m) {
    day = Number(m[1]);
    month = Number(m[2]);
    if (m[3]) year = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
  } else {
    m = s.match(/(\d{1,2})\s+([a-zà-ú]{3,})/);
    if (!m) return null;
    day = Number(m[1]);
    month = MONTHS[m[2].slice(0, 3)];
    const y = s.match(/\b(20\d{2})\b/);
    if (y) year = Number(y[1]);
  }
  if (!month || month > 12 || day < 1 || day > 31) return null;
  const pad = (n) => String(n).padStart(2, "0");
  const baseYear = Number(todayKey.slice(0, 4));
  const build = (y) => `${y}-${pad(month)}-${pad(day)}`;
  let key = build(year || baseYear);
  if (!year && key < addDays(todayKey, -40)) key = build(baseYear + 1);
  const check = new Date(`${key}T00:00:00Z`);
  if (Number.isNaN(check.getTime()) || check.getUTCDate() !== day) return null;
  return key;
}

/**
 * @param {*} obj
 * @param {string} path percorso a punti («a.b.c»)
 * @return {*}
 */
function dig(obj, path) {
  if (!path) return obj;
  let cur = obj;
  for (const part of String(path).split(".")) {
    if (cur === null || cur === undefined || typeof cur !== "object") return undefined;
    cur = cur[part];
  }
  return cur;
}

/**
 * @param {*} raw regola grezza (anche generata dall'AI)
 * @return {?object} regola ripulita, o null se non è una regola valida
 */
function sanitizeRule(raw) {
  if (!raw || typeof raw !== "object") return null;
  const sel = (v) => (typeof v === "string" && v.length > 0 && v.length <= 200 && !/[{};]/.test(v) ? v : "");
  const path = (v) => (typeof v === "string" && v.length <= 120 && /^[\w.-]*$/.test(v) ? v : "");
  const fieldsIn = raw.fields && typeof raw.fields === "object" ? raw.fields : {};
  if (raw.type === "json") {
    const fields = {};
    for (const f of FIELDS) {
      const p = path(fieldsIn[f]);
      if (p) fields[f] = p;
    }
    if (!fields.name) return null;
    const rule = {v: 1, type: "json", itemsPath: path(raw.itemsPath), fields};
    if (raw.dateField && path(raw.dateField)) rule.dateField = path(raw.dateField);
    if (raw.where && typeof raw.where === "object") {
      const where = {};
      for (const [k, v] of Object.entries(raw.where).slice(0, 3)) {
        if (path(k) && ["string", "number", "boolean"].includes(typeof v)) where[k] = v;
      }
      if (Object.keys(where).length) rule.where = where;
    }
    return rule;
  }
  if (raw.type === "vision") {
    // Turni pubblicati come immagine o PDF: l'AI li legge quando cambiano (vision.js).
    const rule = {v: 1, type: "vision"};
    if (sel(raw.imageSelector)) rule.imageSelector = sel(raw.imageSelector);
    if (sel(raw.linkSelector)) rule.linkSelector = sel(raw.linkSelector);
    if (raw.self === true) rule.self = true;
    return rule.imageSelector || rule.linkSelector || rule.self ? rule : null;
  }
  if (raw.type === "html") {
    const fields = {};
    for (const f of FIELDS) {
      const s = fieldsIn[f] === ":self" ? ":self" : sel(fieldsIn[f]);
      if (s) fields[f] = s;
    }
    const itemSelector = sel(raw.itemSelector);
    if (!itemSelector || !(fields.name || raw.detailSelector)) return null;
    const rule = {v: 1, type: "html", itemSelector, fields};
    if (sel(raw.dayContainerSelector)) rule.dayContainerSelector = sel(raw.dayContainerSelector);
    if (sel(raw.dayHeaderSelector)) rule.dayHeaderSelector = sel(raw.dayHeaderSelector);
    if (sel(raw.detailSelector)) {
      rule.detailSelector = sel(raw.detailSelector);
      rule.detailSeparator = typeof raw.detailSeparator === "string" && raw.detailSeparator.length <= 6 && raw.detailSeparator ? raw.detailSeparator : " — ";
      rule.detailFields = Array.isArray(raw.detailFields) ?
        raw.detailFields.filter((f) => FIELDS.includes(f)).slice(0, 6) : [];
      if (!rule.detailFields.length) return null;
    }
    return rule;
  }
  return null;
}

/**
 * @param {*} v
 * @return {?number}
 */
function coord(v, limit) {
  const n = typeof v === "number" ? v : Number(String(v || "").replace(",", "."));
  return Number.isFinite(n) && Math.abs(n) <= limit && n !== 0 ? Math.round(n * 1e6) / 1e6 : null;
}

/**
 * @param {object} raw campi grezzi di una riga
 * @param {string} date YYYY-MM-DD
 * @return {?object} voce normalizzata, o null se priva di nome
 */
function toEntry(raw, date) {
  const name = clean(raw.name, 100);
  if (!name) return null;
  const phone = clean(raw.phone, 24).replace(/[^+\d\s./-]/g, "").trim();
  const entry = {date, name, comune: clean(raw.comune, 60), address: clean(raw.address, 120), phone};
  if (raw.service) entry.service = clean(raw.service, 24);
  const lat = coord(raw.lat, 90);
  const lng = coord(raw.lng, 180);
  if (lat !== null && lng !== null) {
    entry.lat = lat;
    entry.lng = lng;
  }
  return entry;
}

/**
 * @param {import("node-html-parser").HTMLElement} el
 * @param {string} selector
 * @return {string}
 */
function htmlText(el, selector) {
  if (selector === ":self") {
    return clean(el.childNodes.filter((n) => n.nodeType === 3).map((n) => n.text).join(" "));
  }
  return clean(el.querySelector(selector)?.text);
}

/**
 * Applica una regola a un documento.
 * @param {object} rule regola già ripulita
 * @param {string} text corpo scaricato
 * @param {string} todayKey YYYY-MM-DD (Europe/Rome)
 * @return {object[]} voci {date, name, comune, address, phone, lat?, lng?}
 */
function applyRule(rule, text, todayKey) {
  // Le regole «vision» non si applicano al testo: le esegue vision.js.
  if (rule.type === "vision") return [];
  const out = [];
  const seen = new Set();
  const push = (raw, date) => {
    if (out.length >= MAX_ENTRIES) return;
    const e = toEntry(raw, date);
    if (!e) return;
    const id = `${e.date}|${e.name}|${e.comune}|${e.address}`.toLowerCase();
    if (seen.has(id)) return;
    seen.add(id);
    out.push(e);
  };

  if (rule.type === "json") {
    let data;
    try {
      data = JSON.parse(text);
    } catch (_) {
      return [];
    }
    let items = dig(data, rule.itemsPath);
    if (items && !Array.isArray(items) && typeof items === "object") items = Object.values(items);
    if (!Array.isArray(items)) return [];
    for (const item of items) {
      if (!item || typeof item !== "object") continue;
      if (rule.where && !Object.entries(rule.where).every(([k, v]) => dig(item, k) === v)) continue;
      const raw = {};
      for (const [f, p] of Object.entries(rule.fields)) raw[f] = dig(item, p);
      let date = todayKey;
      if (rule.dateField) {
        const d = String(dig(item, rule.dateField) || "").slice(0, 10);
        date = /^\d{4}-\d{2}-\d{2}$/.test(d) ? d : parseItalianDate(d, todayKey);
        if (!date) continue;
      }
      push(raw, date);
    }
    return out;
  }

  const root = parse(text, {blockTextElements: {script: false, style: false, noscript: false}});
  const days = rule.dayContainerSelector ? root.querySelectorAll(rule.dayContainerSelector) : [root];
  for (const day of days) {
    let date = todayKey;
    if (rule.dayHeaderSelector) {
      date = parseItalianDate(day.querySelector(rule.dayHeaderSelector)?.text, todayKey);
      if (!date) continue;
    }
    for (const item of day.querySelectorAll(rule.itemSelector)) {
      const raw = {};
      for (const [f, s] of Object.entries(rule.fields)) raw[f] = htmlText(item, s);
      if (rule.detailSelector) {
        const parts = htmlText(item, rule.detailSelector).split(rule.detailSeparator).map((p) => p.trim());
        rule.detailFields.forEach((f, i) => {
          if (parts[i]) raw[f] = parts[i];
        });
      }
      push(raw, date);
    }
  }
  return out;
}

/**
 * Il risultato sembra un elenco di turni vero? Una regola sbagliata (o un sito
 * cambiato) di solito produce zero righe, righe senza indirizzo o date lontane.
 * @param {object[]} entries
 * @param {string} todayKey
 * @return {{ok: boolean, reason: string}}
 */
function plausible(entries, todayKey) {
  if (entries.length < 3) return {ok: false, reason: "poche-righe"};
  const withPlace = entries.filter((e) => e.address || e.comune || e.phone).length;
  if (withPlace / entries.length < 0.6) return {ok: false, reason: "senza-indirizzo"};
  const horizon = addDays(todayKey, 14);
  if (!entries.some((e) => e.date >= addDays(todayKey, -1) && e.date <= horizon)) {
    return {ok: false, reason: "date-fuori-finestra"};
  }
  const names = new Set(entries.map((e) => e.name.toLowerCase()));
  if (names.size < 2) return {ok: false, reason: "nomi-uguali"};
  return {ok: true, reason: ""};
}

module.exports = {sanitizeRule, applyRule, plausible, parseItalianDate, addDays, clean};
