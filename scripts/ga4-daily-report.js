#!/usr/bin/env node
/**
 * Fotografia giornaliera di Google Analytics (GA4) per KidBox.
 *
 *   node scripts/ga4-daily-report.js            # report testuale
 *   node scripts/ga4-daily-report.js --json     # stesso contenuto, in JSON
 *   node scripts/ga4-daily-report.js --day 2026-09-13   # «ieri» esplicito
 *
 * Una sola property (523225071) raccoglie i quattro stream: app iOS, app
 * Android, web app e landing (che condivide il measurement ID della web app,
 * G-0PG65CW2VF, quindi in GA4 landing e web app sono entrambe `platform=web`
 * e si distinguono solo per `hostName`).
 *
 * Il token si ottiene impersonando il service account `ga4-reader`
 * (nessun ruolo IAM: è Visualizzatore della property in GA4, e basta):
 *
 *   gcloud auth print-access-token \
 *     --impersonate-service-account=ga4-reader@kidbox-42cd7.iam.gserviceaccount.com \
 *     --scopes=https://www.googleapis.com/auth/analytics.readonly
 *
 * Perché così e non con un login utente: il token «normale» di gcloud non ha
 * lo scope Analytics (403 ACCESS_TOKEN_SCOPE_INSUFFICIENT), e
 * `gcloud auth application-default login --scopes=...analytics.readonly`
 * viene rifiutato da Google («Questa app è bloccata»: il client OAuth di
 * gcloud non è verificato per quello scope). L'impersonazione richiede
 * `roles/iam.serviceAccountTokenCreator` sul service account, concesso
 * all'utente il 14/09/2026.
 *
 * Lo script legge e basta: nessuna scrittura, nessun file prodotto. La
 * lettura critica dei numeri (cosa misura davvero ciascun evento) sta nel
 * prompt della routine, non qui.
 */

const { execFileSync } = require("node:child_process");

const PROPERTY = "523225071";
const SERVICE_ACCOUNT = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";
const API = `https://analyticsdata.googleapis.com/v1beta/properties/${PROPERTY}:runReport`;

// Eventi che valgono un funnel, in ordine di lettura. Gli altri (screen_view,
// user_engagement…) restano nella tabella completa ma non qui.
const KEY_EVENTS = [
  "first_open",
  "app_open",
  "pre_signup_screen_shown",
  "login_attempted",
  "signup_completed",
  "onboarding_completed",
  "onboarding_abandoned",
  "family_created",
  "invite_prompt_shown",
  "invite_prompt_accepted",
  "invite_prompt_dismissed",
  "invite_generated",
  "invite_shared",
  "family_join_attempted",
  "family_joined",
  "family_join_failed",
  "content_created",
  "content_shared_read",
  "feature_first_use",
  "ai_message_sent",
  "ai_paywall_shown",
  "paywall_shown",
  "subscription_started",
  "review_prompt_requested",
  // landing
  "store_click",
  "invite_landing_shown",
  "invite_store_click",
  "landing_chat_open",
  "landing_chat_question",
];

// Parametri evento che vale la pena spaccare. Funzionano solo se registrati
// come dimensione personalizzata nella property: altrimenti la API risponde
// 400 e la sezione viene saltata con una nota, non è un guasto.
const BREAKDOWNS = [
  ["content_created", "content_type"],
  ["content_shared_read", "content_type"],
  ["login_attempted", "method"],
  ["invite_shared", "channel"],
  ["invite_prompt_shown", "content_type"],
  ["family_join_failed", "reason"],
  ["feature_first_use", "feature"],
  ["paywall_shown", "trigger_feature"],
  ["ai_message_sent", "agent_type"],
  ["landing_chat_question", "source"],
  ["onboarding_step_shown", "step_name"],
  ["onboarding_step_completed", "step_name"],
  ["onboarding_abandoned", "last_step_seen"],
  ["pre_signup_screen_shown", "screen_name"],
];

// Il funnel si legge per UTENTI, non per eventi: `onboarding_abandoned`
// scattava a ogni background (8 per utente iOS) e `pre_signup_screen_shown`
// a ogni apparizione della schermata. Sui 28 giorni, così ogni gradino è
// «quante persone», e la finestra lunga assorbe i numeri piccoli.
const FUNNEL_USERS = [
  "first_open",
  "pre_signup_screen_shown",
  "login_attempted",
  "signup_completed",
  "onboarding_step_shown",
  "onboarding_completed",
  "family_created",
  "invite_prompt_shown",
  "invite_prompt_accepted",
  "invite_generated",
  "family_join_attempted",
  "family_joined",
  "content_created",
  "content_shared_read",
];

// «Ieri» nel fuso della property (Europe/Rome), come gli altri due script:
// con la data UTC, tra mezzanotte e le 02:00 il giorno sarebbe sbagliato.
function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

function token() {
  try {
    return execFileSync(
      "gcloud",
      [
        "auth",
        "print-access-token",
        `--impersonate-service-account=${SERVICE_ACCOUNT}`,
        "--scopes=https://www.googleapis.com/auth/analytics.readonly",
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    ).trim();
  } catch (e) {
    console.error(
      `Non riesco a impersonare ${SERVICE_ACCOUNT}.\n` +
        "Serve gcloud autenticato come ing.vittorioscocca@gmail.com, che ha\n" +
        "roles/iam.serviceAccountTokenCreator su quel service account.\n" +
        (e.stderr ? `\n${String(e.stderr).trim()}\n` : "")
    );
    process.exit(2);
  }
}

async function runReport(tok, body) {
  const res = await fetch(API, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${tok}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const json = await res.json();
  if (!res.ok) {
    const err = new Error(json.error?.message || `HTTP ${res.status}`);
    err.status = res.status;
    err.reason = json.error?.details?.find((d) => d.reason)?.reason;
    throw err;
  }
  return json;
}

// Trasforma la risposta della API in righe {dim1, dim2, ..., met1, ...}.
function rows(report) {
  const dims = (report.dimensionHeaders || []).map((h) => h.name);
  const mets = (report.metricHeaders || []).map((h) => h.name);
  return (report.rows || []).map((r) => {
    const o = {};
    dims.forEach((n, i) => (o[n] = r.dimensionValues[i].value));
    mets.forEach((n, i) => (o[n] = Number(r.metricValues[i].value)));
    return o;
  });
}

const eventFilter = (names) => ({
  filter: { fieldName: "eventName", inListFilter: { values: names } },
});
const platformFilter = (p) => ({
  filter: { fieldName: "platform", stringFilter: { value: p } },
});

async function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const dayArg = args[args.indexOf("--day") + 1];
  const yesterday = args.includes("--day") && dayArg ? dayArg : shiftDay(romeDate(), -1);
  const dayBefore = shiftDay(yesterday, -1);
  const seriesStart = shiftDay(yesterday, -13); // 14 giorni compreso ieri
  const baseStart = shiftDay(yesterday, -7); // i 7 giorni prima di ieri
  const baseEnd = dayBefore;

  const tok = token();
  const out = { property: PROPERTY, yesterday, dayBefore, baseline: { start: baseStart, end: baseEnd }, notes: [] };

  // 1. Serie giornaliera per piattaforma, ultimi 14 giorni.
  const series = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: seriesStart, endDate: yesterday }],
      dimensions: [{ name: "date" }, { name: "platform" }],
      metrics: [{ name: "activeUsers" }, { name: "newUsers" }, { name: "sessions" }],
      orderBys: [{ dimension: { dimensionName: "date" } }],
      limit: 1000,
    })
  );
  out.series = series;

  // 2. Eventi: ieri e l'altro ieri per piattaforma, più la media dei 7 giorni prima.
  const evYesterday = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: yesterday, endDate: yesterday }],
      dimensions: [{ name: "eventName" }, { name: "platform" }],
      metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
      limit: 1000,
    })
  );
  const evDayBefore = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: dayBefore, endDate: dayBefore }],
      dimensions: [{ name: "eventName" }, { name: "platform" }],
      metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
      limit: 1000,
    })
  );
  const evBase = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: baseStart, endDate: baseEnd }],
      dimensions: [{ name: "eventName" }],
      metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
      limit: 1000,
    })
  );
  out.events = { yesterday: evYesterday, dayBefore: evDayBefore, baseline7d: evBase };

  // 3. Spaccature per parametro evento (solo se la dimensione custom esiste).
  out.breakdowns = {};
  for (const [ev, param] of BREAKDOWNS) {
    try {
      out.breakdowns[`${ev}.${param}`] = rows(
        await runReport(tok, {
          dateRanges: [{ startDate: baseStart, endDate: yesterday }],
          dimensions: [{ name: `customEvent:${param}` }],
          metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
          dimensionFilter: eventFilter([ev]),
          orderBys: [{ metric: { metricName: "eventCount" }, desc: true }],
          limit: 30,
        })
      );
    } catch (e) {
      if (e.status === 400) {
        out.notes.push(
          `Parametro «${param}» di ${ev} non registrato come dimensione personalizzata in GA4: spaccatura saltata.`
        );
      } else throw e;
    }
  }

  // 3-ter. Funnel per utenti unici, 28 giorni e 7 giorni, per piattaforma.
  const funnelRows = async (start, end) =>
    rows(
      await runReport(tok, {
        dateRanges: [{ startDate: start, endDate: end }],
        dimensions: [{ name: "eventName" }, { name: "platform" }],
        metrics: [{ name: "totalUsers" }, { name: "eventCount" }],
        dimensionFilter: eventFilter(FUNNEL_USERS),
        limit: 200,
      })
    );
  out.funnelUsers = {
    d28: { start: shiftDay(yesterday, -27), end: yesterday, rows: await funnelRows(shiftDay(yesterday, -27), yesterday) },
    d7: { start: shiftDay(yesterday, -6), end: yesterday, rows: await funnelRows(shiftDay(yesterday, -6), yesterday) },
  };

  // 4. Web (web app + landing): pagine e sorgenti di traffico, ieri.
  out.web = {};
  out.web.pages = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: yesterday, endDate: yesterday }],
      dimensions: [{ name: "hostName" }, { name: "pagePath" }],
      metrics: [{ name: "screenPageViews" }, { name: "activeUsers" }],
      dimensionFilter: platformFilter("web"),
      orderBys: [{ metric: { metricName: "screenPageViews" }, desc: true }],
      limit: 25,
    })
  );
  out.web.sources = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: yesterday, endDate: yesterday }],
      dimensions: [{ name: "sessionSource" }, { name: "sessionMedium" }],
      metrics: [{ name: "sessions" }, { name: "activeUsers" }],
      dimensionFilter: platformFilter("web"),
      orderBys: [{ metric: { metricName: "sessions" }, desc: true }],
      limit: 15,
    })
  );
  out.web.countries = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: yesterday, endDate: yesterday }],
      dimensions: [{ name: "country" }],
      metrics: [{ name: "activeUsers" }],
      orderBys: [{ metric: { metricName: "activeUsers" }, desc: true }],
      limit: 10,
    })
  );

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

// ---------------------------------------------------------------- stampa

const pad = (s, n) => String(s).padEnd(n);
const num = (n) => (Number.isInteger(n) ? String(n) : n.toFixed(1));

function print(o) {
  const L = [];
  L.push(`# GA4 KidBox — ieri ${o.yesterday} (property ${o.property})`);
  L.push(`Baseline: media giornaliera ${o.baseline.start} → ${o.baseline.end} (7 giorni).`);
  L.push(
    "Attenzione: i dati di ieri possono essere ancora parziali (GA4 consolida entro 24-48h); l'altro ieri è più affidabile."
  );
  L.push("");

  // Serie
  L.push("## Utenti attivi / nuovi / sessioni per giorno e piattaforma (14 gg)");
  const days = [...new Set(o.series.map((r) => r.date))].sort();
  const plats = [...new Set(o.series.map((r) => r.platform))].sort();
  L.push(pad("giorno", 12) + plats.map((p) => pad(`${p} att/nuovi/sess`, 22)).join("") + "totale att.");
  for (const d of days) {
    let tot = 0;
    const cells = plats.map((p) => {
      const r = o.series.find((x) => x.date === d && x.platform === p);
      if (!r) return pad("-", 22);
      tot += r.activeUsers;
      return pad(`${r.activeUsers}/${r.newUsers}/${r.sessions}`, 22);
    });
    L.push(pad(`${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`, 12) + cells.join("") + tot);
  }
  L.push("");

  // Eventi chiave
  L.push("## Eventi chiave (conteggio; tra parentesi utenti)");
  L.push(pad("evento", 26) + pad("ieri", 14) + pad("altro ieri", 14) + pad("media 7gg", 14) + "ieri per piattaforma");
  const sum = (list, ev) =>
    list.filter((r) => r.eventName === ev).reduce((a, r) => ({ c: a.c + r.eventCount, u: a.u + r.totalUsers }), { c: 0, u: 0 });
  for (const ev of KEY_EVENTS) {
    const y = sum(o.events.yesterday, ev);
    const b = sum(o.events.dayBefore, ev);
    const base = o.events.baseline7d.find((r) => r.eventName === ev);
    const baseAvg = base ? base.eventCount / 7 : 0;
    if (!y.c && !b.c && !baseAvg) continue;
    const perPlat = o.events.yesterday
      .filter((r) => r.eventName === ev)
      .map((r) => `${r.platform}:${r.eventCount}`)
      .join(" ");
    L.push(
      pad(ev, 26) +
        pad(`${y.c} (${y.u})`, 14) +
        pad(`${b.c} (${b.u})`, 14) +
        pad(num(baseAvg), 14) +
        perPlat
    );
  }
  L.push("");

  // Altri eventi ieri
  const others = o.events.yesterday
    .filter((r) => !KEY_EVENTS.includes(r.eventName))
    .reduce((m, r) => ((m[r.eventName] = (m[r.eventName] || 0) + r.eventCount), m), {});
  const otherList = Object.entries(others).sort((a, b) => b[1] - a[1]);
  if (otherList.length) {
    L.push("## Altri eventi ieri");
    L.push(otherList.map(([k, v]) => `${k}=${v}`).join(", "));
    L.push("");
  }

  // Funnel per utenti
  const fu = (win, ev, plat) =>
    win.rows.filter((r) => r.eventName === ev && (!plat || r.platform === plat)).reduce((a, r) => a + r.totalUsers, 0);
  L.push(`## Funnel per UTENTI unici — 28 gg (${o.funnelUsers.d28.start} → ${o.funnelUsers.d28.end}) e 7 gg`);
  L.push(pad("passo", 26) + pad("28gg tot", 10) + pad("Android", 9) + pad("iOS", 7) + pad("web", 6) + "7gg tot");
  for (const ev of FUNNEL_USERS) {
    const w = o.funnelUsers.d28;
    const tot = fu(w, ev);
    if (!tot && !fu(o.funnelUsers.d7, ev)) continue;
    L.push(pad(ev, 26) + pad(tot, 10) + pad(fu(w, ev, "Android"), 9) + pad(fu(w, ev, "iOS"), 7) + pad(fu(w, ev, "web"), 6) + fu(o.funnelUsers.d7, ev));
  }
  L.push("Utenti unici per evento, non somma di eventi. login_attempted scatta solo sui provider social: signup_completed può superarlo.");
  L.push("");

  // Breakdown
  const bk = Object.entries(o.breakdowns).filter(([, v]) => v.length);
  if (bk.length) {
    L.push(`## Spaccature per parametro (${o.baseline.start} → ${o.yesterday}, 8 gg)`);
    for (const [k, v] of bk) {
      const dim = Object.keys(v[0]).find((x) => x.startsWith("customEvent:"));
      L.push(`- ${k}: ` + v.map((r) => `${r[dim]}=${r.eventCount}`).join(", "));
    }
    L.push("");
  }

  // Web
  L.push("## Web ieri (web app + landing) — pagine");
  if (!o.web.pages.length) L.push("(nessuna vista pagina)");
  for (const r of o.web.pages) L.push(`${pad(r.screenPageViews, 6)}${pad(r.activeUsers, 5)}${r.hostName}${r.pagePath}`);
  L.push("");
  L.push("## Web ieri — sorgenti (sessioni / utenti)");
  if (!o.web.sources.length) L.push("(nessuna sessione)");
  for (const r of o.web.sources) L.push(`${pad(r.sessions, 6)}${pad(r.activeUsers, 5)}${r.sessionSource} / ${r.sessionMedium}`);
  L.push("");
  L.push("## Paesi ieri (utenti attivi, tutte le piattaforme)");
  L.push(o.web.countries.map((r) => `${r.country}=${r.activeUsers}`).join(", ") || "(nessuno)");
  L.push("");

  if (o.notes.length) {
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore GA4 Data API: ${e.message}${e.reason ? ` (${e.reason})` : ""}`);
  if (e.status === 403) {
    console.error(
      `Il service account ${SERVICE_ACCOUNT} non è (più) Visualizzatore della property GA4 ${PROPERTY}:\n` +
        "GA4 → Amministrazione → Gestione degli accessi alla proprietà → aggiungi quell'email con ruolo Visualizzatore."
    );
  }
  process.exit(1);
});
