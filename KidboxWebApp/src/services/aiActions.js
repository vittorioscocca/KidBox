/**
 * Azioni eseguibili dell'assistente: porta sul web il blocco `KIDBOX_ACTIONS`
 * di `PlanningAIActionBlock` e `PlanningActionExecutor` (iOS).
 *
 * Il modello, quando dice di aver aggiunto qualcosa, allega in coda alla
 * risposta un blocco JSON fra due marcatori. L'app lo esegue, lo toglie dal
 * testo mostrato e riassume all'utente che cosa ha fatto.
 *
 * Come su iOS l'esecuzione è **automatica**, non c'è una conferma: il blocco
 * arriva solo quando l'utente ha già chiesto esplicitamente l'aggiunta, e
 * richiedere due volte la stessa cosa sarebbe una seccatura. Il riepilogo
 * mostrato dopo dice sempre che cosa è stato scritto.
 */
import {
  collection,
  deleteField,
  doc,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { db } from "../firebase";
import { encryptString } from "./noteCrypto";
import { resolveTodoListId } from "./todoTarget";
import { createRequest } from "./requests";

const START = "<<<KIDBOX_ACTIONS>>>";
const END = "<<<END_KIDBOX_ACTIONS>>>";

/** Sezione di prompt copiata da `PlanningAIActionBlock.promptSection`. */
export const ACTIONS_PROMPT = `
AZIONI ESEGUIBILI (obbligatorio quando modifichi dati nell'app):
Se confermi di aver aggiunto o modificato lista spesa, to-do, nota, calendario o promemoria salute, includi SEMPRE alla fine del messaggio (l'app lo nasconde all'utente) un blocco JSON:

${START}
[{"type":"grocery_add","items":["latte","pane"]}]
${END}

Tipi supportati (date in ISO8601 con l'offset del fuso, vedi DATE E ORE):
- grocery_add: {"type":"grocery_add","items":["..."],"category":"..."}
- todo_add: {"type":"todo_add","title":"...","notes":"...","dueAt":"2026-05-17T09:00:00Z","childId":"...","listId":"..."}
- event_add: {"type":"event_add","title":"...","startAt":"...","endAt":"...","isAllDay":false,"notes":"..."}
- note_add: {"type":"note_add","title":"...","body":"..."}
- health_reminder: {"type":"health_reminder","title":"...","dueAt":"..."}
- request_add: {"type":"request_add","title":"...","dueAt":"...","notes":"...","askMembers":["Luca"],"askOutside":false,"outsideLabel":"Nonna"}

RICHIESTE (request_add, non todo_add): quando l'utente cerca QUALCUNO che faccia una cosa («serve qualcuno per…», «chiedi a Luca se può…», «chi può prendere Marco?»). I familiari ricevono una notifica con «Ci penso io» / «Non posso» e il primo che accetta si prende il to-do. askMembers: i nomi dei familiari che l'utente ha indicato, come li ha scritti; omettilo per chiedere a tutti. askOutside true SOLO se l'utente nomina qualcuno che non è in famiglia (nonni, babysitter…), con outsideLabel = come lo chiama: l'app prepara un link da mandargli. dueAt con l'ora esatta: se l'utente dice solo «mattina», «pomeriggio» o «sera», chiedi l'ora e NON includere il blocco finché non la sai. A chi è fuori dall'app NON arriva nessuna notifica: di' che l'app prepara un link da mandargli. Non dire chi è libero o occupato: l'app non lo sa.

NON dire "ho aggiunto" o "fatto" senza il blocco quando l'utente chiede un'aggiunta concreta.`;

/**
 * Fuso e prossimi giorni, da mettere davanti alle azioni.
 *
 * Senza, il modello scriveva l'ora italiana con la «Z» (UTC): un evento delle
 * 16:30 finiva alle 18:30. E sbagliava il giorno della settimana («sabato» →
 * il 4 invece del 3). Stesso testo su iOS e Android.
 */
export function actionsDateHeader(now = new Date()) {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Rome";
  const off = -now.getTimezoneOffset();
  const sign = off >= 0 ? "+" : "-";
  const pad = (n) => String(Math.floor(Math.abs(n))).padStart(2, "0");
  const offset = `${sign}${pad(off / 60)}:${pad(off % 60)}`;
  const day = (d) =>
    new Intl.DateTimeFormat("it-IT", { weekday: "long", day: "numeric", month: "numeric" }).format(d);
  const today = new Intl.DateTimeFormat("it-IT", {
    weekday: "long", day: "numeric", month: "long", year: "numeric",
  }).format(now);
  const next = [];
  for (let i = 1; i <= 7; i += 1) next.push(day(new Date(now.getTime() + i * 86_400_000)));
  return `DATE E ORE: l'utente è nel fuso ${tz} (ora UTC${offset}). Scrivi ogni data con questo offset, es. "2026-10-03T16:30:00${offset}" per le 16:30 locali: MAI la Z.
Oggi è ${today}. Prossimi giorni: ${next.join(", ")}.`;
}

/** Sezione azioni completa, con data e fuso di adesso. */
export function actionsPrompt(now = new Date()) {
  return `${actionsDateHeader(now)}\n${ACTIONS_PROMPT}`;
}

/**
 * Separa il blocco azioni dal testo da mostrare.
 *
 * Se il JSON è malformato si tiene comunque il testo ripulito: mostrare i
 * marcatori all'utente sarebbe peggio che perdere le azioni.
 */
export function processReply(text) {
  const start = text.indexOf(START);
  const end = start >= 0 ? text.indexOf(END, start + START.length) : -1;
  if (start < 0 || end < 0) return { displayText: text.trim(), actions: [] };

  const json = text.slice(start + START.length, end).trim();
  const displayText = (text.slice(0, start) + text.slice(end + END.length)).trim();

  try {
    const parsed = JSON.parse(json);
    return { displayText, actions: Array.isArray(parsed) ? parsed : [] };
  } catch {
    return { displayText, actions: [] };
  }
}

/* ── Esecuzione ──────────────────────────────────────────────────────────── */

const col = (familyId, name) => collection(db, "families", familyId, name);

const clean = (value) => (typeof value === "string" ? value.trim() : "");

/** ISO8601 → Date, `null` se la data non si legge. */
function parseDate(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

async function addGroceryItems({ familyId, uid, items, category, pendingNames }) {
  const already = new Set(pendingNames.map((n) => n.trim().toLowerCase()));
  const names = [];
  for (const raw of items || []) {
    const name = clean(raw);
    const key = name.toLowerCase();
    // `already` cresce mentre si scorre: senza, un elenco che ripete lo stesso
    // articolo («latte, pane, latte») lo scriverebbe due volte. iOS ha lo
    // stesso difetto, perché lì il set dei nomi è fissato prima del ciclo.
    if (!name || already.has(key)) continue;
    already.add(key);
    names.push(name);
  }
  if (!names.length) return null;

  for (const name of names) {
    await setDoc(doc(col(familyId, "groceries"), crypto.randomUUID()), {
      name,
      category: category || null,
      notes: null,
      isPurchased: false,
      isDeleted: false,
      purchasedAt: null,
      purchasedBy: null,
      createdBy: uid,
      createdAt: serverTimestamp(),
      updatedBy: uid,
      updatedAt: serverTimestamp(),
    });
  }
  return `Lista spesa: ${names.length} articol${names.length === 1 ? "o" : "i"} aggiunt${
    names.length === 1 ? "o" : "i"
  }.`;
}

async function addTodo({ familyId, uid, title, notes, dueAt, childId, listId, defaultListName }) {
  // Mai `listId: ""`: un to-do senza lista non compare in nessuna schermata,
  // né qui né su iOS/Android. Vedi `resolveTodoListId`.
  const targetListId = await resolveTodoListId({
    familyId,
    childId: childId ?? "",
    uid,
    listId,
    defaultListName,
  });
  await setDoc(doc(col(familyId, "todos"), crypto.randomUUID()), {
    childId: childId ?? "",
    title,
    listId: targetListId,
    isDone: false,
    isDeleted: false,
    notes: clean(notes) || null,
    dueAt: dueAt ? Timestamp.fromDate(dueAt) : null,
    assignedTo: null,
    priority: 0,
    visibilityScope: "family",
    visibilityMemberIds: [],
    doneAt: null,
    doneBy: null,
    createdBy: uid,
    createdAt: serverTimestamp(),
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
}

async function addEvent({ familyId, uid, title, start, end, isAllDay, notes }) {
  const id = crypto.randomUUID();
  // Fine mai prima dell'inizio: se il modello la omette o la sbaglia, si usa
  // l'inizio, come fa la schermata del calendario.
  const endDate = end && end >= start ? end : start;
  await setDoc(doc(col(familyId, "calendarEvents"), id), {
    id,
    familyId,
    title,
    isAllDay: Boolean(isAllDay),
    categoryRaw: "famiglia",
    recurrenceRaw: "none",
    isDeleted: false,
    startDate: Timestamp.fromDate(start),
    endDate: Timestamp.fromDate(endDate),
    location: null,
    notes: clean(notes) || null,
    visibilityScope: "family",
    visibilityMemberIds: [],
    createdBy: uid,
    createdAt: serverTimestamp(),
    updatedBy: uid,
    updatedAt: serverTimestamp(),
  });
}

async function addNote({ familyId, uid, userName, familyKey, title, body }) {
  await setDoc(doc(col(familyId, "notes"), crypto.randomUUID()), {
    schemaVersion: 1,
    titleEnc: await encryptString(title, familyKey),
    bodyEnc: await encryptString(body, familyKey),
    // I client nativi rimuovono i campi in chiaro legacy a ogni scrittura.
    title: deleteField(),
    body: deleteField(),
    visibilityScope: "family",
    visibilityMemberIds: [],
    isDeleted: false,
    createdAt: serverTimestamp(),
    createdBy: uid,
    createdByName: userName ?? null,
    updatedBy: uid,
    updatedByName: userName ?? null,
    updatedAt: serverTimestamp(),
  });
}

/**
 * Crea una richiesta («Chi prende Marco giovedì?») con lo stesso servizio
 * della vista «Chiedi a…». I nomi detti dall'utente diventano account della
 * famiglia; un nome che non si trova si dice nel riepilogo, e senza nessuno a
 * cui chiedere la richiesta non parte. Gemello di `addRequest` su iOS/Android.
 */
async function addRequest({ action, familyId, uid, userName, members, familyName, defaultChildId, defaultListName, r }) {
  const title = clean(action.title);
  if (!title) return null;
  const others = (members || []).filter((m) => m.id !== uid && !m.isDeleted);
  const wanted = (action.askMembers || []).map(clean).filter(Boolean);
  const recipients = [];
  const unknown = [];
  if (!wanted.length) {
    recipients.push(...others);
  } else {
    for (const name of wanted) {
      const key = name.toLowerCase();
      const match = others.find((m) => {
        const full = (m.displayName || "").trim().toLowerCase();
        return full === key || full.split(" ")[0] === key;
      });
      if (match) recipients.push(match);
      else unknown.push(name);
    }
  }
  const askOutside = action.askOutside === true;
  if (!recipients.length && !askOutside) return r.aiNotSentUnknown(unknown.join(", "));

  // Una lista vera: il to-do nascerà lì alla prima risposta «Ci penso io».
  const childId = action.childId ?? defaultChildId ?? "";
  const listId = await resolveTodoListId({ familyId, childId, uid, listId: action.listId, defaultListName });
  const outsideLabel = clean(action.outsideLabel);
  try {
    const created = await createRequest({
      familyId,
      childId,
      listId,
      uid,
      title,
      notes: clean(action.notes) || null,
      isUrgent: false,
      dueAt: parseDate(action.dueAt),
      draft: {
        recipients: recipients.map((m) => m.id),
        askOutside,
        outsideLabel,
        includeInvite: action.includeInvite !== false,
      },
      familyName: familyName || "",
      inviterDisplayName: userName || "",
    });
    const who = recipients.map((m) => (m.displayName || "").trim().split(" ")[0]).filter(Boolean);
    if (askOutside) who.push(outsideLabel || r.outsideLower);
    const lines = [r.aiSent(who.join(", "), title)];
    if (unknown.length) lines.push(r.aiUnknown(unknown.join(", ")));
    if (created.shareLink) lines.push(r.aiLink(created.shareLink));
    return lines.join("\n");
  } catch (err) {
    return r.aiNotSent(err.message === "DUE_IN_PAST" ? r.dueInPast : err.message);
  }
}

/**
 * Esegue le azioni e restituisce il riepilogo da mostrare, o `null` se non è
 * stato scritto nulla.
 *
 * `loadFamilyKey` è passato dal chiamante e invocato SOLO se arriva una nota:
 * la chiave serve solo per cifrarla, e chiederla sempre farebbe fallire le
 * altre azioni su un dispositivo che non ce l'ha.
 */
export async function executeActions({
  actions,
  familyId,
  uid,
  userName,
  defaultChildId,
  pendingGroceryNames = [],
  loadFamilyKey,
  /** Nome della lista da creare se la famiglia non ne ha ancora nessuna. */
  defaultListName,
  /** Per `request_add`: membri della famiglia, nome della famiglia, testi. */
  members = [],
  familyName = "",
  requestTexts,
}) {
  if (!actions.length) return null;
  const lines = [];

  for (const action of actions) {
    try {
      switch (action.type) {
        case "grocery_add": {
          const line = await addGroceryItems({
            familyId,
            uid,
            items: action.items,
            category: action.category,
            pendingNames: pendingGroceryNames,
          });
          if (line) lines.push(line);
          break;
        }
        case "todo_add": {
          const title = clean(action.title);
          if (!title) break;
          await addTodo({
            familyId,
            uid,
            title,
            notes: action.notes,
            dueAt: parseDate(action.dueAt),
            childId: action.childId ?? defaultChildId ?? "",
            listId: action.listId,
            defaultListName,
          });
          lines.push(`To-do aggiunto: «${title}».`);
          break;
        }
        case "event_add": {
          const title = clean(action.title);
          const start = parseDate(action.startAt) ?? parseDate(action.dueAt);
          if (!title || !start) break;
          await addEvent({
            familyId,
            uid,
            title,
            start,
            end: parseDate(action.endAt),
            isAllDay: action.isAllDay,
            notes: action.notes,
          });
          lines.push(`Evento aggiunto: «${title}».`);
          break;
        }
        case "note_add": {
          const title = clean(action.title) || clean(action.body).split("\n")[0];
          if (!title) break;
          const familyKey = await loadFamilyKey();
          await addNote({
            familyId,
            uid,
            userName,
            familyKey,
            title,
            body: clean(action.body) || title,
          });
          lines.push(`Nota creata: «${title}».`);
          break;
        }
        case "request_add": {
          if (!requestTexts) break;
          const line = await addRequest({
            action,
            familyId,
            uid,
            userName,
            members,
            familyName,
            defaultChildId,
            defaultListName,
            r: requestTexts,
          });
          if (line) lines.push(line);
          break;
        }
        case "health_reminder": {
          // Sul telefono questo diventa una notifica locale programmata. Il web
          // non può schedulare notifiche, quindi diventa un to-do con scadenza:
          // il promemoria resta, e lo ripesca l'app quando sincronizza.
          const title = clean(action.title);
          if (!title) break;
          const due = parseDate(action.dueAt) ?? new Date(Date.now() + 86_400_000);
          await addTodo({
            familyId,
            uid,
            title,
            notes: null,
            dueAt: due,
            childId: action.childId ?? defaultChildId ?? "",
            listId: action.listId,
          });
          lines.push(`Promemoria aggiunto ai to-do: «${title}».`);
          break;
        }
        default:
          break;
      }
    } catch (err) {
      lines.push(`Non riuscito «${action.type}»: ${err.message}`);
    }
  }

  return lines.length ? lines.join("\n") : null;
}
