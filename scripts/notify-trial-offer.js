#!/usr/bin/env node
/**
 * Avviso una tantum della prova Pro ai proprietari di famiglie attive che
 * possono ancora attivarla. NON concede la prova: dal 30/09/2026 la prova parte
 * dal pulsante nelle app (iOS ≥ 2.3.7, Android ≥ 2.4.3, `startProTrial`), e
 * questa notifica serve solo a farla scoprire a chi non apre mai Utilizzo
 * spazio o i Piani.
 *
 *   node scripts/notify-trial-offer.js          # prova: elenco, nessun invio
 *   node scripts/notify-trial-offer.js --yes    # manda le notifiche
 *
 * Destinatari: proprietario di una famiglia
 *   - con almeno un membro attivo negli ultimi ACTIVE_DAYS giorni (Auth
 *     lastRefreshAt), cioè chi con buona probabilità ha già aggiornato l'app;
 *   - senza piano (niente abbonamento, override console o prova in corso);
 *   - senza account di prova dentro (config/internalUsers);
 *   - a cui la prova spetta ancora (nessun `trials/{uid}`);
 *   - mai avvisato prima (`trialOfferNotices/{uid}`, solo server).
 * Una notifica per persona, anche se possiede più famiglie.
 *
 * La versione dell'app non è registrata da nessuna parte: chi ha ancora la
 * versione vecchia non vede il pulsante. Per questo si lancia una settimana
 * dopo l'uscita delle versioni col pulsante, e il testo dice di aggiornare.
 * Rilanciarlo è innocuo: chi è già stato avvisato viene saltato.
 * Autenticazione: gcloud dell'Owner del progetto, come console-daily-report.js.
 */
const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const DOC = `projects/${PROJECT}/databases/(default)/documents`;
const ACTIVE_DAYS = 7;
const DAY = 86400000;
const APPLY = process.argv.includes("--yes");

const TESTI = {
  it: ["Prova Pro gratis per 14 giorni", "Spazio in più, pianificatori e assistente AI, senza carta. Aggiorna KidBox e attivala dall'app con un tocco."],
  en: ["Try Pro free for 14 days", "Extra storage, planners and the AI assistant, no card needed. Update KidBox and start it in the app with one tap."],
  fr: ["Essayez Pro gratuitement pendant 14 jours", "Espace supplémentaire, planificateurs et assistant IA, sans carte. Mettez KidBox à jour et activez-le dans l'app en un geste."],
  es: ["Prueba Pro gratis durante 14 días", "Espacio extra, planificadores y asistente de IA, sin tarjeta. Actualiza KidBox y actívala en la app con un toque."],
};

const tok = execFileSync("gcloud", ["auth", "print-access-token"], { encoding: "utf8" }).trim();
const H = { Authorization: `Bearer ${tok}`, "Content-Type": "application/json", "x-goog-user-project": PROJECT };

async function call(url, body, method) {
  const res = await fetch(url, { method: method || (body ? "POST" : "GET"), headers: H, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) { const e = new Error(`${res.status} ${url}: ${text.slice(0, 300)}`); e.status = res.status; throw e; }
  return json;
}
const val = (f) => (f ? Object.values(f)[0] : null);
const lang = (raw) => { const c = String(raw || "it").toLowerCase().split(/[-_]/)[0]; return TESTI[c] ? c : "it"; };
const ids = async (collectionId) => {
  const rows = await call(`${FS}:runQuery`, { structuredQuery: { from: [{ collectionId }], select: { fields: [] } } });
  return new Set(rows.filter((r) => r.document).map((r) => r.document.name.split("/").pop()));
};

(async () => {
  const cfg = await call(`${FS}/config/trial`).catch(() => ({}));
  if (val(cfg.fields?.enabled) !== true) { console.log("config/trial.enabled non è acceso: la prova non si può attivare, nessun avviso."); return; }

  const internal = new Set();
  const iu = await call(`${FS}/config/internalUsers`).catch(() => ({}));
  for (const v of Object.values(iu.fields || {})) {
    if (v.arrayValue) for (const x of v.arrayValue.values || []) internal.add(val(x));
    if (v.mapValue) for (const k of Object.keys(v.mapValue.fields || {})) internal.add(k);
  }
  const auth = await call(`https://identitytoolkit.googleapis.com/v1/projects/${PROJECT}/accounts:query`, { returnUserInfo: true, limit: "5000" });
  const lastSeen = {};
  for (const u of auth.userInfo || []) lastSeen[u.localId] = Number(u.lastRefreshAt ? Date.parse(u.lastRefreshAt) : u.lastLoginAt || 0);
  const users = await call(`${FS}:runQuery`, { structuredQuery: { from: [{ collectionId: "users" }], select: { fields: [{ fieldPath: "platform" }, { fieldPath: "notificationLanguage" }] } } });
  const userInfo = {};
  for (const r of users) if (r.document) userInfo[r.document.name.split("/").pop()] = { platform: val(r.document.fields?.platform) || "?", lang: lang(val(r.document.fields?.notificationLanguage)) };

  const rows = await call(`${FS}:runQuery`, { structuredQuery: { from: [{ collectionId: "members", allDescendants: true }], select: { fields: [{ fieldPath: "role" }, { fieldPath: "isDeleted" }] } } });
  const fam = {};
  for (const r of rows) {
    const d = r.document; if (!d) continue;
    const f = d.fields || {};
    if (f.isDeleted?.booleanValue || !f.role) continue;
    const parts = d.name.split("/");
    const fid = parts[parts.indexOf("families") + 1];
    (fam[fid] = fam[fid] || []).push({ uid: parts.pop(), role: val(f.role) });
  }
  const trials = await ids("trials");
  const notified = await ids("trialOfferNotices");

  const now = Date.now();
  const esclusi = {};
  const escludi = (m) => { esclusi[m] = (esclusi[m] || 0) + 1; };
  const perOwner = {};
  for (const [fid, members] of Object.entries(fam)) {
    const recent = Math.max(...members.map((m) => lastSeen[m.uid] || 0));
    if (now - recent > ACTIVE_DAYS * DAY) { escludi(`nessun membro attivo negli ultimi ${ACTIVE_DAYS} giorni`); continue; }
    if (members.some((m) => internal.has(m.uid))) { escludi("famiglia con un account di prova"); continue; }
    const famDoc = await call(`${FS}/families/${fid}`).catch(() => null);
    if (!famDoc) { escludi("documento famiglia mancante"); continue; }
    const f = famDoc.fields || {};
    const plan = val(f.plan); const ov = val(f.planOverride); const src = val(f.planSource);
    if (ov === "pro" || ov === "max") { escludi("piano assegnato dalla console"); continue; }
    if (plan && plan !== "free") { escludi(src === "trial" ? "già in prova" : "abbonata"); continue; }
    const owner = val(f.ownerUid) || members.find((m) => m.role === "owner")?.uid;
    if (!owner) { escludi("senza proprietario"); continue; }
    if (trials.has(owner)) { escludi("il proprietario ha già avuto la prova"); continue; }
    if (notified.has(owner)) { escludi("già avvisato"); continue; }
    const prev = perOwner[owner];
    if (prev && prev.recent >= recent) { escludi("il proprietario viene già avvisato per un'altra famiglia"); continue; }
    if (prev) escludi("il proprietario viene già avvisato per un'altra famiglia");
    perOwner[owner] = { fid, owner, recent, n: members.length };
  }
  const scelte = Object.values(perOwner).sort((a, b) => b.recent - a.recent);

  console.log(`Famiglie con membri: ${Object.keys(fam).length}`);
  console.log(`Proprietari da avvisare: ${scelte.length}`);
  for (const [m, n] of Object.entries(esclusi).sort((a, b) => b[1] - a[1])) console.log(`  escluse — ${m}: ${n}`);
  const perPiattaforma = scelte.reduce((acc, s) => { const p = userInfo[s.owner]?.platform || "?"; acc[p] = (acc[p] || 0) + 1; return acc; }, {});
  console.log(`  per piattaforma del proprietario: ${JSON.stringify(perPiattaforma)}`);
  console.log("\nfamiglia  membri  ultimo accesso  proprietario  lingua");
  for (const s of scelte) {
    const u = userInfo[s.owner] || { platform: "?", lang: "it" };
    console.log(`${s.fid.slice(0, 8)}  ${String(s.n).padStart(6)}  ${String(Math.floor((now - s.recent) / DAY)).padStart(5)} giorni fa  ${u.platform.padEnd(12)}  ${u.lang}`);
  }
  if (!APPLY) { console.log("\n(prova: nessun invio. Per mandare: --yes)"); return; }

  let avvisati = 0; let consegne = 0;
  for (const s of scelte) {
    const u = userInfo[s.owner] || { lang: "it" };
    const [title, body] = TESTI[u.lang];
    const toks = await call(`${FS}/users/${s.owner}/fcmTokens?pageSize=50`).catch(() => ({}));
    let ok = 0;
    for (const t of toks.documents || []) {
      const token = val(t.fields?.token);
      if (!token || t.fields?.enabled?.booleanValue === false) continue;
      // Stesso type delle altre push della prova: Android apre i Piani (card in
      // cima), iOS la sezione Abbonamento del Profilo.
      const data = { type: "pro_trial", stage: "offer", familyId: s.fid, title, body };
      await call(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`, { message: {
        token, notification: { title, body }, data,
        apns: { payload: { aps: { alert: { title, body }, sound: "default" } } },
        android: { priority: "HIGH", notification: { sound: "default", channel_id: "family_updates_v2", click_action: "it.vittorioscocca.kidbox.NOTIFICATION_CLICK" } },
      } }).then(() => ok++).catch(() => {});
    }
    consegne += ok;
    // Si segna anche senza consegne (nessun token attivo): non va riprovato ogni volta.
    await call(`https://firestore.googleapis.com/v1/${DOC}:commit`, { writes: [
      { update: { name: `${DOC}/trialOfferNotices/${s.owner}`, fields: { familyId: { stringValue: s.fid }, delivered: { integerValue: String(ok) }, lang: { stringValue: u.lang } } },
        updateTransforms: [{ fieldPath: "sentAt", setToServerValue: "REQUEST_TIME" }],
        currentDocument: { exists: false } },
    ] }).then(() => avvisati++).catch(() => {});
  }
  console.log(`\nAvvisati: ${avvisati}/${scelte.length} · notifiche consegnate a FCM: ${consegne}`);
})().catch((e) => { console.error("ERRORE", e.message); process.exit(1); });
