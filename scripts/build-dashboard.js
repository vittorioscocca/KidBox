#!/usr/bin/env node
/**
 * Cruscotto del mattino: una pagina HTML, generata in modo deterministico dai
 * sette script di report, che la routine `kidbox-ga4-daily` pubblica ogni
 * giorno allo stesso link.
 *
 *   node scripts/build-dashboard.js                       # → dashboard/kidbox-dashboard.html
 *   node scripts/build-dashboard.js --note commento.md    # con il commento del giorno in testa
 *   node scripts/build-dashboard.js --out /percorso/file.html
 *
 * Perché un generatore e non HTML scritto dal modello ogni mattina: stesso
 * layout tutti i giorni, cambiano solo i numeri; e niente può finire nella
 * pagina che non sia già negli script (solo aggregati, mai dati personali).
 * Il testo libero — sintesi e anomalie — lo scrive la routine in un file e
 * qui viene incollato in testa come «commento del giorno».
 *
 * Ogni fonte è indipendente: se uno script fallisce, il suo riquadro dice
 * perché e il resto della pagina esce lo stesso.
 */

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const SOURCES = {
  ga4: "ga4-daily-report.js",
  console: "console-daily-report.js",
  meta: "meta-ads-daily-report.js",
  play: "play-daily-report.js",
  appstore: "appstore-daily-report.js",
  anthropic: "anthropic-daily-report.js",
  gcloud: "gcloud-billing-daily-report.js",
  search: "search-console-daily-report.js",
};

// ------------------------------------------------------------------ raccolta

function runJson(script) {
  try {
    const out = execFileSync("node", [path.join(ROOT, "scripts", script), "--json"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 50 * 1024 * 1024,
      timeout: 180_000,
    });
    return { data: JSON.parse(out), error: null };
  } catch (e) {
    const msg = String(e.stderr || e.message || "").trim().split("\n").filter(Boolean).slice(-2).join(" · ");
    return { data: null, error: msg || "errore sconosciuto" };
  }
}

function romeDate(d = new Date()) {
  return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Rome" });
}
function shiftDay(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
const itDate = (iso) => {
  if (!iso) return "—";
  const [y, m, d] = iso.split("-");
  return `${d}/${m}/${y}`;
};
const itShort = (iso) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}` : "");

// ------------------------------------------------------------------ helpers

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const fmt = (n, dec = 0) => (n == null || Number.isNaN(n) ? "—" : Number(n).toLocaleString("it-IT", { minimumFractionDigits: dec, maximumFractionDigits: dec }));
const eur = (n) => (n == null ? "—" : `${fmt(n, 2)} €`);
const usd = (n) => (n == null ? "—" : `${fmt(n, 2)} $`);
const pct = (x) => (x == null || Number.isNaN(x) ? "—" : `${Math.round(x * 100)}%`);
const sum = (arr) => arr.reduce((a, b) => a + (Number(b) || 0), 0);
const avg = (arr) => (arr.length ? sum(arr) / arr.length : null);

/** Freccia di confronto: ieri contro la media dei 7 giorni prima. */
function delta(value, base) {
  if (value == null || base == null || !base) return { cls: "flat", text: "" };
  const r = (value - base) / base;
  if (Math.abs(r) < 0.1) return { cls: "flat", text: "≈ media 7gg" };
  return { cls: r > 0 ? "up" : "down", text: `${r > 0 ? "+" : "−"}${Math.round(Math.abs(r) * 100)}% vs media 7gg` };
}

// ------------------------------------------------------------------ grafici

/**
 * Linee (una o più serie) su 14 giorni, con area sotto la prima serie, punto
 * finale enfatizzato, etichette dirette a destra e hover con tooltip (i dati
 * stanno in `data-points`, il JS in fondo alla pagina fa il resto).
 */
function lineChart({ labels, series, unit = "", height = 150, decimals = 0 }) {
  const W = 560;
  const H = height;
  const padL = 8;
  const padR = 70;
  const padT = 14;
  const padB = 22;
  const n = labels.length;
  const all = series.flatMap((s) => s.values.filter((v) => v != null));
  const max = Math.max(1, ...all);
  const x = (i) => padL + (i * (W - padL - padR)) / Math.max(1, n - 1);
  const y = (v) => padT + (H - padT - padB) * (1 - v / max);
  const gridVals = [max, max / 2];
  let g = `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(series.map((s) => s.name).join(", "))}" data-points='${esc(JSON.stringify({ labels, series: series.map((s) => ({ name: s.name, values: s.values })), unit, decimals }))}'>`;
  for (const gv of gridVals) {
    g += `<line class="grid" x1="${padL}" x2="${W - padR}" y1="${y(gv).toFixed(1)}" y2="${y(gv).toFixed(1)}"/>`;
    g += `<text class="tick" x="${W - padR + 4}" y="${(y(gv) + 4).toFixed(1)}">${fmt(gv, decimals)}</text>`;
  }
  g += `<line class="axis" x1="${padL}" x2="${W - padR}" y1="${y(0).toFixed(1)}" y2="${y(0).toFixed(1)}"/>`;
  // Etichette di data: prima, metà, ultima.
  for (const i of [0, Math.floor((n - 1) / 2), n - 1]) {
    g += `<text class="tick" text-anchor="${i === 0 ? "start" : i === n - 1 ? "end" : "middle"}" x="${x(i).toFixed(1)}" y="${H - 6}">${itShort(labels[i])}</text>`;
  }
  // Etichette finali: distanziate di almeno 12px, così tre serie vicine non
  // si scrivono una sopra l'altra.
  const lastOf = (s) => s.values.map((v, i) => (v == null ? -1 : i)).filter((i) => i >= 0).pop();
  const labelYs = series.map((s) => { const li = lastOf(s); return li == null ? null : y(s.values[li]) + 4; });
  const order = labelYs.map((v, i) => [v, i]).filter(([v]) => v != null).sort((a, b) => a[0] - b[0]);
  for (let k = 1; k < order.length; k++) if (order[k][0] - order[k - 1][0] < 12) order[k][0] = order[k - 1][0] + 12;
  const bottom = H - padB - 2;
  for (let k = order.length - 1; k >= 0; k--) {
    if (order[k][0] > bottom) order[k][0] = bottom;
    if (k < order.length - 1 && order[k + 1][0] - order[k][0] < 12) order[k][0] = order[k + 1][0] - 12;
  }
  for (const [v, i] of order) labelYs[i] = v;

  series.forEach((s, si) => {
    const pts = s.values.map((v, i) => (v == null ? null : `${x(i).toFixed(1)},${y(v).toFixed(1)}`));
    const segs = [];
    let cur = [];
    for (const p of pts) {
      if (p) cur.push(p);
      else if (cur.length) { segs.push(cur); cur = []; }
    }
    if (cur.length) segs.push(cur);
    if (si === 0 && segs.length === 1 && segs[0].length > 1) {
      const first = segs[0][0].split(",")[0];
      const last = segs[0][segs[0].length - 1].split(",")[0];
      g += `<path class="area s${si + 1}" d="M${first},${y(0).toFixed(1)} L${segs[0].join(" L")} L${last},${y(0).toFixed(1)} Z"/>`;
    }
    for (const seg of segs) g += `<polyline class="line s${si + 1}" points="${seg.join(" ")}"/>`;
    const lastIdx = s.values.map((v, i) => (v == null ? -1 : i)).filter((i) => i >= 0).pop();
    if (lastIdx != null) {
      g += `<circle class="dot s${si + 1}" cx="${x(lastIdx).toFixed(1)}" cy="${y(s.values[lastIdx]).toFixed(1)}" r="4"/>`;
      g += `<text class="label s${si + 1}" x="${W - padR + 4}" y="${labelYs[si].toFixed(1)}">${esc(s.name)} ${fmt(s.values[lastIdx], decimals)}</text>`;
    }
  });
  g += `<g class="hover" hidden><line class="cross" y1="${padT}" y2="${(H - padB).toFixed(1)}"/></g></svg>`;
  return g;
}

/** Barre orizzontali del funnel, in scala sul primo gradino, con tassi di passaggio. */
function funnelChart(steps) {
  const max = Math.max(1, ...steps.map((s) => s.value || 0));
  let h = `<div class="funnel">`;
  steps.forEach((s, i) => {
    const w = ((s.value || 0) / max) * 100;
    const prev = i > 0 ? steps[i - 1].value : null;
    const rate = prev ? ` <span class="rate">${pct((s.value || 0) / prev)}</span>` : "";
    h += `<div class="frow"><div class="flabel">${esc(s.label)}</div><div class="fbar"><div class="ffill${s.muted ? " muted" : ""}" style="width:${Math.max(w, 0.5).toFixed(1)}%"></div><span class="fval">${fmt(s.value)}${rate}</span></div></div>`;
  });
  h += `</div>`;
  return h;
}

// ------------------------------------------------------------------ pagina

function build({ note, outFile }) {
  const results = Object.fromEntries(Object.entries(SOURCES).map(([k, s]) => [k, runJson(s)]));
  const G = results.ga4.data;
  const C = results.console.data;
  const M = results.meta.data;
  const P = results.play.data;
  const A = results.appstore.data;
  const N = results.anthropic.data;
  const B = results.gcloud.data;
  const S = results.search.data;
  const yesterday = C?.yesterday || G?.yesterday || shiftDay(romeDate(), -1);
  const days14 = [...Array(14)].map((_, i) => shiftDay(yesterday, i - 13));
  const days7 = days14.slice(7);

  // ---- GA4: attivi per piattaforma, first_open, eventi
  const gaDay = (iso) => iso.replace(/-/g, "");
  const activeBy = (plat) => days14.map((d) => {
    const rows = (G?.series || []).filter((r) => r.date === gaDay(d) && (!plat || r.platform === plat));
    return rows.length ? sum(rows.map((r) => r.activeUsers)) : G ? 0 : null;
  });
  const activeTot = activeBy(null);
  const evCount = (list, name) => sum((list || []).filter((r) => r.eventName === name).map((r) => r.eventCount));
  const evBase = (name) => {
    const r = (G?.events?.baseline7d || []).find((x) => x.eventName === name);
    return r ? r.eventCount / 7 : 0;
  };
  const funnelUsers = (name, win = "d28") => sum((G?.funnelUsers?.[win]?.rows || []).filter((r) => r.eventName === name).map((r) => r.totalUsers));

  // ---- console: rollup, famiglie, chat, /join
  const metricsByDate = Object.fromEntries((C?.metrics || []).map((m) => [m.date, m]));
  const lastRollup = [...(C?.metrics || [])].reverse().find((m) => !m.missing && m.dau != null);
  const joinShown7 = sum((C?.inviteLanding || []).filter((r) => r.date >= days7[0]).map((r) => r.shown));
  const joinStore7 = sum((C?.inviteLanding || []).filter((r) => r.date >= days7[0]).map((r) => r.storeIos + r.storeAndroid));
  const chat7 = (C?.landingChat || []).filter((r) => r.date >= days7[0]);
  const chatTot = (k) => sum(chat7.map((r) => r[k]));

  // ---- Meta
  const metaByDate = Object.fromEntries((M?.series || []).map((r) => [r.date, r]));
  const spend14 = days14.map((d) => (M ? metaByDate[d]?.spend || 0 : null));
  const activeCampaigns = (M?.campaigns || []).filter((c) => c.status === "ACTIVE");

  // ---- Play / App Store
  const playByDate = Object.fromEntries((P?.installs || []).map((r) => [r.date, r]));
  const playInstalls14 = days14.map((d) => (playByDate[d] ? playByDate[d].installs : null));
  const playCrash14 = sum((P?.errors || []).map((e) => e.reports));
  const asDownloads = A?.reports?.downloads;
  const asDownloads14 = days14.map((d) => {
    if (!asDownloads?.available || !asDownloads.byDay?.[d]) return null;
    return sum(Object.values(asDownloads.byDay[d]));
  });
  const asEngagement = A?.reports?.engagement;

  // ---- Anthropic / Google
  const aiDayTotal = (d) => {
    const m = N?.costByDay?.[d];
    if (!m) return N ? 0 : null;
    return sum(Object.values(m).map((k) => sum(Object.values(k))));
  };
  const ai14 = days14.map(aiDayTotal);
  const gcByDay = B?.byDay || {};
  const gcLastDay = Object.keys(gcByDay).sort().pop();

  // ---- KPI
  const kpis = [
    {
      label: "Utenti attivi ieri (GA4)",
      value: fmt(activeTot[13]),
      sub: G ? `Android ${fmt(activeBy("Android")[13])} · iOS ${fmt(activeBy("iOS")[13])} · web ${fmt(activeBy("web")[13])}` : "GA4 non disponibile",
      delta: delta(activeTot[13], avg(activeTot.slice(6, 13))),
    },
    {
      label: "Nuovi utenti ieri (first_open)",
      value: fmt(evCount(G?.events?.yesterday, "first_open")),
      sub: "include i device di test di Google/Apple",
      delta: delta(evCount(G?.events?.yesterday, "first_open"), evBase("first_open")),
    },
    {
      label: "Famiglie con 2+ membri",
      value: fmt(C?.families?.with2plus),
      sub: C ? `su ${fmt(C.families.withMembers)} con membri · ${pct(C.families.with2plus / (C.families.withMembers || 1))}` : "console non disponibile",
      delta: { cls: "flat", text: "strutturale: cambia lentamente" },
    },
    {
      label: `DAU / WAU / MAU (${lastRollup ? itShort(lastRollup.date) : "—"})`,
      value: lastRollup ? `${fmt(lastRollup.dau)} / ${fmt(lastRollup.wau)} / ${fmt(lastRollup.mau)}` : "—",
      sub: lastRollup ? `WAU/MAU ${pct(lastRollup.stickinessWauMau)} · azioni di valore su Firestore` : "rollup non disponibile",
      delta: lastRollup ? delta(lastRollup.dau, avg(days14.slice(6, 13).map((d) => metricsByDate[d]?.dau).filter((v) => v != null))) : { cls: "flat", text: "" },
    },
    {
      label: "Letture cross-member (xread)",
      value: lastRollup && lastRollup.retrievedTotal ? pct(lastRollup.crossMemberReadRate) : "n/d",
      sub: lastRollup ? `su ${fmt(lastRollup.retrievedTotal)} letture · la tesi del prodotto` : "",
      delta: { cls: "flat", text: "leggere su più giorni" },
    },
    {
      label: "Spesa Meta ieri",
      value: M ? eur(spend14[13]) : "—",
      sub: M ? `${activeCampaigns.length} campagn${activeCampaigns.length === 1 ? "a attiva" : "e attive"} · click ${fmt(metaByDate[yesterday]?.clicks || 0)} · CTR ${fmt((metaByDate[yesterday]?.ctr || 0), 1)}%` : "Meta non disponibile",
      delta: delta(spend14[13], avg(spend14.slice(6, 13).filter((v) => v != null))),
    },
    {
      label: "Costo AI ieri (Anthropic)",
      value: N ? usd(N.totals.yesterday) : "—",
      sub: N ? `mese ${usd(N.totals.monthToDate)} · proiezione ${usd(N.totals.monthProjected)}` : "Anthropic non disponibile",
      delta: N ? delta(N.totals.yesterday, avg(ai14.slice(6, 13))) : { cls: "flat", text: "" },
    },
    {
      label: "Google Cloud, mese (netto)",
      value: B && B.totals.daysWithData ? eur(B.totals.monthNet) : "—",
      sub: B && B.totals.daysWithData ? `lordo ${eur(B.totals.monthGross)} · dati dal ${itDate(B.totals.firstDay)}` : "export in attesa delle prime righe",
      delta: { cls: "flat", text: B && B.totals.daysWithData ? "netto = dopo il free tier" : "" },
    },
  ];

  // ---- Funnel per utenti (28 gg)
  const funnelSteps = [
    ["Installazioni (first_open)", "first_open"],
    ["Login visto", "pre_signup_screen_shown"],
    ["Registrati", "signup_completed"],
    ["Onboarding iniziato", "onboarding_step_shown"],
    ["Onboarding completato", "onboarding_completed"],
    ["Famiglia creata", "family_created"],
    ["Invito generato", "invite_generated"],
    ["Join tentato", "family_join_attempted"],
    ["Entrati in famiglia", "family_joined"],
    ["Contenuto creato", "content_created"],
    ["Letto da un altro membro", "content_shared_read"],
  ].map(([label, ev]) => ({ label, value: G ? funnelUsers(ev) : 0 }));

  // ---- Sorgenti e freschezza
  const sourceRows = [
    ["GA4", results.ga4, G ? `ieri ${itDate(G.yesterday)}` : ""],
    ["Console (Auth + Firestore)", results.console, C ? `rollup fino al ${lastRollup ? itDate(lastRollup.date) : "—"}` : ""],
    ["Meta Ads", results.meta, M ? `ieri ${itDate(M.yesterday)}` : ""],
    ["Google Play", results.play, P ? `installazioni fino al ${itDate(P.installsUpTo)} · crash a ieri` : ""],
    ["App Store", results.appstore, A ? (asDownloads?.available ? `istanze fino al ${asDownloads.latest}` : "istanze App Analytics non ancora generate") : ""],
    ["Anthropic", results.anthropic, N ? `ieri ${itDate(N.yesterday)}` : ""],
    ["Google Cloud", results.gcloud, B ? (B.totals.daysWithData ? `export al ${(B.lastExport || "").slice(0, 16).replace("T", " ")}` : "tabella non ancora creata") : ""],
    ["Search Console", results.search, S ? (S.lastDay ? `dati fino al ${itDate(S.lastDay)} (${S.lagDays} gg di ritardo)` : "property senza dati") : ""],
  ];
  const notes = [...(G?.notes || []), ...(C?.notes || []), ...(M?.notes || []), ...(P?.notes || []), ...(A?.notes || []), ...(N?.notes || []), ...(B?.notes || []), ...(S?.notes || [])];
  // ---- Search Console: serie 28 gg e primi giorni della property
  const scSeries = S?.series || [];
  const scDays = scSeries.map((r) => r.date);
  const scHasData = S && !S.empty && S.last28.impressions > 0;
  const scDelta = (a, b) => (b ? ` (${a >= b ? "+" : ""}${Math.round(((a - b) / b) * 100)}%)` : "");

  // ---- Commento del giorno
  const noteHtml = note
    ? note.split(/\n{2,}/).map((block) => {
      const lines = block.split("\n").filter((l) => l.trim());
      if (lines.every((l) => /^\s*[-•]\s+/.test(l))) return `<ul>${lines.map((l) => `<li>${inline(l.replace(/^\s*[-•]\s+/, ""))}</li>`).join("")}</ul>`;
      if (/^#{1,3}\s/.test(lines[0])) return `<h3>${inline(lines[0].replace(/^#+\s/, ""))}</h3>${lines.length > 1 ? `<p>${lines.slice(1).map(inline).join("<br>")}</p>` : ""}`;
      return `<p>${lines.map(inline).join("<br>")}</p>`;
    }).join("")
    : `<p class="muted">La routine delle 08:30 scrive qui la sintesi e le anomalie del giorno.</p>`;
  function inline(s) {
    return esc(s).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>").replace(/`(.+?)`/g, "<code>$1</code>");
  }

  const generatedAt = new Date().toLocaleString("it-IT", { timeZone: "Europe/Rome", dateStyle: "short", timeStyle: "short" });

  const html = `<title>Cruscotto KidBox</title>
<meta charset="utf-8">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
:root {
  color-scheme: light;
  --bg: #faf7f2; --surface: #ffffff; --surface-2: #f3eee6; --rule: #e7e0d4;
  --ink: #1d1a16; --ink-2: #5d574e; --ink-3: #8d857a;
  --accent: #e2570e; --accent-ink: #ffffff;
  --good: #1a7f37; --warn: #a86400; --bad: #c62828;
  --s1: #2a78d6; --s2: #eb6834; --s3: #1baf7a;
  --shadow: 0 1px 2px rgba(29,26,22,.06), 0 8px 24px -16px rgba(29,26,22,.25);
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --bg: #151311; --surface: #1e1b18; --surface-2: #26221e; --rule: #332e28;
    --ink: #f2ede5; --ink-2: #b9b1a5; --ink-3: #7f776c;
    --accent: #ff7a30; --accent-ink: #1d1a16;
    --good: #4cc26b; --warn: #e0a32e; --bad: #ef6b6b;
    --s1: #3987e5; --s2: #d95926; --s3: #199e70;
    --shadow: 0 1px 2px rgba(0,0,0,.4), 0 8px 24px -16px rgba(0,0,0,.6);
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --bg: #151311; --surface: #1e1b18; --surface-2: #26221e; --rule: #332e28;
  --ink: #f2ede5; --ink-2: #b9b1a5; --ink-3: #7f776c;
  --accent: #ff7a30; --accent-ink: #1d1a16;
  --good: #4cc26b; --warn: #e0a32e; --bad: #ef6b6b;
  --s1: #3987e5; --s2: #d95926; --s3: #199e70;
  --shadow: 0 1px 2px rgba(0,0,0,.4), 0 8px 24px -16px rgba(0,0,0,.6);
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font-family: "IBM Plex Sans", "Helvetica Neue", Arial, sans-serif; font-size: 15px; line-height: 1.45; padding-block: 28px 56px; padding-inline: 20px; }
.wrap { max-width: 1120px; margin: 0 auto; display: grid; gap: 28px; }
h1, h2, h3 { font-family: "Bricolage Grotesque", "IBM Plex Sans", sans-serif; text-wrap: balance; margin: 0; }
h1 { font-size: 30px; font-weight: 700; letter-spacing: -.01em; }
h2 { font-size: 19px; font-weight: 700; }
h3 { font-size: 15px; font-weight: 700; }
.eyebrow { font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: var(--ink-3); font-weight: 600; }
.muted { color: var(--ink-3); }
.num { font-variant-numeric: tabular-nums; }
code { font-family: "IBM Plex Mono", ui-monospace, Menlo, monospace; font-size: .92em; background: var(--surface-2); padding: 0 .3em; border-radius: 4px; }
header { display: flex; flex-wrap: wrap; align-items: flex-end; justify-content: space-between; gap: 12px 24px; border-bottom: 2px solid var(--accent); padding-bottom: 14px; }
header .date { font-family: "Bricolage Grotesque", sans-serif; font-size: 19px; color: var(--ink-2); }
.wordmark { display: flex; align-items: baseline; gap: 12px; }
.wordmark .mark { display: inline-block; width: 14px; height: 14px; border-radius: 4px; background: var(--accent); transform: translateY(-1px); }
section { display: grid; gap: 14px; }
.section-head { display: flex; align-items: baseline; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.section-head .hint { font-size: 13px; color: var(--ink-3); }
.note { background: var(--surface); border-left: 4px solid var(--accent); padding: 16px 20px; box-shadow: var(--shadow); border-radius: 0 8px 8px 0; }
.note p { margin: 0 0 8px; max-width: 72ch; }
.note p:last-child { margin: 0; }
.note ul { margin: 0 0 8px; padding-left: 20px; max-width: 72ch; }
.note h3 { margin: 10px 0 4px; }
.kpis { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
.kpi { background: var(--surface); border-radius: 10px; padding: 14px 16px 12px; box-shadow: var(--shadow); display: grid; gap: 4px; align-content: start; }
.kpi .v { font-family: "Bricolage Grotesque", sans-serif; font-size: 28px; font-weight: 700; line-height: 1.1; font-variant-numeric: tabular-nums; }
.kpi .sub { font-size: 12.5px; color: var(--ink-2); }
.kpi .d { font-size: 12px; font-weight: 600; }
.kpi .d.up { color: var(--good); } .kpi .d.down { color: var(--bad); } .kpi .d.flat { color: var(--ink-3); font-weight: 500; }
.grid2 { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 14px; }
.card { background: var(--surface); border-radius: 10px; padding: 16px 18px; box-shadow: var(--shadow); display: grid; gap: 10px; align-content: start; }
.card h3 { display: flex; justify-content: space-between; gap: 10px; align-items: baseline; }
.card h3 small { font-family: "IBM Plex Sans", sans-serif; font-size: 12px; font-weight: 500; color: var(--ink-3); }
.chart { width: 100%; height: auto; display: block; overflow: visible; }
.chart .grid { stroke: var(--rule); stroke-width: 1; }
.chart .axis { stroke: var(--ink-3); stroke-width: 1; opacity: .5; }
.chart .tick { fill: var(--ink-3); font-size: 10px; font-variant-numeric: tabular-nums; }
.chart .label { fill: var(--ink-2); font-size: 11px; font-weight: 600; }
.chart .line { fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
.chart .line.s1, .chart .dot.s1 { stroke: var(--s1); } .chart .dot.s1 { fill: var(--s1); }
.chart .line.s2, .chart .dot.s2 { stroke: var(--s2); } .chart .dot.s2 { fill: var(--s2); }
.chart .line.s3, .chart .dot.s3 { stroke: var(--s3); } .chart .dot.s3 { fill: var(--s3); }
.chart .dot { stroke-width: 2; fill: var(--surface); }
.chart .area.s1 { fill: var(--s1); opacity: .08; }
.chart .cross { stroke: var(--ink-3); stroke-dasharray: 3 3; }
.legend { display: flex; gap: 14px; flex-wrap: wrap; font-size: 12px; color: var(--ink-2); }
.legend span::before { content: ""; display: inline-block; width: 10px; height: 10px; border-radius: 2px; margin-right: 6px; vertical-align: -1px; background: var(--c); }
.tooltip { position: fixed; pointer-events: none; background: var(--ink); color: var(--bg); font-size: 12px; padding: 6px 9px; border-radius: 6px; box-shadow: var(--shadow); z-index: 10; white-space: nowrap; font-variant-numeric: tabular-nums; }
.funnel { display: grid; gap: 6px; }
.frow { display: grid; grid-template-columns: 200px 1fr; gap: 12px; align-items: center; }
.flabel { font-size: 13px; color: var(--ink-2); text-align: right; }
.fbar { position: relative; height: 22px; background: var(--surface-2); border-radius: 4px; }
.ffill { position: absolute; inset: 0 auto 0 0; background: var(--s1); border-radius: 4px; opacity: .9; }
.ffill.muted { background: var(--ink-3); }
.fval { position: absolute; left: 8px; top: 0; line-height: 22px; font-size: 12.5px; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--ink); mix-blend-mode: normal; }
.fval .rate { font-weight: 500; color: var(--ink-2); margin-left: 6px; }
table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
th, td { text-align: left; padding: 6px 8px; border-bottom: 1px solid var(--rule); vertical-align: top; }
th { font-size: 11px; letter-spacing: .08em; text-transform: uppercase; color: var(--ink-3); font-weight: 600; }
td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
.pill { display: inline-block; font-size: 11px; font-weight: 600; padding: 2px 8px; border-radius: 999px; background: var(--surface-2); color: var(--ink-2); }
.pill.ok { color: var(--good); } .pill.warn { color: var(--warn); } .pill.bad { color: var(--bad); }
.stars { color: var(--warn); letter-spacing: 1px; }
.review { font-size: 13.5px; color: var(--ink-2); }
.review q { font-style: italic; }
.sources td:first-child { font-weight: 600; }
footer { font-size: 12.5px; color: var(--ink-3); display: grid; gap: 4px; }
.tablewrap { overflow-x: auto; }
@media (max-width: 860px) {
  .kpis { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .grid2 { grid-template-columns: 1fr; }
  .frow { grid-template-columns: 1fr; gap: 2px; }
  .flabel { text-align: left; }
}
@media (max-width: 480px) { .kpis { grid-template-columns: 1fr; } h1 { font-size: 24px; } }
@media (prefers-reduced-motion: no-preference) { .ffill { transition: width .4s ease; } }
</style>
<div class="wrap">
  <header>
    <div>
      <div class="eyebrow">Report del mattino · otto fonti</div>
      <div class="wordmark"><span class="mark" aria-hidden="true"></span><h1>Cruscotto KidBox</h1></div>
    </div>
    <div class="date">ieri, ${itDate(yesterday)}</div>
  </header>

  <section>
    <div class="section-head"><h2>Commento del giorno</h2><span class="hint">scritto dalla routine, con le regole di lettura di KidBox</span></div>
    <div class="note">${noteHtml}</div>
  </section>

  <section>
    <div class="section-head"><h2>Ieri in otto numeri</h2><span class="hint">frecce contro la media dei 7 giorni precedenti</span></div>
    <div class="kpis">
      ${kpis.map((k) => `<div class="kpi"><div class="eyebrow">${esc(k.label)}</div><div class="v">${k.value}</div><div class="sub">${esc(k.sub)}</div>${k.delta.text ? `<div class="d ${k.delta.cls}">${esc(k.delta.text)}</div>` : ""}</div>`).join("\n      ")}
    </div>
  </section>

  <section>
    <div class="section-head"><h2>Funnel a 28 giorni, per utenti unici</h2><span class="hint">${G ? `${itDate(G.funnelUsers.d28.start)} → ${itDate(G.funnelUsers.d28.end)} · GA4` : "GA4 non disponibile"}${C ? ` · pagina /join negli ultimi 7 gg: ${fmt(joinShown7)} viste → ${fmt(joinStore7)} tap store` : ""}</span></div>
    <div class="card">${funnelChart(funnelSteps)}</div>
  </section>

  <section>
    <div class="section-head"><h2>Quattordici giorni</h2><span class="hint">passa il mouse per i valori</span></div>
    <div class="grid2">
      <div class="card"><h3>Utenti attivi per piattaforma <small>GA4</small></h3>
        ${G ? lineChart({ labels: days14, series: [{ name: "Android", values: activeBy("Android") }, { name: "iOS", values: activeBy("iOS") }, { name: "web", values: activeBy("web") }] }) : `<p class="muted">non disponibile</p>`}
        <div class="legend"><span style="--c:var(--s1)">Android</span><span style="--c:var(--s2)">iOS</span><span style="--c:var(--s3)">web</span></div></div>
      <div class="card"><h3>Spesa Meta, € al giorno <small>una sola campagna attiva: Traffico Landing</small></h3>
        ${M ? lineChart({ labels: days14, series: [{ name: "spesa €", values: spend14 }], decimals: 2 }) : `<p class="muted">non disponibile</p>`}
        <div class="legend"><span style="--c:var(--s1)">spesa €</span></div></div>
      <div class="card"><h3>Costo AI, $ al giorno <small>Anthropic, fatturato</small></h3>
        ${N ? lineChart({ labels: days14, series: [{ name: "$", values: ai14 }], decimals: 2 }) : `<p class="muted">non disponibile</p>`}
        <div class="legend"><span style="--c:var(--s1)">costo $</span></div></div>
      <div class="card"><h3>Installazioni dagli store <small>Play con 5-7 gg di ritardo · App Store quando Apple genera i report</small></h3>
        ${lineChart({ labels: days14, series: [{ name: "Play", values: playInstalls14 }, { name: "App Store", values: asDownloads14 }] })}
        <div class="legend"><span style="--c:var(--s1)">Google Play</span><span style="--c:var(--s2)">App Store</span></div></div>
    </div>
  </section>

  <section>
    <div class="section-head"><h2>Store</h2></div>
    <div class="grid2">
      <div class="card"><h3>Google Play <small>${P ? `export al ${itDate(P.installsUpTo)}` : "non disponibile"}</small></h3>
        ${P ? `<div class="tablewrap"><table><tr><th>ultimi 7 gg disponibili</th><th class="n">valore</th></tr>
        <tr><td>Installazioni</td><td class="n">${fmt(sum((P.installs || []).slice(-7).map((r) => r.installs)))}</td></tr>
        <tr><td>Disinstallazioni</td><td class="n">${fmt(sum((P.installs || []).slice(-7).map((r) => r.uninstalls)))}</td></tr>
        <tr><td>Device attivi (ultimo giorno)</td><td class="n">${fmt((P.installs || []).at(-1)?.activeDevices)}</td></tr>
        <tr><td>Valutazione media</td><td class="n">${P.rating ? fmt(P.rating.total, 2) : "—"}</td></tr>
        <tr><td>Crash negli ultimi 14 gg</td><td class="n">${fmt(playCrash14)}</td></tr>
        </table></div>
        ${(P.reviews || []).slice(0, 2).map((r) => `<div class="review"><span class="stars">${"★".repeat(r.stars || 0)}${"☆".repeat(5 - (r.stars || 0))}</span> <span class="muted">${itDate(r.date)} · v${esc(r.version || "?")}</span>${r.text ? `<br><q>${esc(r.text)}</q>` : ""}</div>`).join("")}` : `<p class="muted">${esc(results.play.error || "")}</p>`}
      </div>
      <div class="card"><h3>App Store <small>${A ? (asEngagement?.available ? `istanze fino al ${asEngagement.latest}` : "App Analytics: istanze non ancora generate") : "non disponibile"}</small></h3>
        ${A ? (asEngagement?.available ? `<p class="muted">Dati in arrivo: la pagina si popola al primo giorno con istanze.</p>` : `<p class="muted">Apple genera i report 1-2 giorni dopo la richiesta (fatta il 15/09/2026). Intanto, le recensioni:</p>`) : ""}
        ${(A?.reviews || []).slice(0, 3).map((r) => `<div class="review"><span class="stars">${"★".repeat(r.stars || 0)}${"☆".repeat(5 - (r.stars || 0))}</span> <span class="muted">${itDate(r.date)} · ${esc(r.territory || "")}</span>${r.title ? ` <strong>${esc(r.title)}</strong>` : ""}${r.text ? `<br><q>${esc(r.text)}</q>` : ""}</div>`).join("")}
      </div>
    </div>
  </section>

  <section>
    <div class="section-head"><h2>Costi e base utenti</h2></div>
    <div class="grid2">
      <div class="card"><h3>Anthropic <small>costi reali, cache per modello (7 gg)</small></h3>
        ${N ? `<div class="tablewrap"><table><tr><th>modello</th><th class="n">letti da cache</th><th class="n">scritti</th><th class="n">output</th><th class="n">cache hit</th></tr>
        ${Object.entries((() => { const agg = {}; for (const d of days7) for (const [m, u] of Object.entries(N.usageByDay?.[d] || {})) { const a = (agg[m] = agg[m] || { uncached: 0, cacheRead: 0, cacheWrite: 0, output: 0 }); for (const k of Object.keys(a)) a[k] += u[k] || 0; } return agg; })()).map(([m, a]) => { const all = a.uncached + a.cacheRead + a.cacheWrite; return `<tr><td>${esc(m)}</td><td class="n">${fmt(a.cacheRead)}</td><td class="n">${fmt(a.cacheWrite)}</td><td class="n">${fmt(a.output)}</td><td class="n">${all ? pct(a.cacheRead / all) : "—"}</td></tr>`; }).join("") || `<tr><td colspan="5" class="muted">nessuna richiesta negli ultimi 7 giorni</td></tr>`}
        </table></div>
        <p class="muted">Stima interna del mese (ai_costs): ${C ? usd(C.ai?.costUsd) : "—"} · reale ${usd(N.totals.monthToDate)}${C && N.totals.monthToDate ? ` · scarto ${pct((C.ai.costUsd - N.totals.monthToDate) / N.totals.monthToDate)}` : ""}</p>` : `<p class="muted">${esc(results.anthropic.error || "")}</p>`}
      </div>
      <div class="card"><h3>Google Cloud <small>${B ? (B.totals.daysWithData ? `netto = dopo free tier e crediti` : "export attivato il 15/09/2026") : "non disponibile"}</small></h3>
        ${B && B.totals.daysWithData ? `<div class="tablewrap"><table><tr><th>servizio (${itDate(gcLastDay)})</th><th class="n">lordo</th><th class="n">netto</th></tr>
        ${Object.entries(gcByDay[gcLastDay] || {}).sort((a, b) => b[1].cost - a[1].cost).slice(0, 8).map(([s, v]) => `<tr><td>${esc(s)}</td><td class="n">${eur(v.cost)}</td><td class="n">${eur(v.cost + v.credits)}</td></tr>`).join("")}
        </table></div>
        <p class="muted">Mese: lordo ${eur(B.totals.monthGross)} · netto ${eur(B.totals.monthNet)}</p>` : `<p class="muted">${B ? (B.notes[0] || "in attesa delle prime righe") : esc(results.gcloud.error || "")}</p>`}
      </div>
      <div class="card"><h3>Base utenti <small>Auth + Firestore, senza gli account di test</small></h3>
        ${C ? `<div class="tablewrap"><table>
        <tr><td>Account</td><td class="n">${fmt(C.auth.total)}</td><td class="muted">registrati ieri ${fmt(C.auth.signups.yesterday)} · 7gg ${fmt(C.auth.signups.d7)} · 28gg ${fmt(C.auth.signups.d28)}</td></tr>
        <tr><td>«App viva»</td><td class="n">${fmt(C.auth.alive.d7)}</td><td class="muted">7gg · 24h ${fmt(C.auth.alive.d1)} · 28gg ${fmt(C.auth.alive.d28)} (login o rinnovo token)</td></tr>
        <tr><td>Famiglie</td><td class="n">${fmt(C.families.total)}</td><td class="muted">create ieri ${fmt(C.families.createdYesterday)} · 7gg ${fmt(C.families.created7d)} · membri ${fmt(C.families.membersTotal)}</td></tr>
        <tr><td>Paganti</td><td class="n">${fmt(C.families.paying.pro + C.families.paying.max)}</td><td class="muted">pro ${fmt(C.families.paying.pro)} · max ${fmt(C.families.paying.max)} · override console ${fmt(C.families.paying.overridePro + C.families.paying.overrideMax)}</td></tr>
        <tr><td>Ticket arrivati ieri</td><td class="n">${fmt(C.tickets.arrivedSinceYesterday.cases + C.tickets.arrivedSinceYesterday.crash + C.tickets.arrivedSinceYesterday.support)}</td><td class="muted">backlog «new»: bug ${fmt(C.tickets.casesNew)} · crash ${fmt(C.tickets.crashNew)} · supporto ${fmt(C.tickets.supportNew)}</td></tr>
        </table></div>` : `<p class="muted">${esc(results.console.error || "")}</p>`}
      </div>
      <div class="card"><h3>Chat «Chiedi a KidBox» <small>landing, ultimi 7 gg</small></h3>
        ${C ? `<div class="tablewrap"><table>
        <tr><td>Aperture</td><td class="n">${fmt(chatTot("opens"))}</td><td class="muted">risposte ${fmt(chatTot("faqChips") + chatTot("faqMatch") + chatTot("cache") + chatTot("llm"))}: FAQ ${fmt(chatTot("faqChips") + chatTot("faqMatch"))} · cache ${fmt(chatTot("cache"))} · modello ${fmt(chatTot("llm"))} · bloccate ${fmt(chatTot("blocked"))}</td></tr>
        <tr><td>Costo</td><td class="n">${usd(chatTot("costUsd"))}</td><td class="muted">tetto 1 $ al giorno</td></tr>
        </table></div>
        ${(C.landingChatQuestions || []).slice(0, 5).map((q) => `<div class="review"><span class="pill">${fmt(q.n)}×</span> <q>${esc(q.q)}</q> <span class="muted">${esc(q.sources || "")}</span></div>`).join("") || `<p class="muted">nessuna domanda scritta negli ultimi 7 giorni</p>`}` : ""}
      </div>
    </div>
  </section>

  <section>
    <div class="section-head"><h2>Google Search</h2><span class="hint">Search Console · property di dominio kidboxapp.com · ${S?.lastDay ? `dati fino al ${itDate(S.lastDay)}` : "in attesa dei primi dati"}</span></div>
    <div class="grid2">
      <div class="card"><h3>Click e impressioni da Google <small>28 gg · Search Console pubblica con 2-3 gg di ritardo</small></h3>
        ${S && scDays.length ? lineChart({ labels: scDays, series: [{ name: "impressioni", values: scSeries.map((r) => r.impressions) }, { name: "click", values: scSeries.map((r) => r.clicks) }] }) : `<p class="muted">${esc(results.search.error || "non disponibile")}</p>`}
        ${S && !S.empty ? `<p class="muted">Ultimi 7 gg: ${fmt(S.last7.clicks)} click${scDelta(S.last7.clicks, S.prev7.clicks)} su ${fmt(S.last7.impressions)} impressioni${scDelta(S.last7.impressions, S.prev7.impressions)} · CTR ${pct(S.last7.ctr)} · posizione media ${S.last7.position ? S.last7.position.toFixed(1) : "—"} · 28 gg: ${fmt(S.last28.clicks)} click, di cui brand («kidbox») ${fmt(S.brand28.clicks)}</p>` : ""}
        ${S && !scHasData ? `<p class="muted">La property è stata aggiunta a Search Console il 12/09/2026: i dati partono da lì e i primi giorni valgono zero. Non è un calo.</p>` : ""}
      </div>
      <div class="card"><h3>Query e pagine <small>28 gg · click / impressioni / posizione</small></h3>
        ${scHasData ? `<div class="tablewrap"><table>
        ${S.topQueries.slice(0, 6).map((q) => `<tr><td>${esc(q.query)}</td><td class="n">${fmt(q.clicks)}</td><td class="n muted">${fmt(q.impressions)}</td><td class="n muted">${q.position.toFixed(1)}</td></tr>`).join("")}
        ${S.topPages.slice(0, 5).map((q) => `<tr><td class="muted">${esc(q.page)}</td><td class="n">${fmt(q.clicks)}</td><td class="n muted">${fmt(q.impressions)}</td><td class="n muted">${q.position.toFixed(1)}</td></tr>`).join("")}
        </table></div>
        ${S.impressionsNoClicks.length ? `<p class="muted">Compare ma nessuno clicca: ${S.impressionsNoClicks.slice(0, 3).map((q) => `«${esc(q.query)}» (${fmt(q.impressions)}, pos. ${q.position.toFixed(0)})`).join(" · ")}</p>` : ""}` : `<p class="muted">${S ? "ancora nessuna query registrata" : ""}</p>`}
        ${S?.sitemaps?.length ? `<p class="muted">Sitemap: ${S.sitemaps.map((m) => `${esc(m.path)} ${fmt(m.submitted)} URL, letta il ${m.lastDownloaded ? itDate(m.lastDownloaded) : "—"}${m.errors ? `, ${m.errors} errori` : ""}`).join(" · ")}</p>` : ""}
      </div>
    </div>
  </section>

  <section>
    <div class="section-head"><h2>Fonti</h2><span class="hint">generato ${esc(generatedAt)}</span></div>
    <div class="card">
      <div class="tablewrap"><table class="sources">
        ${sourceRows.map(([name, r, fresh]) => `<tr><td>${esc(name)}</td><td>${r.data ? `<span class="pill ok">ok</span>` : `<span class="pill bad">errore</span>`}</td><td class="muted">${r.data ? esc(fresh) : esc(r.error || "")}</td></tr>`).join("")}
      </table></div>
      ${notes.length ? `<ul class="muted" style="margin:0;padding-left:18px;font-size:13px">${notes.map((n) => `<li>${esc(n)}</li>`).join("")}</ul>` : ""}
    </div>
  </section>

  <footer>
    <div>Solo aggregati: nessun nome, email o identificativo. I test dello sviluppatore sono esclusi da rollup e base utenti; da GA4 dopo la release dei client.</div>
    <div>Le regole di lettura (cosa misura davvero ogni numero) stanno nel prompt della routine <code>kidbox-ga4-daily</code>.</div>
  </footer>
</div>
<script>
(function () {
  var tip = document.createElement("div");
  tip.className = "tooltip"; tip.hidden = true; document.body.appendChild(tip);
  var fmt = function (v, d) { return v == null ? "—" : Number(v).toLocaleString("it-IT", { minimumFractionDigits: d, maximumFractionDigits: d }); };
  document.querySelectorAll("svg.chart[data-points]").forEach(function (svg) {
    var data; try { data = JSON.parse(svg.getAttribute("data-points")); } catch (e) { return; }
    var n = data.labels.length, hover = svg.querySelector(".hover"), cross = svg.querySelector(".cross");
    var padL = 8, padR = 70, W = 560;
    function idxAt(evt) {
      var r = svg.getBoundingClientRect(); var x = (evt.clientX - r.left) / r.width * W;
      var i = Math.round((x - padL) / (W - padL - padR) * (n - 1));
      return Math.max(0, Math.min(n - 1, i));
    }
    svg.addEventListener("mousemove", function (evt) {
      var i = idxAt(evt); var cx = padL + i * (W - padL - padR) / Math.max(1, n - 1);
      hover.hidden = false; cross.setAttribute("x1", cx); cross.setAttribute("x2", cx);
      var d = data.labels[i]; var lines = data.series.map(function (s) { return s.name + ": " + fmt(s.values[i], data.decimals || 0) + (data.unit || ""); });
      tip.innerHTML = "<strong>" + d.slice(8, 10) + "/" + d.slice(5, 7) + "</strong><br>" + lines.join("<br>");
      tip.hidden = false; tip.style.left = (evt.clientX + 12) + "px"; tip.style.top = (evt.clientY - 10) + "px";
    });
    svg.addEventListener("mouseleave", function () { hover.hidden = true; tip.hidden = true; });
  });
})();
</script>
`;
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, html);
  return { outFile, errors: Object.entries(results).filter(([, r]) => r.error).map(([k, r]) => `${k}: ${r.error}`) };
}

function main() {
  const args = process.argv.slice(2);
  const noteIdx = args.indexOf("--note");
  const outIdx = args.indexOf("--out");
  const note = noteIdx >= 0 && args[noteIdx + 1] && fs.existsSync(args[noteIdx + 1]) ? fs.readFileSync(args[noteIdx + 1], "utf8").trim() : null;
  const outFile = outIdx >= 0 && args[outIdx + 1] ? path.resolve(args[outIdx + 1]) : path.join(ROOT, "dashboard", "kidbox-dashboard.html");
  const { errors } = build({ note, outFile });
  console.log(`scritto ${outFile}`);
  for (const e of errors) console.error(`fonte non disponibile — ${e}`);
}

main();
