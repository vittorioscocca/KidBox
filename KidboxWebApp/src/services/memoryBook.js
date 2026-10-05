/**
 * La memoria dell'assistente unico sul web: una scheda markdown per ogni
 * sezione dell'app, costruita nel browser dai dati di Firestore a ogni domanda.
 * Stesse schede di iOS (`AgentMemoryBook.swift`) e Android
 * (`AgentMemoryBook.kt`); disegno, budget e regole in
 * `internal/assistente-unico.md`.
 *
 * Le schede di salute riusano `buildHealthContext` (lo stesso della chat
 * Salute, scopo `agentMemory`) con in più i referti letti, che il web prima non
 * mandava. Note, chat e campi del Wallet si decifrano solo se la chiave di
 * famiglia è su questo dispositivo: senza, la scheda lo dice invece di fingere
 * che non ci sia niente.
 */
import { collection, getDocs, query, where } from "firebase/firestore";
import { db } from "../firebase";
import { actionsPrompt } from "./aiActions";
import { loadFacts } from "./aiMemory";
import { loadFamilyKey } from "./familyKey";
import { decryptString } from "./noteCrypto";
import { noteHtmlToText } from "./noteHtml";
import { buildHealthContext, responseLanguageName } from "./healthContext";
import { loadFamilyHealth } from "./health";
import { listenGarage } from "./vehicles";
import { listenPets } from "./pets";
import { listenHome } from "./homeItems";
import { listenTripContent, listenTrips } from "./trips";
import { listenWallet } from "./wallet";
import { effectiveExpiry, listenWalletDocuments } from "./walletDocuments";
import { expandEvents } from "../calendarUtils";
import { isVisibleTo } from "../visibility";
import { categoryFromId } from "../expenseCategories";

const DAY = 86_400_000;
const CALENDAR_PAST_DAYS = 7;
const CALENDAR_FUTURE_DAYS = 60;
const CALENDAR_MAX_OCCURRENCES = 150;
const NOTE_BODY_MAX_CHARS = 1500;
const NOTES_TOTAL_MAX_CHARS = 20_000;
const EXPENSE_DETAIL_DAYS = 90;
const CHAT_MAX_MESSAGES = 30;
const DOCUMENT_INDEX_MAX = 300;

/** Caratteri di payload che valgono un messaggio (`AI_STANDARD_PAYLOAD_CHARS`). */
export const STANDARD_CHARS = 50_000;
/** Margine sotto un messaggio, per le righe di contorno. */
const UNIT_SAFETY_MARGIN = 1500;
const STANDARD_REFERTO_MAX_CHARS = 4000;
const FOCUS_ITEM_MAX_CHARS = 12_000;
const OTHER_MAX_CHARS = 1500;
const PER_DOC_OVERHEAD = 150;
const MIN_USEFUL_CHARS = 300;
// Contesto ridotto in base + appendice: la riserva fuori dalla base (schede che
// cambiano, storico, domanda, appendice), la quota del resto che va alla base,
// e il contorno di domanda.md (intestazione e righe dei titoli).
const BASE_RESERVE = 20_000;
const BASE_SHARE = 0.5;
const APPENDIX_OVERHEAD = 400;
const WALLET_PREFIX = "kb_wallet_doc:";

export const messageUnits = (chars) => Math.max(1, Math.ceil(Math.max(0, chars) / STANDARD_CHARS));

/* ── Focus ───────────────────────────────────────────────────────────────── */

/**
 * Riga del prompt per il focus da Salute: `{ personId, personName, scope,
 * itemId, detail }`, con scope `person | visits | visit | exams | exam`.
 */
export function focusPromptLine(focus) {
  if (!focus) return null;
  const name = focus.personName;
  const what = {
    person: `la salute di ${name}`,
    visits: `le visite di ${name}`,
    visit: `la visita «${focus.detail || ""}» di ${name}`,
    exams: `gli esami di ${name}`,
    exam: `l'esame «${focus.detail || ""}» di ${name}`,
  }[focus.scope] || `la salute di ${name}`;
  // Con esempi: scritta solo come «le domande senza soggetto si riferiscono a
  // questo», Haiku rispondeva sulla famiglia intera.
  return (
    `FOCUS DI QUESTA CONVERSAZIONE: l'utente ha aperto l'assistente da Salute, guardando ${what}. ` +
    `Le domande che non nominano altro («cosa devo fare?», «cosa dice il referto?», «è grave?») riguardano ${what}: ` +
    `rispondi su quello, non sul resto della famiglia. Se chiede esplicitamente d'altro, rispondi d'altro.`
  );
}

/** Tag degli allegati della visita o dell'esame del focus: passano interi. */
const focusItemTags = (focus) => {
  if (!focus?.itemId) return new Set();
  if (focus.scope === "visit") return new Set([`visit:${focus.itemId}`]);
  if (focus.scope === "exam") return new Set([`exam:${focus.itemId}`]);
  return new Set();
};

/* ── Lettura ─────────────────────────────────────────────────────────────── */

const toMillis = (value) => (value?.toMillis ? value.toMillis() : typeof value === "number" ? value : null);

async function readCollection(familyId, name, { onlyActive = true } = {}) {
  const base = collection(db, "families", familyId, name);
  try {
    const snap = await getDocs(onlyActive ? query(base, where("isDeleted", "==", false)) : base);
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  } catch {
    // Una sezione che non si riesce a leggere non deve far fallire l'intera
    // conversazione: si manda il contesto senza di lei.
    return [];
  }
}

/** Primo valore di un `listen…` dei servizi, poi smette di ascoltare. */
function once(listen, args, timeoutMs = 8000) {
  return new Promise((resolve) => {
    let done = false;
    let stop = null;
    const finish = (value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      // Il primo snapshot può arrivare prima che `listen` abbia restituito la
      // funzione per fermarlo: si ferma al giro dopo.
      setTimeout(() => stop?.(), 0);
      resolve(value);
    };
    const timer = setTimeout(() => finish(null), timeoutMs);
    try {
      stop = listen({ ...args, onChange: finish, onError: () => finish(null) });
    } catch {
      finish(null);
    }
  });
}

const sanitize = (text) =>
  (text || "")
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean)
    .join("\n");

const hasText = (doc) => doc.extractionStatusRaw === 3 && sanitize(doc.extractedText).length > 0;

/**
 * Tutti i dati della famiglia che l'assistente può vedere, letti una volta per
 * domanda. Le voci «solo per me» degli altri membri sono già fuori.
 */
export async function loadMemorySnapshot({ familyId, userId, familyName, members, children }) {
  const visible = (row) =>
    isVisibleTo(
      { visibilityScope: row.visibilityScope, visibilityMemberIds: row.visibilityMemberIds, createdBy: row.createdBy },
      userId
    );

  const [
    events, todos, todoLists, groceries, expenses, notes, chat, documents, folders,
    health, garage, petsData, home, trips, wallet, walletDocs, facts, familyKey,
  ] = await Promise.all([
    readCollection(familyId, "calendarEvents"),
    readCollection(familyId, "todos"),
    readCollection(familyId, "todoLists"),
    readCollection(familyId, "groceries"),
    readCollection(familyId, "expenses"),
    readCollection(familyId, "notes"),
    readCollection(familyId, "chatMessages"),
    readCollection(familyId, "documents"),
    readCollection(familyId, "documentCategories"),
    loadFamilyHealth(familyId),
    once(listenGarage, { familyId }),
    once(listenPets, { familyId }),
    once(listenHome, { familyId }),
    once(listenTrips, { familyId }),
    once(listenWallet, { familyId, userId }),
    once(listenWalletDocuments, { familyId, userId }),
    loadFacts(familyId),
    loadFamilyKey({ familyId, userId }).catch(() => null),
  ]);

  const now = Date.now();
  const relevantTrips = (trips || []).filter((t) => t.endDate >= now - 60 * DAY).slice(0, 8);
  const tripContents = Object.fromEntries(
    await Promise.all(
      relevantTrips.map(async (t) => [t.id, await once(listenTripContent, { familyId, tripId: t.id })])
    )
  );

  // Note e chat sono cifrate: senza chiave restano fuori, e la scheda lo dice.
  const decryptedNotes = familyKey
    ? (
        await Promise.all(
          notes.filter(visible).map(async (n) => {
            try {
              return {
                title: (await decryptString(n.titleEnc, familyKey)) || "",
                body: noteHtmlToText(await decryptString(n.bodyEnc, familyKey)) || "",
                updatedAt: toMillis(n.updatedAt) ?? 0,
                updatedBy: n.updatedBy || null,
                updatedByName: n.updatedByName || "",
              };
            } catch {
              return null;
            }
          })
        )
      )
        .filter(Boolean)
        .sort((a, b) => b.updatedAt - a.updatedAt)
    : null;
  const decryptedChat = familyKey
    ? (
        await Promise.all(
          chat
            .filter((m) => !m.isDeletedForEveryone)
            .map(async (m) => {
              try {
                const type = m.typeRaw || m.type || "text";
                let text = null;
                if (type === "text") text = m.textEnc ? await decryptString(m.textEnc, familyKey) : m.text;
                else if (type === "audio" && m.transcriptText) text = `(vocale) ${m.transcriptText}`;
                return text ? { text, sender: m.senderName || "—", at: toMillis(m.createdAt) ?? 0 } : null;
              } catch {
                return null;
              }
            })
        )
      )
        .filter(Boolean)
        .sort((a, b) => a.at - b.at)
    : null;

  // Testo letto dei documenti: `extractedTextEnc` (chiave di famiglia) se c'è,
  // altrimenti il vecchio `extractedText`. Senza chiave, o con un blob che non
  // si apre, il documento risulta «non letto».
  const readDocuments = await Promise.all(
    documents.filter(visible).map(async (d) => {
      let extractedText = typeof d.extractedText === "string" ? d.extractedText : null;
      if (typeof d.extractedTextEnc === "string" && d.extractedTextEnc) {
        extractedText = familyKey ? await decryptString(d.extractedTextEnc, familyKey).catch(() => null) : null;
      }
      return { ...d, extractedText };
    })
  );

  return {
    familyId,
    familyName,
    userId,
    members: members || [],
    children: (children || [])
      .map((c) => ({ ...c, birthDate: toMillis(c.birthDate) }))
      .sort((a, b) => (a.birthDate ?? Infinity) - (b.birthDate ?? Infinity)),
    events: events.filter(visible),
    todos: todos.filter(visible),
    todoListNames: Object.fromEntries(todoLists.map((l) => [l.id, l.name])),
    groceries,
    expenses: expenses
      .map((e) => ({ ...e, when: toMillis(e.date) }))
      .filter((e) => e.when)
      .sort((a, b) => b.when - a.when),
    notes: decryptedNotes,
    chat: decryptedChat,
    documents: readDocuments
      .map((d) => ({ ...d, createdMs: toMillis(d.createdAt) ?? 0, updatedMs: toMillis(d.updatedAt) ?? 0 }))
      .sort((a, b) => b.updatedMs - a.updatedMs),
    folderNames: Object.fromEntries(folders.map((f) => [f.id, f.title])),
    health,
    vehicles: garage?.vehicles || [],
    vehicleEvents: garage?.events || [],
    pets: petsData?.pets || [],
    petEvents: petsData?.events || [],
    homeItems: home?.items || [],
    housePayments: home?.payments || [],
    trips: trips || [],
    tripContents,
    walletTickets: wallet?.tickets || [],
    loyaltyCards: wallet?.cards || [],
    walletDocuments: walletDocs || [],
    facts: facts.map((f) => f.content),
  };
}

/* ── Schede ──────────────────────────────────────────────────────────────── */

const clip = (text, max) => (text.length > max ? `${text.slice(0, max)}…` : text);

function fold(text) {
  return (text || "").normalize("NFD").replace(/\p{M}+/gu, "").toLowerCase();
}

function slug(name) {
  const s = fold(name).replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-+|-+$/g, "");
  return s || "persona";
}

/** Nome della scheda salute di una persona (`salute-marco.md`). */
export const healthFileName = (name) => `salute-${slug(name)}.md`;

/**
 * Costruisce le schede da uno snapshot. `allowance` null = testi interi;
 * altrimenti caratteri concessi a ogni documento (0 = solo il titolo).
 */
export function buildMemoryBook(s, { allowance = null, appendix = null, locale = "it", now = Date.now() } = {}) {
  const loc = { it: "it-IT", en: "en-US", fr: "fr-FR", es: "es-ES" }[locale] || "it-IT";
  const fmtDate = (ms) => new Date(ms).toLocaleDateString(loc, { day: "numeric", month: "long", year: "numeric" });
  const fmtDateTime = (ms) =>
    new Date(ms).toLocaleString(loc, { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
  const fmtTime = (ms) => new Date(ms).toLocaleTimeString(loc, { hour: "2-digit", minute: "2-digit" });
  const fmtWeekday = (ms) => new Date(ms).toLocaleDateString(loc, { weekday: "long", day: "numeric", month: "long" });
  const fmtEuro = (v) => `€ ${Number(v || 0).toFixed(2)}`;

  const memberName = (uid) => {
    if (!uid) return null;
    const m = s.members.find((x) => x.id === uid || x.userId === uid);
    return m?.displayName || null;
  };
  const personName = (id) => s.children.find((c) => c.id === id)?.name || memberName(id);

  const health = s.health || { visits: [], exams: [], treatments: [], vaccines: [], profiles: {} };
  const personTreatments = health.treatments.filter((t) => !t.petId);
  const isCurrent = (t) => t.isActive && (t.isLongTerm || !t.endDate || t.endDate >= now);

  // ── Dove sta un documento ──────────────────────────────────────────────
  const homeOf = (doc) => {
    const tag = doc.notes || "";
    if (tag.startsWith(WALLET_PREFIX)) return { kind: "wallet" };
    const colon = tag.indexOf(":");
    if (colon <= 0) return { kind: "general" };
    const prefix = tag.slice(0, colon);
    const id = tag.slice(colon + 1);
    const find = (list) => list.find((x) => x.id === id);
    switch (prefix) {
      case "visit": {
        const v = find(health.visits);
        return v ? { kind: "health", personId: v.childId, label: `visita del ${v.date ? fmtDate(v.date) : "—"}${v.reason ? ` (${v.reason})` : ""}` } : { kind: "general" };
      }
      case "exam": {
        const e = find(health.exams);
        return e ? { kind: "health", personId: e.childId, label: `esame ${e.name}` } : { kind: "general" };
      }
      case "treatment": {
        const t = find(personTreatments);
        return t ? { kind: "health", personId: t.childId, label: `cura ${t.drugName}` } : { kind: "general" };
      }
      case "homeItem": return { kind: "home", label: find(s.homeItems)?.name || "oggetto di casa" };
      case "housePayment": return { kind: "home", label: find(s.housePayments)?.name || "scadenza di casa" };
      case "vehicle": return { kind: "vehicle", label: find(s.vehicles)?.name || "veicolo" };
      case "vehicleEvent": return { kind: "vehicle", label: find(s.vehicleEvents)?.title || "intervento" };
      case "pet": return { kind: "pet", label: find(s.pets)?.name || "animale" };
      case "petEvent": return { kind: "pet", label: find(s.petEvents)?.title || "evento veterinario" };
      case "expense": return { kind: "expense", label: s.expenses.find((x) => x.id === id)?.title || "spesa" };
      default: return { kind: "general" };
    }
  };
  const placeLabel = (doc, home) => {
    switch (home.kind) {
      case "health": return `Salute di ${personName(home.personId) || "—"}, ${home.label}`;
      case "home": return `Casa, ${home.label}`;
      case "vehicle": return `Veicoli, ${home.label}`;
      case "pet": return `Animali, ${home.label}`;
      case "expense": return `ricevuta della spesa «${home.label}»`;
      case "wallet": return "Wallet";
      default: {
        const folder = doc.categoryId ? s.folderNames[doc.categoryId] : null;
        return folder ? `cartella ${folder}` : "Documenti";
      }
    }
  };

  const documentText = (doc) => {
    const clean = sanitize(doc.extractedText);
    const max = allowance ? allowance[doc.id] : undefined;
    if (max === undefined) return { body: clean, state: "full" };
    if (max <= 0) return { body: "(testo letto non incluso per spazio)", state: "omitted" };
    if (clean.length <= max) return { body: clean, state: "full" };
    return { body: `${clean.slice(0, max)}\n[… testo accorciato: ${max} caratteri su ${clean.length}]`, state: "clipped" };
  };

  const attachmentLines = (tag, indent = "  ") =>
    s.documents
      .filter((d) => d.notes === tag && hasText(d))
      .flatMap((d) => [
        `${indent}Allegato «${d.title}» — testo letto:`,
        ...documentText(d).body.split("\n").filter(Boolean).map((l) => `${indent}  ${l}`),
      ]);

  // Referti dentro il builder di Salute: stesso testo di iOS e Android.
  const refertiFor = (tag, indent, label) =>
    s.documents
      .filter((d) => d.notes === tag && hasText(d))
      .flatMap((d) => {
        const max = allowance ? allowance[d.id] : undefined;
        if (max === 0) return [`${indent}${label} (${d.title}): testo non incluso per spazio`];
        const clean = sanitize(d.extractedText);
        const limit = max === undefined ? (allowance ? STANDARD_REFERTO_MAX_CHARS : null) : max;
        const text = limit && clean.length > limit
          ? `${clean.slice(0, limit)}\n[… referto troncato nel contesto standard; usa “Massima accuratezza” per il testo completo]`
          : clean;
        return [`${indent}${label} (${d.title}):`, `${indent}${text}`];
      });

  const occurrences = (from, to) => expandEvents(s.events, new Date(from), new Date(to));
  const eventLine = (e) => {
    const start = toMillis(e.startDate);
    const end = toMillis(e.endDate) ?? start;
    let line = e.isAllDay ? "tutto il giorno" : `${fmtTime(start)}–${fmtTime(end)}`;
    line += ` ${e.title || "senza titolo"}`;
    const child = e.childId ? personName(e.childId) : null;
    if (child) line += ` (${child})`;
    if (e.categoryRaw) line += ` [${{ children: "figli", school: "scuola", health: "salute", family: "famiglia", admin: "burocrazia", leisure: "tempo libero" }[e.categoryRaw] || e.categoryRaw}]`;
    if (e.location) line += ` @ ${e.location}`;
    const rec = { daily: "ogni giorno", weekly: "ogni settimana", monthly: "ogni mese", yearly: "ogni anno" }[e.recurrenceRaw];
    if (rec) line += ` — ${rec}`;
    if (e.notes && e.notes.trim()) line += ` — note: ${clip(e.notes.trim(), 120)}`;
    return line;
  };
  const todoLine = (t) => {
    let line = t.title || "senza titolo";
    if ((t.priority ?? t.priorityRaw ?? 0) === 1) line += " [URGENTE]";
    const due = toMillis(t.dueAt);
    if (due) line += ` — scadenza ${t.dueHasTime === false ? fmtDate(due) : fmtDateTime(due)}`;
    const who = memberName(t.assignedTo);
    if (who) line += ` → ${who}`;
    else if (t.assignedExternalName) line += ` → ${t.assignedExternalName} (fuori dall'app)`;
    if (t.listId && s.todoListNames[t.listId]) line += ` · lista ${s.todoListNames[t.listId]}`;
    if (t.notes && t.notes.trim()) line += ` — ${clip(t.notes.trim(), 120)}`;
    return line;
  };

  const files = [];
  const add = (name, title, summary, lines) => files.push({ name, title, summary, body: lines.join("\n") });

  // famiglia.md
  {
    const adults = s.members
      .filter((m) => m.displayName)
      .map((m) => (m.role === "admin" ? `${m.displayName} (amministratore)` : m.displayName));
    const lines = [`# Famiglia ${s.familyName}`];
    const me = memberName(s.userId);
    if (me) lines.push(`Sta scrivendo: ${me}`);
    if (adults.length) lines.push("\n## Adulti", ...adults.map((a) => `- ${a}`));
    if (s.children.length) {
      lines.push("\n## Figli");
      s.children.forEach((c) => {
        if (!c.birthDate) return lines.push(`- ${c.name}`);
        // Età e prossimo compleanno già calcolati: lasciati al modello, li
        // sbagliava («compie 1 anno» a una bambina di tre).
        const b = new Date(c.birthDate);
        const today = new Date(now);
        today.setHours(0, 0, 0, 0);
        let next = new Date(today.getFullYear(), b.getMonth(), b.getDate());
        if (next < today) next = new Date(today.getFullYear() + 1, b.getMonth(), b.getDate());
        const turning = next.getFullYear() - b.getFullYear();
        let months = (today.getFullYear() - b.getFullYear()) * 12 + today.getMonth() - b.getMonth();
        if (today.getDate() < b.getDate()) months -= 1;
        const age = months < 24 ? `${Math.max(months, 0)} mesi` : `${Math.floor(months / 12)} anni`;
        lines.push(`- ${c.name}, ${age} (nato/a il ${fmtDate(c.birthDate)}) — prossimo compleanno: ${fmtWeekday(next.getTime())}, compie ${turning} anni`);
      });
    }
    if (s.pets.length) lines.push("\n## Animali", ...s.pets.map((p) => `- ${p.name} (${p.species})`));
    add("famiglia.md", "Famiglia", `${adults.length} adulti, ${s.children.length} figli, ${s.pets.length} animali`, lines);
  }

  // ricordi.md
  if (s.facts.length) {
    add("ricordi.md", "Ricordi", `${s.facts.length} fatti`, [
      "# Ricordi",
      "Fatti emersi dalle conversazioni passate. Usali per personalizzare senza citarli se non serve.",
      ...s.facts.map((f) => `- ${f}`),
    ]);
  }

  // oggi.md
  const openTodos = s.todos.filter((t) => !t.isDone);
  {
    const start = new Date(now).setHours(0, 0, 0, 0);
    const end = start + DAY;
    const today = occurrences(start, end);
    const urgent = openTodos.filter((t) => (t.priority ?? t.priorityRaw ?? 0) === 1 || (toMillis(t.dueAt) ?? Infinity) <= end);
    const doses = health.treatments
      .filter((t) => !t.petId && isCurrent(t))
      .flatMap((t) => (t.scheduleTimes || []).map((h) => `- ore ${h}: ${t.drugName} ${Math.round(t.dosageValue)} ${t.dosageUnit} (${personName(t.childId) || "—"})`))
      .sort();
    const lines = [`# Oggi, ${fmtWeekday(now)}`];
    if (!today.length) lines.push("Nessun evento in calendario.");
    else lines.push("## Eventi", ...today.map((e) => `- ${eventLine(e)}`));
    if (urgent.length) lines.push("## To-do urgenti o in scadenza", ...urgent.slice(0, 20).map((t) => `- ${todoLine(t)}`));
    if (doses.length) lines.push("## Dosi di farmaci", ...doses);
    add("oggi.md", "Oggi", `${today.length} eventi, ${urgent.length} to-do urgenti, ${doses.length} dosi`, lines);
  }

  // calendario.md
  {
    const start = new Date(now).setHours(0, 0, 0, 0) - CALENDAR_PAST_DAYS * DAY;
    const end = now + CALENDAR_FUTURE_DAYS * DAY;
    const all = occurrences(start, end);
    const shown = all.slice(0, CALENDAR_MAX_OCCURRENCES);
    const lines = ["# Calendario", `Dal ${fmtDate(start)} al ${fmtDate(end)}. Gli eventi ricorrenti compaiono in ogni ripetizione.`];
    if (!shown.length) lines.push("Nessun evento in questo periodo.");
    let currentDay = "";
    shown.forEach((e) => {
      const day = fmtWeekday(toMillis(e.startDate));
      if (day !== currentDay) {
        lines.push(`\n## ${day}`);
        currentDay = day;
      }
      lines.push(`- ${eventLine(e)}`);
    });
    if (all.length > shown.length) lines.push(`\n(Altre ${all.length - shown.length} ripetizioni oltre il limite non elencate.)`);
    const upcoming = all.filter((e) => toMillis(e.startDate) >= now).length;
    add("calendario.md", "Calendario", `${upcoming} eventi nei prossimi ${CALENDAR_FUTURE_DAYS} giorni, ricorrenze comprese`, lines);
  }

  // todo.md
  {
    const due = (t) => toMillis(t.dueAt);
    const overdue = openTodos.filter((t) => due(t) && due(t) < now).sort((a, b) => due(a) - due(b));
    const dated = openTodos.filter((t) => due(t) && due(t) >= now).sort((a, b) => due(a) - due(b));
    const undated = openTodos.filter((t) => !due(t));
    const done = s.todos
      .filter((t) => t.isDone && (toMillis(t.doneAt) ?? 0) >= now - 7 * DAY)
      .sort((a, b) => toMillis(b.doneAt) - toMillis(a.doneAt));
    const lines = ["# To-do"];
    if (!openTodos.length) lines.push("Nessun to-do aperto.");
    if (overdue.length) lines.push(`\n## Scaduti (${overdue.length})`, ...overdue.slice(0, 40).map((t) => `- ${todoLine(t)}`));
    if (dated.length) lines.push(`\n## Con scadenza (${dated.length})`, ...dated.slice(0, 60).map((t) => `- ${todoLine(t)}`));
    if (undated.length) lines.push(`\n## Senza data (${undated.length})`, ...undated.slice(0, 60).map((t) => `- ${todoLine(t)}`));
    if (done.length) {
      lines.push("\n## Fatti negli ultimi 7 giorni");
      done.slice(0, 20).forEach((t) => {
        const by = memberName(t.doneBy);
        lines.push(`- ${t.title}${by ? ` — fatto da ${by}` : ""}${t.doneAt ? ` il ${fmtDate(toMillis(t.doneAt))}` : ""}`);
      });
    }
    add("todo.md", "To-do", `${openTodos.length} aperti, ${overdue.length} scaduti`, lines);
  }

  // spesa.md
  {
    const pending = s.groceries.filter((g) => !g.isPurchased);
    const bought = s.groceries.filter((g) => g.isPurchased && (toMillis(g.purchasedAt) ?? 0) >= now - 7 * DAY);
    const lines = ["# Lista della spesa"];
    if (!pending.length) lines.push("Niente da comprare.");
    else {
      lines.push(`\n## Da comprare (${pending.length})`);
      const groups = {};
      pending.forEach((g) => {
        const cat = g.category?.trim() || "Altro";
        let name = g.name;
        if ((g.quantity ?? 1) > 1) name += ` ×${g.quantity}`;
        const by = memberName(g.createdBy);
        if (by) name += ` (da ${by})`;
        (groups[cat] ||= []).push(name);
      });
      Object.keys(groups).sort().forEach((cat) => lines.push(`- [${cat}] ${groups[cat].join(", ")}`));
    }
    if (bought.length) lines.push("\n## Comprati negli ultimi 7 giorni", bought.slice(0, 30).map((g) => g.name).join(", "));
    add("spesa.md", "Lista della spesa", `${pending.length} articoli da comprare`, lines);
  }

  // note.md
  if (s.notes === null) {
    add("note.md", "Note", "non disponibili su questo dispositivo", [
      "# Note",
      "Le note sono cifrate e la chiave di famiglia non è su questo browser: non le vedo. Se te le chiedono, dillo.",
    ]);
  } else if (s.notes.length) {
    const lines = ["# Note"];
    let used = 0;
    const titlesOnly = [];
    s.notes.forEach((n) => {
      const title = n.title || "(senza titolo)";
      if (used >= NOTES_TOTAL_MAX_CHARS) {
        titlesOnly.push(title);
        return;
      }
      const body = clip(n.body.trim(), NOTE_BODY_MAX_CHARS);
      used += body.length;
      const author = memberName(n.updatedBy) || n.updatedByName;
      lines.push(`\n## ${title}`, `Aggiornata il ${fmtDate(n.updatedAt)}${author ? ` da ${author}` : ""}`);
      if (body) lines.push(body);
    });
    if (titlesOnly.length) lines.push("\n## Altre note (solo titolo)", ...titlesOnly.map((t) => `- ${t}`));
    add("note.md", "Note", `${s.notes.length} note`, lines);
  }

  // spese.md
  if (s.expenses.length) {
    const category = (e) => categoryFromId(s.familyId, e.categoryId)?.name || "Altro";
    const recent = s.expenses.filter((e) => e.when >= now - EXPENSE_DETAIL_DAYS * DAY);
    const lines = ["# Spese", `\n## Voci degli ultimi ${EXPENSE_DETAIL_DAYS} giorni (${recent.length})`];
    recent.slice(0, 80).forEach((e) => {
      const who = memberName(e.createdByUid);
      lines.push(`- ${fmtDate(e.when)} — ${e.title || "spesa"}: ${fmtEuro(e.amount)} [${category(e)}]${who ? ` — ${who}` : ""}${e.notes?.trim() ? ` (${clip(e.notes.trim(), 80)})` : ""}`);
    });
    const yearAgo = new Date(now);
    yearAgo.setMonth(yearAgo.getMonth() - 12);
    const byMonth = {};
    s.expenses.filter((e) => e.when >= yearAgo.getTime()).forEach((e) => {
      const d = new Date(e.when);
      const key = d.getFullYear() * 100 + d.getMonth();
      (byMonth[key] ||= []).push(e);
    });
    const monthKeys = Object.keys(byMonth).map(Number).sort((a, b) => b - a);
    if (monthKeys.length) {
      lines.push("\n## Totale per mese (ultimi 12 mesi)");
      monthKeys.forEach((k) => {
        const items = byMonth[k];
        const label = new Date(Math.floor(k / 100), k % 100, 1).toLocaleDateString(loc, { month: "long", year: "numeric" });
        lines.push(`- ${label}: ${fmtEuro(items.reduce((acc, e) => acc + Number(e.amount || 0), 0))} (${items.length} voci)`);
      });
    }
    const thisYear = new Date(now).getFullYear();
    const byCategory = {};
    s.expenses.filter((e) => new Date(e.when).getFullYear() === thisYear).forEach((e) => {
      byCategory[category(e)] = (byCategory[category(e)] || 0) + Number(e.amount || 0);
    });
    const cats = Object.entries(byCategory).sort((a, b) => b[1] - a[1]);
    if (cats.length) lines.push(`\n## Totale per categoria nel ${thisYear}`, ...cats.map(([n, v]) => `- ${n}: ${fmtEuro(v)}`));
    const total = recent.reduce((acc, e) => acc + Number(e.amount || 0), 0);
    add("spese.md", "Spese", `${recent.length} voci negli ultimi ${EXPENSE_DETAIL_DAYS} giorni, ${fmtEuro(total)}`, lines);
  }

  // salute-<nome>.md: figli sempre, adulti solo se hanno dati.
  {
    const persons = s.children.map((c) => ({ id: c.id, name: c.name, child: c }));
    s.members.forEach((m) => {
      const id = m.userId || m.id;
      if (!m.displayName || persons.some((p) => p.id === id)) return;
      const hasData = [health.visits, health.exams, personTreatments, health.vaccines].some((list) => list.some((x) => x.childId === id));
      if (hasData) persons.push({ id, name: m.displayName, child: null });
    });
    const used = new Set();
    persons.forEach((p) => {
      let name = healthFileName(p.name);
      if (used.has(name)) name = `salute-${slug(p.name)}-${used.size + 1}.md`;
      used.add(name);
      const visits = health.visits.filter((v) => v.childId === p.id);
      const exams = health.exams.filter((e) => e.childId === p.id);
      const treatments = personTreatments.filter((t) => t.childId === p.id);
      const active = treatments.filter(isCurrent);
      const past = treatments
        .filter((t) => !isCurrent(t) && (t.startDate ?? 0) >= now - 730 * DAY)
        .sort((a, b) => (b.startDate ?? 0) - (a.startDate ?? 0));
      const vaccines = health.vaccines.filter((v) => v.childId === p.id);
      const profile = health.profiles?.[p.id] || null;

      const lines = [`# Salute di ${p.name}`, "\n--- PROFILO PERSONALE ---"];
      if (p.child?.birthDate) lines.push(`Data di nascita: ${fmtDate(p.child.birthDate)}`);
      if (typeof p.child?.weightKg === "number") lines.push(`Peso: ${p.child.weightKg.toFixed(1)} kg`);
      if (typeof p.child?.heightCm === "number") lines.push(`Altezza: ${Math.round(p.child.heightCm)} cm`);
      if (!p.child) lines.push("Adulto della famiglia");
      if (profile?.doctorName) lines.push(`${p.child ? "Pediatra" : "Medico"}: ${profile.doctorName}`);
      if (profile?.doctorPhone) lines.push(`Telefono del medico: ${profile.doctorPhone}`);
      if (profile?.doctorEmail) lines.push(`Email del medico: ${profile.doctorEmail}`);
      if (profile?.doctorAddress) lines.push(`Studio: ${profile.doctorAddress}`);
      if (past.length) {
        lines.push("\n--- CURE CONCLUSE (ultimi 2 anni) ---");
        past.slice(0, 20).forEach((t) => lines.push(`• ${t.drugName} ${Math.round(t.dosageValue)} ${t.dosageUnit}${t.startDate ? ` — dal ${fmtDate(t.startDate)}` : ""}${t.endDate ? ` al ${fmtDate(t.endDate)}` : ""}`));
      }
      lines.push(
        buildHealthContext({
          subjectName: p.name,
          visits,
          exams,
          treatments: active,
          vaccines,
          profile,
          // Senza budget testi interi (la «massima accuratezza» della chat
          // Salute); col budget decide `allowance`.
          refertoMaxChars: allowance ? STANDARD_REFERTO_MAX_CHARS : null,
          locale,
          purpose: "agentMemory",
          refertiFor,
        })
      );
      const referti = s.documents.filter((d) => {
        const tag = d.notes || "";
        return hasText(d) && (
          exams.some((e) => tag === `exam:${e.id}`) ||
          visits.some((v) => tag === `visit:${v.id}`) ||
          active.some((t) => tag === `treatment:${t.id}`)
        );
      }).length;
      add(name, `Salute di ${p.name}`, `${active.length} cure attive, ${visits.length} visite, ${exams.length} esami, ${vaccines.length} vaccini, ${referti} referti letti`, lines);
    });
  }

  // documenti.md
  {
    const lines = ["# Documenti", `\n## Elenco (${s.documents.length}, i più recenti prima)`];
    s.documents.slice(0, DOCUMENT_INDEX_MAX).forEach((d) => {
      const home = homeOf(d);
      let line = `- ${d.title || d.fileName || "documento"} — ${placeLabel(d, home)}`;
      if (home.kind === "general" && d.childId && personName(d.childId)) line += `, di ${personName(d.childId)}`;
      line += ` · ${fmtDate(d.createdMs || d.updatedMs)}`;
      const mime = d.mimeType || "";
      line += ` · ${mime.includes("pdf") ? "PDF" : mime.startsWith("image/") ? "immagine" : (d.fileName || "").split(".").pop()?.toUpperCase() || "file"}`;
      if (home.kind !== "wallet") {
        if (hasText(d)) line += " · testo letto";
        else if (d.extractionStatusRaw === 1 || d.extractionStatusRaw === 2) line += " · lettura in corso";
      }
      lines.push(line);
    });
    if (s.documents.length > DOCUMENT_INDEX_MAX) lines.push(`(Altri ${s.documents.length - DOCUMENT_INDEX_MAX} documenti più vecchi non elencati.)`);
    const general = s.documents.filter((d) => hasText(d) && ["general", "expense"].includes(homeOf(d).kind));
    let clipped = 0;
    let omitted = 0;
    if (general.length) {
      lines.push("\n## Testo letto dei documenti");
      general.forEach((d) => {
        const t = documentText(d);
        if (t.state === "clipped") clipped += 1;
        if (t.state === "omitted") omitted += 1;
        lines.push(`\n### ${d.title} (${placeLabel(d, homeOf(d))}, ${fmtDate(d.createdMs || d.updatedMs)})`, t.body);
      });
    }
    const read = s.documents.filter(hasText).length;
    let summary = `${s.documents.length} documenti`;
    if (read) summary += `, ${read} con testo letto`;
    if (clipped + omitted) summary += ` (qui: ${clipped} testi accorciati e ${omitted} non inclusi per spazio)`;
    add("documenti.md", "Documenti", summary, lines);
  }

  // wallet.md
  if (s.walletTickets.length || s.walletDocuments.length || s.loyaltyCards.length) {
    const lines = ["# Wallet"];
    if (s.walletTickets.length) {
      lines.push("\n## Biglietti e prenotazioni");
      [...s.walletTickets]
        .sort((a, b) => (a.eventDate ?? Infinity) - (b.eventDate ?? Infinity))
        .slice(0, 30)
        .forEach((t) => {
          let line = `- ${t.title} [${t.kind}]`;
          if (t.eventDate) line += ` — ${fmtDateTime(t.eventDate)}`;
          if (t.eventEndDate) line += ` → ${fmtDateTime(t.eventEndDate)}`;
          if (t.location) line += ` — da/luogo: ${t.location}`;
          if (t.arrivalLocation) line += ` — a: ${t.arrivalLocation}`;
          if (t.seat) line += ` — posto ${t.seat}`;
          if (t.holderName) line += ` — intestato a ${t.holderName}`;
          if (t.emitter) line += ` — ${t.emitter}`;
          if (t.bookingCode) line += ` — prenotazione ${t.bookingCode}`;
          lines.push(line);
        });
    }
    if (s.walletDocuments.length) {
      lines.push("\n## Documenti d'identità (numeri e codici esclusi di proposito)");
      s.walletDocuments.forEach((d) => {
        const meta = d.meta;
        if (!meta) return;
        let line = `- ${d.title || meta.kind}`;
        if (meta.holderName) line += ` di ${meta.holderName}`;
        const exp = effectiveExpiry(meta);
        if (exp) {
          const expMs = typeof exp === "number" ? exp : Date.parse(exp);
          if (!Number.isNaN(expMs)) line += ` — scade il ${fmtDate(expMs)}${expMs < now ? " ⚠️ SCADUTO" : ""}`;
        }
        if (meta.patenteCategories?.length) line += ` — categorie ${meta.patenteCategories.map((c) => c.code).join(", ")}`;
        lines.push(line);
      });
    }
    if (s.loyaltyCards.length) lines.push("\n## Carte fedeltà", s.loyaltyCards.map((c) => c.brandName).sort().join(", "));
    add("wallet.md", "Wallet", `${s.walletTickets.length} biglietti, ${s.walletDocuments.length} documenti d'identità, ${s.loyaltyCards.length} carte fedeltà`, lines);
  }

  // casa.md
  if (s.homeItems.length || s.housePayments.length) {
    const lines = ["# Casa"];
    if (s.homeItems.length) {
      lines.push(`\n## Oggetti, impianti e contratti (${s.homeItems.length})`);
      s.homeItems.slice(0, 40).forEach((h) => {
        let line = `- ${h.name} [${{ appliance: "elettrodomestico", system: "impianto", contract: "contratto", other: "altro" }[h.categoryRaw] || h.categoryRaw}]`;
        const bm = [h.brand, h.model].filter(Boolean).join(" ");
        if (bm) line += ` — ${bm}`;
        if (h.purchaseDate) line += ` — acquisto ${fmtDate(h.purchaseDate)}`;
        if (h.warrantyExpiryDate) line += ` — garanzia fino al ${fmtDate(h.warrantyExpiryDate)}${h.warrantyExpiryDate < now ? " (scaduta)" : ""}`;
        if (h.nextServiceDate) line += ` — prossima manutenzione ${fmtDate(h.nextServiceDate)}`;
        if (h.servicePeriodMonths) line += ` — ogni ${h.servicePeriodMonths} mesi`;
        if (h.notes?.trim()) line += ` — note: ${clip(h.notes.trim(), 120)}`;
        lines.push(line, ...attachmentLines(`homeItem:${h.id}`));
      });
    }
    if (s.housePayments.length) {
      lines.push(`\n## Scadenze e pagamenti (${s.housePayments.length})`);
      s.housePayments.slice(0, 40).forEach((p) => {
        let line = `- ${p.name} — ${p.typeRaw}`;
        if (p.subtypeRaw) line += ` (${p.subtypeRaw})`;
        if (p.importo != null) line += ` — ${fmtEuro(p.importo)}`;
        if (p.giornoDiScadenzaMensile) line += ` — ogni mese il giorno ${p.giornoDiScadenzaMensile}`;
        if (p.dataScadenza) line += ` — scadenza di riferimento ${fmtDate(p.dataScadenza)}`;
        if (p.dataScadenzaContratto) line += ` — contratto fino al ${fmtDate(p.dataScadenzaContratto)}`;
        if (p.fornitore) line += ` — gestore ${p.fornitore}`;
        if (p.note?.trim()) line += ` — note: ${clip(p.note.trim(), 120)}`;
        lines.push(line, ...attachmentLines(`housePayment:${p.id}`));
      });
    }
    add("casa.md", "Casa", `${s.homeItems.length} oggetti, ${s.housePayments.length} scadenze e pagamenti`, lines);
  }

  // veicoli.md
  if (s.vehicles.length) {
    const lines = ["# Veicoli"];
    s.vehicles.forEach((v) => {
      lines.push(`\n## ${v.name}`);
      const facts = [
        v.licensePlate && `targa ${v.licensePlate}`,
        [v.brand, v.model].filter(Boolean).join(" ") || null,
        v.year && `anno ${v.year}`,
        v.currentKm != null && `${v.currentKm} km`,
      ].filter(Boolean);
      if (facts.length) lines.push(facts.join(" · "));
      [["Assicurazione", v.insuranceExpiryDate], ["Revisione", v.revisionExpiryDate], ["Bollo", v.taxExpiryDate], ["Tagliando", v.nextServiceDate]]
        .forEach(([label, date]) => {
          if (date) lines.push(`- ${label}: ${fmtDate(date)}${date < now ? " ⚠️ PASSATA" : ""}`);
        });
      if (v.lastServiceDate) lines.push(`- Ultimo tagliando: ${fmtDate(v.lastServiceDate)}`);
      if (v.notes?.trim()) lines.push(`Note: ${clip(v.notes.trim(), 200)}`);
      lines.push(...attachmentLines(`vehicle:${v.id}`));
      const events = s.vehicleEvents.filter((e) => e.vehicleId === v.id && (e.date ?? 0) >= now - 730 * DAY);
      if (events.length) {
        lines.push("Interventi (ultimi 2 anni):");
        events.slice(0, 30).forEach((e) => {
          let line = `- ${e.date ? fmtDate(e.date) : "—"} ${e.title} — ${e.eventTypeRaw}`;
          if (e.km != null) line += ` — ${e.km} km`;
          if (e.cost != null) line += ` — ${fmtEuro(e.cost)}`;
          if (e.garageName) line += ` — ${e.garageName}`;
          if (e.notes?.trim()) line += ` — ${clip(e.notes.trim(), 100)}`;
          lines.push(line, ...attachmentLines(`vehicleEvent:${e.id}`));
        });
      }
    });
    add("veicoli.md", "Veicoli", `${s.vehicles.length} veicoli, ${s.vehicleEvents.length} interventi`, lines);
  }

  // animali.md
  if (s.pets.length) {
    const lines = ["# Animali"];
    s.pets.forEach((p) => {
      lines.push(`\n## ${p.name}`);
      lines.push([p.species, p.breed, p.birthDate && `nato/a il ${fmtDate(p.birthDate)}`, p.color, p.chipCode && `microchip ${p.chipCode}`].filter(Boolean).join(" · "));
      if (p.notes?.trim()) lines.push(`Note: ${clip(p.notes.trim(), 200)}`);
      lines.push(...attachmentLines(`pet:${p.id}`));
      const cures = health.treatments.filter((t) => t.petId === p.id && isCurrent(t));
      if (cures.length) lines.push(`Cure in corso: ${cures.map((t) => `${t.drugName} ${Math.round(t.dosageValue)} ${t.dosageUnit}`).join(", ")}`);
      const events = s.petEvents.filter((e) => e.petId === p.id);
      if (events.length) {
        lines.push("Eventi:");
        events.slice(0, 30).forEach((e) => {
          let line = `- ${e.date ? fmtDate(e.date) : "—"} ${e.title} — ${e.eventTypeRaw}`;
          if (e.nextDueDate) line += ` — prossimo ${fmtDate(e.nextDueDate)}`;
          if (e.vetName) line += ` — ${e.vetName}`;
          if (e.cost != null) line += ` — ${fmtEuro(e.cost)}`;
          if (e.notes?.trim()) line += ` — ${clip(e.notes.trim(), 100)}`;
          lines.push(line, ...attachmentLines(`petEvent:${e.id}`));
        });
      }
    });
    add("animali.md", "Animali", `${s.pets.length} animali, ${s.petEvents.length} eventi`, lines);
  }

  // viaggi.md
  if (s.trips.length) {
    const relevant = s.trips.filter((t) => t.endDate >= now - 60 * DAY).sort((a, b) => a.startDate - b.startDate);
    const older = s.trips.filter((t) => t.endDate < now - 60 * DAY);
    const lines = ["# Viaggi"];
    relevant.slice(0, 8).forEach((t) => {
      lines.push(`\n## ${t.name}`, `Dal ${fmtDate(t.startDate)} al ${fmtDate(t.endDate)} — stato: ${t.status}${t.budgetTotal > 0 ? ` — budget ${Math.round(t.budgetTotal)} ${t.currency}` : ""}`);
      const content = s.tripContents[t.id];
      (content?.legs || []).forEach((l) => lines.push(`- Tappa: ${l.fromLocation} → ${l.toLocation} (${l.transportMode})`));
      (content?.dayPlans || []).slice(0, 21).forEach((d) => {
        const plan = [d.morningPlan, d.afternoonPlan, d.eveningPlan].filter(Boolean).map((x) => clip(x, 120));
        lines.push(`- ${d.dateString} a ${d.location}${plan.length ? `: ${plan.join(" / ")}` : ""}${d.accommodationName ? ` — alloggio ${d.accommodationName}` : ""}`);
      });
    });
    if (older.length) lines.push("\n## Viaggi passati", ...older.slice(0, 20).map((t) => `- ${t.name}: ${fmtDate(t.startDate)} – ${fmtDate(t.endDate)}`));
    add("viaggi.md", "Viaggi", `${relevant.length} in corso o in programma, ${older.length} passati`, lines);
  }

  // chat.md
  if (s.chat === null) {
    add("chat.md", "Chat di famiglia", "non disponibile su questo dispositivo", [
      "# Chat di famiglia",
      "La chat è cifrata e la chiave di famiglia non è su questo browser: non la vedo.",
    ]);
  } else if (s.chat.length) {
    const last = s.chat.slice(-CHAT_MAX_MESSAGES);
    add("chat.md", "Chat di famiglia", `ultimi ${last.length} messaggi`, [
      "# Chat di famiglia",
      `Ultimi ${last.length} messaggi di testo, dal più vecchio.`,
      ...last.map((m) => `- [${fmtDateTime(m.at)}] ${m.sender}: ${clip(m.text, 300)}`),
    ]);
  }

  // domanda.md: i testi scelti per la domanda di adesso (contesto ridotto), più
  // lunghi della base che sta nelle schede. Va in coda al prompt, fuori dalla
  // cache: è la sola parte che cambia da una domanda all'altra.
  if (appendix) {
    const picked = s.documents
      .filter((d) => (appendix[d.id] || 0) > 0 && hasText(d))
      .sort((a, b) => appendix[b.id] - appendix[a.id] || b.updatedMs - a.updatedMs || (a.id < b.id ? -1 : 1));
    if (picked.length) {
      const lines = [
        "# Testi per questa domanda",
        "Testi letti scelti per la domanda di adesso: qui sono più lunghi che nelle schede sopra, dove sono accorciati. Per questi documenti vale il testo qui sotto.",
      ];
      picked.forEach((d) => {
        const clean = sanitize(d.extractedText);
        const max = appendix[d.id];
        const body = clean.length <= max ? clean : `${clean.slice(0, max)}\n[… testo accorciato: ${max} caratteri su ${clean.length}]`;
        lines.push(`\n## ${d.title || d.fileName || "documento"} (${placeLabel(d, homeOf(d))}, ${fmtDate(d.createdMs || d.updatedMs)})`, body);
      });
      add("domanda.md", "Testi per questa domanda", `${picked.length} testi`, lines);
    }
  }

  return files;
}

/**
 * Schede che cambiano fra una domanda e l'altra (un to-do spuntato, un
 * articolo aggiunto, un messaggio in chat, il tempo che passa). Stanno in fondo,
 * nel secondo blocco del prompt, così il resto del quaderno resta nella cache
 * di Anthropic. Stesso elenco su iOS e Android.
 */
export const VOLATILE_FILES = new Set(["oggi.md", "calendario.md", "todo.md", "spesa.md", "chat.md"]);

/** Cambia a ogni domanda: va in coda, dopo le azioni, e non entra nell'indice. */
const TAIL_FILE = "domanda.md";

/**
 * Il quaderno nel formato del prompt, in due parti: indice e schede stabili,
 * poi le schede che cambiano. L'indice non porta i conteggi di queste ultime:
 * sta nella parte stabile, e un numero che cambia lo farebbe uscire dalla cache.
 */
export function renderBook(files) {
  const card = (f) => [`<scheda file="${f.name}" titolo="${f.title}">`, f.body, "</scheda>"].join("\n");
  const indexLine = (f) =>
    VOLATILE_FILES.has(f.name)
      ? `- ${f.name} — ${f.title}: in fondo, aggiornata a ogni domanda`
      : `- ${f.name} — ${f.title}: ${f.summary}`;
  const book = files.filter((f) => f.name !== TAIL_FILE);
  const index = ["<indice>", ...book.map(indexLine), "</indice>"].join("\n");
  return {
    stable: [index, ...book.filter((f) => !VOLATILE_FILES.has(f.name)).map(card)].join("\n\n"),
    volatile: book.filter((f) => VOLATILE_FILES.has(f.name)).map(card).join("\n\n"),
    tail: files.filter((f) => f.name === TAIL_FILE).map(card).join("\n\n"),
  };
}

/** Ruolo e regole dell'assistente unico. Stesso testo su iOS e Android. */
export function agentRules(familyName, locale, now = new Date()) {
  const day = (d) => new Intl.DateTimeFormat("it-IT", { weekday: "long", day: "numeric", month: "long" }).format(d);
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  return [
    `Sei l'assistente di KidBox della famiglia ${familyName}. KidBox è l'app in cui la famiglia tiene calendario, to-do, lista della spesa, note, spese, documenti, salute, wallet, casa, veicoli, animali e viaggi.`,
    "Qui sotto c'è la tua memoria: una scheda per ogni sezione dell'app, aggiornata adesso, con un indice in cima.",
    "",
    "COME RISPONDI",
    "- Usa i dati delle schede; quando aiuta, di' da dove li prendi («dal referto del 12 marzo…», «nella scheda Casa…»).",
    "- Se un dato non c'è, dillo chiaramente: non inventare date, importi, nomi, valori o documenti.",
    "- Se l'indice o una scheda dice che un testo è accorciato o non incluso e la domanda riguarda proprio quello, dillo e suggerisci di ripetere la domanda con la massima accuratezza.",
    "- Salute: linguaggio semplice, adatto a un genitore. Puoi spiegare referti, valori, cure, vaccini e visite; non fare diagnosi e non cambiare terapie: quando la questione è clinica, dopo aver risposto ricorda di sentire il medico.",
    "- Pianificazione: aiuta a trovare spazi liberi e a non dimenticare scadenze; quando proponi un evento o un to-do indica titolo, data/ora e chi se ne occupa.",
    "- Le password non sono nella tua memoria: se te le chiedono, rimanda alla sezione Password dell'app.",
    `- Date: oggi è ${day(now)}, domani è ${day(tomorrow)}. Prima di dire «domani», «dopodomani» o un giorno della settimana controlla la data scritta nelle schede: non contare a memoria.`,
    `- Rispondi in ${responseLanguageName(locale)}, con tono caldo e pratico, senza preamboli.`,
  ].join("\n");
}

/**
 * Il prompt in due blocchi, ognuno con la sua cache sul server
 * (`systemPromptStable` + `systemPrompt`): regole e schede stabili, poi focus,
 * schede che cambiano e azioni. Il focus va due volte, prima e dopo le schede
 * che cambiano: il 02/10/2026 su Haiku, solo in fondo «cosa devo fare adesso?»
 * aperto da una visita tornava una volta su due con le cose della famiglia; il
 * 05/10/2026 in questa posizione 4 su 4, come in cima al quaderno. Prima
 * stava in cima a tutto, e ogni cambio di focus azzerava la cache.
 */
export function agentSystemPrompt({ familyName, files, focus, locale }) {
  const focusLine = focusPromptLine(focus);
  const book = renderBook(files);
  return {
    stable: [agentRules(familyName, locale), book.stable].join("\n\n"),
    volatile: [focusLine, book.volatile, actionsPrompt(), focusLine].filter(Boolean).join("\n\n"),
    tail: book.tail,
  };
}

/** Caratteri del prompt come li conta il server: le parti insieme. */
export const promptChars = (prompt) => prompt.stable.length + prompt.volatile.length + prompt.tail.length;

/* ── Budget ──────────────────────────────────────────────────────────────── */

const STOPWORDS = new Set([
  "della", "delle", "degli", "dello", "dalla", "dalle", "dagli", "nella", "nelle", "negli", "nello",
  "sulla", "sulle", "sugli", "sullo", "alla", "alle", "agli", "allo", "questo", "questa", "questi",
  "queste", "quello", "quella", "quelli", "quelle", "come", "cosa", "cose", "dove", "quando", "quanto",
  "quanti", "quante", "quale", "quali", "perche", "sono", "siamo", "hanno", "abbiamo", "avete", "fare",
  "fatto", "fatta", "dire", "detto", "anche", "ancora", "sempre", "dopo", "prima", "oggi", "domani",
  "ieri", "ogni", "tutto", "tutti", "tutte", "tutta", "molto", "poco", "meno", "essere", "stato",
  "stata", "stati", "ultimo", "ultima", "ultimi", "ultime", "prossimo", "prossima", "prossimi",
  "prossime", "miei", "nostro", "nostra", "nostri", "nostre", "loro", "suoi", "dimmi", "fammi",
  "spiegami", "ricordami", "riassumi", "riassumimi", "vorrei", "posso", "puoi", "devo", "deve",
  "serve", "servono", "documento", "documenti", "what", "when", "where", "which", "with",
  "about", "have", "does", "this", "that", "there", "their", "from", "please", "dans", "pour",
  "avec", "quel", "quelle", "sont", "cual", "como", "donde", "cuando", "para", "sobre", "tiene",
]);

const terms = (question) =>
  new Set(fold(question).split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 4 && !STOPWORDS.has(w)));

/**
 * Documenti con testo letto che entrano nel quaderno (mai gli identificativi
 * del Wallet), con la persona a cui si riferiscono e il punto in cui stanno.
 */
function textDocuments(s) {
  const health = s.health || { visits: [], exams: [], treatments: [] };
  const personOf = (doc) => {
    const tag = doc.notes || "";
    const id = tag.slice(tag.indexOf(":") + 1);
    if (tag.startsWith("visit:")) return health.visits.find((v) => v.id === id)?.childId || null;
    if (tag.startsWith("exam:")) return health.exams.find((e) => e.id === id)?.childId || null;
    if (tag.startsWith("treatment:")) return health.treatments.find((t) => t.id === id)?.childId || null;
    return doc.childId || null;
  };
  return s.documents
    .filter((d) => hasText(d) && !(d.notes || "").startsWith(WALLET_PREFIX))
    .map((d) => ({ doc: d, fullLength: sanitize(d.extractedText).length, personId: personOf(d) }));
}

/**
 * Divide il budget fra i testi letti quando il quaderno completo non sta in un
 * messaggio. Ordine: allegati della visita o dell'esame del focus, poi i
 * documenti pertinenti alla domanda o alla persona del focus, poi gli altri
 * dal più recente. Stesso algoritmo di iOS e Android.
 * `targetedOnly`: solo focus e pertinenti, e solo se avrebbero più testo di
 * quanto ne hanno già in `floor` (l'appendice della domanda sopra la base).
 */
function allowances(s, { question, focus, availableChars, targetedOnly = false, floor = null }) {
  const qTerms = terms(question);
  const foldedQ = fold(question);
  const names = [
    ...s.children.map((c) => [c.id, c.name]),
    ...s.members.filter((m) => m.displayName).map((m) => [m.userId || m.id, m.displayName]),
  ];
  const mentioned = new Set(names.filter(([, n]) => fold(n).length >= 3 && foldedQ.includes(fold(n))).map(([id]) => id));
  const focusTags = focusItemTags(focus);

  const candidates = textDocuments(s).map((item) => {
    if (focusTags.has(item.doc.notes)) return { item, tier: 0, score: 0, cap: FOCUS_ITEM_MAX_CHARS };
    const head = fold(`${item.doc.title} ${item.doc.fileName}`);
    const body = fold((item.doc.extractedText || "").slice(0, 30_000));
    let score = 0;
    qTerms.forEach((t) => {
      if (head.includes(t)) score += 2;
      else if (body.includes(t)) score += 1;
    });
    if (item.personId && mentioned.has(item.personId)) score += 2;
    if (item.personId && item.personId === focus?.personId) score += 1;
    return score > 0
      ? { item, tier: 1, score, cap: STANDARD_REFERTO_MAX_CHARS }
      : { item, tier: 2, score: 0, cap: OTHER_MAX_CHARS };
  });
  const pool = targetedOnly
    ? candidates.filter((c) => c.tier < 2 && Math.min(c.item.fullLength, c.cap) > (floor?.[c.item.doc.id] ?? 0))
    : candidates;
  pool.sort((a, b) => a.tier - b.tier || b.score - a.score || b.item.doc.updatedMs - a.item.doc.updatedMs);

  let remaining = availableChars;
  const out = {};
  pool.forEach((c) => {
    const room = remaining - PER_DOC_OVERHEAD;
    if (room < MIN_USEFUL_CHARS) {
      out[c.item.doc.id] = 0;
      return;
    }
    const give = Math.min(c.item.fullLength, c.cap, room);
    out[c.item.doc.id] = give;
    remaining -= give + PER_DOC_OVERHEAD;
  });
  // Secondo giro: lo spazio che avanza va ai testi ancora accorciati, nello
  // stesso ordine, fino al testo intero. Il messaggio costa uguale.
  pool.forEach((c) => {
    const id = c.item.doc.id;
    const given = out[id];
    if (given >= c.item.fullLength || remaining <= 0) return;
    if (given === 0) {
      const room = remaining - PER_DOC_OVERHEAD;
      if (room < MIN_USEFUL_CHARS) return;
      out[id] = Math.min(c.item.fullLength, room);
      remaining -= out[id] + PER_DOC_OVERHEAD;
    } else {
      const extra = Math.min(c.item.fullLength - given, remaining);
      out[id] = given + extra;
      remaining -= extra;
    }
  });
  return out;
}

const payloadChars = (prompt, history, question) =>
  promptChars(prompt) + history.reduce((acc, m) => acc + (m.content || "").length, 0) + question.length;

/**
 * Base dei testi nel contesto ridotto: dal più recente, senza guardare domanda
 * né focus, con metà dello spazio che resta in un messaggio dopo le schede
 * stabili e una riserva per schede che cambiano, storico, domanda e
 * appendice. Dipende solo dai dati: due domande di fila hanno la stessa base,
 * e il blocco stabile del prompt resta nella cache. `null` se non c'è spazio.
 */
function baseAllowances(s, stableChars) {
  const units = messageUnits(stableChars + BASE_RESERVE + UNIT_SAFETY_MARGIN);
  const budget = Math.floor((units * STANDARD_CHARS - UNIT_SAFETY_MARGIN - BASE_RESERVE - stableChars) * BASE_SHARE);
  if (budget < MIN_USEFUL_CHARS) return null;
  return allowances(s, { question: "", focus: null, availableChars: budget });
}

/**
 * Quaderno completo e, se non sta in un messaggio, quello ridotto per questa
 * domanda. `history` è lo storico che partirà col messaggio (senza la domanda).
 */
export function planContext(snapshot, { question, focus, history, locale }) {
  const familyName = snapshot.familyName;
  const fullPrompt = agentSystemPrompt({ familyName, files: buildMemoryBook(snapshot, { locale }), focus, locale });
  const fullUnits = messageUnits(payloadChars(fullPrompt, history, question));
  if (fullUnits <= 1) return { fullPrompt, fullUnits: 1, reducedPrompt: null, reducedUnits: 1 };

  // Ridotto: si misura lo scheletro (tutti i testi a zero) e si divide il resto
  // del messaggio fra i documenti, i più utili per primi.
  const zero = Object.fromEntries(textDocuments(snapshot).map((t) => [t.doc.id, 0]));
  const skeleton = agentSystemPrompt({ familyName, files: buildMemoryBook(snapshot, { allowance: zero, locale }), focus, locale });
  // Di solito lo scheletro sta in un messaggio e il ridotto costa 1. Se già lo
  // scheletro non ci sta (02/10/2026: una famiglia con 30 esami e 88 documenti,
  // 50.449 caratteri senza un rigo di testo letto), il ridotto paga i messaggi
  // che servono allo scheletro e li riempie di testi, invece di buttarli tutti.
  const skeletonChars = payloadChars(skeleton, history, question);
  const target = messageUnits(skeletonChars + UNIT_SAFETY_MARGIN) * STANDARD_CHARS - UNIT_SAFETY_MARGIN;
  let reducedPrompt = null;
  let reducedChars = 0;

  // Base + appendice: nelle schede ogni testo ha una base che dipende solo dai
  // dati, uguale per ogni domanda, così resta nella cache; i testi scelti per
  // la domanda vanno in coda, in domanda.md. Misurato il 05/10/2026: col
  // budget diviso per domanda le due domande condividevano 2.165 caratteri e
  // la cache non serviva mai.
  const base = baseAllowances(snapshot, skeleton.stable.length);
  if (base) {
    const withBase = agentSystemPrompt({ familyName, files: buildMemoryBook(snapshot, { allowance: base, locale }), focus, locale });
    let budget = target - payloadChars(withBase, history, question) - APPENDIX_OVERHEAD;
    for (let attempt = 0; budget >= 0 && attempt < 3; attempt += 1) {
      const appendix = allowances(snapshot, { question, focus, availableChars: budget, targetedOnly: true, floor: base });
      reducedPrompt = agentSystemPrompt({ familyName, files: buildMemoryBook(snapshot, { allowance: base, appendix, locale }), focus, locale });
      reducedChars = payloadChars(reducedPrompt, history, question);
      if (reducedChars <= target || budget === 0) break;
      budget = Math.max(0, budget - (reducedChars - target));
    }
    if (reducedChars > target) reducedPrompt = null;
  }

  // Senza spazio per la base (storico lungo, scheletro enorme): il budget si
  // divide per domanda come prima, e la parte dei testi esce dalla cache.
  if (!reducedPrompt) {
    let available = Math.max(0, target - skeletonChars);
    // Il contorno stimato per documento non basta quando un allegato ha molte
    // righe (ognuna indentata): se sfora, lo sforamento esce dal budget e si
    // ridistribuisce.
    for (let attempt = 0; attempt < 3; attempt += 1) {
      const allowance = allowances(snapshot, { question, focus, availableChars: available });
      reducedPrompt = agentSystemPrompt({ familyName, files: buildMemoryBook(snapshot, { allowance, locale }), focus, locale });
      reducedChars = payloadChars(reducedPrompt, history, question);
      if (reducedChars <= target || available === 0) break;
      available = Math.max(0, available - (reducedChars - target));
    }
  }
  const reducedUnits = messageUnits(reducedChars);
  // Un ridotto che costa quanto il completo non è una scelta: si manda il completo.
  if (reducedUnits >= fullUnits) return { fullPrompt, fullUnits, reducedPrompt: null, reducedUnits: fullUnits };
  return { fullPrompt, fullUnits, reducedPrompt, reducedUnits };
}
