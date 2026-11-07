#!/usr/bin/env node
/**
 * Fotografia giornaliera di Google Analytics (GA4) per KidBox.
 *
 *   node scripts/ga4-daily-report.js            # report testuale
 *   node scripts/ga4-daily-report.js --json     # stesso contenuto, in JSON
 *   node scripts/ga4-daily-report.js --day 2026-09-13   # «ieri» esplicito
 *   node scripts/ga4-daily-report.js --insights-from 2026-11-02   # avvisi proattivi dall'uscita
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
const { readSnapshot } = require("./lib/snapshot");
const C = require("../functions/reportCollectors/ga4");
const { PROPERTY, KEY_EVENTS, FUNNEL_USERS, INSIGHT_EVENTS, INSIGHT_BET, romeDate, shiftDay } = C;

const SERVICE_ACCOUNT = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";

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

/**
 * Di default legge lo snapshot che la funzione `reportSnapshotDaily` ha scritto
 * su Firestore stamattina (stesso codice di raccolta: functions/reportCollectors/ga4.js).
 * Dal vivo con `--live`, e sempre dal vivo con `--day` o `--insights-from`
 * (lo snapshot è solo «ieri» con la finestra standard). Se lo snapshot manca,
 * è fallito o ha più di 30 ore, ripiega sul vivo e lo dice nell'intestazione.
 */
async function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const dayArg = args.includes("--day") ? args[args.indexOf("--day") + 1] : null;
  const insFrom = args.includes("--insights-from") ? args[args.indexOf("--insights-from") + 1] : null;
  const forceLive = args.includes("--live") || dayArg || insFrom;

  let out = null;
  let origin = null;
  if (!forceLive) {
    const s = await readSnapshot("ga4");
    if (s.payload) {
      out = s.payload;
      origin = `snapshot Firestore delle ${new Date(s.computedAt).toLocaleTimeString("it-IT", { timeZone: "Europe/Rome", hour: "2-digit", minute: "2-digit" })} (${Math.round(s.ageH)} h fa)`;
    } else {
      origin = `dal vivo (${s.reason})`;
    }
  } else {
    origin = "dal vivo (richiesto)";
  }
  if (!out) out = await C.collect(token(), { day: dayArg, insightsFrom: insFrom });
  out.origin = origin;

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
  if (o.origin) L.push(`Fonte: ${o.origin}.`);
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

  // Funnel sequenziali
  const nomi = { creatori: "chi crea la famiglia", invitati: "chi entra con un invito", uso: "uso dopo la famiglia" };
  for (const [key, steps] of Object.entries(o.closedFunnels || {})) {
    if (!steps.length) continue;
    L.push(`## Funnel SEQUENZIALE 28 gg — ${nomi[key] || key}`);
    steps.forEach((st, i) => {
      const prev = i ? steps[i - 1].users : null;
      L.push(pad(st.label, 26) + pad(st.users, 8) + (prev ? `${Math.round((st.users / (prev || 1)) * 100)}% del passo prima` : ""));
    });
    L.push("");
  }
  L.push("Sequenziale = ogni gradino conta solo chi ha fatto anche i precedenti, in ordine: non supera mai il 100%. «Invito generato» è ~100% perché il wizard lo genera da solo.");
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

  // Avvisi proattivi
  const ins = o.insights;
  const ie = (ev) => ins.events.find((r) => r.eventName === ev) || { eventCount: 0, totalUsers: 0 };
  const shown = ie("insight_shown");
  L.push(
    `## Avvisi proattivi — scommessa 11 (${ins.start} → ${ins.end}${ins.fromRelease ? ", dall'uscita" : ", ultimi 28 gg: per il verdetto usare --insights-from <data uscita>"})`
  );
  for (const ev of INSIGHT_EVENTS) {
    const r = ie(ev);
    L.push(pad(ev, 26) + pad(r.eventCount, 8) + `(${r.totalUsers} utenti)`);
  }
  const pct = (x) => `${Math.round(x * 100)}%`;
  const verdict = (ok) => (ok ? "soglia rispettata ✓" : "soglia mancata ✗");
  if (shown.eventCount < INSIGHT_BET.minShown || shown.totalUsers < INSIGHT_BET.minUsers) {
    L.push(
      `Non misurabile: ${shown.eventCount} insight_shown e ${shown.totalUsers} utenti (servono almeno ${INSIGHT_BET.minShown} e ${INSIGHT_BET.minUsers}).`
    );
  }
  if (shown.eventCount) {
    const a = ie("insight_acted").eventCount / shown.eventCount;
    const b = ie("insight_dismissed").eventCount / shown.eventCount;
    L.push(`(a) azione   insight_acted ÷ insight_shown = ${pct(a)} (soglia ≥ ${pct(INSIGHT_BET.actedMin)}) — ${verdict(a >= INSIGHT_BET.actedMin)}`);
    L.push(`(b) rifiuti  insight_dismissed ÷ insight_shown = ${pct(b)} (soglia ≤ ${pct(INSIGHT_BET.dismissedMax)}) — ${verdict(b <= INSIGHT_BET.dismissedMax)}`);
  }
  if (shown.totalUsers && ins.offUsers !== null) {
    const c = ins.offUsers / shown.totalUsers;
    L.push(`(c) spenti   utenti con delivery=off ÷ utenti con insight_shown = ${ins.offUsers}/${shown.totalUsers} = ${pct(c)} (soglia ≤ ${pct(INSIGHT_BET.offMax)}) — ${verdict(c <= INSIGHT_BET.offMax)}`);
  }
  L.push("Eventi solo da iOS finché il motore non è su Android. Il verdetto si scrive nel registro, non qui.");
  L.push("");

  // Google Ads
  L.push("## Google Ads (da GA4, 14 giorni) — data, campagna, costo, clic, impression");
  if (!o.ads.rows.length) {
    L.push("(nessun costo, clic o impression di Google Ads registrato da GA4: la campagna non consegna, oppure i dati non sono ancora importati)");
  }
  for (const r of o.ads.rows) {
    L.push(
      `${r.date}  ${pad(r.sessionGoogleAdsCampaignName, 34)}${pad(num(r.advertiserAdCost), 8)}${pad(r.advertiserAdClicks, 6)}${r.advertiserAdImpressions}`
    );
  }
  L.push("Sessioni con medium cpc (data=sessioni/nuovi utenti): " +
    (o.ads.sessions.map((r) => `${r.date}=${r.sessions}/${r.newUsers}`).join(", ") || "nessuna"));
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
