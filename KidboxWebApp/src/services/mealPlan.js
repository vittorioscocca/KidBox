/**
 * Piano Alimentare, allineato a `MealPlanRemoteStore` e `MealPlanGenerator`.
 *
 * Percorso: `users/{uid}/mealPlans/{childId}` — **privato per utente**, non
 * sotto `families`: il piano contiene peso, obiettivo e abitudini alimentari di
 * chi lo genera, e sotto `families` il wildcard delle rules lo renderebbe
 * leggibile a tutta la famiglia.
 *
 * Niente listener realtime, come su iOS: il piano è un singolo documento che si
 * legge all'apertura e si riscrive solo quando viene rigenerato. L'eliminazione
 * è un soft-delete, perché gli altri dispositivi devono poter distinguere «mai
 * sincronizzato» da «eliminato altrove».
 *
 * La generazione passa dalla function `askAI` con `purpose: "mealPlan"`: è il
 * server a scegliere il modello, ad applicare le regole di sistema e a
 * rifiutare i piani Free. Qui non si finge nessun controllo di piano.
 */
import { doc, getDoc, serverTimestamp, setDoc, Timestamp } from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { db, functions } from "../firebase";
import { buildHealthContext, profileSummaryLines, responseLanguageName } from "./healthContext";
import { isPaidPlan } from "./profile";

const planRef = (uid, childId) => doc(db, "users", uid, "mealPlans", childId);

/** Referti allegati: tetto più basso della chat Salute, come su iOS. */
export const REFERTO_MAX_CHARS = 1200;

/* ── Tassonomie ──────────────────────────────────────────────────────────── */

export const MEAL_GOALS = [
  {
    raw: "fatLoss",
    it: "Perdere grasso",
    en: "Lose fat",
    prompt: "perdere grasso mantenendo la massa muscolare",
  },
  {
    raw: "maintenance",
    it: "Mantenere il peso",
    en: "Maintain weight",
    prompt: "mantenere il peso migliorando la qualità della dieta",
  },
  {
    raw: "muscleGain",
    it: "Aumentare massa magra",
    en: "Build lean mass",
    prompt: "aumentare la massa magra con un surplus calorico contenuto",
  },
];

export const MEAL_ACTIVITY_LEVELS = [
  {
    raw: "sedentary",
    it: "Sedentario",
    en: "Sedentary",
    prompt: "sedentario (poco o nessun allenamento)",
  },
  {
    raw: "light",
    it: "Leggero",
    en: "Light",
    prompt: "leggero (1-2 allenamenti a settimana)",
  },
  {
    raw: "moderate",
    it: "Moderato",
    en: "Moderate",
    prompt: "moderato (3-4 allenamenti a settimana)",
  },
  {
    raw: "intense",
    it: "Intenso",
    en: "Intense",
    prompt: "intenso (5 o più allenamenti a settimana)",
  },
];

const goalInfo = (raw) => MEAL_GOALS.find((g) => g.raw === raw) || MEAL_GOALS[0];
const levelInfo = (raw) =>
  MEAL_ACTIVITY_LEVELS.find((l) => l.raw === raw) || MEAL_ACTIVITY_LEVELS[2];

export const emptyMealInput = () => ({
  goal: "fatLoss",
  activityLevel: "moderate",
  preferredFoods: "",
  avoidedFoods: "",
  notes: "",
  manualAgeYears: "",
  manualWeightKg: "",
  manualHeightCm: "",
});

/** Numero inserito a mano, con la virgola o col punto, come su iOS. */
export function parseManualNumber(raw, { min, max }) {
  const cleaned = (raw ?? "").toString().trim().replace(",", ".");
  const value = Number(cleaned);
  if (!Number.isFinite(value) || value <= 0) return null;
  if (value < min || value > max) return null;
  return value;
}

export const manualValues = (input) => ({
  ageYears: parseManualNumber(input.manualAgeYears, { min: 1, max: 119 }),
  weightKg: parseManualNumber(input.manualWeightKg, { min: 2, max: 400 }),
  heightCm: parseManualNumber(input.manualHeightCm, { min: 40, max: 260 }),
});

/* ── Persistenza ─────────────────────────────────────────────────────────── */

const millis = (ts) => (ts?.toMillis ? ts.toMillis() : null);

/**
 * Il documento remoto già risolto: `null` quando non esiste, `{ deleted: true }`
 * quando un altro dispositivo l'ha eliminato.
 */
export async function fetchMealPlan({ uid, childId }) {
  const snap = await getDoc(planRef(uid, childId));
  if (!snap.exists()) return null;
  const d = snap.data();
  if (d.isDeleted === true) return { deleted: true };
  if (typeof d.text !== "string" || !d.text) return null;

  return {
    subjectName: d.subjectName || "",
    text: d.text,
    generatedAt: millis(d.generatedAt) || Date.now(),
    messageUnitsConsumed: Number(d.messageUnitsConsumed) || 0,
    input: {
      goal: goalInfo(d.goal).raw,
      activityLevel: levelInfo(d.activityLevel).raw,
      preferredFoods: d.preferredFoods || "",
      avoidedFoods: d.avoidedFoods || "",
      notes: d.notes || "",
      manualAgeYears: d.manualAgeYears || "",
      manualWeightKg: d.manualWeightKg || "",
      manualHeightCm: d.manualHeightCm || "",
    },
  };
}

export async function saveMealPlan({ uid, childId, document: plan }) {
  const input = plan.input;
  await setDoc(
    planRef(uid, childId),
    {
      childId,
      subjectName: plan.subjectName,
      text: plan.text,
      generatedAt: Timestamp.fromMillis(plan.generatedAt),
      messageUnitsConsumed: plan.messageUnitsConsumed,
      goal: input.goal,
      activityLevel: input.activityLevel,
      preferredFoods: input.preferredFoods,
      avoidedFoods: input.avoidedFoods,
      notes: input.notes,
      manualAgeYears: input.manualAgeYears,
      manualWeightKg: input.manualWeightKg,
      manualHeightCm: input.manualHeightCm,
      isDeleted: false,
      updatedAt: serverTimestamp(),
    },
    { merge: true }
  );
}

export async function deleteMealPlan({ uid, childId }) {
  await setDoc(
    planRef(uid, childId),
    { childId, isDeleted: true, text: "", updatedAt: serverTimestamp() },
    { merge: true }
  );
}

/* ── Sezioni del piano ───────────────────────────────────────────────────── */

/**
 * Divide il testo AI sui titoli in MAIUSCOLO (una riga sola) o sui separatori
 * `---`, come `MealPlanSection.parse` su iOS.
 */
export function parseSections(text) {
  const sections = [];
  let title = "";
  let body = [];

  const flush = () => {
    const joined = body.join("\n").trim();
    if (!title && !joined) return;
    sections.push({ id: `${sections.length}-${title}`, title, body: joined });
  };

  const isTitle = (line) => {
    if (line.length <= 3 || line.length > 80) return false;
    if (!/\p{L}/u.test(line)) return false;
    return line === line.toUpperCase();
  };

  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (line === "---") continue;
    if (isTitle(line)) {
      flush();
      title = line;
      body = [];
    } else {
      body.push(raw);
    }
  }
  flush();
  return sections;
}

/* ── Prompt ──────────────────────────────────────────────────────────────── */

/** System prompt, identico a `MealPlanPromptBuilder.systemPrompt`. */
export function systemPrompt(locale) {
  const responseLanguage = responseLanguageName(locale);
  return `Agisci come un coach di nutrizione e fitness basato sull'evidenza, integrato nell'app KidBox.
Analizzi età, altezza, peso, livello di attività, allenamenti, alimentazione, visite mediche,
cure in corso ed esami di laboratorio della persona per costruire un piano alimentare pratico.

LINGUA DELLA RISPOSTA: ${responseLanguage}. Scrivi TUTTO il piano in questa lingua.

COSA DEVI PRODURRE, IN QUEST'ORDINE:
1) STIMA CALORICA — stima le calorie di mantenimento a partire da età, altezza, peso, livello di
attività e allenamenti registrati, poi definisci un deficit (o surplus) calorico realistico
coerente con l'obiettivo. Usa INTERVALLI, non falsa precisione. Aggiungi una riga su come
adattare le calorie alle variazioni settimanali del peso. Massimo 6 righe.
2) OBIETTIVI DI MACRONUTRIENTI — proteine, carboidrati e grassi come intervalli giornalieri, più
una riga sul perché di quella ripartizione. Massimo 5 righe.
3) PIANO DEI PASTI — UNA sola giornata tipo (colazione, pranzo, cena, 1-2 spuntini) sul target
calorico stimato, costruita con gli alimenti graditi. Per ogni pasto una riga con porzioni e
calorie, e una riga con proteine/carboidrati/grassi. Per ogni pasto UNA sola alternativa
equivalente, su una riga. Se ci sono allenamenti, aggiungi 2 righe su cosa mangiare prima e dopo.
Massimo 30 righe in tutto.
4) IDRATAZIONE — acqua e sali, adattati agli allenamenti. Massimo 4 righe.
5) LISTA DELLA SPESA — solo gli alimenti della giornata tipo, raggruppati per reparto, una riga
per reparto con gli alimenti separati da virgola. Massimo 8 righe.
6) PIANO 90 GIORNI — tre blocchi (mese 1, mese 2, mese 3), massimo 3 righe ciascuno, con calorie,
proteine, allenamento e obiettivo intermedio del mese.
7) NOTE DI SALUTE — come condizioni cliniche, cure in corso, allergie e valori di laboratorio
presenti nei dati influenzano il piano. Se un dato manca, dillo. Massimo 6 righe.

LUNGHEZZA:
L'INTERO piano deve stare in circa 1200 parole. È un vincolo, non un suggerimento: meglio una
sezione asciutta che un piano tagliato a metà. Scrivi frasi brevi, niente introduzioni, niente
riepiloghi di quanto hai appena scritto, niente ripetizioni delle regole tra una sezione e l'altra.
Devi arrivare fino in fondo alla sezione 7: se stai correndo lungo, accorcia le sezioni successive.

REGOLE ASSOLUTE:
Il piano deve essere economico, saziante, bilanciato e realistico da seguire per 90 giorni.
Dai priorità a un progresso sostenibile, al mantenimento della massa muscolare e alla salute generale.
NON raccomandare diete estreme, restrizioni eccessive, digiuni prolungati o metodi pericolosi.
NON inventare valori clinici assenti dai dati forniti.
Rispetta sempre allergie, intolleranze e alimenti da evitare indicati.
Se la persona ha meno di 18 anni, è in gravidanza o in allattamento, NON generare un piano
ipocalorico: fornisci solo indicazioni educative sull'equilibrio dei pasti e rimanda al
pediatra o allo specialista.
Chiudi ricordando che il piano è educativo e va validato dal medico o dal nutrizionista curante.

FORMATO:
Titoli di sezione in MAIUSCOLO su una riga sola, esattamente nell'ordine sopra.
Sotto ogni titolo usa testo semplice; per i pasti sono ammessi elenchi brevi con "-".
Vietato Markdown: niente asterischi, cancelletti, backtick o tabelle.`;
}

/** Contenuto utente, identico a `MealPlanPromptBuilder.userContent`. */
export function userContent({ subjectName, input, summary, healthContext }) {
  const lines = [];
  lines.push(`Crea il piano alimentare per ${subjectName}.`);
  lines.push("");
  lines.push("--- OBIETTIVO E PREFERENZE ---");
  lines.push(`Obiettivo: ${goalInfo(input.goal).prompt}`);
  lines.push(`Livello di attività dichiarato: ${levelInfo(input.activityLevel).prompt}`);

  const preferred = (input.preferredFoods || "").trim();
  lines.push(
    preferred
      ? `Alimenti graditi: ${preferred}`
      : "Alimenti graditi: non indicati, usa alimenti comuni, economici e sazianti."
  );

  const avoided = (input.avoidedFoods || "").trim();
  if (avoided) lines.push(`Alimenti da evitare / intolleranze: ${avoided}`);

  const notes = (input.notes || "").trim();
  if (notes) lines.push(`Note aggiuntive: ${notes}`);

  lines.push("");
  lines.push("--- DATI ANTROPOMETRICI E ALLENAMENTI (app Salute) ---");
  lines.push(...(summary.length ? summary : ["Nessun dato antropometrico disponibile."]));

  lines.push("");
  lines.push("--- DATI CLINICI (visite, cure, analisi, referti) ---");
  lines.push(healthContext);

  return lines.join("\n");
}

/* ── Generazione ─────────────────────────────────────────────────────────── */

/**
 * Genera il piano e lo salva. Peso e altezza sono obbligatori: senza, iOS
 * rifiuta la generazione (`missingHealthData`) e qui vale lo stesso, altrimenti
 * il modello stimerebbe le calorie a caso.
 *
 * Il controllo di piano sta qui e non solo nella schermata: questa funzione è
 * il collo di bottiglia attraversato da ogni percorso, rigenerazioni comprese,
 * ed è il punto che una view nuova può dimenticare. Resta comunque il secondo
 * dei tre presidi — a decidere è il gate server dentro `askAI`, l'unico che
 * regge contro un client aggirato. `subscriptionPlan` non passato = lettura
 * non ancora arrivata: si lascia decidere al server invece di bloccare un
 * utente Pro.
 */
export async function generateMealPlan({
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

  const summary = profileSummaryLines({ birthDate, profile, manual });
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
      { role: "user", content: userContent({ subjectName, input, summary, healthContext }) },
    ],
    systemPrompt: systemPrompt(locale),
    familyId,
    purpose: "mealPlan",
  });

  if (!data || typeof data.reply !== "string" || !data.reply.trim()) {
    throw new Error("INVALID_REPLY");
  }

  const plan = {
    subjectName,
    input,
    text: data.reply.trim(),
    generatedAt: Date.now(),
    messageUnitsConsumed: Number(data.messageUnitsConsumed) || 0,
  };
  await saveMealPlan({ uid, childId, document: plan });

  return {
    document: plan,
    usage: {
      messageUnitsConsumed: Number(data.messageUnitsConsumed) || 0,
      usageToday: Number(data.usageToday) || 0,
      dailyLimit: Number(data.dailyLimit) || 0,
    },
  };
}
