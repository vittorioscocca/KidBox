/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// FARMACIE DI TURNO — turni pubblicati come IMMAGINE o come PDF.
//
// Molti enti (ASL, Comuni, Ordini) caricano ogni mese una tabella come PNG o
// come PDF: non c'è testo né regola CSS che tenga. Qui l'AI legge il documento
// (le immagini con la vista, i PDF come documento: anche quelli scansionati), ma
// SOLO quando il contenuto cambia (impronta dei file nel documento
// `pharmacy_sources`): di solito una volta al mese e per tutte le famiglie che
// leggono quella fonte. Il resto dei giorni il codice riusa i turni già letti.
//
// Una regola `vision` dice dove prendere i file: `self` (l'indirizzo stesso è
// un PDF o un'immagine), `imageSelector` (immagini dentro la pagina),
// `linkSelector` (link a PDF o immagini nella pagina).
// L'estrazione dà intervalli («dal 04 ott al 10 ott: Farmacia X») e qui si
// espandono in un turno per giorno.
// ─────────────────────────────────────────────────────────────────────────────

const crypto = require("node:crypto");
const {parse} = require("node-html-parser");
const {estimateCostUsd, MODEL_SONNET} = require("../news/search");
const {download} = require("./fetch");
const {addDays, clean, plausible} = require("./rules");

const MAX_DOCS = 3;
const MAX_IMAGE_BYTES = 4 * 1024 * 1024;
const MAX_PDF_BYTES = 8 * 1024 * 1024;
/** Un PDF più lungo di così non è un elenco di turni (e costerebbe troppo da leggere). */
const MAX_PDF_PAGES = 25;
const MAX_SPAN_DAYS = 62;
const MAX_ENTRIES = 3000;

const SYSTEM = `Leggi tabelle di turni di farmacie italiane da uno o più documenti (immagini o PDF) e trasformale in JSON.
Rispondi SOLO con <kidbox_shifts>{"comune":"…","entries":[{"from":"YYYY-MM-DD","to":"YYYY-MM-DD","name":"Farmacia …","address":"…","phone":"","service":"notturno|pomeridiano|festivo|pomeridiano e festivo|h24|altro"}]}</kidbox_shifts>.
Regole:
- Ogni riga della tabella è UNA voce, con le date di inizio e fine così come scritte («DAL 04 OTT. AL 10 OTT.»). Se una riga ha una sola data, from = to.
- Le date non hanno l'anno: usa quello giusto in base alla data di oggi che ti do e a un eventuale titolo nell'immagine (es. «Ottobre 2026»). Un periodo a cavallo fra due mesi o due anni resta continuo.
- «service» è il titolo della tabella (SERVIZIO NOTTURNO, SERVIZIO POMERIDIANO E FESTIVO, …) o quello del contesto.
- name: il nome della farmacia come scritto, in forma leggibile («FARM. MANNA FEDERICO» → «Farmacia Manna Federico»). address: via o rione come scritto; se manca, "". phone: solo se è scritto.
- «comune»: il comune a cui si riferiscono i turni (dal titolo, dal contesto o dall'indirizzo). Se non si capisce, "".
- Non inventare righe, date o indirizzi. Se un documento non contiene turni (o è di un altro comune o di un altro periodo), non inventare: restituisci per esso nessuna voce.`;

/**
 * @param {string} s
 * @return {string} etichetta del servizio, in forma fissa (i client la traducono)
 */
function serviceKind(s) {
  const t = String(s || "").toLowerCase();
  if (/nott/.test(t)) return "night";
  if (/pomerid/.test(t) && /festiv/.test(t)) return "afternoon_holiday";
  if (/pomerid/.test(t)) return "afternoon";
  if (/festiv/.test(t)) return "holiday";
  if (/24/.test(t)) return "h24";
  return "";
}

/**
 * Pagine del PDF, contate dagli oggetti «/Type /Page». Con i PDF compressi in
 * flussi di oggetti può dare 0: in quel caso conta solo il limite in byte.
 * @param {Buffer} buf
 * @return {number}
 */
function countPdfPages(buf) {
  return (buf.toString("latin1").match(/\/Type\s*\/Page(?![s\w])/g) || []).length;
}

/**
 * Raccoglie i documenti da leggere: la pagina stessa se è un PDF o un'immagine,
 * oppure i file indicati dalla regola dentro la pagina.
 * @param {{self?: boolean, imageSelector?: string, linkSelector?: string}} rule
 * @param {{kind: string, text: string, buffer: Buffer, mediaType: string, finalUrl: string}} page
 * @return {Promise<{docs: {kind: string, mediaType: string, data: Buffer, url: string}[], hash: string, reason: string}>}
 */
async function fetchMedia(rule, page) {
  const docs = [];
  let reason = "";
  const accept = (kind, mediaType, data, url) => {
    if (kind === "pdf") {
      if (data.length > MAX_PDF_BYTES) {
        reason = "too-large";
        return;
      }
      if (countPdfPages(data) > MAX_PDF_PAGES) {
        reason = "too-many-pages";
        return;
      }
    } else if (data.length > MAX_IMAGE_BYTES) {
      reason = "too-large";
      return;
    }
    docs.push({kind, mediaType, data, url});
  };

  if (page.kind !== "text") {
    accept(page.kind, page.mediaType, page.buffer, page.finalUrl);
  } else {
    const root = parse(page.text);
    const urls = [];
    const add = (raw) => {
      if (!raw || raw.startsWith("data:") || raw.startsWith("#") || /^(mailto|tel|javascript):/i.test(raw)) return;
      try {
        const abs = new URL(raw, page.finalUrl).toString();
        if (!urls.includes(abs)) urls.push(abs);
      } catch (_) {/* indirizzo non valido: si salta */}
    };
    if (rule.imageSelector) {
      for (const el of root.querySelectorAll(rule.imageSelector)) add(el.getAttribute("src") || el.getAttribute("data-src") || "");
    }
    if (rule.linkSelector) {
      for (const el of root.querySelectorAll(rule.linkSelector)) add(el.getAttribute("href") || "");
    }
    for (const url of urls.slice(0, MAX_DOCS + 2)) {
      if (docs.length >= MAX_DOCS) break;
      let r;
      try {
        r = await download(url, {maxBytes: MAX_PDF_BYTES, accept: "application/pdf, image/*;q=0.9, */*;q=0.1"});
      } catch (e) {
        reason = reason || e.code || "unreachable";
        continue;
      }
      // Un link che porta a un'altra pagina web non è un documento: si salta.
      if (r.kind === "pdf" || r.kind === "image") accept(r.kind, r.mediaType, r.buffer, r.finalUrl);
    }
  }
  const hash = crypto.createHash("sha1");
  for (const d of docs) hash.update(d.data);
  return {docs, hash: hash.digest("hex"), reason: docs.length ? "" : reason || "no-documents"};
}

/**
 * @param {{apiKey: string, docs: {kind: string, mediaType: string, data: Buffer}[], place: object, todayKey: string}} o
 * @return {Promise<{entries: object[], comune: string, costUsd: number}>}
 */
async function readDocs(o) {
  const fetchNode = (await import("node-fetch")).default;
  const content = [];
  for (const doc of o.docs) {
    content.push({
      type: doc.kind === "pdf" ? "document" : "image",
      source: {type: "base64", media_type: doc.mediaType, data: doc.data.toString("base64")},
    });
  }
  content.push({type: "text", text: `Oggi è ${o.todayKey}. Zona dell'utente: ${o.place?.city || "?"}${o.place?.province ? ` (${o.place.province})` : ""}. Estrai i turni.`});
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 120_000);
  let body;
  try {
    const res = await fetchNode("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal: controller.signal,
      headers: {"Content-Type": "application/json", "x-api-key": o.apiKey, "anthropic-version": "2023-06-01"},
      body: JSON.stringify({
        model: MODEL_SONNET,
        max_tokens: 8000,
        system: SYSTEM,
        messages: [{role: "user", content}],
        output_config: {effort: "low"},
      }),
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`Anthropic ${res.status}: ${text.slice(0, 300)}`);
    body = JSON.parse(text);
  } finally {
    clearTimeout(timer);
  }
  const reply = (body.content || []).filter((b) => b?.type === "text").map((b) => b.text).join("");
  const costUsd = estimateCostUsd(body.usage || {}, MODEL_SONNET);
  const open = reply.lastIndexOf("<kidbox_shifts>");
  const close = reply.indexOf("</kidbox_shifts>", open);
  if (open < 0) return {entries: [], comune: "", costUsd};
  let raw = reply.slice(open + "<kidbox_shifts>".length, close < 0 ? undefined : close).trim();
  raw = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "").trim();
  let json;
  try {
    json = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1));
  } catch (_) {
    return {entries: [], comune: "", costUsd};
  }
  return {entries: expand(json.entries, clean(json.comune, 60)), comune: clean(json.comune, 60), costUsd};
}

/**
 * Da intervalli a un turno per giorno.
 * @param {*} list
 * @param {string} comune
 * @return {object[]}
 */
function expand(list, comune) {
  const out = [];
  const seen = new Set();
  for (const e of Array.isArray(list) ? list : []) {
    const from = String(e?.from || "");
    const to = String(e?.to || e?.from || "");
    const name = clean(e?.name, 100);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to) || !name || from > to) continue;
    const span = Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);
    if (span > MAX_SPAN_DAYS) continue;
    const service = serviceKind(e?.service);
    for (let i = 0; i <= span && out.length < MAX_ENTRIES; i++) {
      const date = addDays(from, i);
      const id = `${date}|${name}|${service}`;
      if (seen.has(id)) continue;
      seen.add(id);
      const entry = {date, name, comune, address: clean(e?.address, 120), phone: clean(e?.phone, 24).replace(/[^+\d\s./-]/g, "").trim()};
      if (service) entry.service = service;
      out.push(entry);
    }
  }
  return out;
}

/**
 * Prende i documenti, li legge (se servono) e controlla che il risultato sia plausibile.
 * @param {{rule: object, page: object, apiKey: string, place: object, todayKey: string, knownHash?: string}} o
 * @return {Promise<{entries: ?object[], hash: string, unchanged: boolean, costUsd: number, reason: string, comune?: string}>}
 *   `unchanged`: i documenti sono gli stessi dell'ultima lettura, non si è speso nulla
 */
async function readFromPage(o) {
  const {docs, hash, reason} = await fetchMedia(o.rule, o.page);
  if (!docs.length) return {entries: null, hash, unchanged: false, costUsd: 0, reason};
  if (o.knownHash && o.knownHash === hash) return {entries: null, hash, unchanged: true, costUsd: 0, reason: ""};
  const read = await readDocs({apiKey: o.apiKey, docs, place: o.place, todayKey: o.todayKey});
  const check = plausible(read.entries, o.todayKey);
  return {
    entries: check.ok ? read.entries : null,
    hash,
    unchanged: false,
    costUsd: read.costUsd,
    reason: check.ok ? "" : check.reason,
    comune: read.comune,
  };
}

module.exports = {readFromPage, expand, serviceKind, _test: {fetchMedia, countPdfPages}};
