/**
 * Piano Fitness, allineato a `FitnessPlanRemoteStore`, `FitnessPlanGenerator`
 * e `FitnessPlanParser`.
 *
 * Percorso: `users/{uid}/fitnessPlans/{childId}` — privato per utente, come il
 * piano alimentare: contiene peso, infortuni e adattamenti clinici.
 *
 * Il documento viaggia come JSON in un singolo campo `payload`, e il formato è
 * quello che `FitnessPlanDocument` (Codable, date ISO-8601) si aspetta di
 * rileggere sul telefono. Due conseguenze da non perdere di vista:
 *
 * - le date vanno scritte SENZA millisecondi: la strategia `.iso8601` di Swift
 *   usa `withInternetDateTime` e rifiuta i decimali di secondo;
 * - i campi non opzionali di Swift devono esserci sempre (`status`, `id` degli
 *   esercizi, `weeks`, …), altrimenti la decodifica fallisce e il telefono
 *   vede il piano come inesistente.
 */
import { doc, getDoc, serverTimestamp, setDoc, Timestamp } from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { db, functions } from "../firebase";
import { buildHealthContext, bmiLine, profileSummaryLines, responseLanguageName } from "./healthContext";
import { manualValues } from "./mealPlan";
import { isPaidPlan } from "./profile";

const planRef = (uid, childId) => doc(db, "users", uid, "fitnessPlans", childId);

/** Settimane generate dal piano base, come `FitnessPlanPromptBuilder.planWeeks`. */
export const PLAN_WEEKS = 4;
export const REFERTO_MAX_CHARS = 1200;

/* ── Tassonomie ──────────────────────────────────────────────────────────── */

export const FITNESS_GOALS = [
  {
    raw: "weightLoss",
    it: "Perdere peso",
    en: "Lose weight",
    emoji: "🔥",
    prompt: "perdere peso riducendo la massa grassa e mantenendo la massa muscolare",
  },
  {
    raw: "toning",
    it: "Tonificare e stare in salute",
    en: "Tone up and stay healthy",
    emoji: "💪",
    prompt: "tonificare il corpo e migliorare la salute generale",
  },
  {
    raw: "race",
    it: "Preparare una gara",
    en: "Train for a race",
    emoji: "🏁",
    prompt: "preparare una gara o un evento sportivo specifico",
  },
];

/**
 * `raw` e ordine seguono `FitnessSport` su iOS: l'ordine conta perché il prompt
 * elenca gli sport nell'ordine dell'enum, non in quello di selezione.
 */
export const FITNESS_SPORTS = [
  { raw: "running", it: "Corsa", en: "Running", prompt: "corsa", race: "corsa su strada" },
  { raw: "walking", it: "Camminata", en: "Walking", prompt: "camminata veloce", race: "camminata" },
  { raw: "marathon", it: "Maratona", en: "Marathon", prompt: "maratona", race: "maratona" },
  { raw: "trail", it: "Trail running", en: "Trail running", prompt: "trail running", race: "trail" },
  { raw: "cycling", it: "Ciclismo", en: "Cycling", prompt: "ciclismo", race: "gara ciclistica" },
  { raw: "swimming", it: "Nuoto", en: "Swimming", prompt: "nuoto", race: "gara di nuoto" },
  { raw: "triathlon", it: "Triathlon", en: "Triathlon", prompt: "triathlon", race: "triathlon" },
  { raw: "gym", it: "Palestra / pesi", en: "Gym / weights", prompt: "allenamento in palestra con i pesi", race: "gara di forza" },
  { raw: "bodyweight", it: "Corpo libero", en: "Bodyweight", prompt: "allenamento a corpo libero", race: "gara a corpo libero" },
  { raw: "functional", it: "Functional / HIIT", en: "Functional / HIIT", prompt: "allenamento funzionale ad alta intensità", race: "gara functional" },
  { raw: "yoga", it: "Yoga / pilates", en: "Yoga / pilates", prompt: "yoga o pilates", race: "sessione yoga" },
  { raw: "tennis", it: "Tennis / padel", en: "Tennis / padel", prompt: "tennis o padel", race: "torneo di tennis o padel" },
  { raw: "football", it: "Calcio", en: "Football", prompt: "calcio", race: "torneo di calcio" },
  { raw: "volleyball", it: "Pallavolo", en: "Volleyball", prompt: "pallavolo", race: "torneo di pallavolo" },
  { raw: "basketball", it: "Basket", en: "Basketball", prompt: "basket", race: "torneo di basket" },
  { raw: "martialArts", it: "Arti marziali", en: "Martial arts", prompt: "arti marziali", race: "gara di arti marziali" },
  { raw: "dance", it: "Danza", en: "Dance", prompt: "danza", race: "esibizione di danza" },
  { raw: "climbing", it: "Arrampicata", en: "Climbing", prompt: "arrampicata", race: "gara di arrampicata" },
  { raw: "rowing", it: "Canottaggio / vogatore", en: "Rowing", prompt: "canottaggio o vogatore", race: "gara di canottaggio" },
  { raw: "skiing", it: "Sci / snowboard", en: "Skiing / snowboard", prompt: "sci o snowboard", race: "gara sugli sci" },
  { raw: "other", it: "Altro", en: "Other", prompt: "altra disciplina", race: "gara non specificata" },
];

export const FITNESS_EXPERIENCE = [
  { raw: "beginner", it: "Principiante", en: "Beginner", prompt: "principiante, poca o nessuna esperienza recente" },
  { raw: "intermediate", it: "Intermedio", en: "Intermediate", prompt: "intermedio, si allena con una certa regolarità" },
  { raw: "advanced", it: "Avanzato", en: "Advanced", prompt: "avanzato, allenamento strutturato da tempo" },
];

export const FITNESS_PLACES = [
  { raw: "home", it: "A casa", en: "At home", prompt: "a casa, con poca o nessuna attrezzatura" },
  { raw: "gym", it: "In palestra", en: "At the gym", prompt: "in palestra, con attrezzatura completa" },
  { raw: "outdoor", it: "All'aperto", en: "Outdoors", prompt: "all'aperto" },
];

export const SESSION_STATUSES = [
  { raw: "planned", it: "In programma", en: "Planned", color: "#8a8a8e" },
  { raw: "done", it: "Completata", en: "Done", color: "#27AE60" },
  { raw: "skipped", it: "Saltata", en: "Skipped", color: "#D93838" },
  { raw: "moved", it: "Spostata", en: "Moved", color: "#E0913A" },
];

export const sessionStatusInfo = (raw) =>
  SESSION_STATUSES.find((s) => s.raw === raw) || SESSION_STATUSES[0];

const infoBy = (list, raw, fallbackIndex = 0) =>
  list.find((x) => x.raw === raw) || list[fallbackIndex];

export const goalInfo = (raw) => infoBy(FITNESS_GOALS, raw, 1);
export const sportInfo = (raw) => infoBy(FITNESS_SPORTS, raw, FITNESS_SPORTS.length - 1);
export const experienceInfo = (raw) => infoBy(FITNESS_EXPERIENCE, raw);
export const placeInfo = (raw) => infoBy(FITNESS_PLACES, raw);

/** Input del wizard, con gli stessi default di `FitnessPlanInput`. */
export const emptyFitnessInput = () => ({
  goal: "toning",
  preferredSports: [],
  raceType: null,
  raceDetail: "",
  raceDate: null,
  // Convenzione `Calendar`: 1 = domenica … 7 = sabato. Default lun/mer/ven.
  trainingWeekdays: [2, 4, 6],
  reminderMinutesFromMidnight: 18 * 60,
  reminderEnabled: true,
  sessionMinutes: 45,
  experience: "beginner",
  place: "home",
  notes: "",
  manualAgeYears: "",
  manualWeightKg: "",
  manualHeightCm: "",
});

/** Il wizard è completo? Stessa regola di `FitnessPlanInput.isComplete`. */
export function isInputComplete(input) {
  if (!input.trainingWeekdays?.length) return false;
  if (input.goal === "race") {
    if (!input.raceType) return false;
    if (input.raceType === "other" && !(input.raceDetail || "").trim()) return false;
  }
  return true;
}

/** Sport nell'ordine dell'enum: il prompt deve essere stabile fra due generazioni. */
export const sortedSports = (input) =>
  FITNESS_SPORTS.filter((s) => (input.preferredSports || []).includes(s.raw));

/** Giorni ordinati partendo dal lunedì, come `sortedWeekdays` con `firstWeekday = 2`. */
export const sortedWeekdays = (input) =>
  [...(input.trainingWeekdays || [])].sort(
    (a, b) => ((a - 2 + 7) % 7) - ((b - 2 + 7) % 7)
  );

/* ── Date ────────────────────────────────────────────────────────────────── */

const startOfDay = (d) => {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x;
};

/** Il piano parte da oggi, come `FitnessPlanGenerator.planStartDate`. */
export const planStartDate = () => startOfDay(new Date()).getTime();

/**
 * ISO-8601 senza millisecondi: `JSONDecoder.dateDecodingStrategy = .iso8601`
 * usa `ISO8601DateFormatter` con `withInternetDateTime`, che sui decimali di
 * secondo fallisce. Con `toISOString()` il telefono non leggerebbe il piano.
 */
const iso = (millisValue) =>
  millisValue == null ? null : new Date(millisValue).toISOString().replace(/\.\d{3}Z$/, "Z");

const fromIso = (value) => {
  if (typeof value !== "string" || !value) return null;
  const t = Date.parse(value);
  return Number.isFinite(t) ? t : null;
};

/** Offset dei giorni in cui la persona si allena, dentro le settimane del piano. */
export function allowedDayOffsets(input, startMillis) {
  const total = PLAN_WEEKS * 7;
  const offsets = [];
  for (let offset = 0; offset < total; offset += 1) {
    const day = new Date(startMillis);
    day.setDate(day.getDate() + offset);
    // `getDay()` è 0 = domenica; la convenzione `Calendar` di iOS parte da 1.
    if ((input.trainingWeekdays || []).includes(day.getDay() + 1)) offsets.push(offset);
  }
  return offsets;
}

const WEEKDAY_NAMES_IT = {
  1: "domenica",
  2: "lunedì",
  3: "martedì",
  4: "mercoledì",
  5: "giovedì",
  6: "venerdì",
  7: "sabato",
};

export const weekdayNames = (weekdays) =>
  weekdays.map((w) => WEEKDAY_NAMES_IT[w]).filter(Boolean).join(", ") || "nessuno";

/* ── Payload Codable ─────────────────────────────────────────────────────── */

/** JS → JSON che `FitnessPlanDocument` sa decodificare. */
function encodeDocument(plan) {
  return {
    subjectName: plan.subjectName,
    input: {
      goal: plan.input.goal,
      preferredSports: plan.input.preferredSports || [],
      raceType: plan.input.raceType ?? null,
      raceDetail: plan.input.raceDetail || "",
      raceDate: iso(plan.input.raceDate),
      trainingWeekdays: plan.input.trainingWeekdays || [],
      reminderMinutesFromMidnight: plan.input.reminderMinutesFromMidnight,
      reminderEnabled: Boolean(plan.input.reminderEnabled),
      sessionMinutes: plan.input.sessionMinutes,
      experience: plan.input.experience,
      place: plan.input.place,
      notes: plan.input.notes || "",
      manualAgeYears: plan.input.manualAgeYears || "",
      manualWeightKg: plan.input.manualWeightKg || "",
      manualHeightCm: plan.input.manualHeightCm || "",
    },
    startDate: iso(plan.startDate),
    summary: plan.summary || "",
    safetyNotes: plan.safetyNotes || [],
    weeks: (plan.weeks || []).map((w) => ({
      index: w.index,
      focus: w.focus || "",
      sessions: (w.sessions || []).map((s) => ({
        id: s.id,
        date: iso(s.date),
        originalDate: iso(s.originalDate),
        weekIndex: s.weekIndex,
        title: s.title,
        activityType: s.activityType,
        durationMinutes: s.durationMinutes,
        intensity: s.intensity || "",
        exercises: (s.exercises || []).map((e) => ({
          id: e.id,
          name: e.name,
          detail: e.detail || "",
          notes: e.notes ?? null,
        })),
        targets: s.targets || [],
        targetKcal: s.targetKcal ?? null,
        notes: s.notes ?? null,
        status: s.status || "planned",
        completedAt: iso(s.completedAt),
        completionSource: s.completionSource ?? null,
        actualActivityTitle: s.actualActivityTitle ?? null,
        matchedWorkoutId: s.matchedWorkoutId ?? null,
        actualMinutes: s.actualMinutes ?? null,
        actualKcal: s.actualKcal ?? null,
        actualHeartRateBpm: s.actualHeartRateBpm ?? null,
      })),
    })),
    generatedAt: iso(plan.generatedAt),
    messageUnitsConsumed: plan.messageUnitsConsumed || 0,
    loggedWorkouts: plan.loggedWorkouts ?? null,
  };
}

/** JSON del telefono → oggetto usato dalla pagina. */
function decodeDocument(raw) {
  const input = raw.input || {};
  return {
    subjectName: raw.subjectName || "",
    input: {
      ...emptyFitnessInput(),
      ...input,
      preferredSports: input.preferredSports || [],
      trainingWeekdays: input.trainingWeekdays || [2, 4, 6],
      raceDate: fromIso(input.raceDate),
    },
    startDate: fromIso(raw.startDate) || Date.now(),
    summary: raw.summary || "",
    safetyNotes: Array.isArray(raw.safetyNotes) ? raw.safetyNotes : [],
    weeks: (Array.isArray(raw.weeks) ? raw.weeks : []).map((w) => ({
      index: Number(w.index) || 1,
      focus: w.focus || "",
      sessions: (Array.isArray(w.sessions) ? w.sessions : []).map((s) => ({
        ...s,
        date: fromIso(s.date),
        originalDate: fromIso(s.originalDate),
        completedAt: fromIso(s.completedAt),
        exercises: Array.isArray(s.exercises) ? s.exercises : [],
        targets: Array.isArray(s.targets) ? s.targets : [],
        status: s.status || "planned",
      })),
    })),
    generatedAt: fromIso(raw.generatedAt) || Date.now(),
    messageUnitsConsumed: Number(raw.messageUnitsConsumed) || 0,
    loggedWorkouts: raw.loggedWorkouts ?? null,
  };
}

/** Tutte le sedute del piano, ordinate per data. */
export const allSessions = (plan) =>
  (plan?.weeks || [])
    .flatMap((w) => w.sessions)
    .sort((a, b) => (a.date || 0) - (b.date || 0));

/** Mezzanotte del giorno di un timestamp: le sedute si confrontano per giorno. */
export const startOfDayMillis = (millis) => {
  const d = new Date(millis);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};

/** Le sedute di un giorno. */
export const sessionsOn = (plan, dayMillis) => {
  const day = startOfDayMillis(dayMillis);
  return allSessions(plan).filter((s) => s.date && startOfDayMillis(s.date) === day);
};

/**
 * La settimana del piano in cui cade un giorno, o `null` se è fuori.
 * Serve al calendario per spegnere i giorni che il piano non copre.
 */
export const weekIndexFor = (plan, dayMillis) => {
  const day = startOfDayMillis(dayMillis);
  for (const week of plan?.weeks || []) {
    for (const s of week.sessions) {
      if (s.date && startOfDayMillis(s.date) === day) return week.index;
    }
  }
  // Nessuna seduta quel giorno: si guarda comunque se cade nell'arco del piano.
  const sessions = allSessions(plan);
  if (sessions.length === 0) return null;
  const first = startOfDayMillis(sessions[0].date);
  const last = startOfDayMillis(sessions[sessions.length - 1].date);
  if (day < first || day > last) return null;
  const weeks = plan.weeks || [];
  for (const week of weeks) {
    const dates = week.sessions.map((s) => s.date).filter(Boolean);
    if (dates.length === 0) continue;
    if (day >= startOfDayMillis(Math.min(...dates)) && day <= startOfDayMillis(Math.max(...dates))) {
      return week.index;
    }
  }
  return null;
};

/** Primo e ultimo giorno coperti dal piano: limitano le frecce del calendario. */
export const planRange = (plan) => {
  const sessions = allSessions(plan);
  if (sessions.length === 0) return null;
  return {
    first: startOfDayMillis(sessions[0].date),
    last: startOfDayMillis(sessions[sessions.length - 1].date),
  };
};

/* ── Persistenza ─────────────────────────────────────────────────────────── */

export async function fetchFitnessPlan({ uid, childId }) {
  const snap = await getDoc(planRef(uid, childId));
  if (!snap.exists()) return null;
  const d = snap.data();
  if (d.isDeleted === true) return { deleted: true };
  if (typeof d.payload !== "string" || !d.payload) return null;
  try {
    return decodeDocument(JSON.parse(d.payload));
  } catch {
    return null;
  }
}

export async function saveFitnessPlan({ uid, childId, document: plan }) {
  await setDoc(
    planRef(uid, childId),
    {
      childId,
      subjectName: plan.subjectName,
      payload: JSON.stringify(encodeDocument(plan)),
      generatedAt: Timestamp.fromMillis(plan.generatedAt),
      startDate: Timestamp.fromMillis(plan.startDate),
      messageUnitsConsumed: plan.messageUnitsConsumed || 0,
      isDeleted: false,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

export async function deleteFitnessPlan({ uid, childId }) {
  await setDoc(
    planRef(uid, childId),
    { childId, isDeleted: true, payload: "", updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/**
 * Segna una seduta come completata, saltata o di nuovo in programma, e
 * riscrive il piano: il telefono rilegge lo stesso documento.
 */
export async function setSessionStatus({ uid, childId, plan, sessionId, status }) {
  const next = {
    ...plan,
    weeks: plan.weeks.map((w) => ({
      ...w,
      sessions: w.sessions.map((s) =>
        s.id === sessionId
          ? {
              ...s,
              status,
              completedAt: status === "done" ? Date.now() : null,
              // `manual` è la sorgente giusta: la spunta l'ha messa una persona.
              completionSource: status === "done" ? "manual" : null,
            }
          : s
      ),
    })),
  };
  await saveFitnessPlan({ uid, childId, document: next });
  return next;
}

/**
 * Sposta una seduta a un altro giorno, come il pulsante «Sposta» del telefono.
 *
 * Due dettagli presi da `FitnessPlanView.move`: `originalDate` si scrive una
 * volta sola — chi sposta due volte ha comunque spostato dalla data del piano,
 * non dall'ultima scelta — e lo stato torna `planned`, perché una seduta
 * rimandata resta da fare. `moved` esiste come stato ma nel flusso di iOS non
 * viene mai assegnato: serve al resoconto settimanale, e non lo forziamo qui.
 *
 * Resta fuori la riorganizzazione AI della settimana, che sul telefono segue
 * lo spostamento: qui la data scelta si applica e basta, cioè esattamente il
 * ramo di ripiego che iOS usa quando l'AI non risponde.
 */
export async function moveSession({ uid, childId, plan, sessionId, newDate }) {
  const next = withMovedSession(plan, sessionId, newDate);
  await saveFitnessPlan({ uid, childId, document: next });
  return next;
}

/** Lo spostamento puro, senza salvataggio: lo condividono `moveSession` e la
 *  riorganizzazione AI, che parte comunque dalla data scelta dall'utente. */
function withMovedSession(plan, sessionId, newDate) {
  const target = startOfDayMillis(newDate);
  return {
    ...plan,
    weeks: plan.weeks.map((w) => ({
      ...w,
      sessions: w.sessions.map((s) =>
        s.id === sessionId
          ? {
              ...s,
              originalDate: s.originalDate ?? s.date,
              date: target,
              status: "planned",
              completedAt: null,
              completionSource: null,
            }
          : s
      ),
    })),
  };
}

/* ── Prompt ──────────────────────────────────────────────────────────────── */

/** System prompt, identico a `FitnessPlanPromptBuilder.systemPrompt`. */
export function systemPrompt(locale) {
  const responseLanguage = responseLanguageName(locale);
  return `Agisci come un preparatore atletico basato sull'evidenza, integrato nell'app KidBox.
Costruisci un piano di allenamento mensile personalizzato leggendo i dati sanitari della
persona: età, peso, altezza, BMI, referti, patologie in corso, terapie farmacologiche,
parametri biometrici e allenamenti già registrati.

LINGUA: ${responseLanguage}. Scrivi in questa lingua TUTTI i testi destinati all'utente
(titoli, esercizi, obiettivi, note). Le CHIAVI del JSON restano in inglese come da schema.

SICUREZZA CLINICA — è la regola che viene prima di tutte le altre:
Adatta intensità, esercizi e volumi alle controindicazioni che emergono dai dati.
Esempi di ragionamento richiesto: con ernia discale o lombalgia niente carichi assiali sulla
colonna (stacchi, squat con bilanciere, military press in piedi) e preferenza per lavoro in
scarico; con terapie che alterano la frequenza cardiaca (beta-bloccanti, antiaritmici) niente
lavoro ad alta intensità e sforzo regolato sulla percezione invece che sui battiti; con
patologie cardiovascolari, respiratorie, metaboliche o articolari riduci l'impatto e la
progressione; in gravidanza o allattamento niente lavoro ad alta intensità o supino prolungato.
Ogni adattamento che fai per un motivo clinico DEVE comparire in "safetyNotes", citando il dato
che lo ha motivato. Se non emergono controindicazioni, scrivilo esplicitamente in una nota.
Se la persona ha meno di 18 anni, proponi solo attività ludico-motoria e rimanda al pediatra.
NON formulare diagnosi e NON inventare valori clinici assenti dai dati.

COSTRUZIONE DEL PIANO:
Genera esattamente ${PLAN_WEEKS} settimane, con progressione settimanale sensata (carico che
cresce e una settimana di scarico se il volume è alto).
Allena SOLO nei giorni indicati come disponibili: ogni sessione deve avere un "dayOffset"
compreso nell'elenco di offset ammessi fornito nel messaggio utente. Non inventare altri giorni.
Ogni sessione deve avere esercizi o attività concrete e obiettivi MISURABILI (minuti, distanza,
calorie, serie × ripetizioni, ritmo). Niente obiettivi generici tipo "allenati bene".
Rispetta la durata indicata per sessione, con una tolleranza di ±10 minuti.
Se la persona indica degli sport, quelli sono la materia del piano: le sedute devono essere
fatte di quelle attività, non di un generico circuito in palestra. Vale per ogni obiettivo,
anche quando non c'è nessuna gara: chi vuole solo tonicità e salute e indica tennis e bici
deve ritrovarsi tennis e bici nel calendario, con il lavoro complementare che serve a
sostenerli. Se gli sport indicati non bastano a coprire l'obiettivo, aggiungi il minimo
necessario e spiega in "notes" perché.
Se l'obiettivo è una gara, struttura il mese come un blocco di preparazione verso quella data.

FORMATO DELLA RISPOSTA — obbligatorio:
Rispondi con UN SOLO oggetto JSON valido, senza testo prima o dopo, senza Markdown, senza
blocchi di codice. Nessun commento. Usa esattamente queste chiavi:

{
  "summary": "3-4 frasi sul piano e sulla logica di progressione",
  "safetyNotes": ["adattamenti clinici, uno per stringa"],
  "weeks": [
    {
      "index": 1,
      "focus": "obiettivo della settimana in una riga",
      "sessions": [
        {
          "dayOffset": 0,
          "title": "titolo breve della seduta",
          "activityType": "corsa | forza | mobilità | cardio | riposo attivo",
          "durationMinutes": 45,
          "intensity": "bassa | media | alta",
          "exercises": [
            {"name": "nome esercizio", "detail": "3 serie x 12 ripetizioni", "notes": "opzionale"}
          ],
          "targets": ["obiettivo misurabile 1", "obiettivo misurabile 2"],
          "targetKcal": 350,
          "notes": "nota breve, opzionale"
        }
      ]
    }
  ]
}

LUNGHEZZA: massimo 4 esercizi e 3 obiettivi per sessione, testi brevi. L'intero JSON deve
restare sotto le 1800 parole: meglio sessioni asciutte che un JSON troncato a metà, che il
client non riuscirebbe a leggere. Devi arrivare fino alla chiusura del JSON.`;
}

const fmtDate = (millisValue) =>
  new Date(millisValue).toLocaleDateString("it-IT", {
    day: "numeric",
    month: "long",
    year: "numeric",
  });

/** Contenuto utente, identico a `FitnessPlanPromptBuilder.userContent`. */
export function userContent({ subjectName, input, startDate, offsets, summary, healthContext }) {
  const lines = [];
  lines.push(`Crea il piano di allenamento mensile per ${subjectName}.`);
  lines.push("");
  lines.push("--- OBIETTIVO E DISPONIBILITÀ ---");
  lines.push(`Obiettivo principale: ${goalInfo(input.goal).prompt}`);

  const sports = sortedSports(input);
  if (sports.length === 0) {
    lines.push("Sport preferiti: non indicati, scegli tu le attività più adatte all'obiettivo.");
  } else {
    lines.push(
      `Sport che la persona vuole praticare: ${sports.map((s) => s.prompt).join(", ")}`
    );
    lines.push(
      "Costruisci le sedute attorno a questi sport. Aggiungi forza, mobilità o cardio " +
        "solo dove servono per completare l'obiettivo o per prevenire gli infortuni tipici " +
        "di queste discipline, spiegandolo nella seduta."
    );
  }

  if (input.goal === "race") {
    let race = "Tipo di gara/evento: ";
    race += input.raceType ? sportInfo(input.raceType).race : "non specificato";
    const detail = (input.raceDetail || "").trim();
    if (detail) race += ` — ${detail}`;
    lines.push(race);
    if (input.raceDate) {
      const weeks = Math.max(
        0,
        Math.round((input.raceDate - Date.now()) / (7 * 24 * 3600 * 1000))
      );
      lines.push(`Data della gara: ${fmtDate(input.raceDate)} (tra circa ${weeks} settimane)`);
    } else {
      lines.push("Data della gara: non indicata, imposta una preparazione generica.");
    }
  }

  lines.push(`Esperienza: ${experienceInfo(input.experience).prompt}`);
  lines.push(`Luogo di allenamento: ${placeInfo(input.place).prompt}`);
  lines.push(`Durata per sessione: circa ${input.sessionMinutes} minuti`);
  lines.push(`Giorni disponibili: ${weekdayNames(sortedWeekdays(input))}`);
  lines.push(`Inizio del piano: ${fmtDate(startDate)} (dayOffset 0)`);
  lines.push(
    `Offset dei giorni ammessi (giorni trascorsi dall'inizio del piano): ${offsets.join(", ")}`
  );

  const notes = (input.notes || "").trim();
  if (notes) lines.push(`Note dell'utente (infortuni, limiti, preferenze): ${notes}`);

  lines.push("");
  lines.push("--- DATI ANTROPOMETRICI E ALLENAMENTI (app Salute) ---");
  lines.push(...(summary.length ? summary : ["Nessun dato antropometrico disponibile."]));

  lines.push("");
  lines.push("--- DATI CLINICI (visite, cure, analisi, referti) ---");
  lines.push(healthContext);

  return lines.join("\n");
}

/* ── Parsing della risposta ──────────────────────────────────────────────── */

/**
 * Isola l'oggetto JSON dalla risposta: il modello a volte lo incornicia con una
 * frase o con un blocco di codice, nonostante il prompt lo vieti.
 */
export function jsonObjectFrom(raw) {
  const cleaned = raw.replaceAll("```json", "").replaceAll("```", "");
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start < 0 || end < 0 || start >= end) return null;
  try {
    const parsed = JSON.parse(cleaned.slice(start, end + 1));
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

const intValue = (v) => {
  if (typeof v === "number") return Math.round(v);
  if (typeof v === "string") {
    const n = Number(v.trim());
    return Number.isFinite(n) ? Math.round(n) : null;
  }
  return null;
};

const newId = () =>
  typeof crypto !== "undefined" && crypto.randomUUID
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;

function parseSession(raw, weekIndex, startMillis) {
  const dayOffset = intValue(raw.dayOffset);
  if (dayOffset == null) return null;
  const date = new Date(startMillis);
  date.setDate(date.getDate() + dayOffset);

  const title = (raw.title || "").trim();
  const activityType = (raw.activityType || "").trim();
  if (!title && !activityType) return null;

  const exercises = (Array.isArray(raw.exercises) ? raw.exercises : [])
    .map((e) => {
      const name = (e?.name || "").trim();
      if (!name) return null;
      return {
        id: newId(),
        name,
        detail: (e.detail || "").trim(),
        notes: (e.notes || "").trim() || null,
      };
    })
    .filter(Boolean);

  const targets = (Array.isArray(raw.targets) ? raw.targets : [])
    .filter((t) => typeof t === "string")
    .map((t) => t.trim())
    .filter(Boolean);

  const givenId = (raw.id || "").trim();

  return {
    id: givenId || newId(),
    date: date.getTime(),
    originalDate: null,
    weekIndex,
    title: title || activityType,
    activityType: activityType || title,
    durationMinutes: intValue(raw.durationMinutes) ?? 40,
    intensity: (raw.intensity || "").trim(),
    exercises,
    targets,
    targetKcal: intValue(raw.targetKcal),
    notes: (raw.notes || "").trim() || null,
    status: "planned",
    completedAt: null,
    completionSource: null,
  };
}

/** Porting di `FitnessPlanParser.parsePlan`. */
export function parsePlan({ raw, subjectName, input, startDate, messageUnitsConsumed }) {
  const object = jsonObjectFrom(raw);
  if (!object) throw new Error("INVALID_PLAN_FORMAT");

  const summary = (object.summary || "").trim();
  const safetyNotes = (Array.isArray(object.safetyNotes) ? object.safetyNotes : [])
    .filter((n) => typeof n === "string")
    .map((n) => n.trim())
    .filter(Boolean);

  const weeks = [];
  (Array.isArray(object.weeks) ? object.weeks : []).forEach((rawWeek, position) => {
    const index = intValue(rawWeek.index) ?? position + 1;
    const sessions = (Array.isArray(rawWeek.sessions) ? rawWeek.sessions : [])
      .map((s) => parseSession(s, index, startDate))
      .filter(Boolean)
      .sort((a, b) => a.date - b.date);
    if (sessions.length === 0) return;
    weeks.push({ index, focus: (rawWeek.focus || "").trim(), sessions });
  });

  if (weeks.length === 0) throw new Error("INVALID_PLAN_FORMAT");

  return {
    subjectName,
    input,
    startDate,
    summary,
    safetyNotes,
    weeks: weeks.sort((a, b) => a.index - b.index),
    generatedAt: Date.now(),
    messageUnitsConsumed,
    loggedWorkouts: null,
  };
}

/* ── Generazione ─────────────────────────────────────────────────────────── */

/**
 * Genera il piano e lo salva.
 *
 * Come per il piano alimentare il controllo di piano sta anche qui, prima della
 * callable: è il punto attraversato da ogni percorso, rigenerazioni comprese.
 * L'autorità resta il gate server dentro `askAI`; `subscriptionPlan` non passato
 * significa «lettura non ancora arrivata», e in quel caso decide il server.
 */
export async function generateFitnessPlan({
  uid,
  familyId,
  childId,
  subjectName,
  birthDate,
  input,
  visits,
  exams,
  treatments,
  vaccines,
  profile,
  subscriptionPlan = null,
  locale = "it",
}) {
  if (subscriptionPlan !== null && !isPaidPlan(subscriptionPlan)) {
    throw new Error("PLAN_NOT_INCLUDED");
  }

  const manual = manualValues(input);
  if (!manual.weightKg || !manual.heightCm) {
    throw new Error("MISSING_HEALTH_DATA");
  }

  const startDate = planStartDate();
  const offsets = allowedDayOffsets(input, startDate);
  if (offsets.length === 0) throw new Error("NO_TRAINING_DAYS");

  const summary = profileSummaryLines({ birthDate, profile, manual });
  const bmi = bmiLine(manual);
  if (bmi) summary.push(bmi);

  const healthContext = buildHealthContext({
    subjectName,
    visits,
    exams,
    treatments,
    vaccines,
    profile,
    refertoMaxChars: REFERTO_MAX_CHARS,
    locale,
  });

  const callable = httpsCallable(functions, "askAI", { timeout: 300_000 });
  const { data } = await callable({
    messages: [
      {
        role: "user",
        content: userContent({
          subjectName,
          input,
          startDate,
          offsets,
          summary,
          healthContext,
        }),
      },
    ],
    systemPrompt: systemPrompt(locale),
    familyId,
    purpose: "fitnessPlan",
  });

  if (!data || typeof data.reply !== "string") throw new Error("INVALID_REPLY");

  const plan = parsePlan({
    raw: data.reply,
    subjectName,
    input,
    startDate,
    messageUnitsConsumed: Number(data.messageUnitsConsumed) || 0,
  });
  await saveFitnessPlan({ uid, childId, document: plan });

  return {
    document: plan,
    usage: {
      messageUnitsConsumed: Number(data.messageUnitsConsumed) || 0,
      usageToday: Number(data.usageToday) || 0,
      dailyLimit: Number(data.dailyLimit) || 0,
    },
  };
}

/* ── Riorganizzazione della settimana ────────────────────────────────────── */

/** Porting di `FitnessPlanPromptBuilder.rescheduleSystemPrompt`. */
export function rescheduleSystemPrompt(locale) {
  const responseLanguage = responseLanguageName(locale);
  return `Sei il preparatore atletico dell'app KidBox. L'utente ha spostato una seduta.
Riorganizza SOLO le sedute rimanenti della settimana indicata, senza aumentare il carico
totale e senza mettere due sedute intense di fila. Non toccare le sedute già completate.
LINGUA dei testi: ${responseLanguage}.

Rispondi con UN SOLO oggetto JSON valido, niente testo attorno, niente Markdown:
{
  "rationale": "una riga sul criterio usato",
  "sessions": [
    {
      "id": "id della seduta esistente",
      "dayOffset": 3,
      "title": "…",
      "activityType": "…",
      "durationMinutes": 45,
      "intensity": "…",
      "exercises": [{"name": "…", "detail": "…"}],
      "targets": ["…"],
      "targetKcal": 300,
      "notes": "…"
    }
  ]
}
Includi solo le sedute che cambiano, con l'id identico a quello ricevuto.`;
}

/** Giorni interi tra l'inizio del piano e una data: è la valuta del prompt,
 *  che ragiona per `dayOffset` e non per date assolute. */
const dayOffsetOf = (millis, startMillis) =>
  Math.round((startOfDayMillis(millis) - startOfDayMillis(startMillis)) / (24 * 3600 * 1000));

const statusLabel = (status) =>
  ({ planned: "da fare", done: "completata", skipped: "saltata", moved: "spostata" }[status] ||
  "da fare");

/** Una riga per seduta, nel formato che il prompt di iOS si aspetta. */
const sessionLines = (sessions, startMillis) => {
  if (!sessions.length) return ["Nessuna seduta."];
  return sessions.map((session) => {
    let line = `id=${session.id} | dayOffset=${dayOffsetOf(session.date, startMillis)}`;
    line += ` | ${fmtDate(session.date)} | ${session.title}`;
    line += ` | ${session.activityType}, ${session.durationMinutes} min, intensità ${session.intensity}`;
    line += ` | stato: ${statusLabel(session.status)}`;
    if (session.exercises?.length) {
      line += ` | esercizi: ${session.exercises.map((e) => `${e.name} (${e.detail})`).join("; ")}`;
    }
    if (session.targets?.length) line += ` | obiettivi: ${session.targets.join("; ")}`;
    return line;
  });
};

/** Porting di `FitnessPlanGenerator.rescheduleUserContent`. */
export function rescheduleUserContent({ plan, movedSession, newDate, weekIndex }) {
  const lines = [];
  lines.push(`L'utente ha spostato una seduta e serve riorganizzare la settimana ${weekIndex}.`);
  lines.push(`Obiettivo del piano: ${goalInfo(plan.input.goal).prompt}`);
  lines.push(`Giorni disponibili: ${weekdayNames(sortedWeekdays(plan.input))}`);
  lines.push(`Inizio del piano (dayOffset 0): ${fmtDate(plan.startDate)}`);
  lines.push(
    `Seduta spostata: "${movedSession.title}" da ${fmtDate(movedSession.date)} ` +
      `a ${fmtDate(newDate)} (dayOffset ${dayOffsetOf(newDate, plan.startDate)})`
  );
  if (plan.safetyNotes?.length) {
    lines.push("");
    lines.push("--- VINCOLI CLINICI GIÀ STABILITI (da rispettare) ---");
    lines.push(...plan.safetyNotes.map((n) => `• ${n}`));
  }
  lines.push("");
  lines.push(`--- SEDUTE DELLA SETTIMANA ${weekIndex} ---`);
  lines.push(
    ...sessionLines(
      (plan.weeks || []).find((w) => w.index === weekIndex)?.sessions || [],
      plan.startDate
    )
  );
  return lines.join("\n");
}

/** Porting di `FitnessPlanParser.parseSessionUpdates`. */
export function parseSessionUpdates(raw, { startMillis, fallbackWeekIndex }) {
  const object = jsonObjectFrom(raw);
  if (!object) throw new Error("INVALID_PLAN_FORMAT");
  return {
    rationale: (object.rationale || "").trim(),
    changes: (Array.isArray(object.changes) ? object.changes : [])
      .filter((c) => typeof c === "string")
      .map((c) => c.trim())
      .filter(Boolean),
    sessions: (Array.isArray(object.sessions) ? object.sessions : [])
      .map((r) => parseSession(r, fallbackWeekIndex, startMillis))
      .filter(Boolean),
  };
}

/**
 * Porting di `FitnessPlanGenerator.apply`: riscrive le sedute che l'AI ha
 * cambiato, lasciando fuori quelle già completate — il resoconto della
 * settimana deve restare quello che è successo davvero — e quella appena
 * spostata a mano, la cui data non è negoziabile.
 */
export function applySessionUpdates(sessions, plan, { skipping = [] } = {}) {
  const skip = new Set(skipping);
  const byId = new Map(sessions.filter((s) => !skip.has(s.id)).map((s) => [s.id, s]));
  const next = {
    ...plan,
    weeks: plan.weeks.map((w) => ({
      ...w,
      sessions: w.sessions.map((existing) => {
        const incoming = byId.get(existing.id);
        if (!incoming || existing.status === "done") return existing;
        const movedDay = startOfDayMillis(incoming.date) !== startOfDayMillis(existing.date);
        return {
          ...existing,
          originalDate: movedDay ? existing.originalDate ?? existing.date : existing.originalDate,
          date: incoming.date,
          title: incoming.title,
          activityType: incoming.activityType,
          durationMinutes: incoming.durationMinutes,
          intensity: incoming.intensity,
          exercises: incoming.exercises,
          targets: incoming.targets,
          targetKcal: incoming.targetKcal,
          notes: incoming.notes,
          status: "planned",
        };
      }),
    })),
  };
  // Le date sono cambiate: ogni settimana va riordinata.
  next.weeks = next.weeks.map((w) => ({
    ...w,
    sessions: [...w.sessions].sort((a, b) => (a.date || 0) - (b.date || 0)),
  }));
  return next;
}

/**
 * Sposta la seduta **e** fa riorganizzare all'AI il resto della settimana,
 * come il pulsante «Sposta» del telefono. Costa un messaggio AI ed è riservata
 * ai piani a pagamento: il gate vero resta quello server dentro `askAI`, che
 * conosce `fitnessAdjust`.
 *
 * Se qualcosa va storto la funzione solleva: lo spostamento a mano resta
 * comunque valido e lo applica chi chiama, esattamente come fa iOS quando
 * l'AI non risponde.
 */
export async function rescheduleSession({
  uid,
  familyId,
  childId,
  plan,
  sessionId,
  newDate,
  subscriptionPlan = null,
  locale = "it",
}) {
  if (subscriptionPlan !== null && !isPaidPlan(subscriptionPlan)) {
    throw new Error("PLAN_NOT_INCLUDED");
  }
  const session = allSessions(plan).find((s) => s.id === sessionId);
  if (!session) throw new Error("INVALID_PLAN_FORMAT");

  const weekIndex = session.weekIndex || 1;
  const callable = httpsCallable(functions, "askAI", { timeout: 300_000 });
  const { data } = await callable({
    messages: [
      {
        role: "user",
        content: rescheduleUserContent({ plan, movedSession: session, newDate, weekIndex }),
      },
    ],
    systemPrompt: rescheduleSystemPrompt(locale),
    familyId,
    purpose: "fitnessAdjust",
  });
  if (!data || typeof data.reply !== "string") throw new Error("INVALID_REPLY");

  const updates = parseSessionUpdates(data.reply, {
    startMillis: plan.startDate,
    fallbackWeekIndex: weekIndex,
  });

  // Prima lo spostamento scelto dall'utente, poi le modifiche dell'AI attorno.
  const moved = withMovedSession(plan, sessionId, newDate);
  const document = applySessionUpdates(updates.sessions, moved, { skipping: [sessionId] });
  await saveFitnessPlan({ uid, childId, document });

  return {
    document,
    rationale: updates.rationale,
    usage: {
      messageUnitsConsumed: Number(data.messageUnitsConsumed) || 0,
      usageToday: Number(data.usageToday) || 0,
      dailyLimit: Number(data.dailyLimit) || 0,
    },
  };
}

/* ── Consuntivo settimanale ──────────────────────────────────────────────── */

/** Porting di `FitnessWeeklyReportBuilder`, per la sola parte senza Apple Salute. */
export function weeklyReport(plan, weekIndex) {
  const week = (plan?.weeks || []).find((w) => w.index === weekIndex);
  if (!week) return null;
  const done = week.sessions.filter((s) => s.status === "done");
  const skipped = week.sessions.filter((s) => s.status === "skipped");
  const totalMinutes = done.reduce((sum, s) => sum + (s.actualMinutes ?? s.durationMinutes ?? 0), 0);
  const totalKcal = done.reduce((sum, s) => sum + (s.actualKcal ?? s.targetKcal ?? 0), 0);
  return {
    weekIndex,
    plannedSessions: week.sessions.length,
    completedSessions: done.length,
    skippedSessions: skipped.length,
    totalMinutes,
    totalKcal,
    completionPercent: week.sessions.length
      ? Math.round((done.length / week.sessions.length) * 100)
      : 0,
  };
}
