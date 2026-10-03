/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// NOTIZIE — una chiamata a Claude con la ricerca web, fino alla risposta finale.
//
// Niente SDK, come il resto del backend: `fetch` sull'endpoint Messages.
//
// Due cose che la ricerca web fa diversamente da una chat normale:
//   - il ciclo delle ricerche gira sul server di Anthropic e dopo 10 iterazioni
//     si ferma con `stop_reason: "pause_turn"`: per continuare si rimanda il
//     turno dell'assistente così com'è, senza aggiungere un «continua»;
//   - gli errori della ricerca (quota, query troppo lunga…) non sono errori
//     HTTP: arrivano come 200 con un blocco `web_search_tool_result` che
//     contiene un oggetto d'errore invece della lista dei risultati.
// ─────────────────────────────────────────────────────────────────────────────

const API_URL = "https://api.anthropic.com/v1/messages";

/** Sonnet per scegliere e verificare le notizie; il filtro dinamico c'è solo dai 4.6 in su. */
const MODEL_SONNET = "claude-sonnet-5-5";
const MODEL_HAIKU = "claude-haiku-4-5";

/** $ per milione di token, e per ricerca ($10 ogni 1.000). */
const PRICES = {
  [MODEL_SONNET]: {input: 2.0, output: 10.0, cacheWrite: 2.5, cacheRead: 0.2},
  [MODEL_HAIKU]: {input: 1.0, output: 5.0, cacheWrite: 1.25, cacheRead: 0.1},
};
const USD_PER_SEARCH = 0.01;

/** Riprese dopo `pause_turn`: oltre, si tiene quello che c'è. */
const MAX_CONTINUATIONS = 3;

/**
 * Il costo stimato di una generazione, ricerche comprese.
 * @param {{input_tokens?: number, output_tokens?: number, cache_creation_input_tokens?: number, cache_read_input_tokens?: number, web_search_requests?: number}} usage
 * @param {string} model
 * @return {number} dollari
 */
function estimateCostUsd(usage, model) {
  const p = PRICES[model] || PRICES[MODEL_SONNET];
  const tokens = ((usage.input_tokens || 0) * p.input +
    (usage.output_tokens || 0) * p.output +
    (usage.cache_creation_input_tokens || 0) * p.cacheWrite +
    (usage.cache_read_input_tokens || 0) * p.cacheRead) / 1e6;
  return tokens + (usage.web_search_requests || 0) * USD_PER_SEARCH;
}

/**
 * La definizione dello strumento per quel modello.
 * @param {string} model
 * @param {number} maxUses
 * @param {object|null} userLocation
 * @return {object}
 */
function webSearchTool(model, maxUses, userLocation) {
  const dynamic = !model.startsWith("claude-haiku");
  const tool = {
    type: dynamic ? "web_search_20260318" : "web_search_20250305",
    name: "web_search",
    max_uses: maxUses,
  };
  if (userLocation) tool.user_location = userLocation;
  return tool;
}

/**
 * Una generazione con ricerca web.
 * @param {{apiKey: string, model?: string, system: string, user: string, maxUses: number, userLocation?: object|null, effort?: string, maxTokens?: number, timeoutMs?: number, deadline?: number, cache?: boolean}} o
 * @return {Promise<{blocks: object[], usage: object, stopReason: string, refusal: object|null, model: string, calls: number, ms: number, searchErrors: string[]}>}
 */
async function searchWithClaude(o) {
  const fetch = (await import("node-fetch")).default;
  const model = o.model || MODEL_SONNET;
  const headers = {
    "Content-Type": "application/json",
    "x-api-key": o.apiKey,
    "anthropic-version": "2023-06-01",
  };
  const body = {
    model,
    max_tokens: o.maxTokens || 16000,
    system: o.system,
    messages: [{role: "user", content: o.user}],
    tools: [webSearchTool(model, o.maxUses, o.userLocation || null)],
  };
  if (o.cache !== false) {
    // Il ciclo delle ricerche rilegge tutto il contesto a ogni passo: senza
    // cache ogni passo lo paga per intero (misurato: 140.000 token in input
    // per un'edizione di 12 ricerche).
    body.cache_control = {type: "ephemeral"};
  }
  if (!model.startsWith("claude-haiku")) {
    // Sonnet 5.5 non accetta `thinking: disabled`: lo spessore si regola con
    // l'effort. «medium» basta a scegliere e verificare; «high» costa il doppio.
    body.output_config = {effort: o.effort || "medium"};
    // Un rifiuto dei classificatori torna come 200 con `stop_reason: "refusal"`:
    // con «default» il server riprova da sé sul modello indicato per quella
    // categoria. Per le notizie è un'assicurazione, non un caso atteso.
    body.fallbacks = "default";
    headers["anthropic-beta"] = "server-side-fallback-2026-07-01";
  }

  const started = Date.now();
  const blocks = [];
  const usage = {input_tokens: 0, output_tokens: 0, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, web_search_requests: 0};
  let stopReason = "";
  let refusal = null;
  let servedBy = model;
  let calls = 0;
  let messages = body.messages;

  let tools = body.tools;
  for (let attempt = 0; attempt <= MAX_CONTINUATIONS; attempt++) {
    const left = o.deadline ? o.deadline - Date.now() : Infinity;
    // Una ripresa senza il tempo per finire pagherebbe ricerche da buttare.
    if (attempt > 0 && left < 45000) break;
    calls++;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(o.timeoutMs || 200000, left));
    let res;
    try {
      res = await fetch(API_URL, {
        method: "POST",
        headers,
        body: JSON.stringify({...body, tools, messages}),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
    const text = await res.text();
    if (res.status === 400 && /user_location|country/i.test(text) && tools[0].user_location) {
      // Un paese che la ricerca non supporta è un 400 su tutta la richiesta:
      // meglio cercare senza localizzazione che non cercare.
      tools = [{...tools[0]}];
      delete tools[0].user_location;
      attempt--;
      continue;
    }
    if (!res.ok) {
      const err = new Error(`Anthropic ${res.status}: ${text.slice(0, 400)}`);
      err.status = res.status;
      throw err;
    }
    const json = JSON.parse(text);
    const content = Array.isArray(json.content) ? json.content : [];
    blocks.push(...content);
    const u = json.usage || {};
    usage.input_tokens += u.input_tokens || 0;
    usage.output_tokens += u.output_tokens || 0;
    usage.cache_creation_input_tokens += u.cache_creation_input_tokens || 0;
    usage.cache_read_input_tokens += u.cache_read_input_tokens || 0;
    usage.web_search_requests += u.server_tool_use?.web_search_requests || 0;
    stopReason = json.stop_reason || "";
    servedBy = json.model || servedBy;
    if (stopReason === "refusal") {
      refusal = json.stop_details || {type: "refusal"};
      break;
    }
    if (stopReason !== "pause_turn") break;
    // Il server riprende da dove si era fermato vedendo il turno dell'assistente
    // che finisce con una ricerca: niente messaggio utente in più.
    messages = [...body.messages, {role: "assistant", content: blocks.slice()}];
  }

  const searchErrors = blocks
      .filter((b) => b?.type === "web_search_tool_result" && b.content && !Array.isArray(b.content))
      .map((b) => b.content.error_code || "unknown");

  return {blocks, usage, stopReason, refusal, model: servedBy, calls, ms: Date.now() - started, searchErrors};
}

module.exports = {
  MODEL_SONNET,
  MODEL_HAIKU,
  estimateCostUsd,
  searchWithClaude,
};
