/**
 * Chat AI di Salute, sui tre livelli che ha iOS:
 *
 *   salute  → `HealthAIChatViewModel`            scope `health-overview-v2-{id}`
 *   visite  → `PediatricVisitsAIChatViewModel`   scope `visits-child-v2-{id}`
 *   analisi → `PediatricExamsAIChatViewModel`    scope `exam-all-v2-{id}`
 *
 * Gli scope sono quelli del telefono, non nuovi: la conversazione aperta qui è
 * **la stessa** che si trova sull'iPhone, perché il documento Firestore ha id
 * deterministico `{provider}__{scopeId}` sotto `users/{uid}/aiConversations`.
 * Cambiare uno di questi id spezzerebbe la continuità senza dare in cambio
 * niente.
 *
 * I system prompt sono il porting di `HealthContextBuilder` (variante
 * `healthChat`), `PediatricVisitsContextBuilder` ed `ExamContextBuilder`.
 * Manca il blocco azioni di pianificazione (`PlanningAIActionBlock`): sul
 * telefono la chat Salute può creare to-do ed eventi, qui no — meglio non
 * prometterlo nel prompt che lasciare l'utente davanti a un'azione che nessuno
 * esegue.
 */
import {
  collection,
  doc,
  onSnapshot,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { db } from "../firebase";
import { buildHealthContext, frequencyLabel } from "./healthContext";
import { examStatusInfo, EXAM_STATUSES } from "./health";

const PROVIDER = "claude";

/* ── Scope ───────────────────────────────────────────────────────────────── */

export const HEALTH_SCOPES = {
  health: (subjectId) => `health-overview-v2-${subjectId}`,
  // iOS distingue bambino e membro adulto nello scope delle visite. Il web non
  // sa sempre quale sia il soggetto, ma il chiamante sì: passa `kind`.
  visits: (subjectId, kind) =>
    kind === "member" ? `visits-member-v2-${subjectId}` : `visits-child-v2-${subjectId}`,
  exams: (subjectId) => `exam-all-v2-${subjectId}`,
};

/** Stesso id deterministico di `KBAIConversation.remoteDocId`. */
const docIdFor = (scopeId) =>
  `${PROVIDER}__${scopeId}`.replaceAll("/", "_").replaceAll("..", "_");

/**
 * `familyId`/`childId` del documento: iOS ci mette il soggetto per la chat
 * Salute e due costanti per visite ed esami. Non sono chiavi di ricerca (la
 * ricerca passa da `visitId`), ma vanno riprodotte perché il telefono le
 * rilegge nel suo modello.
 */
const ownerFieldsFor = (kind, subjectId) => {
  if (kind === "visits") return { familyId: "pediatric-visits", childId: "pediatric-visits" };
  if (kind === "exams") return { familyId: "pediatric-exams", childId: "pediatric-exams" };
  return { familyId: subjectId, childId: subjectId };
};

/* ── Persistenza ─────────────────────────────────────────────────────────── */

const millis = (v) => (v?.toMillis ? v.toMillis() : null);

/** Ascolta la singola conversazione di uno scope. */
export function listenHealthConversation({ uid, scopeId, onChange, onError }) {
  return onSnapshot(
    doc(collection(db, "users", uid, "aiConversations"), docIdFor(scopeId)),
    (snap) => {
      if (!snap.exists()) {
        onChange({ messages: [], createdAt: null });
        return;
      }
      const d = snap.data();
      const messages = Array.isArray(d.messages) ? d.messages : [];
      onChange({
        createdAt: millis(d.createdAt),
        messages: messages
          .filter((m) => m && typeof m.content === "string")
          .map((m) => ({
            id: m.id,
            // `roleRaw` è il nome del campo su iOS: rinominarlo renderebbe i
            // messaggi scritti dal web invisibili al telefono.
            role: m.roleRaw === "assistant" ? "assistant" : "user",
            content: m.content,
            createdAt: millis(m.createdAt) ?? 0,
          }))
          .sort((a, b) => a.createdAt - b.createdAt),
      });
    },
    (err) => onError?.(err)
  );
}

export async function saveHealthConversation({ uid, kind, subjectId, scopeId, messages, createdAt }) {
  await setDoc(
    doc(collection(db, "users", uid, "aiConversations"), docIdFor(scopeId)),
    {
      conversationId: scopeId,
      ...ownerFieldsFor(kind, subjectId),
      visitId: scopeId,
      providerRaw: PROVIDER,
      ownerUserId: uid,
      createdAt: Timestamp.fromMillis(createdAt || Date.now()),
      updatedAt: serverTimestamp(),
      summarizedMessageCount: 0,
      summary: null,
      summaryUpdatedAt: null,
      isDeleted: false,
      messages: messages.map((m) => ({
        id: m.id,
        roleRaw: m.role,
        content: m.content,
        createdAt: Timestamp.fromMillis(m.createdAt),
      })),
    },
    { merge: true }
  );
}

/** Svuota la conversazione. Come «Nuova conversazione» su iOS: i messaggi vanno persi. */
export async function clearHealthConversation({ uid, kind, subjectId, scopeId }) {
  await saveHealthConversation({
    uid,
    kind,
    subjectId,
    scopeId,
    messages: [],
    createdAt: Date.now(),
  });
}

/* ── System prompt: salute ───────────────────────────────────────────────── */

export function healthSystemPrompt({ subjectName, visits, exams, treatments, vaccines, profile, locale }) {
  return buildHealthContext({
    subjectName,
    visits,
    exams,
    treatments,
    vaccines,
    profile,
    locale,
    purpose: "healthChat",
  });
}

/* ── System prompt: visite ───────────────────────────────────────────────── */

const fmtDate = (m) =>
  m ? new Date(m).toLocaleDateString("it-IT", { day: "numeric", month: "long", year: "numeric" }) : "";

const nonEmpty = (v) => typeof v === "string" && v.trim().length > 0;

/** Età in anni e mesi, come `computeAge` su iOS. */
function ageLabel(birthDate) {
  if (!birthDate) return "";
  const now = new Date();
  const b = new Date(birthDate);
  let years = now.getFullYear() - b.getFullYear();
  let months = now.getMonth() - b.getMonth();
  if (now.getDate() < b.getDate()) months -= 1;
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  if (years === 0) return `${months} ${months === 1 ? "mese" : "mesi"}`;
  if (months === 0) return `${years} ${years === 1 ? "anno" : "anni"}`;
  return `${years} ${years === 1 ? "anno" : "anni"} e ${months} ${months === 1 ? "mese" : "mesi"}`;
}

/** Porting di `PediatricVisitsContextBuilder.buildSystemPrompt`. */
export function visitsSystemPrompt({ subjectName, birthDate, visits, treatments }) {
  const lines = [];

  lines.push(
    [
      "Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.",
      "Il tuo ruolo è spiegare in modo chiaro e comprensibile l'insieme delle visite mediche.",
      "",
      "REGOLE IMPORTANTI:",
      "- Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente dopo la diagnosi, di consultare il medico.",
      "- Usa un linguaggio semplice, adatto a un genitore non esperto.",
      "- Puoi aiutare a capire andamento clinico, visite, farmaci, esami, raccomandazioni e referti allegati.",
      "- Se nei documenti ci sono testi estratti, usali.",
      "- Se un testo estratto sembra incompleto o ambiguo, dillo chiaramente.",
      "- Rispondi sempre in italiano.",
    ].join("\n")
  );

  lines.push("\n--- PROFILO BAMBINO ---");
  lines.push(`Nome: ${subjectName}`);
  const age = ageLabel(birthDate);
  if (age) lines.push(`Età: ${age}`);

  lines.push(`\n--- VISITE MEDICHE (${visits.length}) ---`);

  visits.forEach((visit, index) => {
    lines.push(`\n### VISITA ${index + 1}`);
    lines.push(`Data visita: ${fmtDate(visit.date)}`);
    if (nonEmpty(visit.reason)) lines.push(`Motivo: ${visit.reason}`);
    if (nonEmpty(visit.doctorName)) {
      let dl = `Medico: ${visit.doctorName}`;
      if (nonEmpty(visit.doctorSpecialization)) dl += ` (${visit.doctorSpecialization})`;
      lines.push(dl);
    }
    if (nonEmpty(visit.diagnosis)) lines.push(`Diagnosi: ${visit.diagnosis}`);
    if (nonEmpty(visit.recommendations)) lines.push(`Raccomandazioni: ${visit.recommendations}`);

    // Le cure prescritte da questa visita, collegate come sul telefono: prima
    // per `prescribingVisitId`, poi per i riferimenti salvati sulla visita.
    const linked = treatments.filter(
      (t) => t.prescribingVisitId === visit.id || visit.linkedTreatmentIds?.includes(t.id)
    );
    if (linked.length > 0) {
      lines.push("Farmaci programmati:");
      for (const t of linked) {
        let line = `- ${t.drugName}, ${Math.round(t.dosageValue)} ${t.dosageUnit}`;
        line += `, ${frequencyLabel(t)}`;
        line += t.isLongTerm ? ", lungo termine" : `, ${t.durationDays} giorni`;
        if (nonEmpty(t.notes)) line += ` (${t.notes})`;
        lines.push(line);
      }
    }

    if (visit.asNeededDrugs?.length) {
      lines.push("Farmaci al bisogno:");
      for (const drug of visit.asNeededDrugs) {
        let line = `- ${drug.drugName}, ${Math.round(drug.dosageValue ?? 0)} ${drug.dosageUnit || ""}`.trim();
        if (nonEmpty(drug.instructions)) line += ` (${drug.instructions})`;
        lines.push(line);
      }
    }

    if (visit.therapyTypes?.length) {
      lines.push(`Terapie: ${visit.therapyTypes.join(", ")}`);
    }

    if (visit.prescribedExams?.length) {
      lines.push("Esami prescritti:");
      for (const exam of visit.prescribedExams) {
        let line = `- ${exam.name}`;
        if (exam.isUrgent) line += " [URGENTE]";
        if (exam.deadline) line += ` — entro ${fmtDate(exam.deadline)}`;
        if (nonEmpty(exam.preparation)) line += ` (preparazione: ${exam.preparation})`;
        lines.push(line);
      }
    }

    if (nonEmpty(visit.notes)) lines.push(`Note: ${visit.notes}`);

    if (visit.nextVisitDate) {
      let nl = `Prossima visita: ${fmtDate(visit.nextVisitDate)}`;
      if (nonEmpty(visit.nextVisitReason)) nl += ` — ${visit.nextVisitReason}`;
      lines.push(nl);
    }
  });

  lines.push("\n--- FINE CONTESTO ---");
  lines.push("Rispondi alle domande del genitore usando le informazioni sopra.");

  return lines.join("\n");
}

/* ── System prompt: analisi ──────────────────────────────────────────────── */

/** Porting di `ExamContextBuilder.buildSystemPrompt(exams:)`. */
export function examsSystemPrompt({ subjectName, exams }) {
  const lines = [];

  lines.push(
    [
      "Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.",
      "Il tuo ruolo è spiegare in modo chiaro e comprensibile l'insieme degli esami medici pediatrici del bambino.",
      "",
      "REGOLE IMPORTANTI:",
      "- Non fare diagnosi e non sostituirti al medico.",
      "- Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente di consultare il proprio medico.",
      "- Usa un linguaggio semplice, adatto a un genitore non esperto.",
      "- Puoi aiutare a capire quali esami sono in scadenza, urgenti, con risultato disponibile, e il contenuto dei referti.",
      "- Se nei documenti ci sono testi estratti, usali.",
      "- Se un testo estratto sembra incompleto o ambiguo, dillo chiaramente.",
      "- Rispondi sempre in italiano.",
    ].join("\n")
  );

  lines.push("\n--- PROFILO ---");
  lines.push(`Bambino/Persona: ${subjectName}`);
  lines.push(`Numero esami nel contesto: ${exams.length}`);

  const statusSummary = EXAM_STATUSES.map((s) => {
    const count = exams.filter((e) => e.statusRaw === s.raw).length;
    return count > 0 ? `${s.raw}: ${count}` : null;
  })
    .filter(Boolean)
    .join(", ");
  if (statusSummary) lines.push(`Riepilogo per stato: ${statusSummary}`);

  const urgentCount = exams.filter((e) => e.isUrgent).length;
  if (urgentCount > 0) lines.push(`Di cui urgenti: ${urgentCount}`);

  lines.push(`\n--- ESAMI (${exams.length}) ---`);

  const now = Date.now();
  exams.forEach((exam, index) => {
    const status = examStatusInfo(exam.statusRaw);
    lines.push("");
    lines.push("==========");
    lines.push(`ESAME ${index + 1} di ${exams.length}`);
    lines.push(`Nome: ${exam.name}`);
    lines.push(`Stato: ${status.raw}`);
    if (exam.isUrgent) lines.push("Urgente: sì");
    if (exam.deadline) {
      const pending = status.raw === "In attesa" || status.raw === "Prenotato";
      const overdue = exam.deadline < now && pending;
      lines.push(`Scadenza: ${fmtDate(exam.deadline)}${overdue ? " ⚠️ SCADUTA" : ""}`);
    }
    if (nonEmpty(exam.location)) lines.push(`Luogo: ${exam.location}`);
    if (nonEmpty(exam.preparation)) lines.push(`Preparazione: ${exam.preparation}`);
    if (nonEmpty(exam.notes)) lines.push(`Note: ${exam.notes}`);
    if (nonEmpty(exam.resultText)) lines.push(`Risultato: ${exam.resultText}`);
    if (exam.resultDate) lines.push(`Data risultato: ${fmtDate(exam.resultDate)}`);
  });

  lines.push("\n--- FINE DATI ESAMI ---");
  lines.push("\nRispondi alle domande del genitore sugli esami usando le informazioni sopra.");

  return lines.join("\n");
}
