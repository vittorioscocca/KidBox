import { initializeApp }          from 'https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js';
import { getAuth, signInWithPopup, signOut, onAuthStateChanged, GoogleAuthProvider }
                                   from 'https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js';
import { getFirestore, collection, collectionGroup, doc, getDoc, getDocs, onSnapshot, query, orderBy, updateDoc, deleteDoc }
                                   from 'https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js';
import { getFunctions, httpsCallable }
                                   from 'https://www.gstatic.com/firebasejs/11.0.1/firebase-functions.js';
import { initializeAppCheck, ReCaptchaEnterpriseProvider }
                                   from 'https://www.gstatic.com/firebasejs/11.0.1/firebase-app-check.js';

// ── Escape ────────────────────────────────────────────────────────────────
// Titoli dei ticket, nomi di famiglia, nomi utente, versioni: li scrive chi
// usa l'app, e qui finiscono dentro innerHTML. Senza escape, un titolo come
// `<img src=x onerror=…>` girerebbe nel browser dell'admin. Ogni valore che
// non è un numero o un testo nostro passa da `escH`; dentro un `onclick="…"`
// si usa `jsArg`, che produce un letterale JS già protetto per l'attributo.
function escH(v) {
  return String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function jsArg(v) {
  return escH(JSON.stringify(String(v ?? '')));
}

// Chiave del sito reCAPTCHA Enterprise — LA STESSA della web app, va solo
// aggiunta `kidbox-42cd7.web.app` tra i domini autorizzati della chiave.
// È pubblica per design: identifica il sito, NON è un lasciapassare, quindi
// può stare nel sorgente servito. Un *debug token* invece non potrebbe:
// questa pagina è raggiungibile senza login (curl la scarica), e un debug
// token registrato varrebbe come bypass di App Check per l'intero progetto.
// Finché è vuota, App Check resta disattivo e la console funziona come prima.
const RECAPTCHA_SITE_KEY = '6LfZBa8tAAAAACyR2rmcLBU8owNod9b7lfPduPiX';

const CFG_KEY = 'kidbox_dash_cfg_v2';
function getCfg()   { try { return JSON.parse(localStorage.getItem(CFG_KEY)||'null'); } catch { return null; } }
function saveCfg(c) { localStorage.setItem(CFG_KEY, JSON.stringify(c)); }

let app, auth, db, functions, provider;

function initFirebase(cfg) {
  app      = initializeApp(cfg, 'kidbox-admin');

  // Subito dopo initializeApp e PRIMA di getAuth/getFirestore/getFunctions:
  // i token App Check si allegano alle richieste dei servizi creati dopo,
  // quindi invertire l'ordine lascerebbe scoperte le prime chiamate.
  if (RECAPTCHA_SITE_KEY) {
    // try/catch obbligatorio: App Check è infrastruttura OPZIONALE finché
    // l'enforcement è spento, quindi non deve mai poter spegnere la console.
    // Senza, un'eccezione qui salterebbe getAuth/getFirestore/getFunctions
    // qui sotto, lasciandoli non assegnati. Cause plausibili: chiave revocata,
    // dominio non più autorizzato, o un adblocker che blocca google.com/recaptcha.
    try {
      initializeAppCheck(app, {
        provider: new ReCaptchaEnterpriseProvider(RECAPTCHA_SITE_KEY),
        isTokenAutoRefreshEnabled: true,
      });
    } catch (e) {
      console.warn('[AppCheck] inizializzazione fallita, si prosegue senza token:', e);
    }
  } else {
    console.warn('[AppCheck] RECAPTCHA_SITE_KEY non configurata: App Check non attivo. ' +
                 'Obbligatoria prima di abilitare l\'enforcement lato server.');
  }

  auth     = getAuth(app);
  db       = getFirestore(app);
  functions = getFunctions(app, 'europe-west1');
  provider = new GoogleAuthProvider();
}

window.addEventListener('DOMContentLoaded', () => {
  const cfg = getCfg();
  if (cfg) { prefillForm(cfg); initFirebase(cfg); onAuthStateChanged(auth, handleAuth); }

  document.getElementById('btn-login').addEventListener('click', () => {
    if (!auth) { alert('Salva prima la configurazione'); return; }
    signInWithPopup(auth, provider).catch(e => showErr('Login fallito: ' + e.message));
  });
  document.getElementById('btn-save-cfg').addEventListener('click', saveAndConnect);
  document.getElementById('btn-refresh').addEventListener('click', () => loadAll());
  document.getElementById('btn-logout').addEventListener('click', () => signOut(auth));

  // Una pagina per voce di menu: l'hash dell'indirizzo dice quale (#families…),
  // così il link resta valido dopo il ricaricamento.
  document.querySelectorAll('.nav-group-hdr').forEach(h => h.addEventListener('click', () => {
    const g = h.closest('.nav-group');
    g.classList.toggle('open');
    h.setAttribute('aria-expanded', g.classList.contains('open'));
  }));
  window.addEventListener('hashchange', () => showPage(location.hash.slice(1), false));
  showPage(location.hash.slice(1) || 'users', false);

  // sidebar toggle mobile
  document.getElementById('sidebar-toggle')?.addEventListener('click', toggleSidebar);

  // chiudi sidebar cliccando su un nav-item (mobile)
  document.querySelectorAll('.nav-item').forEach(el => {
    el.addEventListener('click', () => {
      if (window.innerWidth <= 640) closeSidebar();
    });
  });
});

function prefillForm(cfg) {
  ['apiKey','authDomain','projectId'].forEach(k => {
    const el = document.getElementById('f-'+k);
    if (el && cfg[k]) el.value = cfg[k];
  });
}

function saveAndConnect() {
  const apiKey     = document.getElementById('f-apiKey').value.trim();
  const projectId  = document.getElementById('f-projectId').value.trim();
  const authDomain = document.getElementById('f-authDomain').value.trim() || `${projectId}.firebaseapp.com`;
  if (!apiKey || !projectId) { alert('API Key e Project ID sono obbligatori'); return; }
  const cfg = { apiKey, authDomain, projectId };
  saveCfg(cfg);
  if (app) { location.reload(); return; }
  initFirebase(cfg);
  onAuthStateChanged(auth, handleAuth);
}

function handleAuth(user) {
  if (user) {
    document.getElementById('screen-login').style.display = 'none';
    document.getElementById('screen-dash').style.display  = 'flex';
    document.getElementById('user-email').textContent     = user.email;
    loadAll();
    initTickets();
    initSupportTickets();
    checkAdminNotifStatus();
    loadPlansConfig();
  } else {
    document.getElementById('screen-login').style.display = 'flex';
    document.getElementById('screen-dash').style.display  = 'none';
  }
}

// ── helpers ──────────────────────────────
function fmtNum(n) {
  if (n==null||isNaN(n)) return '—';
  if (n>=1e6) return (n/1e6).toFixed(1)+'M';
  if (n>=1e3) return (n/1e3).toFixed(1)+'K';
  return String(Math.round(n));
}
function fmtBytes(b) {
  if (!b) return '0 B';
  if (b>=1e12) return (b/1e12).toFixed(2)+' TB';
  if (b>=1e9)  return (b/1e9).toFixed(2)+' GB';
  if (b>=1e6)  return (b/1e6).toFixed(1)+' MB';
  if (b>=1e3)  return (b/1e3).toFixed(1)+' KB';
  return b+' B';
}
const EUR_RATE = 0.92;

// ── Delta di allineamento ──────────────────────────────────────────────────
// AI: niente più delta fisso. I 0,5268 $ erano lo scarto di un solo mese ma
// venivano sommati a ogni mese in corso: a novembre 3 chiamate valevano
// «€0,98». Il costo vero è la fattura Anthropic (anthropic-daily-report.js);
// qui resta la stima interna, che a ottobre era il 26% sotto la fattura.
// Storage: Firebase 871 MB - Firestore 194.2 MB = 676.8 MB non tracciati
//
// Link utili:
//   Anthropic costi  → https://platform.claude.com/cost
//   Firebase Storage → https://console.firebase.google.com/u/1/project/kidbox-42cd7/overview
//   Google Billing   → https://console.cloud.google.com/billing/015E5B-092B59-BED0B8?authuser=1
const STORAGE_DELTA_B = 0;

function fmtEur(n)  { return n==null ? '—' : '€'+Number(n*EUR_RATE).toFixed(2).replace('.',','); }
function fmtUsd(n)  { return fmtEur(n); }

function monthKey() { return new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}).slice(0,7); }
function todayKey() { return new Date().toLocaleDateString('sv-SE',{timeZone:'Europe/Rome'}); }
function setVal(id,v) { const e=document.getElementById(id); if(e) e.textContent=v; }
function setStatus(msg, ok=true) {
  const dot = document.getElementById('status-dot');
  dot.className = 'dot '+(ok?'dot-ok':'dot-err');
  document.getElementById('status-msg').textContent = msg;
  document.getElementById('last-upd').textContent   = new Date().toLocaleTimeString('it-IT');
}
function showErr(msg) {
  const b = document.getElementById('err-box');
  b.textContent = '⚠ '+msg; b.style.display='block';
}

// ── Pie chart ────────────────────────────
// Il canvas non risolve `var(--…)`: un fillStyle così viene ignorato e
// tutte le fette uscivano del colore di prima.
function cssColor(c) {
  const m = /^var\((--[^)]+)\)$/.exec(c || '');
  return m ? getComputedStyle(document.documentElement).getPropertyValue(m[1]).trim() : c;
}
function drawPie(canvasId, slices) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const W = canvas.width, H = canvas.height;
  const cx = W/2, cy = H/2, r = Math.min(W,H)/2 - 8;
  ctx.clearRect(0,0,W,H);
  const total = slices.reduce((s,x)=>s+(x.val||0),0);
  if (!total) {
    ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--color-muted').trim();
    ctx.beginPath(); ctx.arc(cx,cy,r,0,Math.PI*2); ctx.fill();
    return;
  }
  let angle = -Math.PI/2;
  slices.forEach(s => {
    const sweep = (s.val/total)*Math.PI*2;
    ctx.beginPath();
    ctx.moveTo(cx,cy);
    ctx.arc(cx,cy,r,angle,angle+sweep);
    ctx.closePath();
    ctx.fillStyle = cssColor(s.color);
    ctx.fill();
    angle += sweep;
  });
  ctx.beginPath();
  ctx.arc(cx,cy,r*0.55,0,Math.PI*2);
  ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--color-card').trim() || '#fff';
  ctx.fill();
}

// ── Grafici SVG ──────────────────────────
// Barre impilate: `series` = [{name, color, values}] allineate a `labels`.
// SVG con i colori del tema, come renderTrendChart: niente librerie.
// `W` più largo per i grafici a tutta riga: il viewBox si scala con la
// larghezza, e a 420 le scritte uscirebbero enormi.
function renderBarChart(elId, labels, series, fmt = fmtNum, W = 420) {
  const el = document.getElementById(elId);
  if (!el) return;
  const H = 160, PL = 40, PB = 18, PT = 14;
  delete el.dataset.report;
  const totals = labels.map((_, i) => series.reduce((a, x) => a + (x.values[i] || 0), 0));
  const max = Math.max(...totals);
  if (!(max > 0)) { el.innerHTML = '<div class="dim small">Nessun dato</div>'; return; }
  const n = labels.length, slot = (W - PL - 6) / n, bw = Math.max(4, slot * 0.62);
  const y = v => PT + (H - PT - PB) * (1 - v / max);
  let bars = '';
  labels.forEach((l, i) => {
    const x = PL + i * slot + (slot - bw) / 2;
    let acc = 0;
    series.forEach(sr => {
      const v = sr.values[i] || 0;
      if (!v) return;
      const y1 = y(acc + v), y0 = y(acc);
      bars += `<rect x="${x.toFixed(1)}" y="${y1.toFixed(1)}" width="${bw.toFixed(1)}" height="${(y0 - y1).toFixed(1)}" rx="2" style="fill:${sr.color}"><title>${l} · ${sr.name}: ${fmt(v)}</title></rect>`;
      acc += v;
    });
    if (totals[i] && n <= 16) bars += `<text x="${(x + bw / 2).toFixed(1)}" y="${(y(totals[i]) - 3).toFixed(1)}" text-anchor="middle" font-size="8" style="fill:var(--color-text)">${fmt(totals[i])}</text>`;
  });
  const grid = [0, .5, 1].map(f => `<line x1="${PL}" x2="${W - 6}" y1="${y(max * f)}" y2="${y(max * f)}" style="stroke:var(--color-brd)"/><text x="${PL - 4}" y="${y(max * f) + 3}" text-anchor="end" font-size="9" style="fill:var(--color-dim)">${fmt(max * f)}</text>`).join('');
  const every = Math.ceil(n / 6);
  // Etichette contate dall'ultima, così la settimana in corso c'è sempre.
  const ticks = labels.map((l, i) => (n - 1 - i) % every === 0
    ? `<text x="${(PL + i * slot + slot / 2).toFixed(1)}" y="${H - 4}" text-anchor="middle" font-size="9" style="fill:var(--color-dim)">${l}</text>` : '').join('');
  const legend = series.length > 1 ? `<div class="small" style="margin-top:6px">${series.map(sr => `<span style="margin-right:12px;white-space:nowrap"><span style="display:inline-block;width:10px;height:10px;border-radius:2px;background:${sr.color};margin-right:4px"></span>${sr.name}</span>`).join('')}</div>` : '';
  el.innerHTML = `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:auto">${grid}${bars}${ticks}</svg>${legend}`;
  // Per l'export: il grafico come tabella dei suoi numeri.
  // Senza le righe a zero prima che i dati comincino.
  const first = Math.max(0, totals.findIndex(t => t > 0));
  el.dataset.report = reportMdTable(['Periodo', ...series.map(sr => sr.name), ...(series.length > 1 ? ['Totale'] : [])],
    labels.map((l, i) => [l, ...series.map(sr => fmt(sr.values[i] || 0)), ...(series.length > 1 ? [fmt(totals[i])] : [])]).slice(first));
}

// Ciambella con legenda: `slices` = [{name, val, color}].
function renderDonut(elId, slices) {
  const el = document.getElementById(elId);
  if (!el) return;
  const total = slices.reduce((a, x) => a + (x.val || 0), 0);
  const r = 46, C = 2 * Math.PI * r;
  let off = 0, arcs = '';
  if (total) slices.forEach(sl => {
    if (!sl.val) return;
    const len = sl.val / total * C;
    arcs += `<circle cx="60" cy="60" r="${r}" fill="none" stroke-width="22" style="stroke:${sl.color}" stroke-dasharray="${len.toFixed(2)} ${(C - len).toFixed(2)}" stroke-dashoffset="${(-off).toFixed(2)}" transform="rotate(-90 60 60)"><title>${sl.name}: ${sl.val}</title></circle>`;
    off += len;
  });
  else arcs = `<circle cx="60" cy="60" r="${r}" fill="none" stroke-width="22" style="stroke:var(--color-muted)"/>`;
  const pct = v => total ? Math.round(v / total * 100) + '%' : '—';
  el.innerHTML = `<div style="display:flex;align-items:center;gap:20px"><svg viewBox="0 0 120 120" width="120" height="120" style="flex-shrink:0">${arcs}<text x="60" y="64" text-anchor="middle" font-size="16" font-weight="600" style="fill:var(--color-text)">${total}</text></svg>
    <div class="pie-legend">${slices.map(sl => `<div class="legend-item"><div class="legend-dot" style="background:${sl.color}"></div><span class="legend-label">${sl.name}</span><span class="legend-val">${sl.val} · ${pct(sl.val)}</span></div>`).join('')}</div></div>`;
}

const romeDay = d => d.toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' });
// Ultime n settimane (lunedì, Europe/Rome), dalla più vecchia.
function lastNWeeks(n) {
  const w0 = weekStart(todayKey());
  return Array.from({ length: n }, (_, k) => addDaysStr(w0, -7 * (n - 1 - k)));
}
const weekLabel = ws => ws.slice(8, 10) + '/' + ws.slice(5, 7);

// ── UTENTI & FAMIGLIE: grafici ───────────
// Sempre senza account di test e senza le famiglie che li contengono, e
// senza il filtro di periodo delle tabelle: sono l'andamento complessivo.
function renderUserCharts() {
  const users = _allUsersRows.filter(u => !u.internal);
  const fams  = _familyRows.filter(r => !r.internal);
  const now = Date.now(), DAY = 864e5;

  const opened = days => users.filter(u => u.lastOpenAt && now - u.lastOpenAt.getTime() < days * DAY).length;
  const pctOf = (a, b) => b ? ` (${Math.round(a / b * 100)}%)` : '';
  const o7 = opened(7), o30 = opened(30);
  setVal('stat-open-7', fmtNum(o7));
  setVal('stat-open-7-sub', `su ${users.length} utenti${pctOf(o7, users.length)} · app e web`);
  setVal('stat-open-30', fmtNum(o30));
  setVal('stat-open-30-sub', `su ${users.length} utenti${pctOf(o30, users.length)}`);
  const multi = fams.filter(r => r.realMembers >= 2).length;
  setVal('stat-multi', fmtNum(multi));
  setVal('stat-multi-sub', `su ${fams.length} famiglie${pctOf(multi, fams.length)} · senza quelle di prova`);
  const trial = fams.filter(r => r.trial).length;
  setVal('stat-trial', fmtNum(trial));

  const weeks = lastNWeeks(12), idx = {};
  weeks.forEach((w, i) => idx[w] = i);
  const z = () => weeks.map(() => 0);
  const ios = z(), android = z(), other = z();
  users.forEach(u => {
    if (!u.createdAt) return;
    const i = idx[weekStart(romeDay(u.createdAt))];
    if (i == null) return;
    (u.platform === 'ios' ? ios : u.platform === 'android' ? android : other)[i]++;
  });
  renderBarChart('chart-signups', weeks.map(weekLabel), [
    { name: 'iOS', color: 'var(--color-blue)', values: ios },
    { name: 'Android', color: 'var(--color-green)', values: android },
    { name: 'Web / non noto', color: 'var(--color-dim-line)', values: other },
  ]);

  const shared = z(), alone = z();
  fams.forEach(r => {
    if (!r.createdAtMs) return;
    const i = idx[weekStart(romeDay(new Date(r.createdAtMs)))];
    if (i == null) return;
    (r.realMembers >= 2 ? shared : alone)[i]++;
  });
  renderBarChart('chart-newfam', weeks.map(weekLabel), [
    { name: 'Oggi con 2+ membri', color: 'var(--color-orange)', values: shared },
    { name: 'Ancora da soli', color: 'var(--color-dim-line)', values: alone },
  ]);

  const buckets = [['Nessun membro', r => r.realMembers === 0], ['1 membro', r => r.realMembers === 1],
    ['2 membri', r => r.realMembers === 2], ['3 membri', r => r.realMembers === 3], ['4 o più', r => r.realMembers >= 4]]
    .map(([lbl, f]) => [lbl, fams.filter(f).length]).filter(([lbl, n]) => n || lbl !== 'Nessun membro');
  const maxB = Math.max(1, ...buckets.map(b => b[1]));
  document.getElementById('bars-members').innerHTML = buckets.map(([lbl, n]) => `
    <div class="bar-row">
      <div class="bar-lbl">${lbl}</div>
      <div class="bar-track"><div class="bar-fill ${lbl.startsWith('1') || lbl.startsWith('Nessun') ? 'blue' : 'orange'}" style="width:${(n / maxB * 100).toFixed(1)}%"></div></div>
      <div class="bar-val">${n}${pctOf(n, fams.length)}</div>
    </div>`).join('');

  const paid = (plan) => fams.filter(r => !r.trial && !r.manual && r.plan === plan).length;
  renderDonut('donut-plans', [
    { name: 'Free', val: fams.filter(r => !r.trial && !r.manual && r.plan !== 'pro' && r.plan !== 'max').length, color: 'var(--color-dim-line)' },
    { name: 'Prova Pro', val: trial, color: 'var(--color-orange)' },
    { name: 'Pro pagante', val: paid('pro'), color: 'var(--color-blue)' },
    { name: 'Max pagante', val: paid('max'), color: 'var(--color-purple)' },
    { name: 'Pro/Max dati a mano', val: fams.filter(r => r.manual).length, color: 'var(--color-green)' },
  ]);
}

// ── SUPPORTO CHAT ─────────────────────────
let _supportUnsub = null;

function initSupportTickets() {
  if (_supportUnsub) _supportUnsub();
  const q = query(collection(db, 'support_tickets'), orderBy('createdAt', 'desc'));
  _supportUnsub = onSnapshot(q, snap => {
    const tickets = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    const newCount = tickets.filter(t => t.status === 'new').length;
    const navBadge = document.getElementById('nav-support-badge');
    if (navBadge) { navBadge.textContent = newCount > 0 ? newCount : ''; navBadge.style.display = newCount > 0 ? 'inline-flex' : 'none'; }
    const bnBdgS = document.getElementById('bn-bdg-support');
    if (bnBdgS) { bnBdgS.textContent = newCount > 0 ? newCount : ''; bnBdgS.style.display = newCount > 0 ? 'inline-block' : 'none'; }
    setVal('support-count-new',  tickets.filter(t => t.status === 'new').length);
    setVal('support-count-wip',  tickets.filter(t => t.status === 'in_progress').length);
    setVal('support-count-done', tickets.filter(t => t.status === 'resolved' || t.status === 'closed').length);
    renderSupportTable(tickets);
  }, err => console.error('support_tickets snapshot error', err));
}

function renderSupportTable(tickets) {
  const tbody = document.getElementById('support-tbody');
  if (!tbody) return;
  if (tickets.length === 0) {
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:var(--color-dim-line);padding:24px">Nessun ticket di supporto 🎉</td></tr>';
    return;
  }
  const typeIcon  = { bug:'🐛', question:'❓', suggestion:'💡', other:'📝' };
  const statusLabel = { new:'🔴 Nuovo', in_progress:'🟡 In lavorazione', resolved:'🟢 Risolto', closed:'⚫ Chiuso' };
  tbody.innerHTML = tickets.map(t => {
    const ts = t.createdAt?.toDate ? t.createdAt.toDate().toLocaleDateString('it-IT') : '—';
    const icon = typeIcon[t.type] || '📝';
    const st = t.status || 'new';
    const title = (t.title || '—').slice(0, 60);
    return `<tr>
      <td data-label="Tipo" style="font-size:16px">${icon}</td>
      <td data-label="Piattaforma" style="font-size:11px;opacity:.6">${escH(t.platform||'—')}</td>
      <td data-label="Titolo" style="max-width:220px;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis" title="${escH(t.title||'')}">${escH(title)}</td>
      <td data-label="Email" style="font-size:11px;opacity:.7;font-family:var(--mono)">${escH(String(t.userEmail||'—').slice(0,28))}</td>
      <td data-label="Versione" style="font-size:11px;opacity:.7">${escH(t.appVersion||'—')}</td>
      <td data-label="Stato"><span style="font-size:12px">${statusLabel[st]||escH(st)}</span></td>
      <td data-label="Data" style="font-size:11px;opacity:.6">${ts}</td>
      <td style="white-space:nowrap">
        <button class="btn-sm" onclick="supportDetail(${jsArg(t.id)})">🔍</button>
        ${st === 'new' ? `<button class="btn-sm btn-accent" onclick="supportAction('wip',${jsArg(t.id)})" style="margin-left:4px">Prendi</button>` : ''}
        ${st === 'in_progress' ? `<button class="btn-sm btn-accent" onclick="supportAction('resolve',${jsArg(t.id)})" style="margin-left:4px">Risolvi</button>` : ''}
        <button class="btn-sm" onclick="supportAction('delete',${jsArg(t.id)})" style="color:#f06060;margin-left:4px">🗑</button>
      </td>
    </tr>`;
  }).join('');
}

window.supportAction = async function supportAction(action, ticketId) {
  try {
    const ref = doc(db, 'support_tickets', ticketId);
    if (action === 'wip')     await updateDoc(ref, { status: 'in_progress' });
    if (action === 'resolve') await updateDoc(ref, { status: 'resolved' });
    if (action === 'delete') {
      if (!confirm('Eliminare questo ticket di supporto?')) return;
      await deleteDoc(ref);
    }
  } catch(e) { showErr('Errore azione supporto: ' + e.message); }
}

window.supportDetail = async function supportDetail(ticketId) {
  try {
    const snap = await getDoc(doc(db, 'support_tickets', ticketId));
    if (!snap.exists()) { alert('Ticket non trovato'); return; }
    const t = snap.data();
    const typeLabel = { bug:'🐛 Bug', question:'❓ Domanda', suggestion:'💡 Suggerimento', other:'📝 Altro' };
    const conv = (t.conversation || []).map(m =>
      `[${m.role.toUpperCase()}] ${typeof m.content === 'string' ? m.content : JSON.stringify(m.content)}`
    ).join('\n\n---\n\n');
    const logs = t.rawLogs ? t.rawLogs.slice(0, 6000) : '(nessun log)';
    const modal = document.getElementById('support-modal');
    document.getElementById('support-modal-type').textContent    = typeLabel[t.type] || t.type || '—';
    document.getElementById('support-modal-title').textContent   = t.title || '—';
    document.getElementById('support-modal-summary').textContent = t.summary || '—';
    document.getElementById('support-modal-device').textContent  = `${t.platform||'—'} ${t.osVersion||''} · ${t.device||''} · v${t.appVersion||'—'} · ${t.userEmail||'—'}`;
    document.getElementById('support-modal-conv').textContent    = conv || '(nessuna conversazione)';
    document.getElementById('support-modal-logs').textContent    = logs;
    document.getElementById('support-modal-id').textContent      = ticketId;
    modal.style.display = 'flex';
  } catch(e) { showErr('Errore dettaglio supporto: ' + e.message); }
}

// ── TICKET / CRASH REPORTS ────────────────
let _ticketUnsub = null;

function initTickets() {
  if (_ticketUnsub) _ticketUnsub();
  const q = query(collection(db, 'cases'), orderBy('createdAt', 'desc'));
  _ticketUnsub = onSnapshot(q, snap => {
    const cases = snap.docs.map(d => ({ id: d.id, ...d.data() }));
    const newC  = cases.filter(c => c.status === 'new').length;
    const taken = cases.filter(c => c.status === 'taken').length;
    const resolved = cases.filter(c => c.status === 'resolved').length;
    setVal('ticket-new',      newC);
    setVal('ticket-taken',    taken);
    setVal('ticket-resolved', resolved);
    const badge = document.getElementById('ticket-badge');
    if (badge) { badge.textContent = newC > 0 ? newC : ''; badge.style.display = newC > 0 ? 'inline-flex' : 'none'; }
    const navBadge = document.getElementById('nav-ticket-badge');
    if (navBadge) { navBadge.textContent = newC > 0 ? newC : ''; navBadge.style.display = newC > 0 ? 'inline-flex' : 'none'; }
    const bnBdg = document.getElementById('bn-bdg-tickets');
    if (bnBdg) { bnBdg.textContent = newC > 0 ? newC : ''; bnBdg.style.display = newC > 0 ? 'inline-block' : 'none'; }
    renderTicketTable(cases);
  }, err => console.error('tickets snapshot error', err));
}

function renderTicketTable(cases) {
  const tbody = document.getElementById('ticket-tbody');
  if (!tbody) return;
  if (cases.length === 0) {
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center;color:var(--color-dim-line);padding:24px">Nessun ticket 🎉</td></tr>';
    return;
  }
  const severityColor = { critical:'#f06060', high:'#f09050', medium:'#e8c44a', low:'#3bbf80' };
  const statusLabel   = { new:'🔴 Nuovo', taken:'🟡 In carico', resolved:'🟢 Risolto' };
  tbody.innerHTML = cases.map(c => {
    const ts = c.createdAt?.toDate ? c.createdAt.toDate().toLocaleDateString('it-IT') : '—';
    const sev = c.severity || 'medium';
    const st  = c.status || 'new';
    return `<tr>
      <td data-label="Gravità"><span style="background:${severityColor[sev]||'#888888'}22;color:${severityColor[sev]||'#888888'};padding:2px 8px;border-radius:4px;font-size:11px;font-weight:600">${escH(String(sev).toUpperCase())}</span></td>
      <td data-label="Piattaforma"><span style="font-size:11px;opacity:.6">${escH(c.platform||'—')}</span></td>
      <td data-label="Modulo" style="font-family:var(--mono);font-size:10px;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${escH(c.affectedModule||'')}">${escH(c.affectedModule||'—')}</td>
      <td data-label="Descrizione" style="max-width:220px;font-size:12px;white-space:normal;word-break:break-word">${escH(c.summary||'—')}</td>
      <td data-label="Versione" style="font-size:11px;opacity:.7">${escH(c.appVersion||'—')}</td>
      <td data-label="Stato"><span style="font-size:12px">${statusLabel[st]||escH(st)}</span>${c.assignedTo ? `<div style="font-size:10px;opacity:.5;margin-top:2px">${escH(c.assignedTo)}</div>` : ''}</td>
      <td data-label="Data" style="font-size:11px;opacity:.6">${ts}</td>
      <td style="white-space:nowrap">
        ${st === 'new'    ? `<button class="btn-sm" onclick="ticketAction('take',${jsArg(c.id)})">Prendi</button> ` : ''}
        ${st === 'taken'  ? `<button class="btn-sm btn-accent" onclick="ticketAction('resolve',${jsArg(c.id)})">Risolvi</button> ` : ''}
        ${st === 'resolved' ? `<button class="btn-sm" onclick="ticketAction('delete',${jsArg(c.id)})" style="color:#f06060">🗑</button>` : ''}
        ${st === 'new'    ? `<button class="btn-sm" onclick="ticketAction('delete',${jsArg(c.id)})" style="color:#f06060;margin-left:4px">🗑</button>` : ''}
        <button class="btn-sm" onclick="ticketDetail(${jsArg(c.id)})" style="margin-left:2px">🔍</button>
      </td>
    </tr>`;
  }).join('');
}

window.ticketAction = async function ticketAction(action, caseId) {
  try {
    if (action === 'take')    await httpsCallable(functions, 'takeCase')({ caseId });
    if (action === 'resolve') {
      const notes = prompt('Note sulla risoluzione (opzionale):') || '';
      await httpsCallable(functions, 'resolveCase')({ caseId, notes });
    }
    if (action === 'delete') {
      if (!confirm('Eliminare definitivamente questo ticket?')) return;
      await httpsCallable(functions, 'deleteCase')({ caseId });
    }
  } catch(e) { showErr('Errore azione ticket: ' + e.message); }
}

window.ticketDetail = async function ticketDetail(caseId) {
  try {
    const snap = await getDoc(doc(db, 'cases', caseId));
    if (!snap.exists()) { alert('Ticket non trovato'); return; }
    const c = snap.data();
    let rawLogs = '(nessun log disponibile)';
    if (c.reportId) {
      try {
        const rSnap = await getDoc(doc(db, 'crash_reports', c.reportId));
        if (rSnap.exists()) rawLogs = rSnap.data().rawLogs || rawLogs;
      } catch {}
    }
    const modal = document.getElementById('ticket-modal');
    document.getElementById('modal-title').textContent   = c.affectedModule || 'Dettaglio';
    document.getElementById('modal-summary').textContent = c.summary || '—';
    document.getElementById('modal-detail').textContent  = c.detail  || '—';
    document.getElementById('modal-device').textContent  = `${c.platform||'—'} ${c.osVersion||''} · ${c.device||''} · v${c.appVersion||'—'}`;
    document.getElementById('modal-logs').textContent    = rawLogs.slice(0, 8000);
    document.getElementById('modal-caseid').textContent  = caseId;
    modal.style.display = 'flex';
  } catch(e) { showErr('Errore dettaglio: ' + e.message); }
}

// ── ADMIN NOTIFICHE ──────────────────────
window.toggleAdminNotif = async function toggleAdminNotif(btn) {
  if (!auth?.currentUser) { showErr('Devi essere loggato'); return; }
  btn.disabled = true;
  btn.textContent = '⏳';
  try {
    const result = await httpsCallable(functions, 'registerAdminNotifications')({});
    console.log('registerAdminNotifications result:', result);
    btn.textContent = '🔔 Notifiche ✓';
    btn.style.opacity = '1';
    btn.classList.add('btn-accent');
    btn.style.background = '';
    alert('✅ Registrato!\nRiceverai una push su iPhone/iPad per ogni ticket critical.\n\nUID: ' + auth.currentUser.uid);
  } catch(e) {
    console.error('toggleAdminNotif error:', e);
    btn.textContent = '🔔 Notifiche';
    showErr('Errore registrazione notifiche: ' + (e.message || JSON.stringify(e)));
  } finally {
    btn.disabled = false;
  }
}

// ── MANUTENZIONE: contatori famiglie ─────
// Riallinea `user_quotas/{uid}.ownedFamilies`, che regge il limite di 2 famiglie
// per account. Serve per chi possedeva famiglie prima dell'introduzione dei
// trigger: senza il documento le rules leggono 0 e il limite non morde subito.
// Idempotente: si può rieseguire quando si vuole.
window.backfillFamilyQuotas = async function backfillFamilyQuotas(btn) {
  if (!auth?.currentUser) { showErr('Devi essere loggato'); return; }

  const etichetta = btn.innerHTML;
  btn.disabled = true;
  btn.textContent = '⏳';
  try {
    // Prima una simulazione: mostra cosa verrebbe scritto senza toccare nulla.
    const prova = (await httpsCallable(functions, 'backfillFamilyQuotas')({ dryRun: true })).data;
    const oltre = prova.proprietariOltreIlLimite || [];

    const riepilogo =
      `SIMULAZIONE (nulla è stato scritto)\n\n` +
      `Famiglie totali: ${prova.famiglieTotali}\n` +
      `Proprietari distinti: ${prova.proprietariDistinti}\n` +
      `Proprietari oltre il limite di 2: ${oltre.length}\n` +
      (oltre.length ? oltre.map(o => `  • ${o.ownerUid}: ${o.ownedFamilies} famiglie`).join('\n') + '\n' : '') +
      (prova.famiglieSenzaProprietario ? `Famiglie senza ownerUid: ${prova.famiglieSenzaProprietario}\n` : '') +
      `\nScrivere i ${prova.proprietariDistinti} contatori?`;

    if (!confirm(riepilogo)) {
      btn.innerHTML = etichetta;
      return;
    }

    const esito = (await httpsCallable(functions, 'backfillFamilyQuotas')({ dryRun: false })).data;
    alert(`✅ Backfill completato\n\nContatori scritti: ${esito.contatoriScritti}\nFamiglie totali: ${esito.famiglieTotali}`);
    btn.innerHTML = etichetta;
  } catch(e) {
    console.error('backfillFamilyQuotas error:', e);
    showErr('Errore backfill: ' + (e.message || JSON.stringify(e)));
    btn.innerHTML = etichetta;
  } finally {
    btn.disabled = false;
  }
}

// ── LISTINO PIANI ─────
// Editor di `config/plans`, il documento che il backend usa per applicare le
// quote e che iOS/Android leggono per mostrarle. La validazione vera sta lato
// server (functions/plansConfig.js): qui si controlla solo per dare l'errore
// prima del giro di rete. Vedi internal/plans-source-of-truth.md.

const PLANS_LANGS = [
  { code: 'it', nome: 'Italiano' },
  { code: 'en', nome: 'English' },
  { code: 'fr', nome: 'Français' },
  { code: 'es', nome: 'Español' },
];

let plansState = null;   // { plans, source, limits, bundled }

function plansEsc(v) {
  return String(v ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

/** Feature come testo modificabile: una per riga, `icona | testo | *` (* = grassetto). */
function featuresToText(list) {
  return (list || []).map(f => [f.icon || '', f.text || '', f.strong ? '*' : ''].join(' | ')).join('\n');
}
function textToFeatures(text) {
  return String(text || '').split('\n').map(r => r.trim()).filter(Boolean).map(riga => {
    const parti = riga.split('|').map(x => x.trim());
    return { icon: parti[0] || '', text: parti[1] || '', strong: (parti[2] || '') === '*' };
  }).filter(f => f.text);
}

window.loadPlansConfig = async function loadPlansConfig(esplicito) {
  if (!auth?.currentUser) return;
  const box = document.getElementById('plans-editor');
  if (!box) return;
  if (esplicito) box.innerHTML = '<div style="color:var(--color-dim);font-size:13px">Carico…</div>';
  try {
    plansState = (await httpsCallable(functions, 'getPlansConfig')({})).data;
    renderPlansEditor();
  } catch(e) {
    console.error('getPlansConfig error:', e);
    box.innerHTML = '<div style="color:#f87171;font-size:13px">Listino non caricato: ' + plansEsc(e.message) + '</div>';
  }
}

function renderPlansEditor() {
  const { plans, source, limits } = plansState;
  const origine = source === 'firestore'
    ? 'in uso: config/plans (modificato da console)'
    : 'in uso: plans.json dell\'ultimo deploy — config/plans assente o non valido';
  document.getElementById('plans-source').textContent =
    origine + ' · tetti: AI ≤ ' + limits.aiLimitMax + ' (Free ≤ ' + limits.aiLimitFreeMax + '), AI al mese ≤ ' + limits.aiMonthlyLimitMax + ', storage ≤ ' + Math.round(limits.storageBytesMax/1073741824) + ' GB';

  const ordine = ['free','pro','max'];
  document.getElementById('plans-editor').innerHTML = ordine.map(id => {
    const p = plans[id]; if (!p) return '';
    const gb = p.storageBytes >= 1073741824;
    const valoreStorage = gb ? p.storageBytes/1073741824 : p.storageBytes/1048576;
    return `
    <div style="border:1px solid var(--color-brd);border-radius:10px;padding:14px;margin-bottom:14px">
      <div style="font-weight:700;margin-bottom:10px">${plansEsc(p.displayName)} <span style="font-family:var(--mono);font-size:11px;color:var(--color-dim)">${plansEsc(p.productId || 'nessun prodotto store')}</span></div>
      <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:flex-end">
        <div class="field" style="margin:0;width:150px">
          <label>Storage</label>
          <div style="display:flex;gap:6px">
            <input type="number" step="any" min="0" id="plan-${id}-storage" value="${valoreStorage}" style="width:100%" />
            <select id="plan-${id}-unit" style="background:var(--color-muted);border:1px solid var(--color-brd);border-radius:8px;color:var(--color-text);font-size:12px">
              <option value="MB" ${gb?'':'selected'}>MB</option>
              <option value="GB" ${gb?'selected':''}>GB</option>
            </select>
          </div>
        </div>
        <div class="field" style="margin:0;width:120px">
          <label>Messaggi AI</label>
          <input type="number" min="0" step="1" id="plan-${id}-ai" value="${p.aiLimit}" style="width:100%" />
        </div>
        <div class="field" style="margin:0;width:110px">
          <label>Periodo</label>
          <input value="${plansEsc(p.aiPeriod)}" disabled style="width:100%;opacity:.6" title="Free è una tantum, i piani a pagamento sono giornalieri: non si cambia da qui" />
        </div>
        <div class="field" style="margin:0;width:120px">
          <label>Tetto AI / mese</label>
          <input type="number" min="0" step="1" id="plan-${id}-ai-month" value="${p.aiMonthlyLimit ?? 0}" ${p.aiPeriod === 'lifetime' ? 'disabled' : ''} style="width:100%${p.aiPeriod === 'lifetime' ? ';opacity:.6' : ''}" title="Messaggi AI per famiglia nel mese di calendario, oltre al limite giornaliero. 0 = nessun tetto. Se lo cambi, cambia anche il numero scritto nella frase dei messaggi AI (le app installate non conoscono un segnaposto per il mese)." />
        </div>
        <div class="field" style="margin:0;width:120px">
          <label>Prezzo / mese</label>
          <input type="number" step="0.01" min="0" id="plan-${id}-price" value="${p.priceMonthly}" style="width:100%" />
        </div>
        <div class="field" style="margin:0;width:120px">
          <label>Prezzo / anno</label>
          <input type="number" step="0.01" min="0" id="plan-${id}-price-year" value="${p.priceYearly ?? 0}" style="width:100%" title="Solo per le schede della landing: nelle app il prezzo lo mostra lo store. Deve coincidere con App Store Connect e Play Console." />
        </div>
        <label style="display:flex;align-items:center;gap:6px;font-size:12px;color:var(--color-dim);padding-bottom:8px">
          <input type="checkbox" id="plan-${id}-hot" ${p.highlighted?'checked':''} /> in evidenza
        </label>
      </div>
      ${PLANS_LANGS.map(l => `
      <details ${l.code==='it'?'open':''} style="margin-top:10px">
        <summary style="cursor:pointer;font-size:12px;color:var(--color-dim)">${l.nome}</summary>
        <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:8px">
          <div class="field" style="margin:0;width:150px"><label>Prezzo mostrato</label>
            <input id="plan-${id}-price-${l.code}" value="${plansEsc((p.priceLabel||{})[l.code]||'')}" style="width:100%" /></div>
          <div class="field" style="margin:0;flex:1;min-width:200px"><label>Sottotitolo</label>
            <input id="plan-${id}-tag-${l.code}" value="${plansEsc((p.tagline||{})[l.code]||'')}" style="width:100%" /></div>
          <div class="field" style="margin:0;width:160px"><label>Badge</label>
            <input id="plan-${id}-badge-${l.code}" value="${plansEsc((p.badge||{})[l.code]||'')}" style="width:100%" /></div>
        </div>
        <div class="field" style="margin:8px 0 0">
          <label>Feature — una per riga: <code>icona | testo | *</code> (* = grassetto). Segnaposto: <code>{storage}</code>, <code>{aiLimit}</code></label>
          <textarea id="plan-${id}-feat-${l.code}" rows="6" style="width:100%;background:var(--color-muted);border:1px solid var(--color-brd);border-radius:8px;padding:8px;color:var(--color-text);font-family:var(--mono);font-size:12px">${plansEsc(featuresToText((p.features||{})[l.code]))}</textarea>
        </div>
      </details>`).join('')}
    </div>`;
  }).join('');
}

/** Ricostruisce il listino dai campi del form. */
function plansFromForm() {
  const out = {};
  for (const id of ['free','pro','max']) {
    const base = plansState.plans[id];
    const unita = document.getElementById(`plan-${id}-unit`).value === 'GB' ? 1073741824 : 1048576;
    const spec = {
      storageBytes: Math.round(Number(document.getElementById(`plan-${id}-storage`).value) * unita),
      aiLimit: parseInt(document.getElementById(`plan-${id}-ai`).value, 10),
      aiPeriod: base.aiPeriod,
      aiMonthlyLimit: parseInt(document.getElementById(`plan-${id}-ai-month`).value, 10) || 0,
      priceMonthly: Number(document.getElementById(`plan-${id}-price`).value),
      priceYearly: Number(document.getElementById(`plan-${id}-price-year`).value),
      highlighted: document.getElementById(`plan-${id}-hot`).checked,
      priceLabel: {}, tagline: {}, badge: {}, features: {},
    };
    for (const l of PLANS_LANGS) {
      spec.priceLabel[l.code] = document.getElementById(`plan-${id}-price-${l.code}`).value;
      spec.tagline[l.code]    = document.getElementById(`plan-${id}-tag-${l.code}`).value;
      spec.badge[l.code]      = document.getElementById(`plan-${id}-badge-${l.code}`).value;
      spec.features[l.code]   = textToFeatures(document.getElementById(`plan-${id}-feat-${l.code}`).value);
    }
    out[id] = spec;
  }
  return out;
}

/** Differenze sulle sole quote: sono quelle che costano, e vanno confermate a occhio. */
function plansDiffQuote(nuovi) {
  const righe = [];
  for (const id of ['free','pro','max']) {
    const a = plansState.plans[id], b = nuovi[id];
    if (a.storageBytes !== b.storageBytes) righe.push(`${id}: storage ${fmtBytes(a.storageBytes)} → ${fmtBytes(b.storageBytes)}`);
    if (a.aiLimit !== b.aiLimit) righe.push(`${id}: messaggi AI ${a.aiLimit} → ${b.aiLimit}`);
    if ((a.aiMonthlyLimit ?? 0) !== (b.aiMonthlyLimit ?? 0)) righe.push(`${id}: tetto AI mensile ${a.aiMonthlyLimit ?? 0} → ${b.aiMonthlyLimit ?? 0}`);
    if (Number(a.priceMonthly) !== Number(b.priceMonthly)) righe.push(`${id}: prezzo ${a.priceMonthly} → ${b.priceMonthly} (solo etichetta, non tocca lo store)`);
  }
  return righe;
}

window.savePlansConfig = async function savePlansConfig(btn) {
  if (!auth?.currentUser || !plansState) { showErr('Listino non caricato'); return; }
  const nuovi = plansFromForm();
  const quote = plansDiffQuote(nuovi);

  const riepilogo = (quote.length
      ? 'Quote che cambiano:\n\n' + quote.join('\n') + '\n\n'
      : 'Nessuna quota cambia: solo testi.\n\n') +
    'Il backend applica i nuovi valori entro un minuto. Procedo?';
  if (!confirm(riepilogo)) return;

  const nota = prompt('Nota per lo storico (chi/perché):', '') || '';
  const etichetta = btn.innerHTML;
  btn.disabled = true; btn.textContent = '⏳';
  const esitoBox = document.getElementById('plans-result');
  try {
    const esito = (await httpsCallable(functions, 'savePlansConfig')({ plans: nuovi, note: nota })).data;
    esitoBox.textContent = `✅ Listino salvato (${esito.plans} piani)`;
    await loadPlansConfig();
  } catch(e) {
    console.error('savePlansConfig error:', e);
    esitoBox.textContent = '';
    showErr('Listino rifiutato: ' + (e.message || JSON.stringify(e)));
  } finally {
    btn.innerHTML = etichetta; btn.disabled = false;
  }
}

window.restorePlansConfig = async function restorePlansConfig(btn) {
  if (!auth?.currentUser) { showErr('Devi essere loggato'); return; }
  if (!confirm('Riportare config/plans al listino impacchettato con l\'ultimo deploy delle functions?\n\nLe modifiche fatte da console vanno perse (restano nello storico).')) return;
  const etichetta = btn.innerHTML;
  btn.disabled = true; btn.textContent = '⏳';
  try {
    await httpsCallable(functions, 'publishPlansConfig')({});
    document.getElementById('plans-result').textContent = '✅ Ripristinato dal deploy';
    await loadPlansConfig();
  } catch(e) {
    console.error('publishPlansConfig error:', e);
    showErr('Ripristino fallito: ' + (e.message || JSON.stringify(e)));
  } finally {
    btn.innerHTML = etichetta; btn.disabled = false;
  }
}

/** Scarica il listino nel formato di functions/plans.json, per repo e landing. */
window.downloadPlansJson = function downloadPlansJson() {
  if (!plansState) { showErr('Listino non caricato'); return; }
  const plans = {};
  for (const id of ['free','pro','max']) {
    const base = plansState.bundled[id] || {};
    plans[id] = Object.assign({}, plansFromForm()[id], {
      id, order: base.order, displayName: base.displayName,
      productId: base.productId ?? null, currency: base.currency,
    });
  }
  const doc = { version: 1, updatedAt: new Date().toISOString().slice(0,10), plans };
  const blob = new Blob([JSON.stringify(doc, null, 2) + '\n'], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'plans.json';
  a.click();
  URL.revokeObjectURL(a.href);
}

async function checkAdminNotifStatus() {
  if (!auth?.currentUser) return;
  const btn = document.getElementById('btn-notif');
  if (!btn) return;
  try {
    const result = await httpsCallable(functions, 'checkAdminNotifStatus')({});
    if (result.data?.registered) {
      btn.textContent = '🔔 ✓';
      btn.classList.add('btn-accent');
    } else {
      btn.textContent = '🔔';
      btn.classList.remove('btn-accent');
    }
  } catch(e) {
    console.warn('checkAdminNotifStatus:', e.message);
  }
}

// ── families table sort ───────────────────
let _familyRows = [];
let _famSort = { col: 'storage', dir: 'desc' };
let _famQuery = '';

// Ricerca per nome famiglia (anche email del proprietario e Family ID),
// senza distinguere maiuscole e accenti. Filtra solo la tabella: le stat card
// restano sul periodo selezionato.
const normSearch = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
function applyFamilySearch(rows) {
  const q = normSearch(_famQuery);
  if (!q) return rows;
  return rows.filter(r => [r.fname, r.ownerEmail, r.fid].some(v => normSearch(v).includes(q)));
}

window.searchFamilies = function(value) {
  _famQuery = value;
  _famPage = 1;
  renderFamiliesTable(_familyRows);
};

function sortRows(rows, col, dir) {
  return [...rows].sort((a, b) => {
    let va, vb;
    if (col === 'storage')   { va = a.storageBytes; vb = b.storageBytes; }
    else if (col === 'ai')   { va = a.aiMonth;      vb = b.aiMonth; }
    else if (col === 'date') { va = a.updatedAt?.getTime()||0; vb = b.updatedAt?.getTime()||0; }
    else if (col === 'lastOpen') { va = a.lastOpenAt?.getTime()||0; vb = b.lastOpenAt?.getTime()||0; }
    else { va = 0; vb = 0; }
    return dir === 'desc' ? vb - va : va - vb;
  });
}

window.sortFamilies = function(col) {
  if (_famSort.col === col) {
    _famSort.dir = _famSort.dir === 'desc' ? 'asc' : 'desc';
  } else {
    _famSort = { col, dir: 'desc' };
  }
  renderFamiliesTable(_familyRows);
  updateSortHeaders();
};

function updateSortHeaders() {
  document.querySelectorAll('th[data-sort]').forEach(th => {
    const col = th.dataset.sort;
    const arrow = th.querySelector('.sort-arrow');
    if (!arrow) return;
    if (col === _famSort.col) {
      arrow.textContent = _famSort.dir === 'desc' ? ' ↓' : ' ↑';
      th.style.color = 'var(--color-text)';
    } else {
      arrow.textContent = ' ↕';
      th.style.color = '';
    }
  });
}

function renderFamiliesTable(rows) {
  const tbody = document.getElementById('fam-tbody');
  if (!tbody) return;
  const filtered = applyTimeFilter(rows, 'updatedAt');

  // ── aggiorna stat card sempre coerenti con la vista filtrata ──
  // La prova Pro conta come Free: nessuno paga. Pro e Max separano chi paga
  // dagli override della console, che altrimenti sembrano abbonati.
  let pFree=0, pPro=0, pMax=0, mPro=0, mMax=0;
  filtered.forEach(r => {
    if(r.trial) pFree++;
    else if(r.plan==='pro') { pPro++; if(r.manual) mPro++; }
    else if(r.plan==='max') { pMax++; if(r.manual) mMax++; }
    else pFree++;
  });
  setVal('stat-families', fmtNum(filtered.length));
  setVal('stat-plan-pro', fmtNum(pPro));
  setVal('stat-plan-max', fmtNum(pMax));
  setVal('stat-plan-pro-sub', `${fmtNum(pPro-mPro)} paganti · ${fmtNum(mPro)} manuali da console`);
  setVal('stat-plan-max-sub', `${fmtNum(pMax-mMax)} paganti · ${fmtNum(mMax)} manuali da console`);
  _planData = { free: pFree, pro: pPro, max: pMax };
  updateLegend();
  drawPie('pie-plans', [
    { val: pFree, color: 'var(--color-dim-line)' },
    { val: pPro,  color: 'var(--color-blue)' },
    { val: pMax,  color: 'var(--color-purple)' },
  ]);

  const matched = applyFamilySearch(filtered);
  if (matched.length === 0) {
    const msg = _famQuery.trim()
      ? 'Nessuna famiglia corrisponde alla ricerca'
      : 'Nessuna famiglia nel periodo selezionato';
    tbody.innerHTML = `<tr><td colspan="9" class="empty">${msg}</td></tr>`;
    renderPagination('fam', 0, 1, 'famGoPage');
    return;
  }
  const sorted = sortRows(matched, _famSort.col, _famSort.dir);
  const page   = sorted.slice((_famPage-1)*PAGE_SIZE, _famPage*PAGE_SIZE);
  renderPagination('fam', sorted.length, _famPage, 'famGoPage');
  tbody.innerHTML = page.map(r => {
    const email = r.ownerEmail || '—';
    const emailShort = email.length > 28 ? email.slice(0,26)+'…' : email;
    const fnameShort = (r.fname||'—').length > 20 ? (r.fname||'—').slice(0,18)+'…' : (r.fname||'—');
    const platforms = [
      r.iosCount     ? `<span title="${r.iosCount} da iOS">🍎 ${r.iosCount}</span>`     : '',
      r.androidCount ? `<span title="${r.androidCount} da Android">🤖 ${r.androidCount}</span>` : '',
      r.webCount     ? `<span title="${r.webCount} dal web">🌐 ${r.webCount}</span>`     : '',
    ].filter(Boolean).join(' ') || '<span class="dim">—</span>';
    return `
    <tr>
      <td data-label="Family ID" class="mono dim" style="cursor:pointer;font-size:11px" title="${escH(r.fid)}"
        onclick="selectOverrideUser('',${jsArg(email)},${jsArg(r.fid)});showPage('plans')">
        ${escH(String(r.fid).slice(0,18))}…</td>
      <td data-label="Famiglia" style="font-size:13px;font-weight:500" title="${escH(r.fname||'')}">${escH(fnameShort)}</td>
      <td data-label="Email" class="dim" style="font-size:12px" title="${escH(email)}">${escH(emailShort)}</td>
      <td data-label="Piano"><span class="badge badge-${escH(r.plan)}">${escH(r.planLabel || r.plan)}</span></td>
      <td data-label="Dispositivi" style="font-size:13px;white-space:nowrap">${platforms}</td>
      <td data-label="Storage" class="mono">${fmtBytes(r.storageBytes)}</td>
      <td data-label="AI mese" class="mono ${r.aiMonth>0?'hi':''}">${r.aiMonth > 0 ? r.aiMonth : '—'}</td>
      <td data-label="Ultimo accesso" class="mono" style="font-size:11px;white-space:nowrap" title="${r.lastOpenAt ? r.lastOpenAt.toLocaleString('it-IT') + ' · ' + r.openedMembers7d + ' su ' + r.totalMembers + ' membri negli ultimi 7 giorni' : 'Nessun membro ha aperto l\'app iOS o Android negli ultimi 90 giorni'}">${fmtLastActive(r.lastOpenAt)}${r.totalMembers > 1 && r.lastOpenAt ? ` <span class="dim">${r.openedMembers7d}/${r.totalMembers}</span>` : ''}</td>
      <td data-label="Aggiornato" class="dim">${r.updatedAt?r.updatedAt.toLocaleDateString('it-IT'):'—'}</td>
    </tr>`;
  }).join('');
}

// ── FILTRI TEMPORALI ──────────────────────────────────────────────────────────
let _timeFilter = { preset: 'max', from: null, to: null };
const PAGE_SIZE = 10;
let _famPage  = 1;
let _userPage = 1;

function getFilterRange() {
  const now   = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  switch (_timeFilter.preset) {
    case 'today':     return { from: today, to: now };
    case 'yesterday': { const y=new Date(today); y.setDate(y.getDate()-1); const ye=new Date(today); return {from:y, to:ye}; }
    case 'week':      { const w=new Date(today); w.setDate(w.getDate()-7); return {from:w, to:now}; }
    case 'month':     { const m=new Date(today); m.setMonth(m.getMonth()-1); return {from:m, to:now}; }
    case 'custom':    return { from: _timeFilter.from, to: _timeFilter.to };
    default:          return { from: null, to: null };
  }
}

function applyTimeFilter(rows, dateField) {
  const { from, to } = getFilterRange();
  if (!from && !to) return rows;
  return rows.filter(r => {
    const d = r[dateField];
    if (!d) return false;
    if (from && d < from) return false;
    if (to   && d > to)   return false;
    return true;
  });
}

function updateFilterBadge() {
  const badge = document.getElementById('filter-active-badge');
  const { from, to } = getFilterRange();
  if (!from && !to) { badge.style.display='none'; return; }
  const fmt = d => d.toLocaleDateString('it-IT',{day:'2-digit',month:'short',year:'numeric'});
  const labels = { today:'Oggi', yesterday:'Ieri', week:'Ultimi 7 giorni', month:'Ultimo mese' };
  if (_timeFilter.preset !== 'custom') {
    badge.textContent = labels[_timeFilter.preset] || '';
  } else {
    badge.textContent = (from ? fmt(from) : '…') + ' → ' + (to ? fmt(to) : '…');
  }
  badge.style.display = 'inline-block';
}

window.setFilter = function(preset) {
  _timeFilter = { preset, from: null, to: null };
  document.querySelectorAll('.filter-pill').forEach(p => p.classList.remove('active'));
  event.currentTarget.classList.add('active');
  const cw = document.getElementById('filter-custom-wrap');
  if (preset === 'custom') { cw.classList.add('show'); }
  else { cw.classList.remove('show'); }
  _famPage  = 1;
  _userPage = 1;
  updateFilterBadge();
  renderFamiliesTable(_familyRows);
  renderUsersTable(_allUsersRows);
  updateStatsForFilter();
  refreshLandingForFilter();
};

window.applyCustomFilter = function() {
  const fromVal = document.getElementById('filter-from').value;
  const toVal   = document.getElementById('filter-to').value;
  _timeFilter.from = fromVal ? new Date(fromVal) : null;
  _timeFilter.to   = toVal   ? new Date(toVal + 'T23:59:59') : null;
  _famPage  = 1;
  _userPage = 1;
  updateFilterBadge();
  renderFamiliesTable(_familyRows);
  renderUsersTable(_allUsersRows);
  updateStatsForFilter();
  refreshLandingForFilter();
};

function renderPagination(prefix, totalRows, currentPage, goFn) {
  const totalPages = Math.max(1, Math.ceil(totalRows / PAGE_SIZE));
  const wrap = document.getElementById(prefix+'-pagination');
  const info = document.getElementById(prefix+'-pag-info');
  const prev = document.getElementById(prefix+'-pag-prev');
  const next = document.getElementById(prefix+'-pag-next');
  const pages = document.getElementById(prefix+'-pag-pages');

  if (totalRows === 0) { wrap.style.display='none'; return; }
  wrap.style.display = 'flex';

  const start = (currentPage-1)*PAGE_SIZE+1;
  const end   = Math.min(currentPage*PAGE_SIZE, totalRows);
  info.textContent = `${start}–${end} di ${totalRows}`;

  prev.disabled = currentPage <= 1;
  next.disabled = currentPage >= totalPages;

  // mostra max 5 pagine centrate sulla corrente
  const range = [];
  let lo = Math.max(1, currentPage-2);
  let hi = Math.min(totalPages, lo+4);
  lo = Math.max(1, hi-4);
  for (let i=lo; i<=hi; i++) range.push(i);
  pages.innerHTML = range.map(n =>
    `<button class="pag-btn${n===currentPage?' active':''}" onclick="${goFn}(${n})">${n}</button>`
  ).join('');
}

window.toggleSidebar = function() {
  const sb = document.getElementById('sidebar');
  const ov = document.getElementById('sidebar-overlay');
  const open = sb.classList.toggle('open');
  ov.classList.toggle('show', open);
};
window.closeSidebar = function() {
  document.getElementById('sidebar').classList.remove('open');
  document.getElementById('sidebar-overlay').classList.remove('show');
};

window.showPage = function(pid, push = true) {
  const pages = [...document.querySelectorAll('.page')];
  if (!pages.some(p => p.dataset.page === pid)) pid = 'users';
  pages.forEach(p => p.classList.toggle('active', p.dataset.page === pid));
  document.querySelectorAll('.nav-item[data-page]').forEach(l => l.classList.toggle('active', l.dataset.page === pid));
  document.querySelectorAll('.bn-item[data-page]').forEach(l => l.classList.toggle('active', l.dataset.page === pid));
  document.querySelector(`.nav-item[data-page="${pid}"]`)?.closest('.nav-group')?.classList.add('open');
  if (push && location.hash.slice(1) !== pid) history.pushState(null, '', '#' + pid);
  window.scrollTo(0, 0);
  if (pid === 'vault' && typeof window.loadKeyVault === 'function' && window._kbReady) window.loadKeyVault();
};

window.bnGo = function(el, pid) { showPage(pid); };

window.famGoPage = function(p) {
  const filtered = applyFamilySearch(applyTimeFilter(_familyRows, 'updatedAt'));
  const total = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  _famPage = Math.max(1, Math.min(p, total));
  renderFamiliesTable(_familyRows);
};

window.userGoPage = function(p) {
  const filtered = applyTimeFilter(_allUsersRows, 'createdAt');
  const total = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  _userPage = Math.max(1, Math.min(p, total));
  renderUsersTable(_allUsersRows);
};

// ─────────────────────────────────────────────────────────────────────────────
let _userSort = { col: 'lastOpenAt', dir: 'desc' };

window.sortUsers = function(col) {
  if (_userSort.col === col) {
    _userSort.dir = _userSort.dir === 'desc' ? 'asc' : 'desc';
  } else {
    _userSort = { col, dir: 'desc' };
  }
  renderUsersTable(_allUsersRows);
  updateUserSortHeaders();
};

function updateUserSortHeaders() {
  document.querySelectorAll('th[data-usort]').forEach(th => {
    const col = th.dataset.usort;
    const arrow = th.querySelector('.sort-arrow');
    if (!arrow) return;
    if (col === _userSort.col) {
      arrow.textContent = _userSort.dir === 'desc' ? ' ↓' : ' ↑';
      th.style.color = 'var(--color-text)';
    } else {
      arrow.textContent = ' ↕';
      th.style.color = '';
    }
  });
}

function renderFunnelSection(rows) {
  const el = document.getElementById('section-funnel');
  if (!el) return;

  const total = rows.length;
  const withFamily = rows.filter(r => r.totalMembers >= 1).length;
  const multi = rows.filter(r => r.totalMembers >= 2).length;
  const active2 = rows.filter(r => r.activeMembers14d >= 2).length;

  const pct = n => total > 0 ? Math.round(n / total * 100) : 0;
  const bar = (n, base, color) => {
    const w = base > 0 ? Math.round(n / base * 100) : 0;
    return `<div class="funnel-bar-wrap"><div class="funnel-bar" style="width:${w}%;background:${color}"></div></div>`;
  };

  // per-size breakdown
  const sizeMap = {};
  rows.forEach(r => {
    const k = r.totalMembers;
    if (!sizeMap[k]) sizeMap[k] = { count: 0, active: 0 };
    sizeMap[k].count++;
    if (r.activeMembers14d >= 2) sizeMap[k].active++;
  });
  const sizeRows = Object.entries(sizeMap)
    .sort(([a],[b]) => Number(a)-Number(b))
    .map(([k, v]) => `<tr>
      <td>${k === '0' ? '0 (solo owner)' : k} membri</td>
      <td>${v.count}</td>
      <td>${v.active}</td>
      <td>${v.count > 0 ? Math.round(v.active/v.count*100) : 0}%</td>
    </tr>`).join('');

  // target: 2+ membri ma <2 attivi in 14gg
  const targets = rows.filter(r => r.totalMembers >= 2 && r.activeMembers14d < 2)
    .sort((a,b) => b.totalMembers - a.totalMembers)
    .slice(0, 50);
  const targetRows = targets.map(r => `<tr>
    <td class="mono dim" style="font-size:11px">${escH(String(r.fid).slice(0,14))}…</td>
    <td>${escH(r.fname)}</td>
    <td>${r.totalMembers}</td>
    <td>${r.activeMembers14d}</td>
    <td><span class="badge badge-${escH(r.plan)}">${escH(r.planLabel || r.plan)}</span></td>
  </tr>`).join('');

  el.innerHTML = `
  <div class="tcard">
    <div class="tcard-hdr"><span>Funnel di attivazione</span></div>
    <div class="funnel-steps">
      <div class="funnel-step">
        <div class="funnel-step-label">Famiglie registrate</div>
        <div class="funnel-step-val">${total}</div>
        ${bar(total, total, '#6c8ebf')}
        <div class="funnel-step-pct">100%</div>
      </div>
      <div class="funnel-step">
        <div class="funnel-step-label">Con almeno 1 membro</div>
        <div class="funnel-step-val">${withFamily}</div>
        ${bar(withFamily, total, '#5a9e7a')}
        <div class="funnel-step-pct">${pct(withFamily)}%</div>
      </div>
      <div class="funnel-step">
        <div class="funnel-step-label">Con 2+ membri</div>
        <div class="funnel-step-val">${multi}</div>
        ${bar(multi, total, '#e0a040')}
        <div class="funnel-step-pct">${pct(multi)}% <span style="color:var(--color-dim);font-weight:400">· ${withFamily > 0 ? Math.round(multi/withFamily*100) : 0}% del passo prima</span></div>
      </div>
      <div class="funnel-step">
        <div class="funnel-step-label">2+ attivi (14 gg)</div>
        <div class="funnel-step-val">${active2}</div>
        ${bar(active2, total, '#c0504d')}
        <div class="funnel-step-pct">${pct(active2)}% <span style="color:var(--color-dim);font-weight:400">· ${multi > 0 ? Math.round(active2/multi*100) : 0}% del passo prima</span></div>
      </div>
    </div>
  </div>

  <div class="tcard" style="margin-top:16px">
    <div class="tcard-hdr"><span>Breakdown per dimensione famiglia</span></div>
    <div class="tbl-scroll"><table>
      <thead><tr><th>Dimensione</th><th>Famiglie</th><th>2+ attivi</th><th>Tasso</th></tr></thead>
      <tbody>${sizeRows || '<tr><td colspan="4" style="text-align:center;color:var(--color-dim)">Nessun dato</td></tr>'}</tbody>
    </table></div>
  </div>

  <div class="tcard" style="margin-top:16px">
    <div class="tcard-hdr">
      <span>Target attivazione <span class="badge" style="background:var(--color-orange);color:#fff;margin-left:6px">${targets.length}</span></span>
      <span style="font-size:11px;color:var(--color-dim)">2+ membri, &lt;2 attivi in 14 gg</span>
    </div>
    <div class="tbl-scroll"><table>
      <thead><tr><th>ID</th><th>Famiglia</th><th>Membri</th><th>Attivi</th><th>Piano</th></tr></thead>
      <tbody id="funnel-target-tbody">${targetRows || '<tr><td colspan="5" style="text-align:center;color:var(--color-dim)">Nessuna famiglia da attivare</td></tr>'}</tbody>
    </table></div>
  </div>`;
}

// Coorti per settimana di nascita (lun-dom, Europe/Rome): quante famiglie
// trovano un secondo membro e dopo quanti giorni. Le famiglie con un account di
// test dentro restano fuori. L'ultima settimana è incompleta e le coorti
// recenti maturano ancora: non leggerle come un calo.
function renderCohorts(rows) {
  const el = document.getElementById('section-cohorts');
  if (!el) return;
  const byWeek = {};
  rows.filter(r => !r.internal && r.createdAtMs).forEach(r => {
    const w = weekStart(new Date(r.createdAtMs).toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' }));
    const c = (byWeek[w] = byWeek[w] || { families: 0, grown: 0, days: [] });
    c.families++;
    if (r.totalMembers >= 2) {
      c.grown++;
      const second = [...r.joins].sort((a, b) => a - b)[1];
      if (second) c.days.push(Math.max(0, (second - r.createdAtMs) / 86400000));
    }
  });
  const thisWeek = weekStart(new Date().toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' }));
  const weeks = Object.keys(byWeek).sort().reverse().slice(0, 10);
  if (!weeks.length) { el.innerHTML = '<div class="tcard"><div class="dim small" style="padding:12px 16px">Nessuna famiglia con data di creazione</div></div>'; return; }
  const body = weeks.map(w => {
    const c = byWeek[w], ds = c.days.sort((a, b) => a - b);
    const med = ds.length ? ds[Math.floor(ds.length / 2)].toFixed(1) : '—';
    const pct = c.families ? Math.round(c.grown / c.families * 100) : 0;
    return `<tr><td>${w.slice(5)}${w >= thisWeek ? ' <span class="dim">(in corso)</span>' : ''}</td><td>${c.families}</td><td>${c.grown}</td><td><div class="funnel-bar-wrap" style="min-width:90px"><div class="funnel-bar" style="width:${pct}%;background:#5a9e7a"></div></div></td><td>${pct}%</td><td>${med}</td></tr>`;
  }).join('');
  el.innerHTML = `<div class="tcard"><div class="tbl-scroll"><table><thead><tr><th>Settimana dal</th><th>Nate</th><th>Con 2+ membri</th><th></th><th>Tasso</th><th>Giorni al 2° (mediana)</th></tr></thead><tbody>${body}</tbody></table></div>
  <div class="small dim" style="padding:8px 16px">È la stella polare per coorte: separa l'effetto di invito e onboarding dal rumore del giorno. Le coorti recenti maturano ancora, la settimana in corso è incompleta. Senza le famiglie con account di test.</div></div>`;
}

// Contatore nostro della landing (senza cookie): aperture, restati 10 secondi e
// tap sullo store per sorgente, ultimi 7 giorni chiusi. Un giorno senza documento
// vale zero (nessun ping). Doc: functions/landingTraffic.js.
// ── LANDING ──────────────────────────────
// Tre fonti che contano cose diverse e non si sommano:
//  · contatore `landingTraffic` (dal 16/09): ogni apertura di pagina, anche
//    senza consenso ai cookie; letto qui, lettura admin.
//  · Google Search (Search Console): click e impressioni nei risultati, con
//    2-3 giorni di ritardo.
//  · GA4 sugli host della landing: solo chi accetta i cookie, quindi meno.
// Le ultime due arrivano dalla callable getLandingStats (functions/landingStats.js),
// che tiene il risultato 30 minuti; «Aggiorna» lo rifà.
const LANDING_SRC = { meta: ['Meta', 'var(--color-purple)'], google: ['Google', 'var(--color-blue)'], direct: ['Diretto', 'var(--color-orange)'], referral: ['Altri siti', 'var(--color-green)'], other: ['Altro', 'var(--color-dim-line)'] };
const dm = id => id.slice(8, 10) + '/' + id.slice(5, 7);
const pctTxt = (n, d) => d ? Math.round(n / d * 100) + '%' : '—';
function deltaTxt(cur, prev) {
  if (!prev) return '';
  const d = Math.round((cur - prev) / prev * 100);
  return ` · ${d >= 0 ? '+' : ''}${d}% sul periodo prima`;
}
function tableCard(head, rows) {
  if (!rows.length) return '<div class="dim small" style="padding:12px 16px">Nessun dato</div>';
  return `<div class="tbl-scroll"><table><thead><tr>${head.map(h => `<th>${h}</th>`).join('')}</tr></thead><tbody>${
    rows.map(r => `<tr>${r.map((c, i) => `<td data-label="${head[i]}">${c}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`;
}
function barsCard(elId, items, color) {
  const el = document.getElementById(elId);
  if (!el) return;
  const max = Math.max(1, ...items.map(x => x[1]));
  const tot = items.reduce((a, x) => a + x[1], 0);
  el.innerHTML = items.length ? items.map(([lbl, n, sub]) => `
    <div class="bar-row">
      <div class="bar-lbl" title="${escH(lbl)}">${escH(lbl)}</div>
      <div class="bar-track"><div class="bar-fill ${color}" style="width:${(n / max * 100).toFixed(1)}%"></div></div>
      <div class="bar-val">${sub ?? fmtNum(n) + ' · ' + pctTxt(n, tot)}</div>
    </div>`).join('') : '<div class="dim small">Nessun dato</div>';
}
const escHtml = t => String(t).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// Il periodo scelto in alto, in giorni di calendario. Il contatore si filtra qui
// sui documenti per giorno; Google Search e GA4 tornano dal server per periodo.
// «Ultima settimana» sono 7 giorni con oggi, come la card che c'era prima.
function landingPeriod(firstDay) {
  const { from, to } = getFilterRange();
  const local = d => d.toLocaleDateString('sv-SE');
  const today = romeDay(new Date());
  let t = to ? local(new Date(to.getTime() - 1)) : today;
  if (t > today) t = today;
  let f = from ? local(from) : (firstDay || t);
  if (_timeFilter.preset === 'week') f = addDaysStr(t, -6);
  if (f > t) f = t;
  const days = [];
  for (let d = f; d <= t && days.length < 1000; d = addDaysStr(d, 1)) days.push(d);
  const n = days.length;
  const all = !from;
  const label = all ? 'da sempre' : (n === 1 ? dm(f) : `${dm(f)} → ${dm(t)}`);
  return { all, from: f, to: t, days, prev: days.map(d => addDaysStr(d, -n)), label };
}
function setLandingLabels(label) {
  document.querySelectorAll('[data-lp]').forEach(el => { el.textContent = el.dataset.lp.replace('{p}', label); });
}
function refreshLandingForFilter() {
  if (!_ltById) return;
  renderLandingCounter(_ltById);
  loadLandingGoogle(false);
}

let _landingLoaded = false;
let _ltById = null;
let _lgSeq = 0;
async function loadLanding() {
  const el = document.getElementById('section-landing');
  if (!el) return;
  // Google Search e GA4 non bloccano il resto della console.
  loadLandingGoogle(_landingLoaded);
  _landingLoaded = true;
  try {
    const snap = await getDocs(collection(db, 'landingTraffic'));
    const byId = {};
    snap.forEach(d => { byId[d.id] = d.data(); });
    _ltById = byId;
    renderLandingCounter(byId);
  } catch (e) {
    el.innerHTML = `<div class="tcard"><div class="dim small" style="padding:12px 16px">Errore: ${escH(e.message)}</div></div>`;
  }
}

function renderLandingCounter(byId) {
  const el = document.getElementById('section-landing');
  {
    const p = landingPeriod(Object.keys(byId).sort()[0]);
    setLandingLabels(p.label);
    const ids = p.days;
    const sumOf = (list, k) => list.reduce((a, id) => a + (byId[id]?.[k] || 0), 0);
    const allV = sumOf(ids, 'view'), allE = sumOf(ids, 'engaged');
    const stores = k => sumOf(ids, 'store_' + k);
    const allS = stores('ios') + stores('android') + stores('web');
    setVal('lt-views-lbl', p.all ? 'Aperture totali' : 'Aperture');
    setVal('lt-views', allV.toLocaleString('it-IT'));
    setVal('lt-views-sub', `${p.all ? 'dal ' + dm(p.from) : p.label} · ${ids.length} ${ids.length === 1 ? 'giorno' : 'giorni'} · media ${Math.round(allV / ids.length)} al giorno`);
    if (p.all) {
      const w1 = lastNDates(7), w0 = lastNDates(14).slice(7);   // da oggi indietro
      const v1 = sumOf(w1, 'view'), v0 = sumOf(w0, 'view');
      setVal('lt-week-lbl', 'Ultimi 7 giorni');
      setVal('lt-week', fmtNum(v1));
      setVal('lt-week-sub', `aperture negli ultimi 7 giorni (oggi compreso)${deltaTxt(v1, v0)}`);
    } else {
      const v0 = sumOf(p.prev, 'view');
      const range = p.prev.length === 1 ? dm(p.prev[0]) : `${dm(p.prev[0])} → ${dm(p.prev[p.prev.length - 1])}`;
      setVal('lt-week-lbl', 'Periodo prima');
      setVal('lt-week', fmtNum(v0));
      const delta = v0 ? ` · periodo scelto ${allV >= v0 ? '+' : ''}${Math.round((allV - v0) / v0 * 100)}%` : '';
      setVal('lt-week-sub', `${range}${delta}`);
    }
    setVal('lt-engaged', pctTxt(allE, allV));
    setVal('lt-engaged-sub', `${fmtNum(allE)} aperture rimaste almeno 10 s`);
    setVal('lt-store', fmtNum(allS));
    setVal('lt-store-sub', `iOS ${stores('ios')} · Android ${stores('android')} · web ${stores('web')} · ${pctTxt(allS, allV)} delle aperture`);

    const days = ids;
    renderBarChart('chart-lt-daily', days.map(dm), Object.entries(LANDING_SRC).map(([k, [name, color]]) => ({
      name, color, values: days.map(id => byId[id]?.['view_src_' + k] || 0),
    })), fmtNum, 1000);
    const PAGES = { home: 'Home', blog: 'Blog', strumenti: 'Strumenti', scarica: 'Scarica', other: 'Altre pagine' };
    barsCard('bars-lt-pages', Object.entries(PAGES).map(([k, l]) => [l, sumOf(ids, 'view_page_' + k)]).sort((a, b) => b[1] - a[1]), 'orange');
    const PLAT = { ios: 'iPhone / iPad', android: 'Android', other: 'Computer e altro' };
    barsCard('bars-lt-plat', Object.entries(PLAT).map(([k, l]) => [l, sumOf(ids, 'view_plat_' + k)]), 'blue');

    // Tabella per sorgente del periodo scelto.
    const wk = ids;
    const rows = Object.keys(LANDING_SRC).map(k => ({ k, v: sumOf(wk, 'view_src_' + k), e: sumOf(wk, 'engaged_src_' + k), s: sumOf(wk, 'store_src_' + k) }))
      .filter(r => r.v || r.s).sort((a, b) => b.v - a.v);
    document.getElementById('landing-sub').textContent = `· ${p.label}`;
    if (!rows.length) { el.innerHTML = '<div class="tcard"><div class="dim small" style="padding:12px 16px">Nessuna apertura registrata nel periodo</div></div>'; return; }
    const tv = sumOf(wk, 'view'), te = sumOf(wk, 'engaged');
    const ts = sumOf(wk, 'store_ios') + sumOf(wk, 'store_android') + sumOf(wk, 'store_web');
    const tr = rows.map(r => `<tr><td>${LANDING_SRC[r.k][0]}</td><td>${fmtNum(r.v)}</td><td>${fmtNum(r.e)} <span class="dim">${pctTxt(r.e, r.v)}</span></td><td>${fmtNum(r.s)}</td><td>${pctTxt(r.s, r.v)}</td></tr>`).join('');
    el.innerHTML = `<div class="tcard"><div class="tcard-hdr">Per sorgente · ${p.label}</div><div class="tbl-scroll"><table><thead><tr><th>Sorgente</th><th>Aperture</th><th>Restati 10 s</th><th>Tap store</th><th>Store ÷ aperture</th></tr></thead><tbody>${tr}
    <tr><td><b>Totale</b></td><td><b>${fmtNum(tv)}</b></td><td><b>${fmtNum(te)}</b> <span class="dim">${pctTxt(te, tv)}</span></td><td><b>${fmtNum(ts)}</b> <span class="dim">iOS ${sumOf(wk, 'store_ios')} · Android ${sumOf(wk, 'store_android')} · web ${sumOf(wk, 'store_web')}</span></td><td>${pctTxt(ts, tv)}</td></tr></tbody></table></div>
    <div class="small dim" style="padding:8px 16px">Conta le aperture di pagina, non le persone: si confronta con le «landing viste» di Meta, non con gli utenti di GA4. Le tue visite contano come le altre.</div></div>`;
  }
}

// ── Cassaforte v2 (getKeyVaultStats: solo conteggi, interni esclusi) ──
let _kvLoaded = false;
window.loadKeyVault = async function(force) {
  if (_kvLoaded && !force) return;
  _kvLoaded = true;
  const st = document.getElementById('kv-status');
  st.textContent = 'Calcolo…';
  let d;
  try {
    d = (await httpsCallable(functions, 'getKeyVaultStats', { timeout: 120000 })({})).data;
  } catch (e) { st.textContent = 'Errore: ' + e.message; _kvLoaded = false; return; }
  const pct = (a, b) => b ? Math.round(a * 100 / b) + '%' : '—';
  const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
  const f = d.flags || {};
  const sw = !f.exists ? 'interruttore assente (spento)' : f.enabled ? 'acceso per tutti' : f.internal ? 'acceso solo per gli interni' : 'spento';
  st.textContent = `config/keyVault: ${sw}${f.enforce ? ' · obbligatoria' : ''} · calcolato alle ${new Date(d.computedAt).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' })} · account interni esclusi`;
  set('kv-a30', pct(d.active30.withVault, d.active30.users)); set('kv-a30-sub', `${d.active30.withVault} su ${d.active30.users} membri aperti negli ultimi 30 giorni`);
  set('kv-a30-ready', pct(d.active30.allV2, d.active30.users));
  set('kv-a7', pct(d.active7.withVault, d.active7.users)); set('kv-a7-sub', `${d.active7.withVault} su ${d.active7.users}`);
  set('kv-pk', pct(d.active30.withPasskey, d.active30.users));
  const c = d.docs, i = d.internal;
  document.getElementById('kv-detail').innerHTML = `<div class="tcard" style="margin-top:16px"><div class="tcard-hdr">Copie della chiave (memberKeyBackups)</div><div class="tbl-scroll"><table><thead><tr><th></th><th>Documenti</th><th>Quota</th></tr></thead><tbody>
    <tr><td>Solo v1 (il server può aprirla)</td><td>${fmtNum(c.v1Only)}</td><td>${pct(c.v1Only, c.total)}</td></tr>
    <tr><td>v1 + v2</td><td>${fmtNum(c.v1AndV2)}</td><td>${pct(c.v1AndV2, c.total)}</td></tr>
    <tr><td>Solo v2 (dopo la Fase 3)</td><td>${fmtNum(c.v2Only)}</td><td>${pct(c.v2Only, c.total)}</td></tr>
    <tr><td><b>Totale</b></td><td><b>${fmtNum(c.total)}</b></td><td></td></tr></tbody></table></div>
    <div class="small dim" style="padding:8px 16px">Tutti i membri (anche non attivi): ${d.all.withVault} su ${d.all.users} con cassaforte (${pct(d.all.withVault, d.all.users)}). Account interni (${i.users}): ${i.vaults} cassaforti, ${i.docs.withV2} copie v2 su ${i.docs.total}. «Attivo» = ultima apertura dell'app (adminStats/lastOpen): il web non ci entra.</div></div>`;
};

async function loadLandingGoogle(force) {
  const status = document.getElementById('lg-status');
  if (status) status.textContent = 'Caricamento da Google…';
  const seq = ++_lgSeq;
  const p = landingPeriod(_ltById ? Object.keys(_ltById).sort()[0] : null);
  let d;
  try {
    d = (await httpsCallable(functions, 'getLandingStats', { timeout: 70000 })({ force: !!force, all: p.all, from: p.from, to: p.to })).data;
  } catch (e) {
    if (seq === _lgSeq && status) status.textContent = 'Errore: ' + e.message;
    return;
  }
  // Filtro cambiato mentre Google rispondeva: vale l'ultima richiesta.
  if (seq !== _lgSeq) return;
  if (status) status.textContent = `Letti da Google alle ${new Date(d.computedAt).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' })}`;
  renderSearchConsole(d.searchConsole || {}, p);
  renderLandingGa4(d.ga4 || {}, p);
}

function renderSearchConsole(sc, p) {
  const box = document.getElementById('sc-wrap');
  if (sc.error) { box.innerHTML = `<div class="tcard"><div class="dim small" style="padding:12px 16px">Search Console non disponibile: ${escHtml(sc.error)}</div></div>`; return; }
  const daily = sc.daily || [];
  const lastDay = daily.length ? daily[daily.length - 1].keys[0] : null;
  const byDay = new Map(daily.map(r => [r.keys[0], r]));
  const pick = ids => ids.map(id => byDay.get(id)).filter(Boolean);
  const agg = rows => {
    const c = rows.reduce((a, r) => a + r.clicks, 0), im = rows.reduce((a, r) => a + r.impressions, 0);
    const pos = im ? rows.reduce((a, r) => a + r.position * r.impressions, 0) / im : 0;
    return { c, im, ctr: im ? c / im : 0, pos };
  };
  const days = p.all ? daily.map(r => r.keys[0]) : p.days;
  // Google pubblica con 2-3 giorni di ritardo: un periodo che arriva a oggi ha
  // meno giorni del precedente, e il confronto segnerebbe un calo che non c'è.
  const partial = !p.all && !!lastDay && p.to > lastDay;
  const cur = agg(pick(days)), prevRows = p.all || partial ? [] : pick(p.prev), prev = prevRows.length ? agg(prevRows) : null;
  const scNote = partial ? ` · Google ha i dati fino al ${dm(lastDay)}` : '';
  setVal('sc-clicks', fmtNum(cur.c));
  setVal('sc-clicks-sub', `${p.label}${scNote}${prev ? deltaTxt(cur.c, prev.c) : ''}`);
  setVal('sc-impr', fmtNum(cur.im));
  setVal('sc-impr-sub', `volte che KidBox è apparso${scNote}${prev ? deltaTxt(cur.im, prev.im) : ''}`);
  setVal('sc-ctr', (cur.ctr * 100).toFixed(1).replace('.', ',') + '%');
  setVal('sc-pos', cur.pos ? cur.pos.toFixed(1).replace('.', ',') : '—');
  setVal('sc-sub', lastDay ? `· dati fino al ${dm(lastDay)} (Google pubblica con 2-3 giorni di ritardo)` : '');

  const labels = days.map(dm);
  renderBarChart('chart-sc-impr', labels, [{ name: 'Impressioni', color: 'var(--color-blue)', values: days.map(id => byDay.get(id)?.impressions || 0) }]);
  renderBarChart('chart-sc-clicks', labels, [{ name: 'Click', color: 'var(--color-green)', values: days.map(id => byDay.get(id)?.clicks || 0) }]);

  const pctF = x => (x * 100).toFixed(1).replace('.', ',') + '%';
  const posF = x => x.toFixed(1).replace('.', ',');
  document.getElementById('sc-queries').innerHTML = tableCard(['Ricerca', 'Click', 'Impressioni', 'CTR', 'Posizione'],
    (sc.queries || []).sort((a, b) => b.impressions - a.impressions).slice(0, 20)
      .map(r => [escHtml(r.keys[0]), r.clicks, fmtNum(r.impressions), pctF(r.ctr), posF(r.position)]));
  const short = u => u.replace(/^https:\/\/(www\.)?kidboxapp\.com/, '') || '/';
  document.getElementById('sc-pages').innerHTML = tableCard(['Pagina', 'Click', 'Impressioni', 'Posizione'],
    (sc.pages || []).sort((a, b) => b.impressions - a.impressions).slice(0, 20)
      .map(r => [`<span title="${escHtml(r.keys[0])}">${escHtml(short(r.keys[0]))}</span>`, r.clicks, fmtNum(r.impressions), posF(r.position)]));
  const CC = { ita: 'Italia', usa: 'Stati Uniti', esp: 'Spagna', fra: 'Francia', gbr: 'Regno Unito', deu: 'Germania', che: 'Svizzera', bel: 'Belgio', can: 'Canada', mex: 'Messico', arg: 'Argentina', ind: 'India', bra: 'Brasile', nld: 'Paesi Bassi', aus: 'Australia', irl: 'Irlanda', aut: 'Austria', prt: 'Portogallo', col: 'Colombia', chl: 'Cile' };
  barsCard('bars-sc-countries', (sc.countries || []).map(r => [CC[r.keys[0]] || r.keys[0].toUpperCase(), r.impressions,
    `${fmtNum(r.impressions)} impr. · ${r.clicks} click`]), 'blue');
  const DEV = { DESKTOP: 'Computer', MOBILE: 'Telefono', TABLET: 'Tablet' };
  barsCard('bars-sc-devices', (sc.devices || []).map(r => [DEV[r.keys[0]] || r.keys[0], r.impressions,
    `${fmtNum(r.impressions)} impr. · ${r.clicks} click`]), 'blue');
}

function renderLandingGa4(ga, p) {
  const box = document.getElementById('ga-wrap');
  if (ga.error) { box.innerHTML = `<div class="tcard"><div class="dim small" style="padding:12px 16px">GA4 non disponibile: ${escHtml(ga.error)}</div></div>`; return; }
  const iso = k => `${k.slice(0, 4)}-${k.slice(4, 6)}-${k.slice(6, 8)}`;
  const byDay = {};
  (ga.daily || []).forEach(r => { byDay[iso(r.keys[0])] = r.values; });
  const days = p.all ? Object.keys(byDay).sort() : p.days;
  const sumI = (ids, i) => ids.reduce((a, id) => a + (byDay[id]?.[i] || 0), 0);
  // Utenti unici del periodo: la somma per dispositivo (una persona su due
  // dispositivi conta due volte; la somma giornaliera gonfierebbe molto di più).
  const users28 = (ga.devices || []).reduce((a, r) => a + r.values[0], 0);
  const ses = sumI(days, 1), ses0 = p.all ? 0 : sumI(p.prev, 1), views = sumI(days, 2), eng = sumI(days, 3);
  setVal('ga-users', fmtNum(users28));
  setVal('ga-sessions', fmtNum(ses));
  setVal('ga-sessions-sub', `visite, ${p.label}${deltaTxt(ses, ses0)}`);
  setVal('ga-views', fmtNum(views));
  setVal('ga-views-sub', ses ? `${(views / ses).toFixed(1).replace('.', ',')} pagine per visita` : 'pagine viste');
  setVal('ga-engaged', pctTxt(eng, ses));
  setVal('ga-engaged-sub', `${fmtNum(eng)} visite con interazione`);

  renderBarChart('chart-ga-daily', days.map(dm), [{ name: 'Visite', color: 'var(--color-orange)', values: days.map(id => byDay[id]?.[1] || 0) }], fmtNum, 1000);
  document.getElementById('ga-channels').innerHTML = tableCard(['Canale', 'Sorgente', 'Visite', 'Con interazione'],
    (ga.channels || []).map(r => [escHtml(r.keys[0]), escHtml(r.keys[1]), r.values[0], `${r.values[1]} · ${pctTxt(r.values[1], r.values[0])}`]));
  document.getElementById('ga-pages').innerHTML = tableCard(['Pagina', 'Viste', 'Utenti'],
    (ga.pages || []).slice(0, 20).map(r => [escHtml(r.keys[0]), r.values[0], r.values[1]]));
  const EV = { page_view: 'Pagina vista', user_engagement: 'Interazione', session_start: 'Inizio visita', first_visit: 'Prima visita', store_click: 'Tap verso lo store', scroll: 'Scorrimento', click: 'Clic su link esterno', invite_landing_shown: 'Pagina invito vista', invite_store_click: 'Store dalla pagina invito' };
  document.getElementById('ga-events').innerHTML = tableCard(['Evento', 'Volte', 'Persone'],
    (ga.events || []).map(r => [EV[r.keys[0]] ? `${EV[r.keys[0]]} <span class="dim">${r.keys[0]}</span>` : escHtml(r.keys[0]), r.values[0], r.values[1]]));
  const CN = { Italy: 'Italia', Spain: 'Spagna', France: 'Francia', 'United States': 'Stati Uniti', 'United Kingdom': 'Regno Unito', Germany: 'Germania', Switzerland: 'Svizzera', Belgium: 'Belgio', Netherlands: 'Paesi Bassi', Ireland: 'Irlanda', Mexico: 'Messico', Argentina: 'Argentina', Brazil: 'Brasile', India: 'India', Canada: 'Canada', '(not set)': 'non noto' };
  barsCard('bars-ga-countries', (ga.countries || []).map(r => [CN[r.keys[0]] || r.keys[0], r.values[0]]), 'orange');
  const DV = { mobile: 'Telefono', desktop: 'Computer', tablet: 'Tablet' };
  barsCard('bars-ga-devices', (ga.devices || []).map(r => [DV[r.keys[0]] || r.keys[0], r.values[0]]), 'orange');
}

// ── Report scaricabile ────────────────────────────────────────────────────────
// Legge la console com'è ORA (stessi numeri, stesso filtro Periodo) e la scrive
// in Markdown: tutte le pagine, landing compresa. Restano fuori solo i moduli di
// azione (piani, listino, notifiche). I grafici entrano come tabella dei loro
// dati (`data-report`); famiglie e utenti entrano per intero dai dati, non dalla
// pagina della tabella a schermo. Email, nomi delle persone e azioni no.
const REPORT_SKIP = /Gestione Piani|Listino piani|Notifiche push/;
const REPORT_DROP_COLS = /^(Email|Nome|Azioni)$/;
function reportClean(t) { return (t || '').replace(/\s+/g, ' ').replace(/[↕▲▼]/g, '').trim(); }
function reportText(el) {
  const c = el.cloneNode(true);
  c.querySelectorAll('button').forEach(b => b.remove());
  return reportClean(c.textContent);
}
function reportMdTable(head, rows) {
  if (!head.length || !rows.length) return '';
  const cell = c => String(c ?? '—').replace(/\|/g, '/');
  return '\n| ' + head.join(' | ') + ' |\n|' + head.map(() => '---').join('|') + '|\n' +
    rows.map(r => '| ' + r.map(cell).join(' | ') + ' |').join('\n') + '\n';
}
function reportTable(t) {
  const tbodyId = t.querySelector('tbody')?.id;
  if (tbodyId === 'fam-tbody') return reportFamilies();
  if (tbodyId === 'user-tbody') return reportUsers();
  const head = [...t.querySelectorAll('thead th')].map(th => reportClean(th.innerText));
  const keep = head.map(h => !REPORT_DROP_COLS.test(h));
  const rows = [...t.querySelectorAll('tbody tr')].slice(0, 200)
    .map(tr => [...tr.children].map(td => reportClean(td.innerText)).filter((_, i) => keep[i]));
  return reportMdTable(head.filter((_, i) => keep[i]), rows);
}
const repDate = d => d ? new Date(d).toLocaleDateString('it-IT') : '—';
function reportFamilies() {
  const rows = [..._familyRows].sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0)).map(r => [
    r.fid.slice(0, 8), (r.fname || '—') + (r.internal ? ' (prova)' : ''), r.planLabel || r.plan, r.realMembers,
    `iOS ${r.iosCount} · Android ${r.androidCount} · Web ${r.webCount || 0}`, fmtBytes(r.storageBytes), r.aiMonth,
    repDate(r.createdAtMs), repDate(r.lastOpenAt)]);
  return `\nTutte le ${rows.length} famiglie, dalla più recente (senza email).\n` +
    reportMdTable(['ID', 'Famiglia', 'Piano', 'Membri', 'Dispositivi', 'Storage', 'AI mese', 'Creata', 'Ultima apertura'], rows);
}
function reportUsers() {
  const famById = new Map(_familyRows.map(r => [r.fid, r]));
  const rows = [..._allUsersRows].sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)).map(u => {
    const f = famById.get(_familyByUid[u.uid]);
    return [u.uid.slice(0, 8) + (u.internal ? ' (test)' : ''), f ? (f.fname || '—') : '—', f ? (f.planLabel || f.plan) : '—',
      [u.platform, u.web ? 'web' : ''].filter(Boolean).join(' + ') || '—', repDate(u.createdAt), repDate(u.lastOpenAt), repDate(u.lastActiveAt)];
  });
  return `\nTutti i ${rows.length} utenti, dal più recente (senza email né nomi).\n` +
    reportMdTable(['Utente', 'Famiglia', 'Piano', 'Dispositivo', 'Registrato', 'Ultima apertura', 'App viva'], rows);
}
function reportMd(el) {
  if (el.nodeType === 3) return '';
  if (el.dataset?.report) return el.dataset.report;
  if (!el.matches || el.matches('svg,canvas,button,script,style,input,select')) return '';
  if (el.tagName === 'TABLE') return reportTable(el);
  if (el.querySelector(':scope > .card-lbl')) {
    const q = (c) => reportClean(el.querySelector(c)?.innerText);
    return `- **${q('.card-lbl')}**: ${q('.card-val')}${q('.card-sub') ? ' — ' + q('.card-sub') : ''}\n`;
  }
  if (el.classList.contains('bar-row')) return `- ${reportClean(el.querySelector('.bar-lbl')?.innerText)}: ${reportClean(el.querySelector('.bar-val')?.innerText)}\n`;
  if (el.classList.contains('funnel-step')) return `- ${reportClean(el.querySelector('.funnel-step-label')?.innerText)}: ${reportClean(el.querySelector('.funnel-step-val')?.innerText)} (${reportClean(el.querySelector('.funnel-step-pct')?.innerText)})\n`;
  if (el.classList.contains('tcard-hdr')) return `\n### ${reportText(el)}\n`;
  // Testo con grassetti o span in mezzo: una riga sola, altrimenti ogni pezzo
  // verrebbe scritto da solo e le parole di collegamento andrebbero perse.
  if ([...el.children].every(c => /^(B|STRONG|I|EM|SPAN|A|SMALL|CODE)$/.test(c.tagName))) {
    const t = reportText(el);
    return t ? t + '\n' : '';
  }
  return [...el.children].map(reportMd).join('');
}
window.downloadReport = function() {
  const main = document.querySelector('.main');
  if (!main) return;
  const now = new Date();
  const day = now.toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' });
  const badge = document.getElementById('filter-active-badge');
  const filter = badge && badge.style.display !== 'none' ? reportClean(badge.innerText) : 'Tutto';
  let out = `# KidBox · Report console\n\nGenerato ${now.toLocaleString('it-IT', { timeZone: 'Europe/Rome' })} · ultimo aggiornamento dati: ${reportClean(document.getElementById('last-upd')?.innerText)} · mese ${reportClean(document.getElementById('month-badge')?.innerText)} · periodo: ${filter}\n\nSolo aggregati. Account di test esclusi dove indicato. «—» = dato non caricato o non misurato.\n`;
  let on = false;
  const nodes = [...main.children].flatMap(n => n.classList.contains('page') ? [...n.children] : [n]);
  for (const node of nodes) {
    if (node.classList.contains('sec-title')) {
      const title = reportText(node);
      on = !!title && !REPORT_SKIP.test(title);
      if (on) out += `\n## ${title}\n`;
      continue;
    }
    if (on) out += reportMd(node);
  }
  out = out.replace(/\n{3,}/g, '\n\n');
  const url = URL.createObjectURL(new Blob([out], { type: 'text/markdown;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url; a.download = `kidbox-console-${day}.md`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
};

// Ultimo contatto con Auth (login o rinnovo token, vedi `getAuthUsersData`):
// relativo finché è recente, poi la data.
function fmtLastActive(d) {
  if (!d) return '—';
  // Giorni di calendario, non blocchi di 24 ore: alle 00:40 un accesso delle
  // 22:27 della sera prima è "ieri", anche se sono passate solo due ore.
  const startOfDay = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const days = Math.round((startOfDay(new Date()) - startOfDay(d)) / 86400000);
  const time = d.toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' });
  if (days <= 0) return 'oggi ' + time;
  if (days === 1) return 'ieri ' + time;
  if (days < 30) return `${days} gg fa`;
  return d.toLocaleDateString('it-IT');
}

window.userSearchChanged = function userSearchChanged() {
  _userPage = 1;
  renderUsersTable(_allUsersRows);
};

function renderUsersTable(rows) {
  const tbody = document.getElementById('user-tbody');
  if (!tbody) return;
  const filtered = applyTimeFilter(rows, 'createdAt');

  // ── aggiorna stat card coerenti con la vista filtrata ──
  const real = filtered.filter(u => !u.internal);
  setVal('stat-users', fmtNum(real.length));
  setVal('stat-users-sub', filtered.length > real.length ? `profili su Firestore · senza ${filtered.length - real.length} account di test` : 'profili su Firestore');
  const q = (document.getElementById('user-search')?.value || '').trim().toLowerCase();
  const famLabel = u => {
    const f = _familyRows.find(x => x.fid === _familyByUid[u.uid]);
    return f ? `${f.fname || ''} ${f.fid}`.toLowerCase() : '';
  };
  const shown = q ? filtered.filter(u => (u.email || '').toLowerCase().includes(q) || famLabel(u).includes(q)) : filtered;
  setVal('users-table-count', q ? `(${shown.length} di ${filtered.length})` : `(${filtered.length})`);
  let ios=0, android=0, web=0;
  real.forEach(u => { if(u.platform==='ios') ios++; else if(u.platform==='android') android++; if(u.web) web++; });
  setVal('stat-platform-ios',     fmtNum(ios));
  setVal('stat-platform-android', fmtNum(android));
  setVal('stat-platform-web',     fmtNum(web));

  if (shown.length === 0) {
    tbody.innerHTML = `<tr><td colspan="9" class="empty">${q ? 'Nessun utente corrisponde alla ricerca' : 'Nessun utente nel periodo selezionato'}</td></tr>`;
    renderPagination('user', 0, 1, 'userGoPage');
    return;
  }
  const storageByFid = new Map(_familyRows.map(f => [f.fid, f.storageBytes || 0]));
  const storageOf = u => storageByFid.get(_familyByUid[u.uid]) || 0;
  const sorted = [...shown].sort((a, b) => {
    let va, vb;
    if (_userSort.col === 'createdAt') { va = a.createdAt?.getTime()||0; vb = b.createdAt?.getTime()||0; }
    else if (_userSort.col === 'storage') { va = storageOf(a); vb = storageOf(b); }
    else if (_userSort.col === 'lastOpenAt') { va = a.lastOpenAt?.getTime()||0; vb = b.lastOpenAt?.getTime()||0; }
    else if (_userSort.col === 'email') { return _userSort.dir === 'asc' ? a.email.localeCompare(b.email) : b.email.localeCompare(a.email); }
    else { va = 0; vb = 0; }
    return _userSort.dir === 'desc' ? vb - va : va - vb;
  });
  updateUserSortHeaders();
  const page = sorted.slice((_userPage-1)*PAGE_SIZE, _userPage*PAGE_SIZE);
  renderPagination('user', sorted.length, _userPage, 'userGoPage');
  tbody.innerHTML = page.map(u => {
    const fid = _familyByUid[u.uid] || '';
    const fam = fid ? _familyRows.find(f => f.fid === fid) : null;
    const famName = fam ? ((fam.fname && fam.fname !== '—') ? fam.fname : fam.fid.slice(0,14)+'…') : '—';
    const plan = fam ? fam.plan : '';
    const emailShort = u.email.length > 30 ? u.email.slice(0,28)+'…' : u.email;
    const platformBadge = [
      u.platform === 'ios' ? '🍎 iOS' : u.platform === 'android' ? '🤖 Android' : '',
      u.web ? '🌐 Web' : '',
    ].filter(Boolean).join(' · ') || '<span class="dim">—</span>';
    const createdStr = u.createdAt ? u.createdAt.toLocaleDateString('it-IT') : '—';
    const lastOpenStr = fmtLastActive(u.lastOpenAt);
    const lastOpenTitle = u.lastOpenAt ? u.lastOpenAt.toLocaleString('it-IT') : 'Nessuna apertura registrata negli ultimi 90 giorni (web solo dal 02/10)';
    return `
    <tr class="ua-row" onclick="openUserActivity(${jsArg(u.uid)})" title="Vedi cosa ha fatto su KidBox">
      <td data-label="Email" class="dim" style="font-size:12px" title="${escH(u.email)}">${escH(emailShort)}</td>
      <td data-label="Nome" style="font-size:13px;font-weight:500">${escH(u.name)}</td>
      <td data-label="Famiglia" class="dim" style="font-size:12px" title="${escH(fid)}">${escH(famName)}</td>
      <td data-label="Piano">${plan ? `<span class="badge badge-${escH(plan)}">${escH(plan)}</span>` : '<span class="dim">—</span>'}</td>
      <td data-label="Dispositivo" style="font-size:13px;white-space:nowrap">${platformBadge}</td>
      <td data-label="Registrato" class="dim mono" style="font-size:11px">${createdStr}</td>
      <td data-label="Ultima apertura" class="mono" style="font-size:11px;white-space:nowrap" title="${lastOpenTitle}">${lastOpenStr}</td>
      <td data-label="Storage" class="mono" style="font-size:11px;white-space:nowrap" title="Spazio della famiglia">${fam ? fmtBytes(fam.storageBytes) : '—'}</td>
      <td data-label="Attività" style="white-space:nowrap"><span class="ua-open">📊 Vedi ›</span></td>
    </tr>`;
  }).join('');
}

// Scheda di un utente: conteggi per sezione, senza titoli né contenuti.
const UA_FEATURES = { app:'App', documents:'Documenti', chat:'Chat', photoVideo:'Foto e video', health:'Salute', todo:'To-do', grocery:'Spesa', note:'Note', calendar:'Calendario', expenses:'Spese', wallet:'Wallet', passwords:'Password', vehicles:'Veicoli', homeItems:'Casa', pets:'Animali', familyLocation:'Posizione', travel:'Viaggi' };
const UA_ACTIONS = { opened:'aperture', created:'creati', updated:'modificati', completed:'completati', retrieved:'aperti', ai:'messaggi AI' };
window.openUserActivity = async function openUserActivity(uid) {
  const modal = document.getElementById('user-activity-modal');
  const body = document.getElementById('user-activity-body');
  const u = _allUsersRows.find(x => x.uid === uid);
  document.getElementById('user-activity-title').textContent = u ? `${u.name} · ${u.email}` : uid;
  body.innerHTML = '<div class="dim small">Caricamento…</div>';
  modal.style.display = 'flex';
  try {
    const { data } = await httpsCallable(functions, 'getUserActivity')({ uid });
    const rows = (data.rows || []).sort((a, b) => (b.action === 'opened') - (a.action === 'opened') || b.d30 - a.d30);
    const label = r => `${UA_FEATURES[r.feature] || escH(r.feature)} · ${UA_ACTIONS[r.action] || escH(r.action)}`;
    const cell = n => n ? fmtNum(n) : '<span class="dim">—</span>';
    body.innerHTML = rows.length
      ? tableCard(['Cosa', 'Oggi', '7 giorni', '30 giorni'], rows.map(r => [label(r), cell(r.today), cell(r.d7), cell(r.d30)]))
      : '<div class="dim small">Nessuna azione negli ultimi 30 giorni.</div>';
  } catch (e) {
    body.innerHTML = '';
    body.textContent = `Errore: ${e.message}`;
  }
};

// ── load ──────────────────────────────────
let _planData = { free:0, pro:0, max:0 };
let _costData  = { ai:0, storage:0 };

// Copia di utenti e famiglie nel browser (solo su questo computer): all'apertura
// la console mostra subito l'ultimo caricamento, con la sua ora, e intanto
// rilegge tutto. Le date viaggiano come {__d: ms}.
const CACHE_KEY = 'kb-admin-cache-v1';
function saveCache() {
  try {
    const rep = function (k, v) { return this[k] instanceof Date ? { __d: this[k].getTime() } : v; };
    localStorage.setItem(CACHE_KEY, JSON.stringify({
      savedAt: Date.now(), users: _allUsersRows, families: _familyRows,
      internal: [..._internalUids], platform: _platformByUid, familyByUid: _familyByUid,
    }, rep));
  } catch (e) { console.warn('copia locale non salvata', e); }
}
function restoreCache() {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const c = JSON.parse(raw, (k, v) => v && typeof v === 'object' && '__d' in v ? new Date(v.__d) : v);
    _internalUids = new Set(c.internal || []);
    _platformByUid = c.platform || {};
    _allUsersRows = c.users || [];
    renderFamilyViews(c.families || []);
    _familyByUid = c.familyByUid || {};
    renderUsersTable(_allUsersRows);
    renderUserCharts();
    return c.savedAt;
  } catch (e) { console.warn('copia locale illeggibile', e); return null; }
}

async function loadAll() {
  document.getElementById('btn-refresh').disabled = true;
  document.getElementById('err-box').style.display = 'none';
  setStatus('Caricamento…');
  setVal('month-badge', monthKey());
  setVal('ai-month-lbl', `${monthKey()} · mese in corso, il filtro periodo non si applica`);

  // Solo alla prima apertura: con «Aggiorna» i dati a schermo sono già freschi.
  if (!_familyRows.length) {
    const savedAt = restoreCache();
    if (savedAt) setStatus(`Dati del ${new Date(savedAt).toLocaleString('it-IT', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })} · aggiornamento…`);
  }

  try {
    await loadUsers();
    await loadFamilies();
    renderUsersTable(_allUsersRows);
    renderUserCharts();
    saveCache();
    await loadAICosts();
    await loadActiveUsers();
    await loadLanding();
    window._kbReady = true;
    if (location.hash.slice(1) === 'vault') window.loadKeyVault(true);
    updateTotalCost();
    setStatus('Aggiornato', true);
  } catch(e) {
    console.error(e); showErr(e.message); setStatus(e.message, false);
  } finally {
    document.getElementById('btn-refresh').disabled = false;
  }
}

let _usersCache = [];
let _allUsersRows = [];
let _platformByUid = {};
let _familyByUid = {};
// Account di test (config/internalUsers): fuori dai totali, come nei report e
// nel rollup. Documento illeggibile = nessuna esclusione, la console non si ferma.
let _internalUids = new Set();
async function loadUsers() {
  try {
    try {
      const idoc = await getDoc(doc(db, 'config', 'internalUsers'));
      _internalUids = new Set(idoc.exists() && Array.isArray(idoc.data().uids) ? idoc.data().uids : []);
    } catch { _internalUids = new Set(); }
    const [snap, authResult] = await Promise.all([
      getDocs(collection(db,'users')),
      httpsCallable(functions, 'getAuthUsersData')({}).catch(() => ({ data: { users: [] } })),
    ]);
    const authByUid = {};
    for (const u of (authResult.data?.users || [])) authByUid[u.uid] = u;

    _platformByUid = {};
    _allUsersRows = snap.docs.map(d => {
      const u    = d.data();
      const auth = authByUid[d.id] || {};
      const p    = u.platform;
      _platformByUid[d.id] = p;
      const email = u.email || auth.email || '—';
      const name  = [u.firstName, u.lastName].filter(Boolean).join(' ').trim()
                    || u.displayName || auth.displayName || '—';
      return {
        uid: d.id,
        internal: _internalUids.has(d.id),
        email,
        name,
        platform: p || '',
        web: !!auth.web,
        updatedAt: u.updatedAt?.toDate(),
        createdAt: auth.createdAt ? new Date(auth.createdAt) : null,
        lastActiveAt: auth.lastActiveAt ? new Date(auth.lastActiveAt) : null,
        lastOpenAt: auth.lastOpenAt ? new Date(auth.lastOpenAt) : null,
      };
    });

    _usersCache = _allUsersRows
      .filter(u => u.email !== '—')
      .map(u => ({ uid: u.uid, email: u.email, fid: snap.docs.find(d=>d.id===u.uid)?.data().familyId || snap.docs.find(d=>d.id===u.uid)?.data().activeFamilyId || '' }))
      .sort((a,b) => a.email.localeCompare(b.email));
    const sel = document.getElementById('override-email');
    if (sel) {
      sel.innerHTML = '<option value="">— Seleziona utente…</option>' +
        _usersCache.map(u => `<option value="${escH(u.uid)}" data-fid="${escH(u.fid)}">${escH(u.email)}</option>`).join('');
    }
    if (typeof window.bcRenderPicker === 'function') window.bcRenderPicker();
  } catch { setVal('stat-users','N/A'); setVal('stat-platform-ios','N/A'); setVal('stat-platform-android','N/A'); setVal('stat-platform-web','N/A'); }
}

// Quattro letture in parallelo invece di 4 per famiglia in fila (con 293
// famiglie erano ~120 attese una dopo l'altra, 15-25 s): tutte le famiglie,
// tutti i membri e tutti i contatori di spazio con due query di gruppo (le
// rules danno lettura globale all'admin), i messaggi AI del mese. L'email del
// proprietario viene dagli utenti già caricati da loadUsers.
async function loadFamilies() {
  const mk = monthKey();
  const fidOf = ref => { const p = ref.path.split('/'); return p.length === 4 && p[0] === 'families' ? p[1] : null; };
  const [snap, membersByFid, storageByFid, aiByFid] = await Promise.all([
    getDocs(collection(db,'families')),
    getDocs(collectionGroup(db,'members')).then(qs => {
      const m = {};
      qs.forEach(d => { const fid = fidOf(d.ref); if (fid) (m[fid] ||= []).push(d); });
      return m;
    }).catch(e => { console.warn('members: query di gruppo fallita, ripiego per famiglia', e); return null; }),
    getDocs(collectionGroup(db,'stats')).then(qs => {
      const m = {};
      qs.forEach(d => { const fid = fidOf(d.ref); if (fid && d.id === 'storage') m[fid] = d.data().usedBytes || 0; });
      return m;
    }).catch(e => { console.warn('stats: query di gruppo fallita, ripiego per famiglia', e); return null; }),
    getDocs(collection(db,'ai_costs',mk,'families')).then(qs => {
      const m = {};
      qs.forEach(d => { m[d.id] = d.data().calls || 0; });
      return m;
    }).catch(() => ({})),
  ]);
  _familyByUid = {};
  const userByUid = new Map(_allUsersRows.map(u => [u.uid, u]));
  const ago14 = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000);
  const ago7  = new Date(Date.now() -  7 * 24 * 60 * 60 * 1000);

  const rows = await Promise.all(snap.docs.map(async fdoc => {
    const fid  = fdoc.id;
    const d    = fdoc.data();
    const ov   = d.planOverride;
    const plan = (ov === 'pro' || ov === 'max') ? ov : (d.plan || 'free');
    // Prova Pro (functions/proTrial.js): `plan` dice pro ma nessuno paga.
    const trial = plan === 'pro' && d.planSource === 'trial';
    const planLabel = trial ? 'pro · prova' : plan;
    // Piano impostato a mano dalla console: nessuno paga.
    const manual = (ov === 'pro' || ov === 'max');
    // Ultimo accesso: la più recente «Ultima apertura» (session_start, solo
    // iOS e Android) fra i membri, come nella tabella degli utenti.
    let lastOpenAt=null, openedMembers7d=0;
    let storageBytes=0, ownerEmail='—', iosCount=0, androidCount=0, webCount=0, totalMemberCount=0, activeCount14d=0, hasInternal=false;
    // Membro vero = non cancellato e con un ruolo, come rules e server.
    let realMemberCount=0;
    const joins = [];
    if (storageByFid) storageBytes = storageByFid[fid] || 0;
    else { try { const sd=await getDoc(doc(db,'families',fid,'stats','storage')); if(sd.exists()) storageBytes=sd.data().usedBytes||0; } catch {} }
    const aiMonth = aiByFid[fid] || 0;
    try {
      const members = membersByFid ? (membersByFid[fid] || []) : (await getDocs(collection(db,'families',fid,'members'))).docs;
      let ownerUid = null;
      members.forEach(m => {
        const md = m.data();
        totalMemberCount++;
        if (md.isDeleted !== true && md.role) realMemberCount++;
        if (_internalUids.has(m.id)) hasInternal = true;
        const jt = (md.joinedAt || md.createdAt)?.toDate?.();
        if (jt) joins.push(jt.getTime());
        if (md.role === 'owner' || md.role === 'admin') ownerUid = m.id;
        _familyByUid[m.id] = fid;
        const p = _platformByUid[m.id];
        if (p === 'ios') iosCount++;
        else if (p === 'android') androidCount++;
        const userRow = userByUid.get(m.id);
        if (userRow?.web) webCount++;
        // lastActiveAt da Auth (login o rinnovo token, tutti i client).
        // `users/{uid}.updatedAt` resta solo come ripiego se la callable
        // fallisce: si muove col profilo e col token FCM, non con l'uso.
        const lastActive = userRow?.lastActiveAt || userRow?.updatedAt;
        if (lastActive && lastActive > ago14) activeCount14d++;
        const lo = userRow?.lastOpenAt;
        if (lo) {
          if (!lastOpenAt || lo > lastOpenAt) lastOpenAt = lo;
          if (lo > ago7) openedMembers7d++;
        }
      });
      if (!ownerUid && members.length) ownerUid = members[0].id;
      // users/{uid}.email, poi l'email di Auth: è già in _allUsersRows.
      const em = ownerUid ? userByUid.get(ownerUid)?.email : null;
      if (em && em !== '—') ownerEmail = em;
    } catch {}
    const fname = d.name || '—';
    return { fid, fname, plan, trial, manual, planLabel, storageBytes, aiMonth, ownerEmail, iosCount, androidCount, webCount, updatedAt: d.updatedAt?.toDate(), totalMembers: totalMemberCount, realMembers: realMemberCount, activeMembers14d: activeCount14d, lastOpenAt, openedMembers7d, createdAtMs: d.createdAt?.toDate?.().getTime() || 0, joins, internal: hasInternal || fid.startsWith('ZZZ-TEST') };
  }));
  renderFamilyViews(rows);
}

function renderFamilyViews(rows) {
  let planFree=0, planPro=0, planMax=0, totalStorage=0;
  rows.forEach(r => {
    if(r.trial) planFree++;
    else if(r.plan==='pro')  planPro++;
    else if(r.plan==='max') planMax++;
    else planFree++;
    totalStorage+=r.storageBytes;
  });

  const totalStorageReal = totalStorage + STORAGE_DELTA_B;
  setVal('stat-storage',  fmtBytes(totalStorageReal));
  const storageCost = (totalStorageReal/1e9)*0.026;
  setVal('stat-storage-cost', fmtUsd(storageCost));
  _costData.storage = storageCost;
  _planData = { free: planFree, pro: planPro, max: planMax };

  _familyRows = rows;
  renderFamiliesTable(rows);
  renderFunnelSection(rows.filter(r => !r.internal));
  renderCohorts(rows);
  updateSortHeaders();

  // bars storage — mostra nome famiglia
  const topSt = [...rows].sort((a,b)=>b.storageBytes-a.storageBytes).slice(0,8);
  const maxSt = topSt[0]?.storageBytes||1;
  document.getElementById('bars-storage').innerHTML = topSt.length
    ? topSt.map(r=>`
        <div class="bar-row">
          <div class="bar-lbl" title="${escH(r.fid)}">${escH((r.fname && r.fname!=='—') ? r.fname.slice(0,16) : r.fid.slice(0,14)+'…')}</div>
          <div class="bar-track"><div class="bar-fill green" style="width:${(r.storageBytes/maxSt*100).toFixed(1)}%"></div></div>
          <div class="bar-val">${fmtBytes(r.storageBytes)}</div>
        </div>`).join('')
    : '<div class="dim small">Nessun dato</div>';

  drawPie('pie-plans', [
    { val: planFree, color: 'var(--color-dim-line)' },
    { val: planPro,  color: 'var(--color-blue)' },
    { val: planMax,  color: 'var(--color-purple)' },
  ]);
}

async function loadAICosts() {
  const mk = monthKey();
  try {
    const td = await getDoc(doc(db,'ai_costs',mk));
    if (td.exists()) {
      const d = td.data();
      setVal('stat-ai-calls',  fmtNum(d.calls||0));
      setVal('stat-ai-input',  fmtNum(d.inputTokens||0));
      setVal('stat-ai-output', fmtNum(d.outputTokens||0));
      const aiCost = d.costUsd||0;
      setVal('stat-ai-cost', fmtUsd(aiCost));
      _costData.ai = aiCost;
      setVal('stat-ai-per-msg', d.calls ? '€'+(aiCost/d.calls*EUR_RATE).toFixed(4).replace('.',',') : '—');
      const news = d.newsCostUsd||0;
      setVal('stat-ai-news', fmtUsd(news));
      setVal('stat-ai-news-sub', aiCost ? `${Math.round(news/aiCost*100)}% del costo stimato del mese` : 'del costo stimato del mese');
    } else {
      ['stat-ai-calls','stat-ai-input','stat-ai-output'].forEach(i=>setVal(i,'0'));
      setVal('stat-ai-cost','€0,00');
    }
  } catch { ['stat-ai-calls','stat-ai-input','stat-ai-output','stat-ai-cost'].forEach(i=>setVal(i,'N/A')); }

  try {
    const fs   = await getDocs(collection(db,'ai_costs',mk,'families'));
    const fams = fs.docs.map(d=>({fid:d.id,...d.data()})).sort((a,b)=>(b.calls||0)-(a.calls||0));
    const realFams = _familyRows.filter(r => !r.internal);
    const realIds = new Set(realFams.map(r => r.fid));
    const usingAI = fams.filter(f => (f.calls||0) > 0 && realIds.has(f.fid)).length;
    setVal('stat-ai-fams', fmtNum(usingAI));
    setVal('stat-ai-fams-sub', `su ${realFams.length} famiglie${realFams.length ? ` (${Math.round(usingAI/realFams.length*100)}%)` : ''} · senza quelle di prova`);
    const maxC = fams[0]?.calls||1;

    // risolve nome famiglia dal cache _familyRows (i doc ID non hanno prefisso family_)
    function famName(docFid) {
      const row = _familyRows.find(r => r.fid === docFid);
      if (row && row.fname && row.fname !== '—') return row.fname.slice(0,16);
      return docFid.slice(0,14)+'…';
    }

    document.getElementById('bars-ai').innerHTML = fams.length
      ? fams.slice(0,8).map(f=>`
          <div class="bar-row">
            <div class="bar-lbl" title="${escH(f.fid)}">${escH(famName(f.fid))}</div>
            <div class="bar-track"><div class="bar-fill orange" style="width:${((f.calls||0)/maxC*100).toFixed(1)}%"></div></div>
            <div class="bar-val">${f.calls||0} msg</div>
          </div>`).join('')
      : '<div class="dim small">Nessuna chiamata AI questo mese</div>';
  } catch { document.getElementById('bars-ai').innerHTML='<div class="dim small">Nessuna chiamata AI questo mese</div>'; }

  // Ultimi 6 mesi: un documento ai_costs/{YYYY-MM} per mese, 6 letture.
  try {
    const months = [];
    const [y0, m0] = mk.split('-').map(Number);
    for (let k = 5; k >= 0; k--) {
      const d = new Date(Date.UTC(y0, m0 - 1 - k, 1));
      months.push(d.toISOString().slice(0, 7));
    }
    const docs = await Promise.all(months.map(m => getDoc(doc(db, 'ai_costs', m)).catch(() => null)));
    const data = docs.map(d => d?.exists() ? d.data() : {});
    const MESI = ['gen','feb','mar','apr','mag','giu','lug','ago','set','ott','nov','dic'];
    const labels = months.map(m => MESI[Number(m.slice(5)) - 1] + ' ' + m.slice(2, 4));
    renderBarChart('chart-ai-calls', labels, [{ name: 'Messaggi', color: 'var(--color-orange)', values: data.map(d => d.calls || 0) }]);
    const eur = v => '€' + (v * EUR_RATE).toFixed(2).replace('.', ',');
    renderBarChart('chart-ai-cost', labels, [
      { name: 'Notizie', color: 'var(--color-purple)', values: data.map(d => d.newsCostUsd || 0) },
      { name: 'Il resto', color: 'var(--color-red)', values: data.map(d => Math.max(0, (d.costUsd || 0) - (d.newsCostUsd || 0))) },
    ], eur);
  } catch { ['chart-ai-calls', 'chart-ai-cost'].forEach(id => { const e = document.getElementById(id); if (e) e.innerHTML = '<div class="dim small">Non disponibile</div>'; }); }
}

// ── UTENTI ATTIVI ────────────────────────────────────────────────────────────
// Ultimi n giorni come id `YYYY-MM-DD`, dal più recente. Europe/Rome come il
// rollup lato server: usare un fuso diverso disallineerebbe i confini di giornata.
function lastNDates(n) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const d = new Date();
    d.setDate(d.getDate() - i);
    out.push(d.toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' }));
  }
  return out;
}

// Legge SOLO i rollup in metrics/{YYYY-MM-DD}, mai analyticsEvents: il costo di
// lettura resta costante mentre gli eventi crescono, e i grezzi scadono a 90gg.
// Design: internal/analytics-active-users.md
async function loadActiveUsers() {
  const empty = (msg) => {
    ['stat-dau','stat-wau','stat-mau','stat-stick','stat-daf','stat-mpf','stat-xread','stat-noact']
      .forEach(id => setVal(id, '—'));
    document.getElementById('bars-dau').innerHTML  = `<div class="dim small">${msg}</div>`;
    document.getElementById('bars-feat').innerHTML = `<div class="dim small">${msg}</div>`;
  };

  try {
    // Letture per id diretto, non una query ordinata. Gli id sono date
    // `YYYY-MM-DD`, quindi le ricostruiamo: 28 point read, costo costante,
    // nessun indice. `orderBy(documentId(),'desc')` richiederebbe un indice
    // dedicato — Firestore indicizza `__name__` solo in ascendente.
    const ids = lastNDates(28);   // desc: [oggi, ieri, …]
    const snaps = await Promise.all(ids.map(id => getDoc(doc(db,'metrics',id))));
    const days = snaps.filter(s => s.exists()).map(s => ({ id: s.id, ...s.data() }));

    if (!days.length) { empty('Nessun rollup: usa ↻ Ricalcola'); setVal('au-window','· nessun dato'); return; }

    const m = days[0];
    setVal('au-window', `· rollup ${m.id} · ${m.tz||'Europe/Rome'}`);
    setVal('stat-dau', fmtNum(m.dau));
    setVal('stat-wau', fmtNum(m.wau));
    setVal('stat-mau', fmtNum(m.mau));
    setVal('stat-daf', fmtNum(m.daf));
    setVal('stat-maf', fmtNum(m.maf));
    setVal('stat-mpf', (m.activeMembersPerActiveFamily ?? 0).toFixed(2));
    setVal('stat-stick', m.mau ? (m.stickinessWauMau*100).toFixed(0)+'%' : '—');
    // Somma dei join sugli ultimi 28 rollup: evento di crescita, fuori dal DAU.
    setVal('stat-joins', fmtNum(days.reduce((a,d) => a + (d.membersJoined||0), 0)));

    // Cross-member read e aperture a vuoto: aggregate sull'INTERA finestra di
    // 28 giorni, non sul solo ultimo rollup. Su base giornaliera una giornata
    // fiacca (zero letture) le farebbe tornare a n/d ballando con l'attività;
    // sui 28 giorni restano stabili e informative — come la card dei join.
    // Zero ≠ non misurato: se in tutta la finestra non c'è alcuna lettura, è
    // "non ancora misurato", non "nessuno legge".
    const pending = '<span class="dim">n/d</span>';

    // Il rollup salva il rapporto, non il conteggio grezzo: ricostruisco le
    // letture cross-member come rate × total per giorno, poi sommo.
    const totRead = days.reduce((a,d) => a + (d.retrievedTotal||0), 0);
    const totCross = days.reduce((a,d) => a + Math.round((d.crossMemberReadRate||0)*(d.retrievedTotal||0)), 0);
    if (totRead > 0) {
      setVal('stat-xread', (totCross/totRead*100).toFixed(0)+'%');
      document.getElementById('stat-xread-sub').textContent = `su ${fmtNum(totRead)} letture · 28gg`;
    } else {
      document.getElementById('stat-xread').innerHTML = pending;
      document.getElementById('stat-xread-sub').textContent = 'richiede il logger client';
    }

    const totSess = days.reduce((a,d) => a + (d.sessionsTotal||0), 0);
    const totNoAct = days.reduce((a,d) => a + (d.sessionsNoAction||0), 0);
    if (totSess > 0) {
      setVal('stat-noact', fmtNum(totNoAct));
      document.getElementById('stat-noact-sub').textContent = `su ${fmtNum(totSess)} aperture · 28gg`;
    } else {
      document.getElementById('stat-noact').innerHTML = pending;
      document.getElementById('stat-noact-sub').textContent = 'richiede il logger client';
    }

    // DAU ultimi 14 giorni, in ordine cronologico
    const last14 = days.slice(0,14).reverse();
    const maxDau = Math.max(...last14.map(d => d.dau||0), 1);
    document.getElementById('bars-dau').innerHTML = last14.map(d => `
      <div class="bar-row">
        <div class="bar-lbl">${d.id.slice(5)}</div>
        <div class="bar-track"><div class="bar-fill blue" style="width:${((d.dau||0)/maxDau*100).toFixed(1)}%"></div></div>
        <div class="bar-val">${d.dau||0}</div>
      </div>`).join('');

    // Azioni per feature nell'ultimo giorno
    const feats = Object.entries(m.byFeature||{})
      .map(([k,v]) => [k, (v.created||0)+(v.updated||0)+(v.completed||0)+(v.retrieved||0)+(v.ai||0)])
      .filter(([,n]) => n > 0)
      .sort((a,b) => b[1]-a[1]).slice(0,10);
    const maxF = feats[0]?.[1] || 1;
    document.getElementById('bars-feat').innerHTML = feats.length
      ? feats.map(([k,n]) => `
        <div class="bar-row">
          <div class="bar-lbl">${escH(k)}</div>
          <div class="bar-track"><div class="bar-fill green" style="width:${(n/maxF*100).toFixed(1)}%"></div></div>
          <div class="bar-val">${n}</div>
        </div>`).join('')
      : '<div class="dim small">Nessuna azione registrata</div>';

    renderTrendChart(days);
    renderFeatureTable(days);
    renderSharedFunnel(days);

  } catch(e) {
    console.error(e);
    empty('Errore: ' + e.message);
  }
}

// Linee DAU / famiglie attive / WAU su 28 giorni, SVG inline con i colori del
// tema. I giorni senza rollup restano buchi, non zeri: la linea si interrompe.
function renderTrendChart(days) {
  const el = document.getElementById('trend-chart');
  if (!el) return;
  const asc = [...days].reverse();
  if (asc.length < 2) { el.innerHTML = '<div class="dim small">Servono almeno 2 giorni di rollup</div>'; return; }
  const series = [
    ['DAU', 'dau', 'var(--color-blue)'],
    ['Famiglie attive', 'daf', 'var(--color-orange)'],
    ['WAU', 'wau', 'var(--color-purple)'],
  ];
  const W = 420, H = 150, PL = 28, PB = 18, PT = 8;
  const max = Math.max(1, ...asc.flatMap(d => series.map(([, k]) => d[k] || 0)));
  const x = i => PL + (asc.length === 1 ? 0 : i * (W - PL - 6) / (asc.length - 1));
  const y = v => PT + (H - PT - PB) * (1 - v / max);
  const lines = series.map(([, k, c]) => {
    const pts = asc.map((d, i) => d[k] == null ? null : [x(i), y(d[k])]);
    let path = '', pen = false;
    pts.forEach(p => { if (!p) { pen = false; return; } path += (pen ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1); pen = true; });
    return `<path d="${path}" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/>`;
  }).join('');
  const grid = [0, .5, 1].map(f => `<line x1="${PL}" x2="${W-6}" y1="${y(max*f)}" y2="${y(max*f)}" stroke="var(--color-brd)"/><text x="${PL-4}" y="${y(max*f)+3}" text-anchor="end" font-size="9" fill="var(--color-dim)">${Math.round(max*f)}</text>`).join('');
  const ticks = [0, Math.floor((asc.length-1)/2), asc.length-1].map(i => `<text x="${x(i)}" y="${H-4}" text-anchor="middle" font-size="9" fill="var(--color-dim)">${asc[i].id.slice(5)}</text>`).join('');
  const legend = series.map(([n,,c]) => `<span style="margin-right:12px"><span style="display:inline-block;width:10px;height:10px;border-radius:2px;background:${c};margin-right:4px"></span>${n}</span>`).join('');
  el.innerHTML = `<svg viewBox="0 0 ${W} ${H}" style="width:100%;height:auto">${grid}${lines}${ticks}</svg><div class="small" style="margin-top:6px">${legend}</div>`;
  el.dataset.report = reportMdTable(['Giorno', ...series.map(([n]) => n)], asc.map(d => [d.id, ...series.map(([, k]) => d[k] ?? '—')]));
}

// Funnel calcolato dal server (analyticsRollup.buildFamilyFunnel): una famiglia
// è condivisa davvero quando 2+ membri DIVERSI hanno creato contenuto in 28
// giorni. Conta i membri veri (account di test esclusi), non l'attività di
// login come il funnel sotto. Prende il rollup più recente che lo contiene.
function renderSharedFunnel(days) {
  const el = document.getElementById('shared-funnel');
  if (!el) return;
  const src = days.find(d => d.funnel);
  if (!src) { el.innerHTML = '<div class="dim small">Nessun dato: usa ↻ Ricalcola</div>'; return; }
  const f = src.funnel;
  document.getElementById('shared-sub').textContent = `· calcolato ${new Date(f.computedAt).toLocaleString('it-IT')}`;
  const measured = f.creatorDays >= 7;
  const w = (n, base) => base > 0 ? Math.round(n / base * 100) : 0;
  const step = (lbl, n, base, color) => `<div class="funnel-step"><div class="funnel-step-label">${lbl}</div><div class="funnel-step-val">${n}</div><div class="funnel-bar-wrap"><div class="funnel-bar" style="width:${w(n, base)}%;background:${color}"></div></div><div class="funnel-step-pct">${w(n, base)}%</div></div>`;
  const shared = f.multiCreators2, base = f.families;
  const t = f.toSecond;
  const warn = measured ? '' : `<div class="small" style="color:var(--color-orange);margin-bottom:8px">Il dato «chi crea» copre solo ${f.creatorDays} giorni su 28: i passi 3 e 4 sono per difetto. Ricalcola 28 giorni per riempire lo storico.</div>`;
  el.innerHTML = warn + `<div class="funnel-steps">
    ${step('Famiglie', f.families, base, '#6c8ebf')}
    ${step('Con 1+ membro', f.withMembers, base, '#5a9e7a')}
    ${step('Con 2+ membri', f.multi, base, '#e0a040')}
    ${step('2+ membri che creano', shared, base, '#c0504d')}
  </div>
  <div class="small" style="margin-top:10px">Con 2+ membri: <b>${f.multiCreators2}</b> con 2+ che creano · <b>${f.multiCreators1}</b> dove crea uno solo · <b>${f.multiCreators0}</b> dove non crea nessuno.</div>
  <div class="small" style="margin-top:6px">Dalla famiglia al secondo membro: mediana <b>${f.medianDaysToSecond ?? '—'}</b> giorni · stesso giorno ${t.sameDay} · entro 7 giorni ${t.within7d} · oltre ${t.over7d}.</div>`;
}

// Retention a coorte. Coorte = settimana (lun-dom, Europe/Rome) di iscrizione
// su Auth; cella W+k = quota della coorte con almeno un'azione di valore nella
// settimana W+k, letta dai `uids` dei rollup. Si calcola a richiesta perché
// legge 14 settimane di rollup (98 point read). Le celle fuori dalla copertura
// dei rollup o in una settimana non ancora chiusa restano «·»: non sono zero.
// Gli account di test (config/internalUsers) escono dalle coorti.
function weekStart(dateStr) {
  const d = new Date(dateStr + 'T12:00:00Z');
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d.toISOString().slice(0, 10);
}
function addDaysStr(dateStr, n) {
  const d = new Date(dateStr + 'T12:00:00Z');
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
function computeRetention(users, rollups, internal, today) {
  const weekUids = {};               // weekStart -> Set(uid attivi)
  let coverageStart = null;
  for (const r of rollups) {
    if (!coverageStart || r.id < coverageStart) coverageStart = r.id;
    const w = weekStart(r.id);
    (weekUids[w] = weekUids[w] || new Set());
    (r.uids || []).forEach(u => weekUids[w].add(u));
  }
  const cohorts = {};
  for (const u of users) {
    if (!u.createdAt || internal.has(u.uid)) continue;
    const w = weekStart(u.createdAt.toLocaleDateString('sv-SE', { timeZone: 'Europe/Rome' }));
    (cohorts[w] = cohorts[w] || []).push(u.uid);
  }
  const thisWeek = weekStart(today);
  const lags = [0, 1, 2, 4, 8];
  return Object.keys(cohorts).sort().reverse().slice(0, 10).map(w => {
    const cells = lags.map(k => {
      const ws = addDaysStr(w, 7 * k);
      // settimana chiusa (k=0 è quella d'iscrizione: la prendiamo anche se in corso)
      if (k > 0 && ws >= thisWeek) return null;
      // copertura piena: il primo rollup deve precedere l'inizio della settimana
      if (!coverageStart || coverageStart > ws) return null;
      const act = weekUids[ws] || new Set();
      return cohorts[w].filter(u => act.has(u)).length;
    });
    return { week: w, size: cohorts[w].length, lags, cells };
  });
}
window.loadRetention = async function(btn) {
  const el = document.getElementById('retention-table');
  const orig = btn.textContent; btn.disabled = true; btn.textContent = '…';
  try {
    if (!_allUsersRows.length) throw new Error('Elenco utenti non ancora caricato');
    const ids = lastNDates(98);
    const [snaps, intSnap] = await Promise.all([
      Promise.all(ids.map(id => getDoc(doc(db, 'metrics', id)))),
      getDoc(doc(db, 'config', 'internalUsers')).catch(() => null),
    ]);
    const rollups = snaps.filter(x => x.exists()).map(x => ({ id: x.id, ...x.data() }));
    const internal = new Set((intSnap && intSnap.exists() && intSnap.data().uids) || []);
    const today = ids[0];
    const rows = computeRetention(_allUsersRows, rollups, internal, today);
    if (!rows.length) { el.innerHTML = '<div class="dim small">Nessun utente con data di iscrizione</div>'; return; }
    const cell = (n, size) => n == null ? '<td class="dim">·</td>'
      : `<td title="${n} su ${size}">${size ? Math.round(n / size * 100) : 0}%</td>`;
    el.innerHTML = `<div class="tbl-scroll"><table><thead><tr><th>Settimana</th><th>Iscritti</th><th>W0</th><th>+1</th><th>+2</th><th>+4</th><th>+8</th></tr></thead><tbody>${
      rows.map(r => `<tr><td>${r.week.slice(5)}</td><td>${r.size}</td>${r.cells.map(n => cell(n, r.size)).join('')}</tr>`).join('')
    }</tbody></table></div>
    <div class="small dim" style="margin-top:8px">${rollups.length} giorni di rollup letti (dal ${rollups.map(r => r.id).sort()[0] || '—'}). «·» = settimana non ancora chiusa o prima del primo rollup, non zero. Passa il mouse sulla cella per il conteggio.</div>`;
  } catch (e) {
    el.innerHTML = `<div class="dim small">Errore: ${escH(e.message)}</div>`;
  } finally {
    btn.disabled = false; btn.textContent = orig;
  }
};

// Somma di byFeature sui rollup: dove si crea, si legge, si usa l'AI. Chi non
// compare non è stato usato in 28 giorni (o non emette ancora l'evento).
function renderFeatureTable(days) {
  const el = document.getElementById('feat-table');
  if (!el) return;
  const tot = {};
  days.forEach(d => Object.entries(d.byFeature || {}).forEach(([f, v]) => {
    const t = tot[f] || (tot[f] = { created: 0, updated: 0, completed: 0, retrieved: 0, ai: 0, giorni: 0 });
    ['created','updated','completed','retrieved','ai'].forEach(k => t[k] += v[k] || 0);
    t.giorni += 1;
  }));
  const rows = Object.entries(tot)
    .map(([f, t]) => [f, t, t.created + t.updated + t.completed + t.retrieved + t.ai])
    .filter(r => r[2] > 0).sort((a, b) => b[2] - a[2]);
  if (!rows.length) { el.innerHTML = '<div class="dim small" style="padding:12px 16px">Nessuna azione registrata</div>'; return; }
  const n = v => v ? fmtNum(v) : '<span class="dim">·</span>';
  el.innerHTML = `<table><thead><tr><th>Funzione</th><th>Creati</th><th>Aggiorn.</th><th>Compl.</th><th>Letture</th><th>AI</th><th>Giorni</th></tr></thead><tbody>${
    rows.map(([f, t]) => `<tr><td>${escH(f)}</td><td>${n(t.created)}</td><td>${n(t.updated)}</td><td>${n(t.completed)}</td><td>${n(t.retrieved)}</td><td>${n(t.ai)}</td><td>${t.giorni}</td></tr>`).join('')
  }</tbody></table>`;
}

// Ricalcola oggi + ieri. Idempotente: riscrive gli stessi documenti.
window.runRollup = async function(btn, nDays = 2) {
  const orig = btn.textContent;
  btn.disabled = true; btn.textContent = '…';
  try {
    const user = auth.currentUser;
    if (!user) throw new Error('Non autenticato');
    const token = await user.getIdToken();
    const cfg = getCfg();
    const res = await fetch(`https://europe-west1-${cfg.projectId}.cloudfunctions.net/runAnalyticsRollup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
      body: JSON.stringify({ data: { days: nDays } })
    });
    const json = await res.json();
    if (json.error) throw new Error(json.error.message || 'Errore sconosciuto');
    const lines = json.result.days.slice(-5).map(d => `${d.date}  DAU ${d.dau}  ·  ${d.eventsScanned} eventi`).join('\n');
    btn.textContent = '✓';
    await loadActiveUsers();
    alert('Rollup ricalcolato:\n\n' + lines);
  } catch(e) {
    alert('Errore: ' + e.message);
  } finally {
    btn.disabled = false; btn.textContent = orig;
  }
}

window.resetStorageAll = async function(btn) {
  if (!confirm('Ricalcola storage per TUTTE le famiglie?\n\nI contatori verranno riscritti con i valori reali da Firestore.')) return;
  btn.disabled = true;
  btn.textContent = '…';
  try {
    const user = auth.currentUser;
    if (!user) throw new Error('Non autenticato');
    const token = await user.getIdToken();
    const cfg = getCfg();
    const res = await fetch(`https://europe-west1-${cfg.projectId}.cloudfunctions.net/initStorageUsageAdmin`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token },
      body: JSON.stringify({ data: {} })
    });
    const json = await res.json();
    if (json.error) throw new Error(json.error.message || 'Errore sconosciuto');
    const d = json.result;
    btn.textContent = '↺ Reset';
    btn.disabled = false;
    alert(`Storage resettato!\n\nFamiglie: ${d.totalFamilies}\nTotale: ${fmtBytes(d.grandTotalBytes)}`);
    loadAll();
  } catch(e) {
    btn.textContent = '↺ Reset';
    btn.disabled = false;
    alert('Errore: ' + e.message);
  }
}

// ── OVERRIDE UTENTE → FAMIGLIE → PIANO ───────────────────────
window.onOverrideUserSelect = async function(sel) {
  const uid = sel.value;
  document.getElementById('override-families-wrap').style.display = 'none';
  document.getElementById('override-plan-wrap').style.display = 'none';
  document.getElementById('btn-override').style.display = 'none';
  document.getElementById('override-family-id').value = '';
  document.getElementById('override-families-list').innerHTML = '';
  if (!uid) return;

  const listEl = document.getElementById('override-families-list');
  listEl.innerHTML = '<div class="dim small">⏳ Caricamento famiglie…</div>';
  document.getElementById('override-families-wrap').style.display = 'flex';

  try {
    const membersSnap = await Promise.all(
      (await getDocs(collection(db,'families'))).docs.map(async fdoc => {
        const fid = fdoc.id;
        try {
          const mSnap = await getDoc(doc(db,'families',fid,'members',uid));
          if (!mSnap.exists()) return null;
          const role = mSnap.data().role || '';
          const fname = fdoc.data().name || '';
          const plan = fdoc.data().planOverride || fdoc.data().plan || 'free';
          return { fid, fname, role, plan };
        } catch { return null; }
      })
    );
    const owned = membersSnap.filter(f => f && (f.role === 'owner' || f.role === 'admin'));

    if (!owned.length) {
      listEl.innerHTML = '<div class="dim small">⚠ Nessuna famiglia trovata per questo utente</div>';
      return;
    }

    const selEmail = sel.options[sel.selectedIndex]?.text || '';
    listEl.innerHTML = owned.map(f => `
      <div style="display:flex;align-items:center;justify-content:space-between;
           padding:10px 14px;border-radius:10px;background:var(--color-muted);
           border:2px solid transparent;cursor:pointer;transition:border .15s"
           id="frow-${escH(f.fid)}"
           onclick="selectOverrideFamily(${jsArg(f.fid)},${jsArg(f.fname||f.fid.slice(0,8))},${jsArg(f.plan)},${jsArg(selEmail)})">
        <div>
          <div style="font-size:13px;font-weight:600">${escH(f.fname || '—')}</div>
          <div style="font-size:10px;font-family:var(--mono);color:var(--color-dim)">${escH(String(f.fid).slice(0,24))}…</div>
        </div>
        <span class="badge badge-${escH(f.plan)}">${escH(f.plan)}</span>
      </div>`).join('');
  } catch(e) {
    listEl.innerHTML = `<div class="dim small">⚠ Errore: ${escH(e.message)}</div>`;
  }
};

window.selectOverrideFamily = function(fid, fname, currentPlan, email) {
  document.querySelectorAll('[id^="frow-"]').forEach(el => el.style.borderColor = 'transparent');
  const row = document.getElementById('frow-' + fid);
  if (row) row.style.borderColor = 'var(--color-accent)';

  document.getElementById('override-family-id').value = fid;
  document.getElementById('override-family-resolved').textContent =
    `${email} · ${fname} · Family ID: ${fid}`;
  document.getElementById('override-plan-wrap').style.display = 'block';
  document.getElementById('btn-override').style.display = 'inline-block';

  const planSel = document.getElementById('override-plan');
  for (const opt of planSel.options) {
    if (opt.value === currentPlan) { planSel.value = currentPlan; break; }
  }
};

window.selectOverrideUser = function(uid, email, fid) {
  const sel = document.getElementById('override-email');
  if (!sel) return;
  for (const opt of sel.options) {
    if (opt.textContent.trim() === email) { sel.value = opt.value; break; }
  }
  onOverrideUserSelect(sel);
};

window.setPlanOverride = async function() {
  const familyId = document.getElementById('override-family-id').value.trim();
  const plan     = document.getElementById('override-plan').value;
  const note     = document.getElementById('override-note').value.trim();
  const btn      = document.getElementById('btn-override');
  const res        = document.getElementById('override-result');

  if (!familyId) { res.textContent = '⚠ Seleziona un utente dalla lista'; res.className='override-msg err'; return; }

  btn.disabled = true;
  btn.textContent = '…';
  res.textContent = '';
  res.className = 'override-msg';

  try {
    const fn = httpsCallable(functions, 'setFamilyPlanOverride');
    await fn({ familyId, plan: plan === 'none' ? null : plan, note });
    const sel = document.getElementById('override-email');
    const emailLabel = sel?.options[sel.selectedIndex]?.text || familyId;
    res.textContent = plan === 'none'
      ? `✓ Override rimosso per ${emailLabel}`
      : `✓ Piano ${plan.toUpperCase()} assegnato a ${emailLabel}`;
    res.className = 'override-msg ok';
    loadAll();
  } catch(e) {
    res.textContent = '✗ ' + (e.message || String(e));
    res.className = 'override-msg err';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Applica';
  }
};

// ── BROADCAST NOTIFICHE ───────────────────────────────────────────────
// Il pulsante "Invia davvero" resta disabilitato finché l'anteprima non ha
// girato con gli stessi identici parametri. Non è un fastidio burocratico: è
// l'unico modo di garantire che il numero di destinatari che l'admin ha letto
// sia quello che parte. Qualsiasi modifica al testo o al target lo ridisabilita.
let _bcPreviewedKey = null;

function bcParams() {
  const mode = document.getElementById('bc-mode').value;
  const p = {
    title: document.getElementById('bc-title').value.trim(),
    body:  document.getElementById('bc-body').value.trim(),
  };
  if (document.getElementById('bc-bypass')?.checked) p.bypassOptOut = true;
  if (mode === 'picked') {
    p.uids = Array.from(document.getElementById('bc-uids').selectedOptions).map(o => o.value);
  } else if (mode === 'inactive') {
    p.segment = 'inactive';
    p.inactiveDays = parseInt(document.getElementById('bc-inactive-days').value, 10) || 14;
  } else {
    p.segment = mode;
  }
  return p;
}

function bcInvalidate() {
  _bcPreviewedKey = null;
  const b = document.getElementById('bc-send');
  if (b) b.disabled = true;
}

window.bcCount = function() {
  const t = document.getElementById('bc-title').value;
  const b = document.getElementById('bc-body').value;
  setVal('bc-title-count', `${t.length}/80`);
  setVal('bc-body-count',  `${b.length}/300`);
  bcInvalidate();
};

window.bcModeChange = function() {
  const mode = document.getElementById('bc-mode').value;
  document.getElementById('bc-picked-wrap').style.display   = mode === 'picked'   ? 'flex' : 'none';
  document.getElementById('bc-inactive-wrap').style.display = mode === 'inactive' ? 'block' : 'none';
  bcInvalidate();
};

window.bcRenderPicker = function() {
  const sel = document.getElementById('bc-uids');
  if (!sel) return;
  const q = (document.getElementById('bc-filter')?.value || '').toLowerCase();
  const keep = new Set(Array.from(sel.selectedOptions).map(o => o.value));
  const rows = _usersCache.filter(u => !q || u.email.toLowerCase().includes(q));
  sel.innerHTML = rows.map(u =>
    `<option value="${escH(u.uid)}"${keep.has(u.uid) ? ' selected' : ''}>${escH(u.email)}</option>`).join('');
  bcInvalidate();
};

async function bcCall(dryRun) {
  const p = bcParams();
  if (!p.title || !p.body) throw new Error('Titolo e testo sono obbligatori.');
  if (p.uids && p.uids.length === 0) throw new Error('Seleziona almeno un utente.');
  const r = await httpsCallable(functions, 'sendBroadcast')({ ...p, dryRun });
  return { params: p, data: r.data };
}

window.bcPreview = async function(btn) {
  const res = document.getElementById('bc-result');
  btn.disabled = true; const label = btn.textContent; btn.textContent = '…';
  try {
    const { params, data } = await bcCall(true);
    const silent = data.recipients - data.reachable;
    res.innerHTML = `👁 <strong>${data.recipients}</strong> destinatari (${escH(data.describe)}) · ` +
      `<strong>${data.reachable}</strong> raggiungibili su ${data.tokens} dispositivi` +
      (silent > 0 ? ` · <span class="dim">${silent} senza token push</span>` : '') +
      (data.optedOut > 0
        ? ` · <strong>⚠ ${data.optedOut} con almeno un dispositivo disattivato</strong>`
        : '');
    res.className = 'override-msg ok';
    if (data.reachable > 0) {
      _bcPreviewedKey = JSON.stringify(params);
      document.getElementById('bc-send').disabled = false;
    } else {
      bcInvalidate();
    }
  } catch(e) {
    res.textContent = '✗ ' + (e.message || String(e));
    res.className = 'override-msg err';
    bcInvalidate();
  } finally {
    btn.disabled = false; btn.textContent = label;
  }
};

window.bcSend = async function(btn) {
  const res = document.getElementById('bc-result');
  const p = bcParams();
  if (JSON.stringify(p) !== _bcPreviewedKey) {
    res.textContent = '⚠ Messaggio o destinatari cambiati: rifai l\'anteprima.';
    res.className = 'override-msg err';
    bcInvalidate();
    return;
  }
  const who = p.uids ? `${p.uids.length} utenti selezionati` : `segmento "${p.segment}"`;
  const override = p.bypassOptOut
    ? '\n\n⚠ DEROGA ATTIVA: riceveranno anche i dispositivi su cui le notifiche erano state disattivate.'
    : '';
  if (!confirm(`Invio REALE a ${who}.\n\n"${p.title}"\n${p.body}${override}\n\nLe push non si annullano. Procedere?`)) return;

  btn.disabled = true; const label = btn.textContent; btn.textContent = 'Invio…';
  try {
    const { data } = await bcCall(false);
    res.innerHTML = `✓ Inviate <strong>${data.sent}</strong> notifiche a ${data.reachable} utenti` +
      (data.optedOut > 0 ? ` · <strong>${data.optedOut} in deroga</strong>` : '') +
      (data.failed ? ` · <span class="dim">${data.failed} fallite (token morti ripuliti)</span>` : '');
    res.className = 'override-msg ok';
  } catch(e) {
    res.textContent = '✗ ' + (e.message || String(e));
    res.className = 'override-msg err';
  } finally {
    btn.textContent = label;
    bcInvalidate(); // un invio riuscito non autorizza il successivo
  }
};

function updateTotalCost() {
  const tot = _costData.ai + _costData.storage;
  if (tot>0) {
    setVal('stat-total-cost', fmtEur(tot));
  }

  drawPie('pie-costs', [
    { val: _costData.ai,      color: 'var(--color-orange)' },
    { val: _costData.storage, color: 'var(--color-green)' },
  ]);

  drawPie('pie-plans', [
    { val: _planData.free, color: 'var(--color-dim-line)' },
    { val: _planData.pro,  color: 'var(--color-blue)' },
    { val: _planData.max,  color: 'var(--color-purple)' },
  ]);
}

// ── AGGIORNAMENTO STATISTICHE PER FILTRO TEMPORALE ───────────────────────────
// I costi AI esistono solo per mese (ai_costs/{YYYY-MM}): un periodo di giorni
// non si può ricavare, e sommare i mesi che tocca faceva sembrare «7 giorni» due
// mesi interi. La sezione AI resta sul mese in corso e lo dice nel titolo.
function updateStatsForFilter() {
  // utenti e famiglie sono già aggiornati da renderUsersTable/renderFamiliesTable
  updateTotalCost();
  updateLegend();
}

function updateLegend() {
  const setV = (id,v) => { const e=document.getElementById(id); if(e) e.textContent=v; };
  setV('leg-free', fmtNum(_planData.free));
  setV('leg-pro',  fmtNum(_planData.pro));
  setV('leg-max',  fmtNum(_planData.max));
}
