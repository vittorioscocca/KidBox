/**
 * Contesto clinico per l'AI, porting di `HealthContextBuilder` (iOS) nella sua
 * variante `purpose: .clinicalRecord`: solo dati sanitari, nessuna azione di
 * pianificazione.
 *
 * Lo stesso testo alimenta Piano Alimentare, Piano Fitness e Cartella clinica,
 * esattamente come sul telefono. Rispetto a iOS manca la parte Apple Salute:
 * il browser non ha accesso a HealthKit, quindi peso, altezza ed età arrivano
 * solo dai campi compilati a mano nel form.
 */
import {
  examStatusInfo,
  vaccineStatusInfo,
  vaccineTypeInfo,
  totalDoses,
} from "./health";

const fmtDate = (millis, locale = "it") =>
  millis
    ? new Date(millis).toLocaleDateString(locale === "en" ? "en-US" : "it-IT", {
        day: "numeric",
        month: "long",
        year: "numeric",
      })
    : "";

const nonEmpty = (v) => typeof v === "string" && v.trim().length > 0;

/** Etichetta di frequenza, come `KBTreatment.frequencyDisplayLabel`. */
export function frequencyLabel(t, locale = "it") {
  if (t.intervalBetweenDosesDays > 0) {
    return locale === "en"
      ? `Every ${t.intervalBetweenDosesDays} days`
      : `Ogni ${t.intervalBetweenDosesDays} giorni`;
  }
  if (locale === "en") {
    return `${t.dailyFrequency} time${t.dailyFrequency === 1 ? "" : "s"} a day`;
  }
  return `${t.dailyFrequency} volt${t.dailyFrequency === 1 ? "a" : "e"} al giorno`;
}

/* ── Blocchi ─────────────────────────────────────────────────────────────── */

function appendTreatments(treatments, lines, locale) {
  if (treatments.length === 0) return;
  lines.push(`\n--- CURE ATTIVE (${treatments.length}) ---`);
  for (const t of treatments) {
    let line = `• ${t.drugName}`;
    line += ` — ${Math.round(t.dosageValue)} ${t.dosageUnit}`;
    line += `, ${frequencyLabel(t, locale)}`;
    if (t.isLongTerm) {
      line += ", lungo termine";
    } else {
      line += `, ${t.durationDays} giorni`;
      if (t.endDate) line += ` (fine: ${fmtDate(t.endDate, locale)})`;
    }
    if (nonEmpty(t.notes)) line += ` — ${t.notes}`;
    lines.push(line);
  }
}

function appendVaccines(vaccines, lines, locale) {
  if (vaccines.length === 0) return;
  lines.push(`\n--- VACCINI (${vaccines.length}) ---`);
  for (const v of vaccines) {
    const displayName = nonEmpty(v.commercialName)
      ? v.commercialName
      : vaccineTypeInfo(v.vaccineTypeRaw).it;

    let datePart = "";
    if (v.administeredDate) {
      datePart = `somministrato il ${fmtDate(v.administeredDate, locale)}`;
    } else if (v.scheduledDate) {
      datePart = `programmato per ${fmtDate(v.scheduledDate, locale)}`;
    }

    let line = `• ${displayName}`;
    if (datePart) line += ` — ${datePart}`;
    if (v.totalDoses > 1) line += ` (dose ${v.doseNumber}/${v.totalDoses})`;
    line += ` [${vaccineStatusInfo(v.statusRaw).raw}]`;
    if (nonEmpty(v.lotNumber)) line += ` — Lotto: ${v.lotNumber}`;
    if (nonEmpty(v.administeredBy)) line += ` — ${v.administeredBy}`;
    if (nonEmpty(v.notes)) line += ` — ${v.notes}`;
    lines.push(line);
  }
}

function appendVisits(visits, lines, locale) {
  if (visits.length === 0) return;
  lines.push(`\n--- VISITE MEDICHE (${visits.length}) ---`);
  visits.forEach((visit, index) => {
    lines.push("");
    lines.push(`## VISITA ${index + 1} — ${fmtDate(visit.date, locale)}`);
    if (nonEmpty(visit.reason)) lines.push(`Motivo: ${visit.reason}`);
    if (nonEmpty(visit.doctorName)) {
      let dl = `Medico: ${visit.doctorName}`;
      if (nonEmpty(visit.doctorSpecialization)) dl += ` (${visit.doctorSpecialization})`;
      lines.push(dl);
    }
    if (nonEmpty(visit.diagnosis)) lines.push(`Diagnosi: ${visit.diagnosis}`);
    if (nonEmpty(visit.recommendations)) lines.push(`Raccomandazioni: ${visit.recommendations}`);

    if (visit.asNeededDrugs?.length) {
      const drugs = visit.asNeededDrugs
        .map((d) => `${d.drugName} ${Math.round(d.dosageValue ?? 0)} ${d.dosageUnit || ""}`.trim())
        .join(", ");
      lines.push(`Farmaci al bisogno: ${drugs}`);
    }
    if (visit.therapyTypes?.length) {
      lines.push(`Terapie: ${visit.therapyTypes.join(", ")}`);
    }
    if (visit.prescribedExams?.length) {
      const exams = visit.prescribedExams
        .map((e) => `${e.name}${e.isUrgent ? " [URGENTE]" : ""}`)
        .join(", ");
      lines.push(`Esami prescritti: ${exams}`);
    }
    if (nonEmpty(visit.notes)) lines.push(`Note: ${visit.notes}`);
    if (visit.nextVisitDate) {
      let nl = `Prossima visita: ${fmtDate(visit.nextVisitDate, locale)}`;
      if (nonEmpty(visit.nextVisitReason)) nl += ` — ${visit.nextVisitReason}`;
      lines.push(nl);
    }
  });
}

function appendExams(exams, lines, locale, refertoMaxChars) {
  if (exams.length === 0) return;
  lines.push(`\n--- ESAMI (${exams.length}) ---`);
  const now = Date.now();
  for (const exam of exams) {
    const status = examStatusInfo(exam.statusRaw);
    let line = `• ${exam.name} [${status.raw}]`;
    if (exam.isUrgent) line += " [URGENTE]";
    if (exam.deadline) {
      const pending = status.raw === "In attesa" || status.raw === "Prenotato";
      const overdue = exam.deadline < now && pending;
      line += ` — scadenza: ${fmtDate(exam.deadline, locale)}${overdue ? " ⚠️ SCADUTA" : ""}`;
    }
    if (nonEmpty(exam.resultText)) {
      line += ` — Risultato: ${truncate(exam.resultText, refertoMaxChars)}`;
    }
    lines.push(line);
  }
}

/** Tetto ai testi lunghi, come `HealthAiDocumentText.prepareExtractedTextForAI`. */
function truncate(text, maxChars) {
  const clean = text.replace(/\s+/g, " ").trim();
  if (!maxChars || clean.length <= maxChars) return clean;
  return `${clean.slice(0, maxChars)}…`;
}

/* ── Entry point ─────────────────────────────────────────────────────────── */

/**
 * Contesto clinico completo del soggetto.
 *
 * @param {object} args
 * @param {string} args.subjectName    nome mostrato all'AI
 * @param {Array}  args.visits         visite del soggetto
 * @param {Array}  args.exams          esami del soggetto
 * @param {Array}  args.treatments     cure attive
 * @param {Array}  args.vaccines       vaccini registrati
 * @param {object} [args.profile]      scheda medica (allergie, gruppo sanguigno)
 * @param {number} [args.refertoMaxChars] tetto ai testi dei referti
 * @param {string} [args.locale]
 */
export function buildHealthContext({
  subjectName,
  visits = [],
  exams = [],
  treatments = [],
  vaccines = [],
  profile = null,
  refertoMaxChars = 1200,
  locale = "it",
  purpose = "clinicalRecord",
}) {
  const lines = [];

  // Due usi, due intestazioni: la chat parla al genitore, la cartella clinica è
  // materiale grezzo per un altro prompt. Il corpo dei dati è identico.
  lines.push(
    purpose === "healthChat"
      ? [
          "Sei un assistente medico informativo integrato nell'app KidBox, pensata per genitori.",
          "Il tuo ruolo è offrire una visione d'insieme chiara e comprensibile della salute della persona.",
          "",
          "REGOLE IMPORTANTI:",
          "- Se l'utente chiede una diagnosi o un parere clinico vincolante, ricordagli gentilmente, dopo aver dato il tuo parere, di consultare il proprio medico.",
          "- Usa un linguaggio semplice, adatto a un genitore non esperto.",
          "- Puoi aiutare a capire cure in corso, vaccini, visite recenti, esami in attesa e referti allegati.",
          "- Se nei documenti ci sono testi estratti, usali per contestualizzare meglio.",
          "- Se un testo estratto sembra incompleto o ambiguo, dillo esplicitamente.",
          "- Rispondi sempre in italiano.",
        ].join("\n")
      : [
          "CONTESTO DATI CLINICI KidBox (solo salute: visite, esami, cure, vaccini, referti allegati).",
          "NON usare né menzionare: veicoli, garage, casa, animali domestici, lista spesa, to-do generici, calendario famiglia, viaggi.",
          "Usa esclusivamente i dati sotto per integrare la cartella clinica.",
        ].join("\n")
  );

  lines.push("\n--- PROFILO ---");
  lines.push(`Nome: ${subjectName}`);
  if (profile) {
    if (nonEmpty(profile.bloodGroup)) lines.push(`Gruppo sanguigno: ${profile.bloodGroup}`);
    if (nonEmpty(profile.allergies)) lines.push(`Allergie registrate: ${profile.allergies}`);
    if (nonEmpty(profile.medicalNotes)) lines.push(`Note mediche: ${profile.medicalNotes}`);
  }

  lines.push("\n--- RIEPILOGO SALUTE ---");
  lines.push(`Cure attive: ${treatments.length}`);
  lines.push(`Vaccini registrati: ${vaccines.length}`);
  lines.push(`Visite registrate: ${visits.length}`);
  lines.push(`Esami totali: ${exams.length}`);

  const pending = exams.filter(
    (e) => e.statusRaw === "In attesa" || e.statusRaw === "Prenotato"
  );
  if (pending.length > 0) lines.push(`Esami in attesa / prenotati: ${pending.length}`);
  const urgent = pending.filter((e) => e.isUrgent);
  if (urgent.length > 0) lines.push(`Esami urgenti: ${urgent.length}`);

  appendTreatments(treatments, lines, locale);
  appendVaccines(vaccines, lines, locale);
  appendVisits([...visits].sort((a, b) => (b.date || 0) - (a.date || 0)), lines, locale);
  appendExams(
    [...exams].sort((a, b) => (a.deadline || Infinity) - (b.deadline || Infinity)),
    lines,
    locale,
    refertoMaxChars
  );

  if (purpose === "healthChat") {
    lines.push("\n--- FINE CONTESTO SALUTE ---");
    lines.push("Rispondi alle domande usando le informazioni sopra.");
  } else {
    lines.push("\n--- FINE DATI CLINICI ---");
  }
  return lines.join("\n");
}

/**
 * Righe antropometriche, porting di `MealPlanPromptBuilder.profileSummaryLines`
 * per la sola parte che il browser può conoscere: i valori inseriti a mano e
 * quelli già registrati nella scheda medica.
 */
export function profileSummaryLines({ birthDate, profile, manual = {} }) {
  const lines = [];

  if (birthDate) {
    const years = Math.floor((Date.now() - birthDate) / (365.25 * 24 * 3600 * 1000));
    lines.push(`Età: ${years} anni`);
  } else if (manual.ageYears) {
    lines.push(`Età: ${manual.ageYears} anni (indicata dall'utente)`);
  } else {
    lines.push("Età: non disponibile");
  }

  if (manual.heightCm) {
    lines.push(`Altezza: ${Math.round(manual.heightCm)} cm (indicata dall'utente)`);
  } else {
    lines.push("Altezza: non disponibile");
  }

  if (manual.weightKg) {
    lines.push(`Peso: ${manual.weightKg.toFixed(1)} kg (indicato dall'utente)`);
  } else {
    lines.push("Peso: non disponibile");
  }

  if (nonEmpty(profile?.bloodGroup)) lines.push(`Gruppo sanguigno: ${profile.bloodGroup}`);
  if (nonEmpty(profile?.allergies)) lines.push(`Allergie registrate: ${profile.allergies}`);
  if (nonEmpty(profile?.medicalNotes)) lines.push(`Note mediche: ${profile.medicalNotes}`);

  // Il browser non legge HealthKit: senza allenamenti importati va detto,
  // altrimenti il modello inventa un volume di attività che non esiste.
  lines.push("Allenamenti registrati: non disponibili da questo dispositivo (browser)");

  return lines;
}

/** BMI, quando peso e altezza ci sono entrambi. */
export function bmiLine(manual = {}) {
  const { weightKg, heightCm } = manual;
  if (!weightKg || !heightCm) return null;
  const m = heightCm / 100;
  return `BMI calcolato: ${(weightKg / (m * m)).toFixed(1)}`;
}

/** Riepilogo delle cure in corso per il riquadro «dosi previste». */
export function treatmentDoseSummary(treatment, locale = "it") {
  const total = totalDoses(treatment);
  if (total < 0) return locale === "en" ? "Long term" : "Lungo termine";
  return locale === "en" ? `${total} doses` : `${total} dosi`;
}

/** Nome (in italiano) della lingua in cui l'AI deve rispondere. */
export const responseLanguageName = (locale) =>
  ({ en: "inglese", fr: "francese", es: "spagnolo" })[locale] || "italiano";
