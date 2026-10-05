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
 *
 * ## Cifratura (dal 02/10/2026)
 *
 * Testo dei messaggi e riassunto possono essere cifrati con la chiave della
 * famiglia della conversazione (`contentEnc`, `summaryEnc`, stesso formato delle
 * note e di `AIChatRemoteStore` su iOS). La lettura capisce sempre entrambi i
 * formati. La scrittura cifra solo a interruttore acceso
 * (`text_encryption_enabled`): prima, le build iOS vecchie riscriverebbero
 * in chiaro l'array intero e cancellerebbero i messaggi che non sanno leggere.
 * Acceso, un documento ancora in chiaro appena letto si riscrive cifrato, e
 * senza chiave non si scrive niente: mai testo in chiaro come ripiego.
 */
import {
  collection,
  deleteField,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { db, functions } from "../firebase";
import { loadFamilyKey } from "./familyKey";
import { textEncryptionEnabled } from "./featureFlags";
import { decryptString, encryptString } from "./noteCrypto";

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

/** Chiave della famiglia, o null se su questo browser non c'è. */
async function familyKeyOrNull(uid, familyId) {
  try {
    return await loadFamilyKey({ familyId, userId: uid });
  } catch {
    return null;
  }
}

/**
 * Testo di un campo che può essere cifrato o legacy in chiaro. Un testo
 * cifrato che non si apre torna `null`: chi chiama decide cosa farne, ma non
 * deve mai scambiarlo per una stringa vuota da riscrivere.
 */
async function openField(enc, plain, familyKey) {
  if (typeof enc === "string" && enc) {
    if (!familyKey) return null;
    try {
      return await decryptString(enc, familyKey);
    } catch {
      return null;
    }
  }
  return typeof plain === "string" ? plain : null;
}

async function readConversation(snap, familyKey) {
  const d = snap.data();
  const raw = Array.isArray(d.messages) ? d.messages : [];
  const messages = (
    await Promise.all(
      raw
        .filter((m) => m && (typeof m.contentEnc === "string" || typeof m.content === "string"))
        .map(async (m) => {
          const content = await openField(m.contentEnc, m.content, familyKey);
          return {
            id: m.id,
            // `roleRaw` è il nome del campo su iOS: cambiarlo qui renderebbe i
            // messaggi del web invisibili al telefono.
            role: m.roleRaw === "assistant" ? "assistant" : "user",
            // Un messaggio che non si decifra resta con il suo blob: alla
            // prossima scrittura torna su com'era, invece di sparire.
            content: content ?? "🔒",
            locked: content === null ? m.contentEnc : undefined,
            createdAt: millis(m.createdAt) ?? 0,
          };
        })
    )
  ).sort((a, b) => a.createdAt - b.createdAt);
  return {
    docId: snap.id,
    id: d.conversationId || snap.id,
    familyId: d.familyId || "",
    scopeId: d.visitId || "",
    isDeleted: Boolean(d.isDeleted),
    createdAt: millis(d.createdAt) ?? 0,
    updatedAt: millis(d.updatedAt) ?? 0,
    summary: await openField(d.summaryEnc, d.summary, familyKey),
    // Ancora in chiaro su Firestore: va riscritto cifrato.
    legacyPlain:
      raw.some((m) => m && typeof m.content === "string") ||
      (typeof d.summary === "string" && d.summary.length > 0),
    messages,
  };
}

/**
 * Conversazioni dell'assistente: quella corrente più gli archivi, dalla più
 * recente. Le chat legate a una visita medica restano fuori: hanno una loro
 * schermata sul telefono e qui non avrebbero contesto.
 *
 * La decifratura è asincrona: se nel frattempo arriva uno snapshot nuovo, il
 * risultato del vecchio si butta. I documenti di questa famiglia ancora in
 * chiaro (comprese le vecchie chat Salute) si riscrivono cifrati, una volta.
 */
export function listenConversations({ uid, familyId, onChange, onError }) {
  let generation = 0;
  const migrated = new Set();
  return onSnapshot(
    conversationsCol(uid),
    async (snap) => {
      const mine = ++generation;
      try {
        const familyKey = await familyKeyOrNull(uid, familyId);
        const ours = snap.docs.filter((d) => (d.data().familyId || "") === familyId);
        const all = await Promise.all(ours.map((d) => readConversation(d, familyKey)));
        if (mine !== generation) return;
        const rows = all
          .filter(
            (c) =>
              !c.isDeleted &&
              (c.scopeId === currentScopeId(familyId) ||
                c.scopeId.startsWith(`planning-archive-${familyId}-`))
          )
          .sort((a, b) => b.updatedAt - a.updatedAt);
        onChange(rows);
        if (familyKey && textEncryptionEnabled()) {
          all
            .filter((c) => c.legacyPlain && !migrated.has(c.docId))
            .forEach((c) => {
              migrated.add(c.docId);
              encryptInPlace({ uid, docId: c.docId, conversation: c, familyKey }).catch((err) =>
                console.warn("cifratura della conversazione non riuscita:", err?.name)
              );
            });
        }
      } catch (err) {
        onError?.(err);
      }
    },
    (err) => onError?.(err)
  );
}

/**
 * Riscrive cifrato un documento ancora in chiaro, senza toccare `updatedAt`:
 * gli archivi non devono risalire in cima allo storico, e su iOS il riassunto
 * segue l'ultima scrittura.
 */
async function encryptInPlace({ uid, docId, conversation, familyKey }) {
  await setDoc(
    doc(conversationsCol(uid), docId),
    {
      messages: await messagesPayload(conversation.messages, familyKey),
      summary: deleteField(),
      summaryEnc: conversation.summary ? await encryptString(conversation.summary, familyKey) : deleteField(),
    },
    { merge: true }
  );
}

/**
 * Messaggi per Firestore: cifrati se c'è la chiave (interruttore acceso), in
 * chiaro altrimenti. Un messaggio che qui non si è potuto decifrare torna su
 * col suo blob originale in entrambi i casi.
 */
async function messagesPayload(messages, familyKey) {
  return Promise.all(
    messages.map(async (m) => {
      const row = { id: m.id, roleRaw: m.role, createdAt: Timestamp.fromMillis(m.createdAt) };
      if (m.locked) row.contentEnc = m.locked;
      else if (familyKey) row.contentEnc = await encryptString(m.content, familyKey);
      else row.content = m.content;
      return row;
    })
  );
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
  // Acceso l'interruttore, senza chiave lancia MissingFamilyKeyError: meglio un
  // errore che il testo in chiaro.
  const familyKey = textEncryptionEnabled() ? await loadFamilyKey({ familyId, userId: uid }) : null;
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
      // Un solo formato per volta: la lettura preferisce `summaryEnc`, e uno
      // vecchio rimasto lì coprirebbe quello nuovo.
      summary: familyKey ? deleteField() : summary,
      summaryEnc: familyKey && summary ? await encryptString(summary, familyKey) : deleteField(),
      summaryUpdatedAt: summary ? serverTimestamp() : null,
      isDeleted: false,
      messages: await messagesPayload(messages, familyKey),
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
export async function askAssistant({ messages, systemPrompt, systemPromptStable, systemPromptTail, familyId, purpose }) {
  const callable = httpsCallable(functions, "askAI", { timeout: 120_000 });
  const { data } = await callable({
    messages: messages.map((m) => ({ role: m.role, content: m.content })),
    systemPrompt,
    // Parte del prompt che cambia di rado: il server la mette in cache da sola.
    ...(systemPromptStable ? { systemPromptStable } : {}),
    // Coda che cambia a ogni domanda (testi scelti nel contesto ridotto): senza cache.
    ...(systemPromptTail ? { systemPromptTail } : {}),
    familyId,
    // `familyAgent` riconosce l'assistente in log e analytics del server.
    ...(purpose ? { purpose } : {}),
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

/**
 * Lo storico che parte con una domanda all'assistente: l'eventuale riassunto più
 * gli ultimi 6 messaggi, come su iOS e Android. Mandare tutta la conversazione
 * farebbe crescere il costo a ogni scambio, con la memoria già nel prompt.
 */
export function recentPayload(messages) {
  const summary = messages.find((m) => m.id?.startsWith(SUMMARY_PREFIX));
  const rest = messages.filter((m) => !m.id?.startsWith(SUMMARY_PREFIX)).slice(-6);
  return summary ? [summary, ...rest] : rest;
}

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
