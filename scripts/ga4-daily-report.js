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
 * Il token viene dalle Application Default Credentials di gcloud, che devono
 * essere state create con lo scope Analytics (una tantum, nel browser):
 *
 *   gcloud auth application-default login \
 *     --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly
 *
 * Il token «normale» di `gcloud auth print-access-token` NON basta: non ha lo
 * scope Analytics e la Data API risponde 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT.
 *
 * Lo script legge e basta: nessuna scrittura, nessun file prodotto. La
 * lettura critica dei numeri (cosa misura davvero ciascun evento) sta nel
 * prompt della routine, non qui.
 */

const { execFileSync } = require("node:child_process");

const PROPERTY = "523225071";
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
];

// Parametri evento che vale la pena spaccare. Funzionano solo se registrati
// come dimensione personalizzata nella property: altrimenti la API risponde
// 400 e la sezione viene saltata con una nota, non è un guasto.
const BREAKDOWNS = [
  ["content_created", "content_type"],
  ["content_shared_read", "content_type"],
  ["login_attempted", "method"],
  ["invite_shared", "channel"],
  ["family_join_failed", "reason"],
  ["feature_first_use", "feature"],
  ["paywall_shown", "trigger_feature"],
  ["ai_message_sent", "agent_type"],
];

function isoDay(d) {
  return d.toISOString().slice(0, 10);
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return isoDay(d);
}

function token() {
  try {
    return execFileSync("gcloud", ["auth", "application-default", "print-access-token"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (e) {
    console.error(
      "Non riesco a ottenere un token dalle Application Default Credentials.\n" +
        "Serve un login una tantum con lo scope Analytics:\n\n" +
        "  gcloud auth application-default login \\\n" +
        "    --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly\n"
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
      "x-goog-user-project": "kidbox-42cd7",
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
  const yesterday = args.includes("--day") && dayArg ? dayArg : shiftDay(isoDay(new Date()), -1);
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
  L.push(pad("giorno", 10) + plats.map((p) => pad(p + " act/new/sess", 20)).join("") + "totale att.");
  for (const d of days) {
    let tot = 0;
    const cells = plats.map((p) => {
      const r = o.series.find((x) => x.date === d && x.platform === p);
      if (!r) return pad("-", 20);
      tot += r.activeUsers;
      return pad(`${r.activeUsers}/${r.newUsers}/${r.sessions}`, 20);
    });
    L.push(pad(`${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`, 10) + cells.join("") + tot);
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
  if (e.reason === "ACCESS_TOKEN_SCOPE_INSUFFICIENT") {
    console.error(
      "Le ADC non hanno lo scope Analytics. Rifai il login:\n" +
        "  gcloud auth application-default login --scopes=https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/analytics.readonly"
    );
  }
  process.exit(1);
});
