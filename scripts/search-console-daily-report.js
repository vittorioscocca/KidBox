#!/usr/bin/env node
/**
 * Fotografia giornaliera di Google Search Console per kidboxapp.com
 * (property di dominio `sc-domain:kidboxapp.com`: landing, blog, app.).
 *
 *   node scripts/search-console-daily-report.js           # report testuale
 *   node scripts/search-console-daily-report.js --json    # stesso contenuto, in JSON
 *
 * È il pezzo a monte del funnel che GA4 non vede: quante volte KidBox compare
 * su Google (impressioni), quante persone cliccano, con che posizione media,
 * per quali query e su quali pagine. Più lo stato delle sitemap.
 *
 * Search Console pubblica i dati con 2-3 giorni di ritardo: «ieri» qui è
 * l'ultimo giorno disponibile, non il giorno di calendario. Le finestre
 * (7 gg, 28 gg, confronto col periodo precedente) partono da lì.
 *
 * Stesso meccanismo di GA4: token del service account ga4-reader per
 * impersonazione, con lo scope `webmasters.readonly`. Il service account va
 * aggiunto una volta come utente della property (Search Console →
 * Impostazioni → Utenti e autorizzazioni → Aggiungi utente, autorizzazione
 * «Limitata» basta).
 *
 * Solo lettura.
 */
const { execFileSync } = require("node:child_process");
const { readSnapshot } = require("./lib/snapshot");
const C = require("../functions/reportCollectors/searchConsole");
const { SITE } = C;

/**
 * Obiettivi concordati il 16/09/2026, partendo da 11 impressioni/giorno, 0
 * click, «kidbox» in posizione 11 e ~195 pagine indicizzate su 458. Sono
 * stime, non promesse: un dominio nuovo può stare fermo due mesi e poi
 * partire. Il report stampa lo stato contro la scadenza più vicina non
 * ancora passata. `storeFromGoogle` lo misura il contatore landing (report
 * console), non Search Console: qui resta solo come promemoria.
 */
const GOALS = [
  { by: "2026-10-15", brandPosition: 3, impressionsPerDay: 40, clicksPerDay: 1, pagesWithImpressions: 40, nonBrandShare: null, storeFromGoogle: null },
  { by: "2026-11-15", brandPosition: 1, impressionsPerDay: 100, clicksPerDay: 5, pagesWithImpressions: 80, nonBrandShare: 0.7, storeFromGoogle: 1 },
  { by: "2026-12-31", brandPosition: 1, impressionsPerDay: 300, clicksPerDay: 15, pagesWithImpressions: 150, nonBrandShare: 0.8, storeFromGoogle: 3 },
];
const SERVICE_ACCOUNT = "ga4-reader@kidbox-42cd7.iam.gserviceaccount.com";

function token() {
  try {
    return execFileSync(
      "gcloud",
      [
        "auth",
        "print-access-token",
        `--impersonate-service-account=${SERVICE_ACCOUNT}`,
        "--scopes=https://www.googleapis.com/auth/webmasters.readonly",
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
 * Di default legge lo snapshot scritto stamattina da `reportSnapshotDaily`
 * (stesso codice di raccolta: functions/reportCollectors/searchConsole.js).
 * `--live` forza la lettura dal vivo; se lo snapshot manca, è fallito o ha più
 * di 30 ore, ripiega sul vivo e lo dice nell'intestazione.
 */
function addGoals(out) {
  if (out.empty) return;
  const last = out.lastDay;
  // Stato contro gli obiettivi: la prima scadenza non passata (o l'ultima).
  const goal = GOALS.find((g) => g.by >= last) || GOALS[GOALS.length - 1];
  out.goals = {
    by: goal.by,
    items: [
      { label: "posizione «kidbox»", target: goal.brandPosition, value: out.brandKidbox?.position ?? null, lowerIsBetter: true },
      { label: "impressioni/giorno (7 gg)", target: goal.impressionsPerDay, value: out.last7.impressions / 7 },
      { label: "click/giorno (7 gg)", target: goal.clicksPerDay, value: out.last7.clicks / 7 },
      { label: "pagine con impressioni (28 gg)", target: goal.pagesWithImpressions, value: out.pagesWithImpressions28 },
      ...(goal.nonBrandShare != null ? [{ label: "quota non-brand sui click (28 gg)", target: goal.nonBrandShare, value: out.last28.clicks ? 1 - out.brand28.clicks / out.last28.clicks : null, pct: true }] : []),
    ],
    storeFromGoogle: goal.storeFromGoogle,
  };

}

async function main() {
  const asJson = process.argv.includes("--json");
  let out = null;
  let origin;
  if (!process.argv.includes("--live")) {
    const s = await readSnapshot("searchConsole");
    if (s.payload) {
      out = s.payload;
      origin = `snapshot Firestore delle ${new Date(s.computedAt).toLocaleTimeString("it-IT", { timeZone: "Europe/Rome", hour: "2-digit", minute: "2-digit" })} (${Math.round(s.ageH)} h fa)`;
    } else {
      origin = `dal vivo (${s.reason})`;
    }
  } else {
    origin = "dal vivo (richiesto)";
  }
  if (!out) out = await C.collect(token());
  out.origin = origin;
  addGoals(out);
  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

const pad = (s, n) => String(s ?? "-").padEnd(n);
const pct = (x) => `${((x || 0) * 100).toFixed(1)}%`;
const pos = (x) => (x ? x.toFixed(1) : "-");
const delta = (a, b) => (b ? ` (${a >= b ? "+" : ""}${(((a - b) / b) * 100).toFixed(0)}%)` : "");
const line = (label, t, p) => `${pad(label, 14)}click ${pad(String(t.clicks) + (p ? delta(t.clicks, p.clicks) : ""), 14)}impr. ${pad(String(t.impressions) + (p ? delta(t.impressions, p.impressions) : ""), 16)}CTR ${pad(pct(t.ctr), 8)}pos. ${pos(t.position)}`;

function print(o) {
  const L = [];
  L.push(`# Search Console — ${o.site}`);
  if (o.empty) {
    for (const n of o.notes) L.push(`- ${n}`);
    process.stdout.write(L.join("\n") + "\n");
    return;
  }
  if (o.origin) L.push(`Fonte: ${o.origin}.`);
  L.push(`Ultimo giorno disponibile: ${o.lastDay} (Search Console pubblica con ${o.lagDays} gg di ritardo). Le finestre partono da lì.`);
  L.push("");
  L.push(line("Ultimo giorno", o.last));
  L.push(line("Ultimi 7 gg", o.last7, o.prev7));
  L.push(line("Ultimi 28 gg", o.last28, o.prev28));
  L.push(`Brand (query con «kidbox») 28 gg: ${o.brand28.clicks} click su ${o.last28.clicks} (${o.last28.clicks ? Math.round((o.brand28.clicks / o.last28.clicks) * 100) : 0}%), ${o.brand28.impressions} impressioni. Il resto è gente che non ci conosceva.`);
  L.push("");

  L.push(`## Obiettivi — scadenza ${o.goals.by}`);
  for (const g of o.goals.items) {
    const v = g.value == null ? null : g.pct ? `${Math.round(g.value * 100)}%` : g.lowerIsBetter ? g.value.toFixed(1) : g.value.toFixed(1).replace(/\.0$/, "");
    const t = g.pct ? `${Math.round(g.target * 100)}%` : String(g.target);
    const done = g.value == null ? false : g.lowerIsBetter ? g.value <= g.target : g.value >= g.target;
    const progress = g.value == null || g.lowerIsBetter ? "" : ` (${Math.min(100, Math.round((g.value / g.target) * 100))}%)`;
    L.push(`${done ? "✓" : "·"} ${pad(g.label, 36)}${pad(v ?? "n/d", 8)}→ ${t}${progress}`);
  }
  if (o.goals.storeFromGoogle) L.push(`· ${pad("tap store da Google al giorno", 36)}${pad("(contatore landing, report console)", 8)}→ ${o.goals.storeFromGoogle}`);
  L.push("");
  L.push("## Serie 28 gg (click / impressioni / posizione)");
  for (const s of o.series) L.push(`${pad(s.date, 12)}${pad(s.clicks, 6)}${pad(s.impressions, 8)}${pos(s.position)}`);
  L.push("");

  L.push("## Query più cliccate — 28 gg");
  if (!o.topQueries.length) L.push("(nessuna)");
  for (const q of o.topQueries) L.push(`${pad(q.clicks, 6)}${pad(q.impressions, 8)}${pad(pct(q.ctr), 8)}${pad(pos(q.position), 6)}${q.query}`);
  L.push("");
  L.push("## Pagine più cliccate — 28 gg");
  for (const p of o.topPages) L.push(`${pad(p.clicks, 6)}${pad(p.impressions, 8)}${pad(pct(p.ctr), 8)}${pad(pos(p.position), 6)}${p.page}`);
  L.push("");
  L.push("## Compare ma nessuno clicca — 28 gg (impressioni, posizione)");
  if (!o.impressionsNoClicks.length) L.push("(nessuna)");
  for (const q of o.impressionsNoClicks) L.push(`${pad(q.impressions, 8)}${pad(pos(q.position), 6)}${q.query}`);
  L.push("");
  L.push("## Paesi e dispositivi — 28 gg");
  L.push(o.byCountry.map((c) => `${c.country} ${c.clicks}/${c.impressions}`).join(" · ") || "(nessuno)");
  L.push(o.byDevice.map((d) => `${d.device} ${d.clicks}/${d.impressions}`).join(" · ") || "(nessuno)");
  L.push("");
  L.push("## Sitemap");
  if (!o.sitemaps.length) L.push("(nessuna sitemap inviata)");
  for (const s of o.sitemaps) L.push(`${pad(s.path, 28)}inviate ${pad(s.submitted, 6)}indicizzate ${pad(s.indexed, 6)}errori ${s.errors} avvisi ${s.warnings} · letta il ${s.lastDownloaded || "-"}${s.pending ? " (in attesa)" : ""}`);
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore Search Console: ${e.message}`);
  if (e.status === 403) {
    console.error(`Il service account ${SERVICE_ACCOUNT} non è utente della property ${SITE}: aggiungerlo in Search Console → Impostazioni → Utenti e autorizzazioni.`);
  }
  process.exit(1);
});
