/**
 * Memoria famiglia: porta sul web `FamilyMemoryService` e `MemoryFactRemoteStore`.
 *
 * Sono fatti DURATURI estratti dalle conversazioni («la bambina non mangia
 * verdura», «pagano le bollette a inizio mese») e riusati nei prompt successivi.
 * Vivono in `families/{familyId}/memoryFacts/{id}`, condivisi con tutta la
 * famiglia e con i client nativi: lo schema è quello del telefono, campo per
 * campo, altrimenti i fatti scritti dal web non comparirebbero nell'app.
 *
 * L'estrazione parte dopo la compattazione, sui messaggi che stanno per essere
 * archiviati: è l'unico momento in cui c'è una conversazione conclusa da
 * riassumere, ed è dove la fa anche iOS.
 *
 * Cifratura (dal 02/10/2026): il testo del fatto può viaggiare cifrato con la
 * chiave di famiglia (`contentEnc`, formato di iOS e Android). La lettura
 * capisce entrambi i formati; la scrittura cifra con l'interruttore
 * `ai_conversations_encrypted` acceso, e allora i fatti ancora in chiaro si
 * riscrivono cifrati la prima volta che si leggono. Senza chiave non si scrive.
 */
import {
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { auth, db } from "../firebase";
import { askAssistant } from "./aiChat";
import { aiConversationsEncrypted } from "./featureFlags";
import { loadFamilyKey } from "./familyKey";
import { decryptString, encryptString } from "./noteCrypto";

/** Categorie ammesse, uguali a `MemoryFactCategory`. Una riga con una categoria
 *  fuori elenco viene scartata, come su iOS. */
const CATEGORIES = new Set([
  "salute",
  "abitudini",
  "preferenze",
  "scuola",
  "relazioni",
  "casa",
  "wallet",
  "animali",
  "altro",
]);

const MAX_FACTS_PER_FAMILY = 25;
const DEDUPE_PREFIX_WORDS = 6;
const MAX_FACTS_PER_EXTRACTION = 8;
const TRANSCRIPT_MESSAGES = 20;

/** Copiato da `extractionSystemPrompt`: cambiarlo qui farebbe estrarre al web
 *  fatti di forma diversa da quelli del telefono, nella stessa collezione. */
const EXTRACTION_PROMPT = `Sei un estrattore di memoria familiare per KidBox.
Analizza la conversazione e estrai SOLO fatti DURATURI sulla famiglia (abitudini, preferenze, problemi ricorrenti, relazioni, stili di vita).

REGOLE:
- Max 8 fatti, ognuno su una riga separata nel formato: [categoria] fatto
- Categorie valide: salute, abitudini, preferenze, scuola, relazioni, casa, wallet, animali, altro
- Ogni fatto: max 20 parole, in italiano, terza persona.
- IGNORA: eventi one-time, dati già strutturati nell'app (visite, farmaci, calendari), informazioni temporanee.
- INCLUDI: pattern comportamentali, preferenze espresse, osservazioni narrative, cose dette in modo informale dall'utente che rivelano la famiglia.
- Per 'casa': includi solo pattern ricorrenti (elettrodomestici problematici, abitudini di manutenzione), NON interventi one-time.
- Per 'wallet': includi pattern di spesa, priorità dichiarate, budget abituali.
- Per 'animali': includi salute cronica, preferenze veterinarie, abitudini.
- Se non ci sono fatti duraturi, rispondi esattamente: NESSUN_FATTO`;

const factsCol = (familyId) => collection(db, "families", familyId, "memoryFacts");

const millis = (value) => (value?.toMillis ? value.toMillis() : null);

/** Chiave della famiglia, o null se su questo browser non c'è. */
async function familyKeyOrNull(familyId) {
  const uid = auth.currentUser?.uid;
  if (!uid) return null;
  try {
    return await loadFamilyKey({ familyId, userId: uid });
  } catch {
    return null;
  }
}

/** Testo del fatto per Firestore: un solo formato per volta. */
async function contentFields(content, familyKey) {
  return familyKey
    ? { contentEnc: await encryptString(content, familyKey), content: deleteField() }
    : { content, contentEnc: deleteField() };
}

/** Famiglie i cui fatti in chiaro sono già stati ricifrati in questa sessione. */
const reencrypted = new Set();

/** I fatti della famiglia, dal più vecchio: è l'ordine in cui si tagliano. */
export async function loadFacts(familyId) {
  try {
    const [snap, familyKey] = await Promise.all([getDocs(factsCol(familyId)), familyKeyOrNull(familyId)]);
    const rows = await Promise.all(
      snap.docs.map(async (d) => {
        const f = d.data();
        let content = typeof f.content === "string" ? f.content : null;
        const legacyPlain = !(typeof f.contentEnc === "string" && f.contentEnc);
        if (!legacyPlain) {
          // Un blob che non si apre fa saltare il fatto.
          content = familyKey ? await decryptString(f.contentEnc, familyKey).catch(() => null) : null;
        }
        return {
          docId: d.id,
          id: f.id || d.id,
          content,
          category: CATEGORIES.has(f.categoryRaw) ? f.categoryRaw : "altro",
          createdAt: millis(f.createdAt) ?? 0,
          legacyPlain,
        };
      })
    );
    const facts = rows
      .filter((f) => typeof f.content === "string" && f.content.length > 0)
      .sort((a, b) => a.createdAt - b.createdAt);
    if (familyKey && aiConversationsEncrypted() && !reencrypted.has(familyId)) {
      reencrypted.add(familyId);
      facts
        .filter((f) => f.legacyPlain)
        .forEach(async (f) => {
          try {
            await setDoc(doc(factsCol(familyId), f.docId), await contentFields(f.content, familyKey), { merge: true });
          } catch {
            // Riprova alla prossima sessione.
          }
        });
    }
    return facts;
  } catch {
    return [];
  }
}

/** Blocco di prompt, identico a quello di `PlanningContextBuilder`. */
export function memorySection(facts) {
  if (!facts.length) return null;
  return (
    `\n## Memoria famiglia (fatti appresi dalle conversazioni precedenti)\n` +
    facts.map((f) => `• ${f.content}`).join("\n") +
    `\n\nUsa questi fatti per personalizzare le risposte senza menzionare esplicitamente ` +
    `che li hai memorizzati, a meno che non sia rilevante.`
  );
}

/* ── Estrazione ──────────────────────────────────────────────────────────── */

/** Ultimi 20 scambi, senza i riassunti: riassumere un riassunto non aggiunge fatti. */
function buildTranscript(messages, isSummary) {
  const dialog = messages.filter(
    (m) => !isSummary(m) && (m.role === "user" || m.role === "assistant")
  );
  return dialog
    .slice(-TRANSCRIPT_MESSAGES)
    .map((m) => `${m.role === "user" ? "Utente" : "Assistente"}: ${m.content}`)
    .join("\n\n");
}

/** «[abitudini] cenano presto» → {category, content}. Righe fuori formato: scartate. */
function parseFactLine(line) {
  if (!line.startsWith("[")) return null;
  const close = line.indexOf("]");
  if (close < 0) return null;
  const category = line.slice(1, close).trim().toLowerCase();
  const content = line.slice(close + 1).trim();
  if (!content || !CATEGORIES.has(category)) return null;
  return { category, content };
}

function parseExtractedFacts(raw) {
  const trimmed = (raw || "").trim();
  if (trimmed.toUpperCase() === "NESSUN_FATTO") return [];
  const out = [];
  for (const line of trimmed.split(/\r?\n/)) {
    const parsed = parseFactLine(line.trim());
    if (parsed) out.push(parsed);
    if (out.length >= MAX_FACTS_PER_EXTRACTION) break;
  }
  return out;
}

/** Chiave di deduplica: le prime sei parole in minuscolo, come su iOS. */
function dedupeKey(content) {
  return content
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, DEDUPE_PREFIX_WORDS)
    .join(" ");
}

/**
 * Estrae i fatti dalla conversazione e li salva, deduplicando e tenendo la
 * famiglia entro i 25 fatti (si tagliano i più vecchi).
 *
 * Non solleva: è manutenzione in sottofondo, e un errore qui non deve
 * rovinare la conversazione che l'utente sta avendo.
 */
export async function extractAndStore({ familyId, messages, conversationId, isSummary }) {
  try {
    const transcript = buildTranscript(messages, isSummary);
    if (!transcript) return 0;

    const { reply } = await askAssistant({
      messages: [{ role: "user", content: transcript }],
      systemPrompt: EXTRACTION_PROMPT,
      familyId,
    });

    const parsed = parseExtractedFacts(reply);
    if (!parsed.length) return 0;

    const existing = await loadFacts(familyId);
    const seen = new Set(existing.map((f) => dedupeKey(f.content)));

    const toInsert = [];
    for (const fact of parsed) {
      const key = dedupeKey(fact.content);
      // `seen` cresce strada facendo, così due fatti quasi uguali nella stessa
      // estrazione non entrano entrambi.
      if (!key || seen.has(key)) continue;
      seen.add(key);
      toInsert.push(fact);
    }
    if (!toInsert.length) return 0;

    const overflow = existing.length + toInsert.length - MAX_FACTS_PER_FAMILY;
    if (overflow > 0) {
      for (const old of existing.slice(0, overflow)) {
        await deleteDoc(doc(factsCol(familyId), old.docId));
      }
    }

    // Acceso l'interruttore, senza chiave lancia: niente fatti in chiaro.
    const familyKey = aiConversationsEncrypted()
      ? await loadFamilyKey({ familyId, userId: auth.currentUser?.uid })
      : null;
    for (const fact of toInsert) {
      const id = crypto.randomUUID();
      await setDoc(doc(factsCol(familyId), id), {
        id,
        familyId,
        ...(await contentFields(fact.content, familyKey)),
        categoryRaw: fact.category,
        sourceConversationId: conversationId || null,
        createdAt: Timestamp.now(),
        updatedAt: serverTimestamp(),
      });
    }
    return toInsert.length;
  } catch {
    return 0;
  }
}
