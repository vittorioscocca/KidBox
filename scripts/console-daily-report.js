#!/usr/bin/env node
/**
 * Fotografia giornaliera dei dati della console admin di KidBox, letti alla
 * fonte (Firestore + Firebase Auth) invece che dalla pagina.
 *
 *   node scripts/console-daily-report.js           # report testuale
 *   node scripts/console-daily-report.js --json    # stesso contenuto, in JSON
 *   node scripts/console-daily-report.js --day 2026-09-13
 *
 * Complementare a `ga4-daily-report.js`: GA4 dice cosa fanno gli utenti nelle
 * app, qui c'è quello che GA4 non sa — la base installata (Auth), la struttura
 * delle famiglie (quante hanno davvero 2+ membri), il rollup `metrics/{date}`
 * con la cross-member read (la metrica che prova la tesi del prodotto), i
 * piani a pagamento, i costi AI e i ticket aperti.
 *
 * Token: `gcloud auth print-access-token` dell'utente (Owner del progetto),
 * come fa già la routine dei ticket. Le API usate: Firestore REST (point read,
 * runQuery, runAggregationQuery) e Identity Toolkit `accounts:batchGet`.
 *
 * Letture Firestore per esecuzione: ~14 point read su `metrics`, una decina di
 * aggregazioni (1 lettura ciascuna) e una query sul collection group `members`
 * (una lettura per membro, ~200): trascurabile rispetto al free tier.
 *
 * Privacy: il report contiene solo aggregati. Niente email, nomi, uid o id di
 * famiglia — i dati per-utente restano nella console, dietro login.
 */

const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const TZ = "Europe/Rome";
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const AUTH = `https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:batchGet`;

function token() {
  try {
    return execFileSync("gcloud", ["auth", "print-access-token"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (e) {
    console.error("gcloud non è autenticato (serve ing.vittorioscocca@gmail.com, Owner del progetto).");
    console.error(String(e.stderr || "").trim());
    process.exit(2);
  }
}

// Giorno solare in Europe/Rome, come il rollup.
function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: TZ });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
// Mezzanotte di Rome di un giorno YYYY-MM-DD, come istante ISO (UTC).
function romeMidnight(iso) {
  const probe = new Date(`${iso}T00:00:00Z`);
  const offsetMin = (new Date(probe.toLocaleString("en-US", { timeZone: TZ })) - probe) / 60000;
  return new Date(probe.getTime() - offsetMin * 60000).toISOString();
}

async function call(tok, url, body, method) {
  const res = await fetch(url, {
    method: method || (body ? "POST" : "GET"),
    headers: {
      Authorization: `Bearer ${tok}`,
      "Content-Type": "application/json",
      "x-goog-user-project": PROJECT,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${url.replace(FS, "").slice(0, 60)}: ${json.error?.message || res.status}`);
  return json;
}

// --- decodifica valori Firestore REST -------------------------------------
function val(v) {
  if (v == null) return null;
  if ("integerValue" in v) return Number(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("stringValue" in v) return v.stringValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("timestampValue" in v) return v.timestampValue;
  if ("nullValue" in v) return null;
  if ("mapValue" in v) return fields(v.mapValue.fields);
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(val);
  return null;
}
function fields(f) {
  const o = {};
  for (const [k, v] of Object.entries(f || {})) o[k] = val(v);
  return o;
}

async function getDoc(tok, path, mask) {
  const q = mask ? "?" + mask.map((m) => `mask.fieldPaths=${m}`).join("&") : "";
  const res = await fetch(`${FS}/${path}${q}`, {
    headers: { Authorization: `Bearer ${tok}`, "x-goog-user-project": PROJECT },
  });
  if (res.status === 404) return null;
  const json = await res.json();
  if (!res.ok) throw new Error(`${path}: ${json.error?.message || res.status}`);
  return fields(json.fields);
}

async function count(tok, collectionId, where, allDescendants) {
  const structuredQuery = { from: [{ collectionId, allDescendants: !!allDescendants }] };
  if (where) structuredQuery.where = where;
  const r = await call(tok, `${FS}:runAggregationQuery`, {
    structuredAggregationQuery: { structuredQuery, aggregations: [{ count: {}, alias: "n" }] },
  });
  return Number(r[0]?.result?.aggregateFields?.n?.integerValue || 0);
}
const eq = (field, stringValue) => ({
  fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: { stringValue } },
});
const gte = (field, timestampValue) => ({
  fieldFilter: { field: { fieldPath: field }, op: "GREATER_THAN_OR_EQUAL", value: { timestampValue } },
});

async function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const dayArg = args[args.indexOf("--day") + 1];
  const yesterday = args.includes("--day") && dayArg ? dayArg : shiftDay(romeDate(), -1);
  const seriesStart = shiftDay(yesterday, -13);
  const month = yesterday.slice(0, 7);
  const tok = token();
  const out = { yesterday, tz: TZ, notes: [] };

  // 0. Account di test dello sviluppatore: fuori da tutto (config/internalUsers).
  const internalDoc = (await getDoc(tok, "config/internalUsers")) || {};
  const internalUids = new Set(Array.isArray(internalDoc.uids) ? internalDoc.uids : []);
  out.internalExcluded = internalUids.size;

  // 1. Base utenti da Auth: registrazioni e «app viva» (login o rinnovo token).
  const users = [];
  let pageToken;
  do {
    const r = await call(tok, `${AUTH}?maxResults=500${pageToken ? `&nextPageToken=${pageToken}` : ""}`);
    users.push(...(r.users || []));
    pageToken = r.nextPageToken;
  } while (pageToken);
  const allUsers = users.length;
  for (let i = users.length - 1; i >= 0; i--) if (internalUids.has(users[i].localId)) users.splice(i, 1);
  const yStart = Date.parse(romeMidnight(yesterday));
  const yEnd = Date.parse(romeMidnight(shiftDay(yesterday, 1)));
  const lastActive = (u) =>
    Math.max(Number(u.lastLoginAt || 0), u.lastRefreshAt ? Date.parse(u.lastRefreshAt) : 0);
  const inWindow = (fn, days) => users.filter((u) => fn(u) >= yEnd - days * 86400e3 && fn(u) < yEnd).length;
  const created = (u) => Number(u.createdAt || 0);
  const providers = {};
  for (const u of users) {
    const ids = (u.providerUserInfo || []).map((p) => p.providerId);
    const key = ids.length ? ids.sort().join("+") : "anonimo";
    providers[key] = (providers[key] || 0) + 1;
  }
  out.auth = {
    total: users.length,
    totalWithInternal: allUsers,
    unverifiedEmail: users.filter((u) => u.email && !u.emailVerified).length,
    disabled: users.filter((u) => u.disabled).length,
    signups: { yesterday: users.filter((u) => created(u) >= yStart && created(u) < yEnd).length, d7: inWindow(created, 7), d28: inWindow(created, 28) },
    alive: { d1: inWindow(lastActive, 1), d7: inWindow(lastActive, 7), d14: inWindow(lastActive, 14), d28: inWindow(lastActive, 28) },
    providers,
  };

  // 2. Famiglie e membri: struttura, non attività.
  const [famTotal, famYesterday, fam7, famPro, famMax, ovPro, ovMax, usersDocs] = await Promise.all([
    count(tok, "families"),
    count(tok, "families", gte("createdAt", romeMidnight(yesterday))),
    count(tok, "families", gte("createdAt", romeMidnight(shiftDay(yesterday, -6)))),
    count(tok, "families", eq("plan", "pro")),
    count(tok, "families", eq("plan", "max")),
    count(tok, "families", eq("planOverride", "pro")),
    count(tok, "families", eq("planOverride", "max")),
    count(tok, "users"),
  ]);
  // Distribuzione membri per famiglia: una lettura per membro, solo il nome.
  const memberRows = await call(tok, `${FS}:runQuery`, {
    structuredQuery: {
      from: [{ collectionId: "members", allDescendants: true }],
      select: { fields: [{ fieldPath: "__name__" }] },
    },
  });
  const perFamily = {};
  for (const r of memberRows) {
    const name = r.document?.name;
    if (!name) continue;
    const fid = name.split("/families/")[1]?.split("/")[0];
    if (fid) perFamily[fid] = (perFamily[fid] || 0) + 1;
  }
  const sizes = Object.values(perFamily);
  out.families = {
    total: famTotal,
    createdYesterday: famYesterday,
    created7d: fam7,
    usersDocs,
    membersTotal: sizes.reduce((a, b) => a + b, 0),
    withMembers: sizes.length,
    with2plus: sizes.filter((n) => n >= 2).length,
    with3plus: sizes.filter((n) => n >= 3).length,
    paying: { pro: famPro, max: famMax, overridePro: ovPro, overrideMax: ovMax },
  };

  // 3. Rollup metrics (14 giorni): il rollup delle 03:15 chiude il giorno prima.
  const days = [];
  for (let i = 0; i < 14; i++) days.push(shiftDay(seriesStart, i));
  const rollups = await Promise.all(
    days.map((d) =>
      getDoc(tok, `metrics/${d}`, [
        "dau", "daf", "wau", "mau", "waf", "maf", "stickinessDauMau", "stickinessWauMau",
        "membersJoined", "familiesGrown", "crossMemberReadRate", "retrievedTotal",
        "sessionsTotal", "sessionsNoAction", "activeMembersPerActiveFamily", "byFeature", "eventsScanned",
      ])
    )
  );
  out.metrics = days.map((date, i) => ({ date, ...(rollups[i] || { missing: true }) }));
  if (!rollups[13]) {
    // Il rollup di ieri lo scrive analyticsRollupDaily alle 03:15 Europe/Rome:
    // prima di quell'ora la sua assenza è normale, dopo è un guasto.
    const romeHour = Number(new Date().toLocaleString("en-US", { timeZone: TZ, hour: "2-digit", hour12: false }));
    const isYesterdayDefault = yesterday === shiftDay(romeDate(), -1);
    out.notes.push(
      isYesterdayDefault && romeHour < 4
        ? `Il rollup metrics/${yesterday} non c'è ancora: analyticsRollupDaily gira alle 03:15 (${TZ}). Non è un guasto a quest'ora.`
        : `Il rollup metrics/${yesterday} non esiste: analyticsRollupDaily (03:15) non ha girato o è fallito.`
    );
  }

  // 3-bis. Pagina d'invito /join: contatore nostro (functions/inviteLanding.js),
  // indipendente dal consenso GA4. Stessi 14 giorni del rollup.
  const landing = await Promise.all(days.map((d) => getDoc(tok, `inviteLanding/${d}`)));
  out.inviteLanding = days.map((date, i) => {
    const r = landing[i] || {};
    const shown = (r.shown_ios || 0) + (r.shown_android || 0) + (r.shown_other || 0);
    return { date, shown, shownIos: r.shown_ios || 0, shownAndroid: r.shown_android || 0, shownOther: r.shown_other || 0, storeIos: r.store_ios || 0, storeAndroid: r.store_android || 0, web: r.web || 0 };
  });

  // 3-ter. Chat «Chiedi a KidBox» della landing (functions/landingChat): contatori
  // del giorno e testo delle domande libere, che scade dopo 30 giorni. Anche
  // qui un contatore nostro: GA4 sulla landing vede solo chi ha acconsentito.
  const chatDays = days.slice(7);
  const chat = await Promise.all(chatDays.map((d) => getDoc(tok, `landingChat/${d}`)));
  out.landingChat = chatDays.map((date, i) => {
    const r = chat[i] || {};
    const sum = (prefix) => Object.entries(r).filter(([k]) => k.startsWith(prefix)).reduce((a, [, v]) => a + (Number(v) || 0), 0);
    const faq = {};
    for (const [k, v] of Object.entries(r)) {
      const m = /^(faq|faqmatch)_(.+)$/.exec(k);
      if (m) faq[m[2]] = (faq[m[2]] || 0) + (Number(v) || 0);
    }
    return {
      date,
      opens: r.opens || 0,
      faqChips: sum("faq_"),
      faqMatch: sum("faqmatch_"),
      cache: r.source_cache || 0,
      llm: r.source_llm || 0,
      blocked: sum("blocked_"),
      errors: r.errors || 0,
      costUsd: r.costUsd || 0,
      faq,
    };
  });
  const qRows = await call(tok, `${FS}:runQuery`, {
    structuredQuery: {
      from: [{ collectionId: "landingChatQuestions" }],
      where: { fieldFilter: { field: { fieldPath: "day" }, op: "GREATER_THAN_OR_EQUAL", value: { stringValue: chatDays[0] } } },
      limit: 2000,
    },
  });
  const grouped = new Map();
  for (const row of qRows) {
    if (!row.document) continue;
    const d = fields(row.document.fields);
    if (d.day > yesterday) continue;
    const key = String(d.q || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^\p{L}\p{N}\s]/gu, " ").replace(/\s+/g, " ").trim();
    if (!key) continue;
    const g = grouped.get(key) || { q: d.q, n: 0, langs: new Set(), sources: new Set() };
    g.n++;
    g.langs.add(d.lang);
    g.sources.add(d.source);
    grouped.set(key, g);
  }
  out.landingChatQuestions = [...grouped.values()]
    .sort((x, y) => y.n - x.n)
    .slice(0, 20)
    .map((g) => ({ q: g.q, n: g.n, langs: [...g.langs].join("/"), sources: [...g.sources].join("/") }));
  out.landingChatDistinctQuestions = grouped.size;

  // 4. Costi AI del mese e ticket aperti.
  out.ai = (await getDoc(tok, `ai_costs/${month}`, ["calls", "inputTokens", "outputTokens", "costUsd"])) || { calls: 0, costUsd: 0 };
  out.ai.month = month;
  // «new» è lo stato (backlog da triagare), «ieri» è l'arrivo: senza il
  // secondo, cinque ticket fermi da luglio leggono come cinque crash di ieri.
  const since = romeMidnight(yesterday);
  const [casesNew, crashNew, supportNew, casesY, crashY, supportY] = await Promise.all([
    count(tok, "cases", eq("status", "new")),
    count(tok, "crash_reports", eq("status", "new")),
    count(tok, "support_tickets", eq("status", "new")),
    count(tok, "cases", gte("createdAt", since)),
    count(tok, "crash_reports", gte("createdAt", since)),
    count(tok, "support_tickets", gte("createdAt", since)),
  ]);
  out.tickets = { casesNew, crashNew, supportNew, arrivedSinceYesterday: { cases: casesY, crash: crashY, support: supportY } };

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

// ------------------------------------------------------------------ stampa
const pad = (s, n) => String(s ?? "-").padEnd(n);
const pct = (x) => (x == null ? "n/d" : `${Math.round(x * 100)}%`);

function print(o) {
  const L = [];
  L.push(`# Console KidBox — ieri ${o.yesterday} (${o.tz})`);
  L.push("");

  const a = o.auth;
  L.push("## Base utenti (Firebase Auth)");
  L.push(`Account: ${a.total} (email non verificata: ${a.unverifiedEmail}, disabilitati: ${a.disabled}; esclusi ${o.internalExcluded} account di test); documenti users: ${o.families.usersDocs}`);
  L.push(`Registrati: ieri ${a.signups.yesterday} · 7gg ${a.signups.d7} · 28gg ${a.signups.d28}`);
  L.push(`«App viva» (login o rinnovo token, include il background): 24h ${a.alive.d1} · 7gg ${a.alive.d7} · 14gg ${a.alive.d14} · 28gg ${a.alive.d28}`);
  L.push("Provider: " + Object.entries(a.providers).sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k}=${v}`).join(", "));
  L.push("");

  const f = o.families;
  L.push("## Famiglie");
  L.push(`Totali ${f.total} · create ieri ${f.createdYesterday} · create 7gg ${f.created7d} · membri totali ${f.membersTotal}`);
  L.push(`Funnel struttura: con ≥1 membro ${f.withMembers} → con 2+ membri ${f.with2plus} (${pct(f.with2plus / (f.withMembers || 1))}) → con 3+ ${f.with3plus}`);
  L.push(`A pagamento: pro ${f.paying.pro} · max ${f.paying.max} · override console pro/max ${f.paying.overridePro}/${f.paying.overrideMax}`);
  L.push("");

  L.push("## Rollup attività (metrics/{date}, azioni di valore su Firestore) — 14 gg");
  L.push(pad("giorno", 12) + pad("DAU", 5) + pad("DAF", 5) + pad("WAU", 5) + pad("MAU", 5) + pad("W/M", 6) + pad("join", 6) + pad("xread", 8) + pad("sess", 8) + "eventi");
  for (const m of o.metrics) {
    if (m.missing) { L.push(pad(m.date, 12) + "(rollup mancante)"); continue; }
    const xread = m.retrievedTotal ? `${pct(m.crossMemberReadRate)}/${m.retrievedTotal}` : "n/d";
    const sess = m.sessionsTotal ? `${m.sessionsNoAction}/${m.sessionsTotal}` : "n/d";
    L.push(pad(m.date, 12) + pad(m.dau, 5) + pad(m.daf, 5) + pad(m.wau, 5) + pad(m.mau, 5) + pad(pct(m.stickinessWauMau), 6) + pad(m.membersJoined, 6) + pad(xread, 8) + pad(sess, 8) + m.eventsScanned);
  }
  L.push("xread = quota di letture di contenuti caricati da un ALTRO membro / letture totali; sess = aperture senza azione / totali; n/d = non misurato.");
  L.push("");

  const y = o.metrics[13];
  const feat = (m) => Object.entries(m?.byFeature || {});
  L.push("## Per feature — ieri (creati/aggiornati/completati/letti/AI)");
  const fy = feat(y).filter(([, v]) => Object.values(v).some((n) => n));
  L.push(fy.length ? fy.map(([k, v]) => `${k}=${v.created || 0}/${v.updated || 0}/${v.completed || 0}/${v.retrieved || 0}/${v.ai || 0}`).join(", ") : "(nessuna azione registrata)");
  const agg = {};
  for (const m of o.metrics.slice(7)) for (const [k, v] of feat(m)) {
    agg[k] = agg[k] || { created: 0, updated: 0, completed: 0, retrieved: 0, ai: 0 };
    for (const c of Object.keys(agg[k])) agg[k][c] += v[c] || 0;
  }
  L.push("## Per feature — ultimi 7 gg (somma)");
  const f7 = Object.entries(agg).filter(([, v]) => Object.values(v).some((n) => n)).sort((x, y2) => Object.values(y2[1]).reduce((s, n) => s + n, 0) - Object.values(x[1]).reduce((s, n) => s + n, 0));
  L.push(f7.length ? f7.map(([k, v]) => `${k}=${v.created}/${v.updated}/${v.completed}/${v.retrieved}/${v.ai}`).join(", ") : "(nessuna)");
  L.push("");

  L.push("## Pagina d'invito /join (contatore nostro, dal 15/09/2026) — 14 gg");
  L.push(pad("giorno", 12) + pad("viste", 7) + pad("iOS/And/altro", 15) + pad("→ store iOS", 13) + pad("→ store And", 13) + "→ web app");
  for (const r of o.inviteLanding) {
    if (!r.shown && !r.storeIos && !r.storeAndroid && !r.web) continue;
    L.push(pad(r.date, 12) + pad(r.shown, 7) + pad(`${r.shownIos}/${r.shownAndroid}/${r.shownOther}`, 15) + pad(r.storeIos, 13) + pad(r.storeAndroid, 13) + r.web);
  }
  const lt = o.inviteLanding.slice(7).reduce((a, r) => ({ shown: a.shown + r.shown, store: a.store + r.storeIos + r.storeAndroid, web: a.web + r.web }), { shown: 0, store: 0, web: 0 });
  L.push(`Ultimi 7 gg: ${lt.shown} viste → ${lt.store} tap store (${pct(lt.shown ? lt.store / lt.shown : null)}) → ${lt.web} web app. Chi ha già l'app non passa di qui: il link si apre direttamente in KidBox.`);
  L.push("");

  L.push("## Chat «Chiedi a KidBox» sulla landing (contatore nostro) — 7 gg");
  L.push(pad("giorno", 12) + pad("aperture", 10) + pad("chip FAQ", 10) + pad("FAQ locale", 12) + pad("cache", 7) + pad("modello", 9) + pad("bloccate", 10) + "costo $");
  for (const r of o.landingChat) {
    if (!r.opens && !r.faqChips && !r.faqMatch && !r.cache && !r.llm && !r.blocked) continue;
    L.push(pad(r.date, 12) + pad(r.opens, 10) + pad(r.faqChips, 10) + pad(r.faqMatch, 12) + pad(r.cache, 7) + pad(r.llm, 9) + pad(r.blocked + (r.errors ? ` (+${r.errors} err)` : ""), 10) + r.costUsd.toFixed(3));
  }
  const ct = o.landingChat.reduce((a, r) => {
    a.opens += r.opens; a.free += r.faqChips + r.faqMatch + r.cache; a.llm += r.llm; a.cost += r.costUsd;
    for (const [k, v] of Object.entries(r.faq)) a.faq[k] = (a.faq[k] || 0) + v;
    return a;
  }, { opens: 0, free: 0, llm: 0, cost: 0, faq: {} });
  const answered = ct.free + ct.llm;
  L.push(`Totale 7 gg: ${ct.opens} aperture · ${answered} risposte, di cui senza modello ${ct.free} (${pct(answered ? ct.free / answered : null)}) · costo ${ct.cost.toFixed(2)} USD (tetto 1 $/giorno).`);
  const faqTop = Object.entries(ct.faq).sort((x, y) => y[1] - x[1]).map(([k, v]) => `${k} ${v}`).join(", ");
  if (faqTop) L.push(`Domande suggerite (chip + ricerca locale): ${faqTop}`);
  if (o.landingChatQuestions.length) {
    L.push(`Domande scritte più frequenti (${o.landingChatDistinctQuestions} diverse; fonte: llm = modello, cache, faq_* = risposta scritta, blocked_* = limite):`);
    for (const g of o.landingChatQuestions) L.push(`- ${g.n}× «${g.q}» [${g.langs}; ${g.sources}]`);
    L.push("Le domande dello sviluppatore non sono escluse: la landing non sa chi scrive.");
  }
  L.push("");

  L.push(`## AI — mese ${o.ai.month}`);
  L.push(`Chiamate ${o.ai.calls || 0} · token in/out ${o.ai.inputTokens || 0}/${o.ai.outputTokens || 0} · costo ${(o.ai.costUsd || 0).toFixed(2)} USD`);
  L.push("");
  const t = o.tickets, ar = t.arrivedSinceYesterday;
  L.push("## Ticket");
  L.push(`Arrivati da ieri: bug/segnalazioni ${ar.cases} · crash ${ar.crash} · supporto chat ${ar.support}`);
  L.push(`Backlog con status «new» (qualunque data): bug/segnalazioni ${t.casesNew} · crash ${t.crashNew} · supporto chat ${t.supportNew}`);
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore: ${e.message}`);
  process.exit(1);
});
