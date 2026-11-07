/* eslint-disable -- stile degli script (prettier), condiviso con scripts/ */
/**
 * Raccolta dei dati GA4 per il report: UNICA copia del codice, usata sia da
 * `scripts/ga4-daily-report.js` (lettura dal vivo) sia dalla funzione
 * pianificata `reportSnapshotDaily` (che salva il risultato su Firestore).
 * Nessuna dipendenza: solo `fetch`. Il token lo passa chi chiama.
 */

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
  "purchase_started",
  "purchase_cancelled",
  "purchase_failed",
  "subscription_started",
  "review_prompt_requested",
  // landing
  "store_click",
  "invite_landing_shown",
  "invite_store_click",
  "landing_chat_open",
  "landing_chat_question",
];

/**
 * Funnel sequenziali per ramo (vedi 3-quater). «Invito generato» nel ramo di chi
 * crea è quasi il 100% perché il wizard genera il link da solo: non misura una
 * condivisione, e la perdita vera si vede nel ramo di chi entra.
 */
const CLOSED_FUNNELS = {
  creatori: [
    ["Installazione", "first_open"],
    ["Login visto", "pre_signup_screen_shown"],
    ["Login tentato", "login_attempted"],
    ["Famiglia creata", "family_created"],
    ["Invito generato", "invite_generated"],
  ],
  invitati: [
    ["Installazione", "first_open"],
    ["Join tentato", "family_join_attempted"],
    ["Entrato in famiglia", "family_joined"],
  ],
  uso: [
    ["Famiglia creata", "family_created"],
    ["Contenuto creato", "content_created"],
    ["Letto da un altro membro", "content_shared_read"],
  ],
};

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
  ["purchase_started", "trigger_feature"],
  ["purchase_failed", "reason"],
  ["ai_message_sent", "agent_type"],
  ["landing_chat_question", "source"],
  ["onboarding_step_shown", "step_name"],
  ["onboarding_step_completed", "step_name"],
  ["onboarding_abandoned", "last_step_seen"],
  ["pre_signup_screen_shown", "screen_name"],
  ["insight_shown", "type"],
  ["insight_acted", "via"],
  ["insight_dismissed", "type"],
];

// Avvisi proattivi (scommessa 11 del registro di /auto-miglioramento).
// Soglie confermate dall'utente il 23/10/2026; «non misurabile» sotto i minimi.
const INSIGHT_EVENTS = [
  "insight_shown",
  "insight_acted",
  "insight_dismissed",
  "insight_snoozed",
  "insight_prefs_changed",
];
const INSIGHT_BET = {
  actedMin: 0.3, // insight_acted ÷ insight_shown
  dismissedMax: 0.2, // insight_dismissed ÷ insight_shown
  offMax: 0.1, // utenti che li spengono ÷ utenti che li ricevono
  minShown: 100,
  minUsers: 20,
};

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


async function collect(tok, { day = null, insightsFrom = null } = {}) {
  const yesterday = day || shiftDay(romeDate(), -1);
  const dayBefore = shiftDay(yesterday, -1);
  const seriesStart = shiftDay(yesterday, -13); // 14 giorni compreso ieri
  const baseStart = shiftDay(yesterday, -7); // i 7 giorni prima di ieri
  const baseEnd = dayBefore;

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

  // 3-quater. Funnel SEQUENZIALI (GA4 runFunnelReport, v1alpha): ogni gradino
  // conta solo chi ha fatto anche i precedenti, in quest'ordine. Il funnel qui
  // sopra mette in fila contatori indipendenti e supera il 100% (chi entra con
  // un invito apre l'onboarding senza essersi «registrato»; chi ha già una
  // famiglia genera inviti). I rami sono due perché due sono i percorsi.
  // Ordine reale del wizard a 2 pagine: la famiglia nasce prima di
  // onboarding_completed, che scatta dopo la pagina dell'invito.
  out.closedFunnels = {};
  for (const [key, steps] of Object.entries(CLOSED_FUNNELS)) {
    try {
      const res = await fetch(`https://analyticsdata.googleapis.com/v1alpha/properties/${PROPERTY}:runFunnelReport`, {
        method: "POST",
        headers: { Authorization: `Bearer ${tok}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          dateRanges: [{ startDate: shiftDay(yesterday, -27), endDate: yesterday }],
          funnel: {
            isOpenFunnel: false,
            steps: steps.map(([name, ev]) => ({ name, filterExpression: { funnelEventFilter: { eventName: ev } } })),
          },
        }),
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.error?.message || `HTTP ${res.status}`);
      // Righe "1. Nome" → {label, users}; l'ordine è quello dei passi.
      out.closedFunnels[key] = (json.funnelTable?.rows || []).map((r) => ({
        label: r.dimensionValues[0].value.replace(/^\d+\.\s*/, ""),
        users: Number(r.metricValues[0].value),
      }));
    } catch (e) {
      out.notes.push(`Funnel sequenziale «${key}» non disponibile: ${e.message}`);
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

  // 4-bis. Avvisi proattivi: i tre rapporti della scommessa 11. Finestra
  // dall'uscita (--insights-from) fino a ieri; senza data, gli ultimi 28 giorni.
  const insArg = insightsFrom;
  const insStart = insArg || shiftDay(yesterday, -27);
  out.insights = { start: insStart, end: yesterday, fromRelease: Boolean(insArg), events: [], offUsers: null };
  out.insights.events = rows(
    await runReport(tok, {
      dateRanges: [{ startDate: insStart, endDate: yesterday }],
      dimensions: [{ name: "eventName" }],
      metrics: [{ name: "eventCount" }, { name: "totalUsers" }],
      dimensionFilter: eventFilter(INSIGHT_EVENTS),
    })
  );
  try {
    const off = rows(
      await runReport(tok, {
        dateRanges: [{ startDate: insStart, endDate: yesterday }],
        metrics: [{ name: "totalUsers" }],
        dimensionFilter: {
          andGroup: {
            expressions: [
              eventFilter(["insight_prefs_changed"]),
              { filter: { fieldName: "customEvent:delivery", stringFilter: { value: "off" } } },
            ],
          },
        },
      })
    );
    out.insights.offUsers = off.length ? off[0].totalUsers : 0;
  } catch (e) {
    if (e.status === 400) {
      out.notes.push(
        "Parametro «delivery» di insight_prefs_changed non registrato come dimensione personalizzata in GA4: rapporto (c) della scommessa 11 non calcolabile."
      );
    } else throw e;
  }

  // 5. Google Ads (collegato a GA4 dal 15/10/2026): costo, clic e impression
  // per giorno e campagna, ultimi 14 giorni. Isolato: se la combinazione di
  // metriche non è accettata o non ci sono dati, il resto del report non cade.
  out.ads = { rows: [], sessions: [] };
  try {
    out.ads.rows = rows(
      await runReport(tok, {
        dateRanges: [{ startDate: shiftDay(yesterday, -13), endDate: yesterday }],
        dimensions: [{ name: "date" }, { name: "sessionGoogleAdsCampaignName" }],
        metrics: [
          { name: "advertiserAdCost" },
          { name: "advertiserAdClicks" },
          { name: "advertiserAdImpressions" },
        ],
        orderBys: [{ dimension: { dimensionName: "date" } }],
        limit: 200,
      })
    ).filter((r) => r.sessionGoogleAdsCampaignName !== "(not set)");
    out.ads.sessions = rows(
      await runReport(tok, {
        dateRanges: [{ startDate: shiftDay(yesterday, -13), endDate: yesterday }],
        dimensions: [{ name: "date" }],
        metrics: [{ name: "sessions" }, { name: "newUsers" }],
        dimensionFilter: {
          filter: { fieldName: "sessionMedium", stringFilter: { value: "cpc" } },
        },
        orderBys: [{ dimension: { dimensionName: "date" } }],
      })
    );
  } catch (e) {
    out.notes.push(`Google Ads in GA4 non letto: ${e.message}`);
  }
  return out;
}

module.exports = {
  collect,
  PROPERTY,
  KEY_EVENTS,
  FUNNEL_USERS,
  INSIGHT_EVENTS,
  INSIGHT_BET,
  romeDate,
  shiftDay,
};
