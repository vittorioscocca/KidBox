#!/usr/bin/env node
/**
 * Regalo una tantum della prova Pro alle famiglie già esistenti e attive.
 *
 * La prova automatica (functions/proTrial.js) scatta solo alla nascita di una
 * famiglia: chi usava KidBox prima del 29/09/2026 non l'ha mai ricevuta. Questo
 * script gliela concede con le STESSE scritture e gli stessi paletti:
 *   - piano `pro`, planSource `trial`, planExpiresAt fra 14 giorni sulla famiglia;
 *   - registro `trials/{uid}` del proprietario (source: "gift"): una per persona;
 *   - mai a famiglie con un piano (abbonamento o override console), mai a chi ha
 *     già avuto la prova, mai a famiglie con dentro un account di prova.
 * Poi manda al proprietario una push nella sua lingua (type `pro_trial`).
 *
 *   node scripts/grant-trial-gift.js               # prova: elenco, nessuna scrittura
 *   node scripts/grant-trial-gift.js --yes         # concede e manda le push
 *   node scripts/grant-trial-gift.js --yes --no-push
 *
 * Attiva = almeno un membro con accesso o rinnovo della sessione negli ultimi
 * ACTIVE_DAYS giorni (Auth lastRefreshAt, lo stesso dato «app viva» del report).
 * Rilanciarlo è innocuo: chi ha già la prova viene saltato.
 * Autenticazione: gcloud dell'Owner del progetto, come console-daily-report.js.
 */
const { execFileSync } = require("node:child_process");

const PROJECT = "kidbox-42cd7";
const FS = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const DOC = `projects/${PROJECT}/databases/(default)/documents`;
const ACTIVE_DAYS = 14;
const TRIAL_DAYS = 14;
const AI_LIMIT = 50;
const DAY = 86400000;
const APPLY = process.argv.includes("--yes");
const PUSH = !process.argv.includes("--no-push");

const TESTI = {
  it: ["Un regalo per la tua famiglia", "14 giorni di Pro: spazio in più, pianificatori e assistente AI sbloccati, senza carta."],
  en: ["A gift for your family", "14 days of Pro: extra storage, planners and the AI assistant unlocked, no card needed."],
  fr: ["Un cadeau pour votre famille", "14 jours de Pro : espace supplémentaire, planificateurs et assistant IA débloqués, sans carte."],
  es: ["Un regalo para tu familia", "14 días de Pro: espacio extra, planificadores y asistente de IA desbloqueados, sin tarjeta."],
};

const tok = execFileSync("gcloud", ["auth", "print-access-token"], { encoding: "utf8" }).trim();
const H = { Authorization: `Bearer ${tok}`, "Content-Type": "application/json", "x-goog-user-project": PROJECT };

async function call(url, body, method) {
  const res = await fetch(url, { method: method || (body ? "POST" : "GET"), headers: H, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) { const e = new Error(`${res.status} ${url}: ${text.slice(0, 300)}`); e.status = res.status; e.json = json; throw e; }
  return json;
}
const val = (f) => (f ? Object.values(f)[0] : null);
const lang = (raw) => { const c = String(raw || "it").toLowerCase().split(/[-_]/)[0]; return TESTI[c] ? c : "it"; };

(async () => {
  // 1. Account di prova, attività Auth e piattaforma.
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

  // 2. Membri attivi per famiglia (non cancellati e con ruolo, come isMember nelle rules).
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

  // 3. Registro delle prove: una per persona.
  const trials = new Set();
  const tr = await call(`${FS}:runQuery`, { structuredQuery: { from: [{ collectionId: "trials" }], select: { fields: [] } } });
  for (const r of tr) if (r.document) trials.add(r.document.name.split("/").pop());

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
    // Una per persona: se possiede più famiglie attive, quella usata più di recente.
    const prev = perOwner[owner];
    if (prev && prev.recent >= recent) { escludi("il proprietario ne riceve già un'altra"); continue; }
    if (prev) escludi("il proprietario ne riceve già un'altra");
    perOwner[owner] = { fid, owner, recent, n: members.length, updateTime: famDoc.updateTime };
  }
  const scelte = Object.values(perOwner).sort((a, b) => b.recent - a.recent);

  console.log(`Famiglie con membri: ${Object.keys(fam).length}`);
  console.log(`Riceverebbero la prova: ${scelte.length}`);
  for (const [m, n] of Object.entries(esclusi).sort((a, b) => b[1] - a[1])) console.log(`  escluse — ${m}: ${n}`);
  const perMembri = scelte.reduce((acc, s) => { const k = s.n >= 2 ? "2+" : "1"; acc[k] = (acc[k] || 0) + 1; return acc; }, {});
  console.log(`  di cui con 1 membro: ${perMembri["1"] || 0} · con 2+ membri: ${perMembri["2+"] || 0}`);
  console.log("\nfamiglia  membri  ultimo accesso  proprietario  lingua");
  for (const s of scelte) {
    const u = userInfo[s.owner] || { platform: "?", lang: "it" };
    console.log(`${s.fid.slice(0, 8)}  ${String(s.n).padStart(6)}  ${String(Math.floor((now - s.recent) / DAY)).padStart(5)} giorni fa  ${u.platform.padEnd(12)}  ${u.lang}`);
  }
  console.log(`\nCosto AI nel caso peggiore: ${scelte.length} × ${AI_LIMIT} messaggi.`);
  if (!APPLY) { console.log("\n(prova: nessuna scrittura. Per concedere: --yes)"); return; }

  // 4. Concessione: famiglia + registro in un solo commit atomico, con precondizioni.
  let concesse = 0; let push = 0; const fallite = [];
  for (const s of scelte) {
    const expires = new Date(now + TRIAL_DAYS * DAY).toISOString();
    try {
      await call(`https://firestore.googleapis.com/v1/${DOC}:commit`, { writes: [
        { update: { name: `${DOC}/families/${s.fid}`, fields: { plan: { stringValue: "pro" }, planSource: { stringValue: "trial" }, planExpiresAt: { timestampValue: expires } } },
          updateMask: { fieldPaths: ["plan", "planSource", "planExpiresAt"] },
          updateTransforms: [{ fieldPath: "planUpdatedAt", setToServerValue: "REQUEST_TIME" }],
          currentDocument: { updateTime: s.updateTime } },
        { update: { name: `${DOC}/trials/${s.owner}`, fields: { familyId: { stringValue: s.fid }, plan: { stringValue: "pro" }, days: { integerValue: String(TRIAL_DAYS) }, aiLimit: { integerValue: String(AI_LIMIT) }, expiresAt: { timestampValue: expires }, source: { stringValue: "gift" } } },
          updateTransforms: [{ fieldPath: "startedAt", setToServerValue: "REQUEST_TIME" }],
          currentDocument: { exists: false } },
      ] });
      concesse++;
    } catch (e) { fallite.push(`${s.fid.slice(0, 8)}: ${e.status}`); continue; }

    if (!PUSH) continue;
    const u = userInfo[s.owner] || { lang: "it" };
    const [title, body] = TESTI[u.lang];
    const toks = await call(`${FS}/users/${s.owner}/fcmTokens?pageSize=50`).catch(() => ({}));
    for (const t of toks.documents || []) {
      const token = val(t.fields?.token);
      if (!token || t.fields?.enabled?.booleanValue === false) continue;
      const data = { type: "pro_trial", stage: "gift", familyId: s.fid, title, body };
      await call(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`, { message: {
        token, notification: { title, body }, data,
        apns: { payload: { aps: { alert: { title, body }, sound: "default" } } },
        android: { priority: "HIGH", notification: { sound: "default", channel_id: "family_updates_v2", click_action: "it.vittorioscocca.kidbox.NOTIFICATION_CLICK" } },
      } }).then(() => push++).catch(() => {});
    }
  }
  console.log(`\nConcesse: ${concesse}/${scelte.length} · push consegnate a FCM: ${push}`);
  if (fallite.length) console.log(`Non concesse (cambiate nel frattempo o già con prova): ${fallite.join(", ")}`);
})().catch((e) => { console.error("ERRORE", e.message); process.exit(1); });
