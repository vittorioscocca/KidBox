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

const START = "<<<KIDBOX_ACTIONS>>>";
const END = "<<<END_KIDBOX_ACTIONS>>>";

/** Sezione di prompt copiata da `PlanningAIActionBlock.promptSection`. */
export const ACTIONS_PROMPT = `
AZIONI ESEGUIBILI (obbligatorio quando modifichi dati nell'app):
Se confermi di aver aggiunto o modificato lista spesa, to-do, nota, calendario o promemoria salute, includi SEMPRE alla fine del messaggio (l'app lo nasconde all'utente) un blocco JSON:

${START}
[{"type":"grocery_add","items":["latte","pane"]}]
${END}

Tipi supportati (date in ISO8601 UTC):
- grocery_add: {"type":"grocery_add","items":["..."],"category":"..."}
- todo_add: {"type":"todo_add","title":"...","notes":"...","dueAt":"2026-05-17T09:00:00Z","childId":"...","listId":"..."}
- event_add: {"type":"event_add","title":"...","startAt":"...","endAt":"...","isAllDay":false,"notes":"..."}
- note_add: {"type":"note_add","title":"...","body":"..."}
- health_reminder: {"type":"health_reminder","title":"...","dueAt":"..."}

NON dire "ho aggiunto" o "fatto" senza il blocco quando l'utente chiede un'aggiunta concreta.`;

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

async function addTodo({ familyId, uid, title, notes, dueAt, childId, listId }) {
  await setDoc(doc(col(familyId, "todos"), crypto.randomUUID()), {
    childId: childId ?? "",
    title,
    listId: listId || "",
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
