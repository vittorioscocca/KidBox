/**
 * Assistente AI: conversazioni e chiamata al modello.
 *
 * Le chat vivono in `users/{uid}/aiConversations/{docId}`, **private per utente**
 * — nessun altro membro della famiglia le vede — con lo stesso schema di
 * `AIChatRemoteStore` su iOS: i messaggi sono un array dentro il documento.
 *
 * L'id del documento è deterministico, `{provider}__{scopeId}`, così tutti i
 * dispositivi dello stesso utente scrivono sullo stesso documento.
 *
 * ## Perché il web ha uno storico e il telefono no
 *
 * iOS tiene UNA sola conversazione per famiglia (`planning-agent-{familyId}`) e
 * il suo pulsante «Nuova conversazione» la svuota: i messaggi vecchi si
 * perdono. Qui la sessione corrente è **la stessa** del telefono, così le due
 * app continuano lo stesso discorso; «Nuova sessione» però, invece di buttare
 * via i messaggi, li archivia in un documento a parte prima di svuotare.
 *
 * Gli archivi hanno uno scope che iOS non cerca mai, quindi il telefono li
 * scarica e li ignora: costano un po' di spazio locale, non creano confusione.
 */
import {
  collection,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { db, functions } from "../firebase";

const PROVIDER = "claude";

/** Scope della conversazione condivisa con iOS e Android. */
export const currentScopeId = (familyId) => `planning-agent-${familyId}`;

/** Scope di un archivio: iOS non lo cerca, quindi non interferisce. */
const archiveScopeId = (familyId) => `planning-archive-${familyId}-${Date.now()}`;

/** Stesso id deterministico di `KBAIConversation.remoteDocId`. */
const docIdFor = (scopeId) =>
  `${PROVIDER}__${scopeId}`.replaceAll("/", "_").replaceAll("..", "_");

const conversationsCol = (uid) => collection(db, "users", uid, "aiConversations");

const millis = (value) => (value?.toMillis ? value.toMillis() : null);

function readConversation(snap) {
  const d = snap.data();
  const messages = Array.isArray(d.messages) ? d.messages : [];
  return {
    docId: snap.id,
    id: d.conversationId || snap.id,
    familyId: d.familyId || "",
    scopeId: d.visitId || "",
    isDeleted: Boolean(d.isDeleted),
    createdAt: millis(d.createdAt) ?? 0,
    updatedAt: millis(d.updatedAt) ?? 0,
    messages: messages
      .filter((m) => m && typeof m.content === "string")
      .map((m) => ({
        id: m.id,
        // `roleRaw` è il nome del campo su iOS: cambiarlo qui renderebbe i
        // messaggi del web invisibili al telefono.
        role: m.roleRaw === "assistant" ? "assistant" : "user",
        content: m.content,
        createdAt: millis(m.createdAt) ?? 0,
      }))
      .sort((a, b) => a.createdAt - b.createdAt),
  };
}

/**
 * Conversazioni dell'assistente: quella corrente più gli archivi, dalla più
 * recente. Le chat legate a una visita medica restano fuori: hanno una loro
 * schermata sul telefono e qui non avrebbero contesto.
 */
export function listenConversations({ uid, familyId, onChange, onError }) {
  return onSnapshot(
    conversationsCol(uid),
    (snap) => {
      const rows = snap.docs
        .map(readConversation)
        .filter(
          (c) =>
            !c.isDeleted &&
            (c.scopeId === currentScopeId(familyId) ||
              c.scopeId.startsWith(`planning-archive-${familyId}-`))
        )
        .sort((a, b) => b.updatedAt - a.updatedAt);
      onChange(rows);
    },
    (err) => onError?.(err)
  );
}

function messagesPayload(messages) {
  return messages.map((m) => ({
    id: m.id,
    roleRaw: m.role,
    content: m.content,
    createdAt: Timestamp.fromMillis(m.createdAt),
  }));
}

/** Scrive la conversazione intera, messaggi inclusi (come fa `upsert` su iOS). */
export async function saveConversation({
  uid,
  familyId,
  scopeId,
  conversationId,
  messages,
  createdAt,
  summary = null,
}) {
  const scope = scopeId || currentScopeId(familyId);
  await setDoc(
    doc(conversationsCol(uid), docIdFor(scope)),
    {
      conversationId: conversationId || scope,
      familyId,
      // iOS usa `childId` come contenitore dello scope famiglia per l'agente di
      // pianificazione: qui si replica, altrimenti il documento risulterebbe
      // malformato al telefono.
      childId: familyId,
      visitId: scope,
      providerRaw: PROVIDER,
      ownerUserId: uid,
      createdAt: Timestamp.fromMillis(createdAt || Date.now()),
      updatedAt: serverTimestamp(),
      summarizedMessageCount: 0,
      summary,
      summaryUpdatedAt: summary ? serverTimestamp() : null,
      isDeleted: false,
      messages: messagesPayload(messages),
    },
    { merge: true }
  );
}

/**
 * Archivia la sessione corrente e la svuota.
 *
 * Prima l'archivio, poi lo svuotamento: se si azzerasse per primo e la seconda
 * scrittura fallisse, la conversazione sarebbe persa — che è esattamente quello
 * che questa funzione serve a evitare.
 */
export async function startNewSession({ uid, familyId, messages, createdAt }) {
  if (messages.length > 0) {
    const scope = archiveScopeId(familyId);
    await saveConversation({
      uid,
      familyId,
      scopeId: scope,
      conversationId: scope,
      messages,
      createdAt: createdAt || messages[0]?.createdAt || Date.now(),
    });
  }
  await saveConversation({
    uid,
    familyId,
    scopeId: currentScopeId(familyId),
    messages: [],
    createdAt: Date.now(),
  });
}

/** Nasconde una conversazione archiviata. Marcata, non rimossa: è lo stesso
 *  `isDeleted` che i client nativi si aspettano di trovare. */
export async function deleteConversation({ uid, docId }) {
  await setDoc(
    doc(conversationsCol(uid), docId),
    { isDeleted: true, updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/* ── Modello ─────────────────────────────────────────────────────────────── */

/**
 * Chiama la function `askAI`, lo stesso endpoint di iOS e Android.
 *
 * La quota è applicata dal server: qui non si finge alcun controllo di piano,
 * si mostra soltanto il contatore che il server restituisce.
 */
export async function askAssistant({ messages, systemPrompt, familyId }) {
  const callable = httpsCallable(functions, "askAI", { timeout: 120_000 });
  const { data } = await callable({
    messages: messages.map((m) => ({ role: m.role, content: m.content })),
    systemPrompt,
    familyId,
  });
  if (!data || typeof data.reply !== "string") {
    throw new Error("Risposta dell'assistente non valida.");
  }
  return {
    reply: data.reply,
    usageToday: data.usageToday ?? 0,
    dailyLimit: data.dailyLimit ?? 0,
    period: data.period || "daily",
  };
}

/**
 * Prompt di compattazione, copiato da `compactionSystemPrompt` su iOS: il
 * riassunto deve venire fuori uguale sulle due superfici, perché diventa il
 * contesto con cui la conversazione prosegue.
 */
const COMPACTION_PROMPT =
  "Riassumi in modo conciso ma completo la conversazione seguente, mantenendo i punti chiave, " +
  "le decisioni prese e il contesto importante. Il riassunto sarà usato come contesto per " +
  "continuare la conversazione.";

/**
 * Decide se compattare, con la stessa regola di `compactIfNeeded` su iOS: si
 * guarda la **quota AI consumata**, non la lunghezza della chat, e si compatta
 * al massimo una volta ogni 20% di quota superato il 60%.
 *
 * `lastStep` è quello restituito dalla chiamata precedente; parte da 0 e vive
 * quanto la pagina, come la variabile in memoria del telefono.
 */
export function compactionStep({ usageToday, dailyLimit, lastStep }) {
  if (!dailyLimit || usageToday < dailyLimit * 0.6) return null;
  const stepBase = dailyLimit * 0.2;
  if (stepBase <= 0) return null;
  const step = Math.floor(usageToday / stepBase);
  return step > lastStep ? step : null;
}

/**
 * Chiede al modello il riassunto della conversazione. Costa un messaggio di
 * quota come qualsiasi altra chiamata: è il prezzo che paga anche l'app.
 */
export async function summarizeConversation({ messages, familyId }) {
  const { reply } = await askAssistant({
    messages,
    systemPrompt: COMPACTION_PROMPT,
    familyId,
  });
  return reply;
}

/** Prefisso dell'id del messaggio-riassunto, come su iOS (`summary-{id}`). */
export const SUMMARY_PREFIX = "summary-";

/** Contatore d'uso senza inviare un messaggio. */
export async function fetchUsage(familyId) {
  const callable = httpsCallable(functions, "getAIUsage");
  const { data } = await callable({ familyId });
  return {
    usageToday: data?.usageToday ?? 0,
    dailyLimit: data?.dailyLimit ?? 0,
    period: data?.period || "daily",
  };
}
