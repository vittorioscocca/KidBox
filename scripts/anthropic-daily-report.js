#!/usr/bin/env node
/**
 * Fotografia giornaliera dei costi Anthropic (API Claude) dell'organizzazione.
 *
 *   node scripts/anthropic-daily-report.js           # report testuale
 *   node scripts/anthropic-daily-report.js --json    # stesso contenuto, in JSON
 *
 * È il costo REALE fatturato da Anthropic, contro la stima interna di
 * `ai_costs/{YYYY-MM}` che stampa `console-daily-report.js`: le due cifre
 * devono assomigliarsi, e quando divergono è la stima a essere sbagliata.
 *
 * Due endpoint della Usage & Cost Admin API (raw HTTP, non è nell'SDK):
 * - `/v1/organizations/cost_report`: dollari per giorno, modello e voce
 *   (input, output, cache hit, cache write, web search…). Importi in
 *   **centesimi** come stringhe decimali, solo bucket giornalieri.
 * - `/v1/organizations/usage_report/messages`: token per giorno e modello,
 *   distinti in non in cache / letti dalla cache / scritti in cache / output.
 *   Da qui il tasso di cache hit, che decide quanto costa una domanda.
 *
 * Autenticazione: chiave personale «KidBox Report» con scope Organizzazione
 * (l'Admin API rifiuta le chiavi di workspace, e non esiste per gli account
 * individuali: l'organizzazione è stata convertita in team il 15/09/2026
 * apposta). Vive nel Portachiavi di macOS:
 *
 *   security add-generic-password -a kidbox -s anthropic-admin-key -w '<chiave>' -U
 *
 * Solo lettura. I dati arrivano entro ~5 minuti dalle richieste.
 */

const { execFileSync } = require("node:child_process");

const API = "https://api.anthropic.com/v1/organizations";
const TZ = "Europe/Rome";

function apiKey() {
  try {
    return execFileSync("security", ["find-generic-password", "-a", "kidbox", "-s", "anthropic-admin-key", "-w"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch {
    console.error(
      "Chiave Anthropic non trovata nel Portachiavi (voce «anthropic-admin-key», account «kidbox»).\n" +
        "Va creata in Claude Console → Chiavi API (scope Organizzazione) e salvata con:\n" +
        "  security add-generic-password -a kidbox -s anthropic-admin-key -w '<chiave>' -U"
    );
    process.exit(2);
  }
}

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

async function getAll(key, path, params) {
  const out = [];
  let page = null;
  for (;;) {
    const url = new URL(`${API}/${path}`);
    for (const [k, v] of Object.entries(params)) {
      if (Array.isArray(v)) v.forEach((x) => url.searchParams.append(`${k}[]`, x));
      else url.searchParams.set(k, v);
    }
    if (page) url.searchParams.set("page", page);
    const res = await fetch(url, {
      headers: {
        "x-api-key": key,
        "anthropic-version": "2023-06-01",
        "User-Agent": "KidBoxReport/1.0 (https://kidboxapp.com)",
      },
    });
    const json = await res.json();
    if (!res.ok || json.error) {
      const e = json.error || {};
      const err = new Error(`${path}: ${e.message || res.status}`);
      err.type = e.type;
      throw err;
    }
    out.push(...(json.data || []));
    if (!json.has_more || !json.next_page) break;
    page = json.next_page;
  }
  return out;
}

// «Claude Haiku 4.5 - Input Tokens, Cache Write» → «Haiku 4.5» / «cache write».
function shortModel(model, description) {
  const m = /^Claude ([A-Za-z]+ [0-9.]+)/.exec(description || "");
  if (m) return m[1];
  // claude-haiku-4-5-20251001 → «Haiku 4.5», come nelle descrizioni dei costi.
  const id = /^claude-([a-z]+)-(\d+)(?:-(\d+))?/.exec(model || "");
  if (id) return `${id[1][0].toUpperCase()}${id[1].slice(1)} ${id[2]}${id[3] ? `.${id[3]}` : ""}`;
  return model || "?";
}
function costKind(description) {
  const d = (description || "").toLowerCase();
  if (d.includes("cache write")) return "cache write";
  if (d.includes("cache hit")) return "cache hit";
  if (d.includes("output")) return "output";
  if (d.includes("input")) return "input";
  return description || "?";
}

async function main() {
  const asJson = process.argv.includes("--json");
  const yesterday = shiftDay(romeDate(), -1);
  const start = shiftDay(yesterday, -13);
  const monthStart = `${yesterday.slice(0, 7)}-01`;
  const key = apiKey();
  const out = { yesterday, start, notes: [] };

  // Le finestre sono in UTC: si chiede dal primo del mese o da 14 giorni fa
  // (il più vecchio dei due) fino a oggi escluso.
  const from = start < monthStart ? start : monthStart;
  const costBuckets = await getAll(key, "cost_report", {
    starting_at: `${from}T00:00:00Z`,
    ending_at: `${shiftDay(yesterday, 1)}T00:00:00Z`,
    group_by: ["description"],
    bucket_width: "1d",
    limit: 31,
  });
  // giorno → modello → voce → USD
  const cost = {};
  for (const b of costBuckets) {
    const day = b.starting_at.slice(0, 10);
    for (const r of b.results || []) {
      const model = shortModel(r.model, r.description);
      const kind = costKind(r.description);
      const usd = Number(r.amount) / 100; // centesimi → dollari
      ((cost[day] = cost[day] || {})[model] = cost[day][model] || {})[kind] = (cost[day][model][kind] || 0) + usd;
    }
  }
  out.costByDay = cost;

  const usageBuckets = await getAll(key, "usage_report/messages", {
    starting_at: `${start}T00:00:00Z`,
    ending_at: `${shiftDay(yesterday, 1)}T00:00:00Z`,
    group_by: ["model"],
    bucket_width: "1d",
    limit: 31,
  });
  const usage = {};
  for (const b of usageBuckets) {
    const day = b.starting_at.slice(0, 10);
    for (const r of b.results || []) {
      const model = shortModel(r.model, "");
      const cc = r.cache_creation || {};
      (usage[day] = usage[day] || {})[model] = {
        uncached: r.uncached_input_tokens || 0,
        cacheRead: r.cache_read_input_tokens || 0,
        cacheWrite: (cc.ephemeral_5m_input_tokens || 0) + (cc.ephemeral_1h_input_tokens || 0),
        output: r.output_tokens || 0,
        webSearch: r.server_tool_use?.web_search_requests || 0,
      };
    }
  }
  out.usageByDay = usage;

  // Totali.
  const dayTotal = (d) => Object.values(cost[d] || {}).reduce((a, m) => a + Object.values(m).reduce((x, y) => x + y, 0), 0);
  out.totals = {
    yesterday: dayTotal(yesterday),
    dayBefore: dayTotal(shiftDay(yesterday, -1)),
    last7: [...Array(7)].reduce((a, _, i) => a + dayTotal(shiftDay(yesterday, -i)), 0),
    prev7: [...Array(7)].reduce((a, _, i) => a + dayTotal(shiftDay(yesterday, -7 - i)), 0),
    monthToDate: Object.keys(cost).filter((d) => d >= monthStart && d <= yesterday).reduce((a, d) => a + dayTotal(d), 0),
  };
  const dayOfMonth = Number(yesterday.slice(8, 10));
  const daysInMonth = new Date(Number(yesterday.slice(0, 4)), Number(yesterday.slice(5, 7)), 0).getDate();
  out.totals.monthProjected = (out.totals.monthToDate / dayOfMonth) * daysInMonth;

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

const pad = (s, n) => String(s ?? "-").padEnd(n);
const usd = (x) => `${(x || 0).toFixed(2)} $`;
const cents = (x) => `${((x || 0) * 100).toFixed(1)}¢`;
const k = (n) => (n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n));

function print(o) {
  const L = [];
  L.push(`# Anthropic (API Claude) — ieri ${o.yesterday}, costi reali fatturati`);
  const t = o.totals;
  L.push(`Ieri ${usd(t.yesterday)} · altro ieri ${usd(t.dayBefore)} · ultimi 7 gg ${usd(t.last7)} (7 gg prima ${usd(t.prev7)}) · mese a ieri ${usd(t.monthToDate)}, proiezione ${usd(t.monthProjected)}`);
  L.push("");

  L.push("## Costo per giorno e modello — 14 gg (input / cache hit / cache write / output)");
  const models = [...new Set(Object.values(o.costByDay).flatMap((m) => Object.keys(m)))].sort();
  for (let i = 13; i >= 0; i--) {
    const d = shiftDay(o.yesterday, -i);
    const byModel = o.costByDay[d];
    if (!byModel) { L.push(pad(d, 12) + "—"); continue; }
    const parts = models.filter((m) => byModel[m]).map((m) => {
      const c = byModel[m];
      const tot = Object.values(c).reduce((a, b) => a + b, 0);
      return `${m} ${usd(tot)} (${cents(c.input)} / ${cents(c["cache hit"])} / ${cents(c["cache write"])} / ${cents(c.output)})`;
    });
    L.push(pad(d, 12) + parts.join(" · "));
  }
  L.push("");

  L.push("## Token per modello — ultimi 7 gg (non in cache / letti da cache / scritti in cache / output) e tasso di cache hit");
  const agg = {};
  for (let i = 6; i >= 0; i--) {
    const d = shiftDay(o.yesterday, -i);
    for (const [m, u] of Object.entries(o.usageByDay[d] || {})) {
      const a = (agg[m] = agg[m] || { uncached: 0, cacheRead: 0, cacheWrite: 0, output: 0, webSearch: 0 });
      for (const key of Object.keys(a)) a[key] += u[key] || 0;
    }
  }
  if (!Object.keys(agg).length) L.push("(nessuna richiesta)");
  for (const [m, a] of Object.entries(agg).sort()) {
    const inputAll = a.uncached + a.cacheRead + a.cacheWrite;
    const hit = inputAll ? a.cacheRead / inputAll : 0;
    L.push(`${pad(m, 12)}${pad(k(a.uncached), 8)}${pad(k(a.cacheRead), 8)}${pad(k(a.cacheWrite), 8)}${pad(k(a.output), 8)}cache hit ${(hit * 100).toFixed(0)}%${a.webSearch ? ` · web search ${a.webSearch}` : ""}`);
  }
  L.push("Cache hit = letti da cache ÷ tutto l'input. Sotto il 50% con prompt lunghi ripetuti (chat landing, copilota) la cache si sta raffreddando tra una chiamata e l'altra.");
  L.push("");
  L.push("Confronto: la stima interna del mese è in «AI — mese» del report console (ai_costs). Se diverge di oltre il 20% dal «mese a ieri» qui sopra, è la stima a essere sbagliata.");
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore Usage & Cost API: ${e.message}`);
  if (e.type === "permission_error") {
    console.error("La chiave non ha accesso all'Admin API: serve una chiave con scope Organizzazione di un'organizzazione team (non un account individuale).");
  } else if (e.type === "authentication_error") {
    console.error("Chiave non valida o revocata: ricrearla in Claude Console → Chiavi API e salvarla nel Portachiavi.");
  }
  process.exit(1);
});
