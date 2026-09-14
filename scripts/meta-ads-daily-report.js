#!/usr/bin/env node
/**
 * Fotografia giornaliera delle inserzioni Meta (Facebook/Instagram) di KidBox.
 *
 *   node scripts/meta-ads-daily-report.js           # report testuale
 *   node scripts/meta-ads-daily-report.js --json    # stesso contenuto, in JSON
 *   node scripts/meta-ads-daily-report.js --day 2026-09-13
 *
 * Terzo blocco della routine `kidbox-ga4-daily`, accanto a GA4 e console:
 * qui c'è quanto si spende e cosa dichiara Meta; l'incrocio con quello che
 * arriva davvero nell'app (first_open in GA4, registrazioni in Auth) lo fa
 * la routine, non questo script.
 *
 * Account: act_26185514281057282 (EUR, Europe/Rome), portfolio PassBox,
 * condiviso con kidbox_app. Token: utente di sistema «Conversions API System
 * User» del portfolio kidbox_app, app «KidBox Ads Reader» (creata apposta:
 * l'app KidBox del Login non può avere il caso d'uso Marketing API), permesso
 * solo `ads_read`, scadenza mai. Il token vive nel Portachiavi di macOS:
 *
 *   security add-generic-password -a kidbox -s meta-ads-token -w '<token>' -U
 *
 * e lo script lo legge con `security find-generic-password … -w`. Mai nel
 * repo, mai nel prompt della routine.
 */

const { execFileSync } = require("node:child_process");

const ACCOUNT = "act_26185514281057282";
const API = "https://graph.facebook.com/v21.0";
const TZ = "Europe/Rome";

// Le azioni che contano per KidBox, nell'ordine in cui vanno lette.
// Meta ne riporta decine (post_engagement, page_engagement…): rumore.
const KEY_ACTIONS = [
  ["link_click", "click sul link"],
  ["landing_page_view", "landing viste"],
  ["omni_app_install", "installazioni (Meta)"],
  ["mobile_app_install", "installazioni mobile"],
  ["omni_activate_app", "attivazioni app"],
  ["app_custom_event.fb_mobile_activate_app", "aperture app (SDK)"],
  ["omni_complete_registration", "registrazioni (Meta)"],
  ["lead", "lead"],
];

function token() {
  try {
    return execFileSync("security", ["find-generic-password", "-a", "kidbox", "-s", "meta-ads-token", "-w"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch {
    console.error(
      "Token Meta non trovato nel Portachiavi (voce «meta-ads-token», account «kidbox»).\n" +
        "Va rigenerato da Meta Business → Utenti di sistema → Conversions API System User → Genera token\n" +
        "(app «KidBox Ads Reader», permesso ads_read) e salvato con:\n" +
        "  security add-generic-password -a kidbox -s meta-ads-token -w '<token>' -U"
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

async function get(tok, path, params) {
  const url = new URL(`${API}/${path}`);
  url.searchParams.set("access_token", tok);
  for (const [k, v] of Object.entries(params || {})) url.searchParams.set(k, typeof v === "string" ? v : JSON.stringify(v));
  const res = await fetch(url);
  const json = await res.json();
  if (!res.ok || json.error) {
    const e = json.error || {};
    const err = new Error(`${path}: ${e.message || res.status}`);
    err.code = e.code;
    err.subcode = e.error_subcode;
    throw err;
  }
  return json;
}

const num = (x) => (x == null || x === "" ? 0 : Number(x));
function actionsMap(list) {
  const m = {};
  for (const a of list || []) m[a.action_type] = num(a.value);
  return m;
}

async function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const dayArg = args[args.indexOf("--day") + 1];
  const yesterday = args.includes("--day") && dayArg ? dayArg : shiftDay(romeDate(), -1);
  const seriesStart = shiftDay(yesterday, -13);
  const tok = token();
  const out = { account: ACCOUNT, yesterday, notes: [] };

  const acct = await get(tok, ACCOUNT, { fields: "name,currency,account_status,amount_spent" });
  out.currency = acct.currency;
  out.accountStatus = acct.account_status; // 1 = attivo
  out.lifetimeSpend = num(acct.amount_spent) / 100; // Meta lo dà in centesimi

  // Campagne: stato e budget, per sapere cosa sta girando.
  const camps = await get(tok, `${ACCOUNT}/campaigns`, {
    fields: "name,objective,effective_status,daily_budget,lifetime_budget,start_time,stop_time",
    limit: "100",
  });
  out.campaigns = camps.data.map((c) => ({
    id: c.id,
    name: c.name,
    objective: c.objective,
    status: c.effective_status,
    dailyBudget: c.daily_budget ? num(c.daily_budget) / 100 : null,
    lifetimeBudget: c.lifetime_budget ? num(c.lifetime_budget) / 100 : null,
    start: (c.start_time || "").slice(0, 10),
    stop: (c.stop_time || "").slice(0, 10),
  }));

  // Serie giornaliera dell'account, 14 giorni.
  const series = await get(tok, `${ACCOUNT}/insights`, {
    fields: "spend,impressions,reach,clicks,cpc,cpm,ctr,actions",
    time_range: { since: seriesStart, until: yesterday },
    time_increment: "1",
    limit: "100",
  });
  out.series = series.data.map((r) => ({
    date: r.date_start,
    spend: num(r.spend),
    impressions: num(r.impressions),
    reach: num(r.reach),
    clicks: num(r.clicks),
    cpc: num(r.cpc),
    cpm: num(r.cpm),
    ctr: num(r.ctr),
    actions: actionsMap(r.actions),
  }));

  // Ieri per campagna, con costo per azione.
  const byCamp = await get(tok, `${ACCOUNT}/insights`, {
    level: "campaign",
    fields: "campaign_name,spend,impressions,clicks,cpc,ctr,actions,cost_per_action_type",
    time_range: { since: yesterday, until: yesterday },
    limit: "100",
  });
  out.yesterdayByCampaign = byCamp.data.map((r) => ({
    name: r.campaign_name,
    spend: num(r.spend),
    impressions: num(r.impressions),
    clicks: num(r.clicks),
    cpc: num(r.cpc),
    ctr: num(r.ctr),
    actions: actionsMap(r.actions),
    costPerAction: actionsMap(r.cost_per_action_type),
  }));

  // Ultimi 7 giorni per campagna: il livello a cui i numeri piccoli iniziano a dire qualcosa.
  const byCamp7 = await get(tok, `${ACCOUNT}/insights`, {
    level: "campaign",
    fields: "campaign_name,spend,impressions,clicks,cpc,ctr,actions,cost_per_action_type",
    time_range: { since: shiftDay(yesterday, -6), until: yesterday },
    limit: "100",
  });
  out.last7ByCampaign = byCamp7.data.map((r) => ({
    name: r.campaign_name,
    spend: num(r.spend),
    impressions: num(r.impressions),
    clicks: num(r.clicks),
    cpc: num(r.cpc),
    ctr: num(r.ctr),
    actions: actionsMap(r.actions),
    costPerAction: actionsMap(r.cost_per_action_type),
  }));

  if (out.accountStatus !== 1) out.notes.push(`Account pubblicitario non attivo (account_status=${out.accountStatus}).`);
  if (!out.campaigns.some((c) => c.status === "ACTIVE")) out.notes.push("Nessuna campagna attiva.");

  if (asJson) {
    process.stdout.write(JSON.stringify(out, null, 2) + "\n");
    return;
  }
  print(out);
}

// ------------------------------------------------------------------ stampa
const pad = (s, n) => String(s ?? "-").padEnd(n);
const eur = (x) => `${(x || 0).toFixed(2)}`;
const pct = (x) => `${(x || 0).toFixed(1)}%`;

function print(o) {
  const L = [];
  L.push(`# Meta Ads KidBox — ieri ${o.yesterday} (${o.account}, ${o.currency}, ${TZ})`);
  L.push(`Speso da sempre: ${eur(o.lifetimeSpend)} ${o.currency}`);
  L.push("");

  L.push("## Campagne");
  for (const c of o.campaigns) {
    const budget = c.dailyBudget != null ? `${eur(c.dailyBudget)}/giorno` : c.lifetimeBudget != null ? `${eur(c.lifetimeBudget)} totale` : "senza budget";
    L.push(`${pad(c.status, 9)} ${c.name} — ${c.objective}, ${budget}, dal ${c.start}${c.stop ? ` al ${c.stop}` : ""}`);
  }
  L.push("");

  L.push("## Account per giorno (14 gg)");
  L.push(pad("giorno", 12) + pad("spesa", 8) + pad("impr", 7) + pad("reach", 7) + pad("click", 7) + pad("CPC", 7) + pad("CTR", 7) + "azioni chiave");
  const byDate = Object.fromEntries(o.series.map((r) => [r.date, r]));
  for (let i = 0; i < 14; i++) {
    const d = shiftDay(o.yesterday, i - 13);
    const r = byDate[d];
    if (!r) { L.push(pad(d, 12) + "(nessuna consegna)"); continue; }
    const acts = KEY_ACTIONS.filter(([k]) => r.actions[k]).map(([k, label]) => `${label}=${r.actions[k]}`).join(", ");
    L.push(pad(d, 12) + pad(eur(r.spend), 8) + pad(r.impressions, 7) + pad(r.reach, 7) + pad(r.clicks, 7) + pad(eur(r.cpc), 7) + pad(pct(r.ctr), 7) + acts);
  }
  // Somme per finestra di date, non per posizione: i giorni senza consegna
  // non hanno riga nella serie.
  const sumWindow = (from, to) => {
    const t = { spend: 0, clicks: 0, impressions: 0 };
    for (let i = from; i <= to; i++) {
      const r = byDate[shiftDay(o.yesterday, i)];
      if (!r) continue;
      t.spend += r.spend; t.clicks += r.clicks; t.impressions += r.impressions;
    }
    return t;
  };
  const tot7 = sumWindow(-6, 0);
  const totPrev7 = sumWindow(-13, -7);
  L.push(`Ultimi 7 gg: spesa ${eur(tot7.spend)}, ${tot7.impressions} impr, ${tot7.clicks} click · 7 gg prima: spesa ${eur(totPrev7.spend)}, ${totPrev7.impressions} impr, ${totPrev7.clicks} click`);
  L.push("");

  const campBlock = (title, rows) => {
    L.push(title);
    if (!rows.length) { L.push("(nessuna consegna)"); L.push(""); return; }
    for (const r of rows) {
      const acts = KEY_ACTIONS.filter(([k]) => r.actions[k])
        .map(([k, label]) => `${label}=${r.actions[k]}${r.costPerAction[k] ? ` (${eur(r.costPerAction[k])} l'una)` : ""}`)
        .join(", ");
      L.push(`- ${r.name}: spesa ${eur(r.spend)}, ${r.impressions} impr, ${r.clicks} click, CPC ${eur(r.cpc)}, CTR ${pct(r.ctr)}${acts ? ` · ${acts}` : ""}`);
    }
    L.push("");
  };
  campBlock("## Ieri per campagna", o.yesterdayByCampaign);
  campBlock("## Ultimi 7 gg per campagna", o.last7ByCampaign);

  L.push("Le «installazioni» e «attivazioni» sono attribuite da Meta (finestra 7gg click / 1gg view): sovrastimano. Il numero onesto è first_open di GA4 e le registrazioni Auth.");
  if (o.notes.length) {
    L.push("");
    L.push("## Note");
    for (const n of o.notes) L.push(`- ${n}`);
  }
  process.stdout.write(L.join("\n") + "\n");
}

main().catch((e) => {
  console.error(`Errore Marketing API: ${e.message}`);
  if (e.code === 190) {
    console.error(
      "Token non valido o revocato. Rigeneralo da Meta Business → Utenti di sistema → Conversions API System User → Genera token\n" +
        "(app «KidBox Ads Reader», ads_read, scadenza mai) e salvalo con:\n" +
        "  security add-generic-password -a kidbox -s meta-ads-token -w '<token>' -U"
    );
  }
  process.exit(1);
});
