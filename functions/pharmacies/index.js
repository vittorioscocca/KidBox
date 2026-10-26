/* eslint-disable max-len, no-control-regex */
// ─────────────────────────────────────────────────────────────────────────────
// FARMACIE DI TURNO (Pro e Max) — disegno e numeri in internal/farmacie-di-turno.md
//
// Tre idee:
//   1. Il dato viene da una FONTE UFFICIALE (Federfarma, Ordine dei farmacisti,
//      ASL, Comune), mai da un aggregatore presentato come ufficiale.
//   2. Il costo dell'AI si paga UNA volta: l'AI trova la pagina e scrive una
//      REGOLA di estrazione (`rules.js`); da lì il codice rilegge la pagina ogni
//      giorno, senza AI. Se la regola smette di funzionare il dato si nasconde
//      e resta il link alla fonte.
//   3. L'utente può SEMPRE indicare a mano il sito da usare, a prescindere da
//      quello che ha trovato l'AI. Quel sito vale solo per la sua famiglia: non
//      diventa mai la fonte condivisa di una zona (un link sbagliato
//      contaminerebbe tutti).
//
// Collezioni, tutte solo-server (le rules non le aprono):
//   pharmacy_sources/{key}   la fonte: url, regola, affidabilità, prossimo giro
//   pharmacy_shifts/{key}    i turni letti l'ultima volta (solo da oggi in poi)
//   pharmacy_family/{fid}    scelta manuale, tentativi del giorno
//   pharmacy_usage/{day}     spesa AI del giorno, per il tetto globale
// `key` = «lombardia», «torino» (fonti incluse nel codice), `IT_regione_citta`
// (trovate dall'AI, condivise) o `manual_{familyId}` (scelte dall'utente).
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const P = require("../news/prompts");
const {searchWithClaude, estimateCostUsd, MODEL_SONNET} = require("../news/search");
const {download, parseUrl, FetchError} = require("./fetch");
const {sanitizeRule, applyRule, plausible, addDays} = require("./rules");
const {BUILTIN_SOURCES} = require("./builtin");
const vision = require("./vision");

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const REGION = "europe-west1";
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const TZ = "Europe/Rome";
const MAX_STORED_ENTRIES = 1800;
const MAX_OTHERS = 40;
const UPCOMING_DAYS = 7;
/** Una fonte che nessuno legge da più di così non si rilegge più. */
const IDLE_MS = 7 * DAY_MS;

const DEFAULTS = {
  enabled: true,
  usdPerMessage: 0.02,
  /** Tetto di spesa AI al giorno per tutta la funzione: oltre, niente nuove ricerche. */
  dailyBudgetUsd: 3,
  /** Stime prenotate prima di spendere, poi conguagliate sul costo vero. */
  discoveryEstimateUsd: 0.2,
  ruleEstimateUsd: 0.1,
  maxUnitsDiscovery: 10,
  maxUnitsRule: 6,
  discoveryMaxUses: 5,
  /** Tentativi AI al giorno per famiglia (ricerca + sito indicato a mano). */
  maxAttemptsPerDay: 4,
};
const CONFIG_TTL_MS = 60 * 1000;
let configCache = {at: 0, cfg: null};

/**
 * @param {*} v
 * @param {number} max
 * @return {string}
 */
function text(v, max = 80) {
  return typeof v === "string" ? v.replace(/[\u0000-\u001f]/g, " ").trim().slice(0, max) : "";
}

/**
 * @param {string} s
 * @return {string} minuscole, senza accenti né punteggiatura
 */
function norm(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "");
}

/**
 * @param {*} raw
 * @return {?{countryCode: string, region: string, province: string, city: string}}
 */
function parsePlace(raw) {
  if (!raw || typeof raw !== "object") return null;
  const countryCode = text(raw.countryCode, 2).toUpperCase();
  if (!/^[A-Z]{2}$/.test(countryCode)) return null;
  return {countryCode, region: text(raw.region, 60), province: text(raw.province, 60), city: text(raw.city, 60)};
}

/**
 * @param {Date} [now]
 * @return {string} YYYY-MM-DD a Roma
 */
function todayKeyRome(now = new Date()) {
  return now.toLocaleDateString("sv-SE", {timeZone: TZ});
}

/**
 * @param {number} usd
 * @param {typeof DEFAULTS} cfg
 * @param {number} cap
 * @return {number} messaggi AI
 */
function unitsFor(usd, cfg, cap) {
  return Math.min(cap, Math.max(1, Math.round((Number(usd) || 0) / cfg.usdPerMessage)));
}

/**
 * @param {string} url
 * @return {string} host senza «www.»
 */
function hostOf(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "").toLowerCase();
  } catch (_) {
    return "";
  }
}

// ── Claude senza ricerca ─────────────────────────────────────────────────────

/**
 * Una chiamata a Messages, senza strumenti.
 * @param {{apiKey: string, system: string, user: string, maxTokens?: number}} o
 * @return {Promise<{text: string, usage: object}>}
 */
async function callClaude(o) {
  const fetch = (await import("node-fetch")).default;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 90_000);
  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal: controller.signal,
      headers: {"Content-Type": "application/json", "x-api-key": o.apiKey, "anthropic-version": "2023-06-01"},
      body: JSON.stringify({
        model: MODEL_SONNET,
        max_tokens: o.maxTokens || 2500,
        system: o.system,
        messages: [{role: "user", content: o.user}],
        output_config: {effort: "low"},
      }),
    });
    const body = await res.text();
    if (!res.ok) throw new Error(`Anthropic ${res.status}: ${body.slice(0, 300)}`);
    const json = JSON.parse(body);
    return {
      text: (json.content || []).filter((b) => b?.type === "text").map((b) => b.text).join(""),
      usage: json.usage || {},
    };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @param {string} raw testo della risposta
 * @param {string} tag
 * @return {?object}
 */
function taggedJson(raw, tag) {
  const open = raw.lastIndexOf(`<${tag}>`);
  if (open < 0) return null;
  const close = raw.indexOf(`</${tag}>`, open);
  let body = raw.slice(open + tag.length + 2, close < 0 ? undefined : close).trim();
  body = body.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
  const a = body.indexOf("{");
  const b = body.lastIndexOf("}");
  if (a < 0 || b <= a) return null;
  try {
    return JSON.parse(body.slice(a, b + 1));
  } catch (_) {
    return null;
  }
}

/**
 * Una versione compatta della pagina, buona per un prompt: niente script, stili
 * né attributi tranne classi e id, che sono ciò che serve a scrivere i selettori.
 * @param {string} body
 * @param {string} contentType
 * @return {string}
 */
function skeleton(body, contentType) {
  const looksJson = /json/i.test(contentType) || /^\s*[[{]/.test(body);
  if (looksJson) return body.slice(0, 14000);
  const s = body
      .replace(/<!--[\s\S]*?-->/g, "")
      .replace(/<(script|style|svg|noscript|head|iframe|template)\b[\s\S]*?<\/\1>/gi, "")
      .replace(/\s(?!class=|id=|alt=|src=)[a-zA-Z_:][\w:.-]*="[^"]*"/g, "")
      .replace(/\s(?!class=|id=|alt=|src=)[a-zA-Z_:][\w:.-]*='[^']*'/g, "")
      .replace(/\s+/g, " ");
  return s.slice(0, 60000);
}

const RULE_SYSTEM = `Sei un tecnico che scrive regole per leggere elenchi di farmacie di turno italiane da una pagina web.
Ti do il codice semplificato di UNA pagina e devi rispondere con una regola JSON, dentro <kidbox_rule>…</kidbox_rule>, senza altro testo.

Forme ammesse:
HTML: {"type":"html","dayContainerSelector":"CSS del blocco di UN giorno (opzionale)","dayHeaderSelector":"CSS, relativo al blocco, dell'intestazione con la data del giorno (opzionale)","itemSelector":"CSS di UNA farmacia","fields":{"name":"CSS relativo alla riga oppure \\":self\\" per il testo diretto","address":"…","comune":"…","phone":"…"},"detailSelector":"CSS di un elemento unico con più dati separati (opzionale)","detailSeparator":" — ","detailFields":["comune","address","phone"]}
JSON: {"type":"json","itemsPath":"percorso.a.punti.verso.l'array","where":{"campo":valore},"dateField":"campo con la data (opzionale)","fields":{"name":"campo","address":"campo","comune":"campo","phone":"campo","lat":"campo","lng":"campo"}}

VISIONE: {"type":"vision","imageSelector":"CSS delle <img> che contengono le tabelle dei turni"}
  Usala quando nel codice non c'è l'elenco in testo ma ci sono immagini (alt o nome file tipo «Turni Farmacie Ottobre 2026») che sembrano le tabelle dei turni: le leggerà l'AI con la vista.

Regole:
- Usa SOLO selettori che compaiono nel codice che ti do. Non inventare classi.
- Vanno estratte le farmacie DI TURNO (notturno, festivo, h24): se la pagina ha anche l'elenco generale, scegli la parte dei turni.
- Se la pagina ha più giorni, indica dayContainerSelector e dayHeaderSelector così le date si leggono; se è solo «oggi», ometti entrambi.
- Se i turni NON sono nel codice (PDF, immagine, caricati da script, mappa) rispondi {"unreadable":true,"reason":"…"}.`;

/**
 * Chiede all'AI una regola per una pagina e la prova. Un solo tentativo di
 * correzione, con il motivo del fallimento.
 * @param {{apiKey: string, url: string, place: object, body: string, contentType: string, todayKey: string}} o
 * @return {Promise<{rule: ?object, entries: object[], costUsd: number, reason: string, imageHash?: string}>}
 */
async function generateRule(o) {
  const page = skeleton(o.body, o.contentType);
  let costUsd = 0;
  let feedback = "";
  for (let attempt = 0; attempt < 2; attempt++) {
    const reply = await callClaude({
      apiKey: o.apiKey,
      system: RULE_SYSTEM,
      user: `Zona: ${o.place.city || "?"} (${o.place.province || o.place.region || "Italia"}). Pagina: ${o.url}\nOggi: ${o.todayKey}.${feedback}\n\n<pagina>\n${page}\n</pagina>`,
    });
    costUsd += estimateCostUsd(reply.usage, MODEL_SONNET);
    const json = taggedJson(reply.text, "kidbox_rule");
    if (!json) return {rule: null, entries: [], costUsd, reason: "no-rule"};
    if (json.unreadable) return {rule: null, entries: [], costUsd, reason: text(json.reason, 160) || "unreadable"};
    const rule = sanitizeRule(json);
    if (!rule) {
      feedback = "\nLa regola precedente non era valida: rispetta esattamente le forme ammesse.";
      continue;
    }
    if (rule.type === "vision") {
      try {
        const v = await vision.readFromPage({rule, pageHtml: o.body, pageUrl: o.url, apiKey: o.apiKey, place: o.place, todayKey: o.todayKey});
        costUsd += v.costUsd;
        if (v.entries) return {rule, entries: v.entries, costUsd, reason: "", imageHash: v.hash};
        return {rule: null, entries: [], costUsd, reason: v.reason || "vision-failed"};
      } catch (e) {
        return {rule: null, entries: [], costUsd, reason: "vision-error"};
      }
    }
    const entries = applyRule(rule, o.body, o.todayKey);
    const check = plausible(entries, o.todayKey);
    if (check.ok) return {rule, entries, costUsd, reason: ""};
    feedback = `\nLa regola precedente ha prodotto ${entries.length} righe e non è plausibile (${check.reason}). Correggila.`;
  }
  return {rule: null, entries: [], costUsd, reason: "rule-failed"};
}

// ── Il modulo ────────────────────────────────────────────────────────────────

/**
 * @param {{assertFamilyMember: Function, resolveAIQuota: Function, checkAndIncrementAIUsage: Function, refundAIUsage: Function}} deps
 * @return {object}
 */
function build(deps) {
  const db = () => admin.firestore();

  /**
   * Parametri da `config/pharmacies`, con i default come rete di sicurezza.
   * @return {Promise<typeof DEFAULTS>}
   */
  async function loadConfig() {
    if (configCache.cfg && Date.now() - configCache.at < CONFIG_TTL_MS) return configCache.cfg;
    const cfg = {...DEFAULTS};
    try {
      const snap = await db().doc("config/pharmacies").get();
      for (const k of Object.keys(DEFAULTS)) {
        const v = snap.get(k);
        if (typeof v === typeof DEFAULTS[k] && (typeof v !== "number" || Number.isFinite(v))) cfg[k] = v;
      }
    } catch (e) {
      logger.warn("pharmacies: config non letta", {error: e.message});
    }
    configCache = {at: Date.now(), cfg};
    return cfg;
  }

  /**
   * Login, famiglia, interruttore e piano: il Free non ha le farmacie di turno
   * (trappola di /gating-pro: `isAIAccessible` non è il piano, qui si guarda
   * la quota `lifetime`).
   * @param {object} request
   * @return {Promise<{uid: string, familyId: string, quota: object, cfg: typeof DEFAULTS}>}
   */
  async function gate(request) {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
    const familyId = typeof request.data?.familyId === "string" ? request.data.familyId : "";
    if (!ID_RE.test(familyId)) throw new HttpsError("invalid-argument", "familyId non valido.");
    const cfg = await loadConfig();
    if (!cfg.enabled) throw new HttpsError("failed-precondition", "Le farmacie di turno sono sospese.", {reason: "pharmacies-disabled"});
    await deps.assertFamilyMember(uid, familyId);
    const quota = await deps.resolveAIQuota(uid, familyId);
    if (quota.period === "lifetime") {
      throw new HttpsError("permission-denied", "Le farmacie di turno sono incluse nei piani Pro e Max.", {reason: "plan"});
    }
    return {uid, familyId, quota, cfg};
  }

  /**
   * Il luogo della famiglia (lo stesso delle Notizie) o quello del telefono.
   * @param {string} familyId
   * @param {object} d
   * @return {Promise<?object>}
   */
  async function placeFor(familyId, d) {
    const snap = await db().doc(`families/${familyId}/news/settings`).get();
    return parsePlace(snap.get("place")) || parsePlace(d.place);
  }

  const sourceRef = (key) => db().collection("pharmacy_sources").doc(key);
  const shiftsRef = (key) => db().collection("pharmacy_shifts").doc(key);
  const familyRef = (fid) => db().collection("pharmacy_family").doc(fid);

  /**
   * @param {object} place
   * @return {string} chiave della fonte condivisa trovata dall'AI per quel comune
   */
  function placeKey(place) {
    return `${place.countryCode}_${norm(place.region || place.province) || "x"}_${norm(place.city) || "x"}`.slice(0, 120);
  }

  /**
   * La fonte con la regola aggiornata dal codice, se è una di quelle incluse.
   * @param {string} key
   * @return {Promise<?object>}
   */
  async function getSource(key) {
    const builtin = BUILTIN_SOURCES.find((b) => b.key === key);
    const snap = await sourceRef(key).get();
    if (builtin) {
      return {
        ...(snap.exists ? snap.data() : {}),
        key, kind: "builtin", label: builtin.label, url: builtin.url, pageUrl: builtin.pageUrl,
        rule: builtin.rule, coverage: builtin.coverage, confidence: "verified", refreshHours: builtin.refreshHours,
        status: snap.get("status") || "ok",
      };
    }
    return snap.exists ? snap.data() : null;
  }

  /**
   * @param {object} src
   * @param {string} todayKey
   * @param {object[]} entries
   * @return {number} millisecondi del prossimo rilievo
   */
  function nextFetchMs(src, todayKey, entries) {
    const last = entries.reduce((m, e) => (e.date > m ? e.date : m), todayKey);
    const ahead = Math.round((Date.parse(`${last}T00:00:00Z`) - Date.parse(`${todayKey}T00:00:00Z`)) / DAY_MS);
    const hours = src.refreshHours || (ahead <= 1 ? 3 : ahead <= 3 ? 12 : 24);
    return Date.now() + hours * HOUR_MS;
  }

  /**
   * Rilegge una fonte col codice (nessuna AI). Un fallimento non cancella i
   * turni già salvati: restano fino a quando non scadono per data.
   * @param {string} key
   * @return {Promise<{ok: boolean, reason?: string}>}
   */
  async function refreshSource(key, opts = {}) {
    const src = await getSource(key);
    if (!src?.rule || !src.url) return {ok: false, reason: "no-rule"};
    const todayKey = todayKeyRome();
    const fail = async (reason) => {
      const failures = (src.failures || 0) + 1;
      await sourceRef(key).set({
        ...(src.kind === "builtin" ? {key, kind: "builtin"} : {}),
        failures, lastError: reason, lastErrorAtMs: Date.now(),
        status: failures >= 3 ? "error" : src.status || "ok",
        nextFetchAtMs: Date.now() + 6 * HOUR_MS,
      }, {merge: true});
      logger.warn("pharmacies: lettura fallita", {key, reason, failures});
      return {ok: false, reason};
    };
    let page;
    try {
      page = await download(src.url);
    } catch (e) {
      return fail(e instanceof FetchError ? e.code : String(e.message || e).slice(0, 80));
    }
    const rule = sanitizeRule(src.rule);
    if (!rule) return fail("bad-rule");
    if (rule.type === "vision") return refreshVision(key, src, rule, page, todayKey, fail, opts);
    const entries = applyRule(rule, page.text, todayKey).filter((e) => e.date >= addDays(todayKey, -1));
    const check = plausible(entries, todayKey);
    if (!check.ok) return fail(check.reason);
    entries.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
    const kept = entries.slice(0, MAX_STORED_ENTRIES);
    const hash = crypto.createHash("sha1").update(JSON.stringify(kept)).digest("hex");
    await Promise.all([
      shiftsRef(key).set({
        entries: kept, fetchedAtMs: Date.now(), url: src.url, label: src.label, contentHash: hash,
        coverageEnd: kept[kept.length - 1].date,
      }),
      sourceRef(key).set({
        ...(src.kind === "builtin" ? {key, kind: "builtin"} : {}),
        status: "ok", failures: 0, lastError: null, lastOkAtMs: Date.now(),
        nextFetchAtMs: nextFetchMs(src, todayKey, kept),
      }, {merge: true}),
    ]);
    return {ok: true};
  }

  /**
   * Fonti con i turni in immagine: la pagina si scarica sempre, ma l'AI legge le
   * immagini solo se sono cambiate (impronta). Senza chiave (chiamata di
   * lettura) o oltre il tetto di spesa non si fa nulla: restano i turni già letti.
   * @param {string} key
   * @param {object} src
   * @param {object} rule
   * @param {{text: string, finalUrl: string}} page
   * @param {string} todayKey
   * @param {Function} fail
   * @param {{allowAI?: boolean}} opts
   * @return {Promise<{ok: boolean, reason?: string}>}
   */
  async function refreshVision(key, src, rule, page, todayKey, fail, opts) {
    if (!opts.allowAI) return {ok: false, reason: "vision-needs-ai"};
    const cfg = await loadConfig();
    if (await overBudget(todayKey, cfg)) {
      await sourceRef(key).set({nextFetchAtMs: Date.now() + 6 * HOUR_MS}, {merge: true});
      return {ok: false, reason: "budget"};
    }
    let v;
    try {
      v = await vision.readFromPage({
        rule, pageHtml: page.text, pageUrl: page.finalUrl, apiKey: ANTHROPIC_API_KEY.value(),
        place: src.place || {}, todayKey, knownHash: src.imageHash,
      });
    } catch (e) {
      return fail(e instanceof FetchError ? e.code : String(e.message || e).slice(0, 80));
    }
    if (v.costUsd) await recordSpend(todayKey, "vision", v.costUsd, 0);
    const next = Date.now() + 12 * HOUR_MS;
    if (v.unchanged) {
      await Promise.all([
        shiftsRef(key).set({fetchedAtMs: Date.now()}, {merge: true}),
        sourceRef(key).set({status: "ok", failures: 0, lastError: null, lastOkAtMs: Date.now(), nextFetchAtMs: next}, {merge: true}),
      ]);
      return {ok: true};
    }
    if (!v.entries) return fail(v.reason || "vision-failed");
    const entries = v.entries.filter((e) => e.date >= addDays(todayKey, -1)).sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0)).slice(0, MAX_STORED_ENTRIES);
    if (!entries.length) return fail("date-fuori-finestra");
    await Promise.all([
      shiftsRef(key).set({
        entries, fetchedAtMs: Date.now(), url: src.url, label: src.label, coverageEnd: entries[entries.length - 1].date, contentHash: v.hash,
      }),
      sourceRef(key).set({
        status: "ok", failures: 0, lastError: null, lastOkAtMs: Date.now(), nextFetchAtMs: next, imageHash: v.hash,
      }, {merge: true}),
    ]);
    return {ok: true};
  }

  /**
   * Legge i turni salvati e, se mancano o sono vecchi, li rilegge subito.
   * @param {string} key
   * @param {boolean} touch segna la fonte come «letta» (tiene vivo l'aggiornamento)
   * @return {Promise<?object>} {fetchedAtMs, entries} o null
   */
  async function loadShifts(key, touch) {
    let snap = await shiftsRef(key).get();
    const age = snap.exists ? Date.now() - (snap.get("fetchedAtMs") || 0) : Infinity;
    if (age > 6 * HOUR_MS && (await getSource(key))?.rule?.type !== "vision") {
      await refreshSource(key).catch((e) => logger.warn("pharmacies: refresh in lettura", {key, error: e.message}));
      snap = await shiftsRef(key).get();
    }
    if (touch) {
      await sourceRef(key).set({lastReadAtMs: Date.now(), ...(BUILTIN_SOURCES.some((b) => b.key === key) ? {key, kind: "builtin"} : {})}, {merge: true}).catch(() => {});
    }
    return snap.exists ? snap.data() : null;
  }

  /**
   * Quale fonte serve questa famiglia: la sua (manuale), poi quelle incluse nel
   * codice che coprono il comune, poi quella trovata dall'AI per quel comune.
   * @param {string} familyId
   * @param {object} place
   * @param {object} fam documento `pharmacy_family`
   * @return {Promise<?{key: string, src: object, shifts: ?object}>}
   */
  async function resolveSource(familyId, place, fam) {
    if (fam.manual?.url) {
      const key = `manual_${familyId}`;
      const src = await getSource(key);
      if (src) return {key, src, shifts: src.rule ? await loadShifts(key, true) : null};
    }
    const region = norm(place.region);
    const province = norm(place.province);
    for (const b of BUILTIN_SOURCES) {
      const inRegion = b.regionMatch.test(region) || b.regionMatch.test(province);
      const inProvince = !!b.provinceMatch && b.provinceMatch.test(province);
      if (!inRegion && !inProvince) continue;
      if (b.provinceMatch && province && !inProvince) continue;
      const shifts = await loadShifts(b.key, true);
      if (!shifts) continue;
      if (b.coverage === "listed" && !shifts.entries.some((e) => norm(e.comune) === norm(place.city))) continue;
      return {key: b.key, src: await getSource(b.key), shifts};
    }
    const key = placeKey(place);
    const src = await getSource(key);
    if (src) return {key, src, shifts: src.rule ? await loadShifts(key, true) : null};
    return null;
  }

  /**
   * @param {object} shifts
   * @param {object} place
   * @param {string} todayKey
   * @param {?{lat: number, lng: number}} here
   * @return {object}
   */
  function viewOf(shifts, place, todayKey, here) {
    const city = norm(place.city);
    const horizon = addDays(todayKey, UPCOMING_DAYS);
    const entries = (shifts?.entries || []).filter((e) => e.date >= todayKey && e.date <= horizon);
    const mine = entries.filter((e) => city && norm(e.comune) === city);
    const others = entries.filter((e) => e.date === todayKey && !(city && norm(e.comune) === city));
    if (here) {
      const d2 = (e) => (e.lat === undefined ? Infinity : (e.lat - here.lat) ** 2 + (e.lng - here.lng) ** 2);
      others.sort((a, b) => d2(a) - d2(b));
    }
    const upcoming = {};
    for (const e of mine) if (e.date > todayKey) (upcoming[e.date] ||= []).push(e);
    return {
      dateKey: todayKey,
      today: mine.filter((e) => e.date === todayKey),
      upcoming: Object.entries(upcoming).map(([date, items]) => ({date, items})),
      others: others.slice(0, MAX_OTHERS),
      hasToday: entries.some((e) => e.date === todayKey),
    };
  }

  /**
   * @param {?object} src
   * @param {?object} shifts
   * @param {object} fam
   * @return {object} come il client descrive la fonte
   */
  function describeSource(src, shifts, fam) {
    return {
      kind: src.kind,
      label: src.label || hostOf(src.url),
      url: src.pageUrl || src.url,
      confidence: src.confidence,
      fetchedAtMs: shifts?.fetchedAtMs || null,
      readable: !!src.rule,
      manual: src.kind === "manual",
      lastError: src.status === "error" ? src.lastError || "error" : null,
      hasManual: !!fam.manual?.url,
    };
  }

  // ── Spesa e tentativi ───────────────────────────────────────────────────────

  /**
   * @param {string} dateKey
   * @param {typeof DEFAULTS} cfg
   * @return {Promise<boolean>}
   */
  async function overBudget(dateKey, cfg) {
    const snap = await db().collection("pharmacy_usage").doc(dateKey).get();
    return (snap.get("costUsd") || 0) >= cfg.dailyBudgetUsd;
  }

  /**
   * @param {string} dateKey
   * @param {string} kind
   * @param {number} costUsd
   * @param {number} searches
   * @return {Promise<void>}
   */
  async function recordSpend(dateKey, kind, costUsd, searches) {
    const inc = admin.firestore.FieldValue.increment;
    const monthKey = dateKey.slice(0, 7);
    await Promise.all([
      db().collection("pharmacy_usage").doc(dateKey).set({
        costUsd: inc(costUsd), searches: inc(searches), runs: inc(1),
        byKind: {[kind]: inc(costUsd)}, updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}),
      db().collection("ai_costs").doc(monthKey).set({
        calls: inc(1), costUsd: inc(costUsd), pharmacyCostUsd: inc(costUsd), pharmacySearches: inc(searches),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true}),
    ]).catch((e) => logger.warn("pharmacies: registrazione spesa fallita", {error: e.message}));
  }

  /**
   * Conta un tentativo AI della famiglia; oltre il tetto giornaliero rifiuta.
   * @param {string} familyId
   * @param {string} dateKey
   * @param {typeof DEFAULTS} cfg
   * @return {Promise<void>}
   */
  async function takeAttempt(familyId, dateKey, cfg) {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(familyRef(familyId));
      const a = snap.get("attempts");
      const n = a?.dateKey === dateKey ? a.n : 0;
      if (n >= cfg.maxAttemptsPerDay) {
        throw new HttpsError("resource-exhausted", "Hai già provato diverse volte oggi: riprova domani.", {reason: "pharmacies-attempts"});
      }
      tx.set(familyRef(familyId), {attempts: {dateKey, n: n + 1}}, {merge: true});
    });
  }

  /**
   * Prenota una stima di messaggi AI; la restituisce se la famiglia non può pagarla.
   * @param {object} ctx {uid, familyId, quota}
   * @param {number} units
   * @return {Promise<void>}
   */
  async function reserve(ctx, units) {
    await deps.checkAndIncrementAIUsage(ctx.familyId, ctx.uid, ctx.quota, units).catch((e) => {
      if (e instanceof HttpsError && e.code === "resource-exhausted") {
        throw new HttpsError("resource-exhausted", e.message, {...(e.details || {}), pharmacies: true, units});
      }
      throw e;
    });
  }

  /**
   * Conguaglia fra la stima prenotata e il costo vero.
   * @param {object} ctx
   * @param {number} reserved
   * @param {number} used
   * @return {Promise<void>}
   */
  async function settle(ctx, reserved, used) {
    if (used < reserved) {
      await deps.refundAIUsage(ctx.familyId, ctx.uid, ctx.quota, reserved - used);
    } else if (used > reserved) {
      await deps.checkAndIncrementAIUsage(ctx.familyId, ctx.uid, ctx.quota, used - reserved).catch(() => {});
    }
  }

  // ── getPharmacies ───────────────────────────────────────────────────────────

  const getPharmacies = onCall(
      {region: REGION, maxInstances: 20, invoker: "public", timeoutSeconds: 60},
      async (request) => {
        const {familyId, cfg} = await gate(request);
        const d = request.data || {};
        const place = await placeFor(familyId, d);
        const estimate = {
          find: unitsFor(cfg.discoveryEstimateUsd + cfg.ruleEstimateUsd, cfg, cfg.maxUnitsDiscovery + cfg.maxUnitsRule),
          manual: unitsFor(cfg.ruleEstimateUsd, cfg, cfg.maxUnitsRule),
        };
        if (!place || !place.city) return {status: "no-place", estimate};
        if (place.countryCode !== "IT") return {status: "unsupported", estimate};

        const famSnap = await familyRef(familyId).get();
        const fam = famSnap.exists ? famSnap.data() : {};
        const resolved = await resolveSource(familyId, place, fam);
        if (!resolved) return {status: "none", place: {city: place.city}, estimate, hasManual: false};

        const {src, shifts} = resolved;
        const here = Number.isFinite(d.lat) && Number.isFinite(d.lng) ? {lat: d.lat, lng: d.lng} : null;
        const source = describeSource(src, shifts, fam);
        if (!src.rule) return {status: "unreadable", source, estimate};
        const todayKey = todayKeyRome();
        const view = viewOf(shifts, place, todayKey, here);
        // Nessun turno per oggi in tutta la fonte = la fonte è ferma: niente
        // elenco (potrebbe essere di ieri), solo il link.
        const status = !shifts || !view.hasToday ? "stale" : "ready";
        logger.info("getPharmacies", {familyId, key: resolved.key, status, today: view.today.length, others: view.others.length});
        return {status, source, estimate, place: {city: place.city}, ...(status === "ready" ? view : {dateKey: todayKey, today: [], upcoming: [], others: []})};
      },
  );

  // ── findPharmacySource (AI) ─────────────────────────────────────────────────

  const DISCOVERY_SYSTEM = `Cerchi la pagina UFFICIALE con le farmacie di turno di una zona italiana.
Fonti ammesse, in ordine di preferenza: Federfarma (provinciale o regionale), Ordine dei farmacisti della provincia, ASL/ATS/AUSL, sito del Comune o della Regione.
NON sono fonti ufficiali: portali che raccolgono turni di tutta Italia (torrinomedica, farmaciediturno.org, paginegialle, siti di notizie, blog). Se non trovi di meglio puoi proporne uno, ma devi dire official=false.
Preferisci una pagina che mostra i turni in HTML o JSON; un PDF va bene solo se è l'unica opzione (dillo in "format").
Rispondi SOLO con <kidbox_news>{"url":"https://…","label":"nome dell'ente","official":true|false,"confidence":"high|medium|low","format":"html|json|pdf|other","note":"una riga"}</kidbox_news>. Se non trovi nulla: {"url":null}.
L'url deve essere uno dei risultati della ricerca, mai inventato.`;

  const findPharmacySource = onCall(
      {region: REGION, maxInstances: 10, invoker: "public", timeoutSeconds: 300, secrets: [ANTHROPIC_API_KEY]},
      async (request) => {
        const ctx = await gate(request);
        const {familyId, cfg} = ctx;
        const place = await placeFor(familyId, request.data || {});
        if (!place?.city) throw new HttpsError("invalid-argument", "Manca il comune.", {reason: "no-place"});
        if (place.countryCode !== "IT") throw new HttpsError("failed-precondition", "Per ora solo in Italia.", {reason: "unsupported"});
        const todayKey = todayKeyRome();

        const key = placeKey(place);
        const existing = await getSource(key);
        // Una fonte illeggibile si riprova dopo una settimana: i siti cambiano.
        const retryable = existing?.status === "error" ||
          (existing?.status === "unreadable" && Date.now() - (existing.createdAtMs || 0) > 7 * DAY_MS);
        if (existing && !retryable) return {status: "exists"};
        if (await overBudget(todayKey, cfg)) {
          throw new HttpsError("resource-exhausted", "Le ricerche di oggi sono finite: riprova domani.", {reason: "pharmacies-budget"});
        }
        await takeAttempt(familyId, todayKey, cfg);
        const reserved = unitsFor(cfg.discoveryEstimateUsd + cfg.ruleEstimateUsd, cfg, cfg.maxUnitsDiscovery + cfg.maxUnitsRule);
        await reserve(ctx, reserved);

        let cost = 0;
        let searches = 0;
        try {
          const userLocation = {type: "approximate", country: "IT", city: place.city, timezone: TZ};
          if (place.region) userLocation.region = place.region;
          const r = await searchWithClaude({
            apiKey: ANTHROPIC_API_KEY.value(),
            model: MODEL_SONNET,
            system: DISCOVERY_SYSTEM,
            user: `Comune: ${place.city}${place.province ? ` (provincia di ${place.province})` : ""}${place.region ? `, ${place.region}` : ""}. Oggi: ${todayKey}. Trova dove si pubblicano i turni delle farmacie.`,
            maxUses: cfg.discoveryMaxUses,
            effort: "low",
            userLocation,
            maxTokens: 3000,
            timeoutMs: 120000,
            deadline: Date.now() + 140000,
          });
          cost += estimateCostUsd(r.usage, r.model);
          searches = r.usage.web_search_requests;
          const found = r.refusal ? null : P.extractTaggedJson(P.replyText(r.blocks));
          const allowed = P.collectSearchUrls(r.blocks);
          const norm1 = found?.url ? P.normalizeUrl(found.url) : null;
          if (!found?.url || !norm1 || !allowed.has(norm1)) {
            await recordSpend(todayKey, "discovery", cost, searches);
            await settle(ctx, reserved, unitsFor(cost, cfg, reserved));
            return {status: "not-found"};
          }
          const url = allowed.get(norm1);
          let page;
          try {
            page = await download(url);
          } catch (e) {
            page = null;
            logger.warn("pharmacies: pagina trovata ma non scaricabile", {url, error: e.message});
          }
          let rule = null;
          let entries = [];
          let imageHash = null;
          if (page && found.format !== "pdf") {
            const g = await generateRule({apiKey: ANTHROPIC_API_KEY.value(), url, place, body: page.text, contentType: page.contentType, todayKey});
            cost += g.costUsd;
            rule = g.rule;
            entries = g.entries;
            imageHash = g.imageHash || null;
          }
          const official = found.official === true;
          const high = found.confidence === "high";
          const confidence = rule && official && high ? "ai" : "uncertain";
          await sourceRef(key).set({
            key, kind: "ai", label: text(found.label, 80) || hostOf(url), url, pageUrl: url, urlHost: hostOf(url),
            rule: rule || null, imageHash: imageHash || null, place: {city: place.city, province: place.province, region: place.region},
            confidence, official, aiConfidence: text(found.confidence, 8), format: text(found.format, 8),
            coverage: "listed", placeKey: key, status: rule ? "ok" : "unreadable", failures: 0,
            createdAtMs: Date.now(), lastReadAtMs: Date.now(), nextFetchAtMs: Date.now() + (rule ? 3 * HOUR_MS : 30 * DAY_MS),
          });
          if (rule) {
            entries.sort((a, b) => (a.date < b.date ? -1 : 1));
            await shiftsRef(key).set({
              entries: entries.slice(0, MAX_STORED_ENTRIES), fetchedAtMs: Date.now(), url, label: text(found.label, 80),
              coverageEnd: entries[entries.length - 1].date,
            });
          }
          await recordSpend(todayKey, "discovery", cost, searches);
          await settle(ctx, reserved, unitsFor(cost, cfg, reserved));
          logger.info("findPharmacySource", {familyId, key, url, confidence, readable: !!rule, cost});
          return {status: rule ? "found" : "unreadable", confidence};
        } catch (e) {
          await recordSpend(todayKey, "discovery", cost, searches);
          await deps.refundAIUsage(familyId, ctx.uid, ctx.quota, reserved).catch(() => {});
          if (e instanceof HttpsError) throw e;
          logger.error("pharmacies: ricerca fonte fallita", {familyId, error: e.message});
          throw new HttpsError("unavailable", "La ricerca non è riuscita. Riprova fra poco.");
        }
      },
  );

  // ── setPharmacySource (a mano) ──────────────────────────────────────────────

  const setPharmacySource = onCall(
      {region: REGION, maxInstances: 10, invoker: "public", timeoutSeconds: 180, secrets: [ANTHROPIC_API_KEY]},
      async (request) => {
        const ctx = await gate(request);
        const {familyId, cfg} = ctx;
        const d = request.data || {};
        const key = `manual_${familyId}`;

        // Togliere la scelta manuale: si torna alla fonte automatica.
        if (d.url === null || d.url === "") {
          await Promise.all([
            familyRef(familyId).set({manual: admin.firestore.FieldValue.delete()}, {merge: true}),
            sourceRef(key).delete(),
            shiftsRef(key).delete(),
          ]);
          return {status: "cleared"};
        }

        let parsed;
        try {
          parsed = parseUrl(d.url);
        } catch (_) {
          throw new HttpsError("invalid-argument", "Questo non sembra un indirizzo web.", {reason: "invalid-url"});
        }
        const url = parsed.toString();
        const place = (await placeFor(familyId, d)) || {countryCode: "IT", region: "", province: "", city: ""};
        const todayKey = todayKeyRome();

        let page;
        try {
          page = await download(url);
        } catch (e) {
          const reason = e instanceof FetchError ? e.code : "unreachable";
          throw new HttpsError("failed-precondition", "Non riesco ad aprire questo sito.", {reason});
        }

        // Prima le regole già note per lo stesso sito: nessun costo.
        let rule = null;
        let entries = [];
        const host = hostOf(url);
        const known = await db().collection("pharmacy_sources").where("urlHost", "==", host).limit(5).get();
        const candidates = [
          ...BUILTIN_SOURCES.filter((b) => hostOf(b.url) === host || hostOf(b.pageUrl) === host).map((b) => b.rule),
          ...known.docs.filter((doc) => doc.get("status") === "ok").map((doc) => doc.get("rule")),
        ];
        for (const candidate of candidates) {
          const r = sanitizeRule(candidate);
          if (!r) continue;
          const e = applyRule(r, page.text, todayKey);
          if (plausible(e, todayKey).ok) {
            rule = r;
            entries = e;
            break;
          }
        }
        let costNote = 0;
        let imageHash = null;
        if (!rule) {
          if (await overBudget(todayKey, cfg)) {
            throw new HttpsError("resource-exhausted", "Le letture di oggi sono finite: riprova domani.", {reason: "pharmacies-budget"});
          }
          await takeAttempt(familyId, todayKey, cfg);
          const reserved = unitsFor(cfg.ruleEstimateUsd, cfg, cfg.maxUnitsRule);
          await reserve(ctx, reserved);
          let g;
          try {
            g = await generateRule({apiKey: ANTHROPIC_API_KEY.value(), url, place, body: page.text, contentType: page.contentType, todayKey});
          } catch (e) {
            await deps.refundAIUsage(familyId, ctx.uid, ctx.quota, reserved).catch(() => {});
            logger.error("pharmacies: regola fallita", {familyId, error: e.message});
            throw new HttpsError("unavailable", "Non sono riuscito a leggere il sito. Riprova fra poco.");
          }
          await recordSpend(todayKey, "rule", g.costUsd, 0);
          await settle(ctx, reserved, unitsFor(g.costUsd, cfg, reserved));
          rule = g.rule;
          entries = g.entries;
          imageHash = g.imageHash || null;
          costNote = g.costUsd;
        }

        const readable = !!rule;
        await Promise.all([
          sourceRef(key).set({
            key, kind: "manual", familyId, label: host, url, pageUrl: url, urlHost: host, rule: rule || null,
            imageHash, place: {city: place.city, province: place.province, region: place.region},
            confidence: "manual", coverage: "listed", status: readable ? "ok" : "unreadable", failures: 0,
            createdAtMs: Date.now(), lastReadAtMs: Date.now(), nextFetchAtMs: Date.now() + (readable ? 3 * HOUR_MS : 30 * DAY_MS),
          }),
          familyRef(familyId).set({manual: {url, setAtMs: Date.now()}}, {merge: true}),
          readable ?
            shiftsRef(key).set({
              entries: entries.sort((a, b) => (a.date < b.date ? -1 : 1)).slice(0, MAX_STORED_ENTRIES),
              fetchedAtMs: Date.now(), url, label: host, coverageEnd: entries[entries.length - 1].date,
            }) : shiftsRef(key).delete(),
        ]);
        logger.info("setPharmacySource", {familyId, host, readable, cost: costNote});
        return {status: readable ? "ok" : "unreadable"};
      },
  );

  // ── refreshPharmacyShifts (ogni ora, senza AI) ──────────────────────────────

  const refreshPharmacyShifts = onSchedule(
      {region: REGION, schedule: "every 60 minutes", timeZone: TZ, maxInstances: 1, timeoutSeconds: 540, memory: "512MiB", secrets: [ANTHROPIC_API_KEY]},
      async () => {
        const deadline = Date.now() + 480_000;
        const due = await db().collection("pharmacy_sources").where("nextFetchAtMs", "<=", Date.now()).limit(80).get();
        let done = 0;
        let failed = 0;
        for (const doc of due.docs) {
          if (Date.now() > deadline) break;
          if (Date.now() - (doc.get("lastReadAtMs") || 0) > IDLE_MS) continue;
          const r = await refreshSource(doc.id, {allowAI: true}).catch((e) => ({ok: false, reason: e.message}));
          if (r.ok) done++;
          else failed++;
        }
        logger.info("refreshPharmacyShifts", {due: due.size, done, failed});
      },
  );

  return {getPharmacies, findPharmacySource, setPharmacySource, refreshPharmacyShifts};
}

module.exports = {build, _internal: {norm, skeleton}};
