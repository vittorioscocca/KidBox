/**
 * Cartella clinica, porting della pipeline iOS (`ClinicalRecordBuilder` →
 * `ClinicalRecordAISynthesizer` → `ClinicalRecordReportParser`).
 *
 * Due passaggi, come sul telefono:
 *
 *  1. **bozza nativa** — costruita solo dai dati dell'app, senza AI e senza
 *     costi: è già leggibile e stampabile per conto suo;
 *  2. **sintesi AI** — la bozza più i dati grezzi vengono passati ad `askAI`
 *     con `purpose: "clinicalRecord"` (il server usa Sonnet), che li riscrive
 *     in prosa narrativa.
 *
 * Come su iOS il documento **non** viene sincronizzato: `ClinicalRecordStore`
 * lo tiene nei file locali del dispositivo, qui vive in `localStorage`. È una
 * scelta, non una scorciatoia: la cartella contiene la rilettura clinica di
 * tutto lo storico, e non ha una collezione condivisa in cui i client nativi
 * andrebbero a cercarla.
 */
import { httpsCallable } from "firebase/functions";
import { functions } from "../firebase";
import { buildHealthContext, frequencyLabel } from "./healthContext";
import { examStatusInfo, vaccineDate, vaccineTypeInfo } from "./health";

/* ── Persistenza locale ──────────────────────────────────────────────────── */

const storageKey = (childId) => `kidbox:clinicalRecord:${childId}`;

export function loadReport(childId) {
  try {
    const raw = localStorage.getItem(storageKey(childId));
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function saveReport(childId, report) {
  try {
    localStorage.setItem(storageKey(childId), JSON.stringify(report));
  } catch {
    // Quota piena o storage negato: la cartella resta comunque a schermo.
  }
}

export function deleteReport(childId) {
  try {
    localStorage.removeItem(storageKey(childId));
  } catch {
    /* niente da fare */
  }
}

/* ── Sanitizzazione ──────────────────────────────────────────────────────── */

/** Porting di `ClinicalRecordTextSanitizer.sanitize`. */
export function sanitize(text) {
  let s = (text || "").replaceAll("\r\n", "\n");
  for (const token of ["```", "**", "__", "`", "*/", "/*"]) s = s.replaceAll(token, "");

  const lines = s.split("\n").map((line) => {
    let l = line.trim();
    while (l.startsWith("#")) l = l.slice(1);
    l = stripListMarker(l.trim());
    return l.replaceAll("*", "");
  });

  return lines.join("\n").replaceAll("\n\n\n", "\n\n").trim();
}

function stripListMarker(line) {
  if (line.startsWith("• ")) return line.slice(2);
  if (line.startsWith("- ") && !line.startsWith("--")) return line.slice(2);
  if (line.startsWith("* ")) return line.slice(2);
  const numbered = /^(\d+)\.\s(.*)$/.exec(line);
  return numbered ? numbered[2] : line;
}

/* ── Parsing in sezioni ──────────────────────────────────────────────────── */

function isSectionHeader(line) {
  if (line.startsWith("CARTELLA CLINICA")) return false;
  if (line.startsWith("•") || line.startsWith("-")) return false;
  if (/^\d/.test(line)) return false;
  return line === line.toUpperCase() && line.length > 8 && !line.includes(":");
}

/** Porting di `ClinicalRecordReportParser.parse`. */
export function parseReport({ text, subjectName, source }) {
  const lines = sanitize(text).split("\n");
  const areas = [];
  let title = "Sintesi";
  let buffer = [];

  const flush = () => {
    const body = buffer.join("\n").trim();
    buffer = [];
    if (!body) return;
    const bullets = body
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.startsWith("•"))
      .slice(0, 8);
    areas.push({
      id: `${areas.length}-${title}`,
      title,
      summary: bullets[0] || body.slice(0, 80),
      narrative: body,
      bullets,
    });
  };

  for (const line of lines) {
    const t = line.trim();
    if (t === "---" || isSectionHeader(t)) {
      flush();
      if (isSectionHeader(t)) title = t;
      continue;
    }
    buffer.push(line);
  }
  flush();

  return {
    generatedAt: Date.now(),
    source,
    subjectName,
    headerLines: lines.slice(0, 6),
    areas,
    fullDocumentLines: lines.filter((l) => l !== "" || l === "---"),
  };
}

/* ── Bozza nativa ────────────────────────────────────────────────────────── */

const fmtDate = (m) =>
  m ? new Date(m).toLocaleDateString("it-IT", { day: "2-digit", month: "2-digit", year: "numeric" }) : "";

const nonEmpty = (v) => typeof v === "string" && v.trim().length > 0;

/**
 * Bozza nativa: struttura, date e numeri presi dai dati dell'app, senza AI.
 * È il documento che l'AI riceve come riferimento e trasforma in narrativa.
 *
 * Le aree si costruiscono per blocchi e non ri-parsando il testo prodotto: qui
 * il titolo di ogni sezione è già noto, e passare da `parseReport` lo
 * perderebbe ogni volta che è corto (la sua euristica chiede più di 8
 * caratteri, e «PEDIATRA» non ci arriva).
 */
export function buildNativeReport({
  subjectName,
  birthDate,
  profile,
  visits,
  exams,
  treatments,
  vaccines,
}) {
  const header = [`CARTELLA CLINICA — ${subjectName.toUpperCase()}`];

  const anagrafica = [];
  if (birthDate) {
    const years = Math.floor((Date.now() - birthDate) / (365.25 * 24 * 3600 * 1000));
    anagrafica.push(`Data di nascita ${fmtDate(birthDate)} (${years} anni)`);
  }
  if (nonEmpty(profile?.bloodGroup)) anagrafica.push(`gruppo sanguigno ${profile.bloodGroup}`);
  if (nonEmpty(profile?.doctorName)) anagrafica.push(`medico di riferimento ${profile.doctorName}`);
  if (anagrafica.length) header.push(`${anagrafica.join(", ")}.`);
  header.push(`Documento generato il ${fmtDate(Date.now())}.`);

  /** Blocchi `{ title, lines }`: `title` vuoto solo per l'intestazione. */
  const blocks = [{ title: "", lines: header }];

  const noteLines = [];
  if (nonEmpty(profile?.allergies)) noteLines.push(`• Allergie: ${profile.allergies}`);
  if (nonEmpty(profile?.medicalNotes)) noteLines.push(`• Note: ${profile.medicalNotes}`);
  if (noteLines.length) blocks.push({ title: "ALLERGIE E NOTE MEDICHE", lines: noteLines });

  const cure =
    treatments.length === 0
      ? ["• Nessuna terapia in corso registrata."]
      : treatments.map((t) => {
          let line = `• ${t.drugName} ${Math.round(t.dosageValue)} ${t.dosageUnit}, ${frequencyLabel(t)}`;
          line += t.isLongTerm
            ? ", lungo termine"
            : `, ${t.durationDays} giorni dal ${fmtDate(t.startDate)}`;
          if (nonEmpty(t.notes)) line += ` — ${t.notes}`;
          return line;
        });
  blocks.push({ title: "STATO ATTUALE DELLE CURE", lines: cure });

  // Le visite sono raggruppate per specializzazione: è il taglio per aree
  // cliniche che la cartella si aspetta di avere già nella bozza.
  const bySpec = new Map();
  for (const v of visits) {
    const key = v.doctorSpecialization || "Altro";
    bySpec.set(key, [...(bySpec.get(key) || []), v]);
  }
  for (const [spec, group] of [...bySpec.entries()].sort((a, b) => b[1].length - a[1].length)) {
    const lines = [];
    for (const v of [...group].sort((a, b) => (b.date || 0) - (a.date || 0))) {
      let line = `• ${fmtDate(v.date)}`;
      if (nonEmpty(v.reason)) line += ` — ${v.reason}`;
      if (nonEmpty(v.doctorName)) line += ` (${v.doctorName})`;
      lines.push(line);
      if (nonEmpty(v.diagnosis)) lines.push(`  Diagnosi: ${v.diagnosis}`);
      if (nonEmpty(v.recommendations)) lines.push(`  Raccomandazioni: ${v.recommendations}`);
    }
    blocks.push({ title: spec.toUpperCase(), lines });
  }

  const withResults = exams.filter((e) => nonEmpty(e.resultText));
  if (withResults.length > 0) {
    blocks.push({
      title: "LABORATORIO E REFERTI",
      lines: [...withResults]
        .sort((a, b) => (b.resultDate || 0) - (a.resultDate || 0))
        .map((e) => `• ${e.name} — ${fmtDate(e.resultDate || e.deadline)}: ${e.resultText}`),
    });
  }

  if (vaccines.length > 0) {
    blocks.push({
      title: "VACCINAZIONI",
      lines: vaccines.map((v) => {
        const name = v.commercialName || vaccineTypeInfo(v.vaccineTypeRaw).it;
        let line = `• ${name} — ${fmtDate(vaccineDate(v))}`;
        if (v.totalDoses > 1) line += ` (dose ${v.doseNumber}/${v.totalDoses})`;
        return line;
      }),
    });
  }

  const pending = exams.filter(
    (e) => e.statusRaw === "In attesa" || e.statusRaw === "Prenotato"
  );
  if (pending.length > 0) {
    blocks.push({
      title: "ESAMI IN ATTESA",
      lines: pending.map((e) => {
        let line = `• ${e.name} [${examStatusInfo(e.statusRaw).raw}]`;
        if (e.isUrgent) line += " — URGENTE";
        if (e.deadline) line += ` — scadenza ${fmtDate(e.deadline)}`;
        return line;
      }),
    });
  }

  blocks.push({
    title: "RIEPILOGO",
    lines: [
      `• ${visits.length} visite, ${exams.length} esami, ${treatments.length} cure in corso, ` +
        `${vaccines.length} vaccinazioni registrate.`,
    ],
  });

  const fullDocumentLines = [];
  blocks.forEach((block, i) => {
    if (i > 0) fullDocumentLines.push("---");
    if (block.title) fullDocumentLines.push(block.title);
    fullDocumentLines.push(...block.lines);
  });

  return {
    generatedAt: Date.now(),
    source: "native",
    subjectName,
    headerLines: header,
    areas: blocks.map((block, i) => ({
      id: `native-${i}`,
      title: block.title || subjectName,
      summary: block.lines[0] || "",
      narrative: block.lines.join("\n"),
      bullets: block.lines.filter((l) => l.startsWith("•")).slice(0, 8),
    })),
    fullDocumentLines,
  };
}

/* ── Sintesi AI ──────────────────────────────────────────────────────────── */

/** System prompt, identico a `ClinicalRecordAISynthesizer.systemPrompt`. */
const SYSTEM_PROMPT = `Sei un medico di famiglia che redige una cartella clinica sintetica e professionale.
Scrivi esclusivamente in prosa narrativa fluente in italiano.

REGOLE ASSOLUTE:
ZERO bullet point, ZERO trattini elenco, ZERO elenchi puntati o numerati.
ZERO intestazioni ripetitive tipo "Valore:", "Data:", "Risultato:".
Ogni sezione è un paragrafo continuo di 3-6 frasi.
I dati numerici (pressione, peso, altezza, esami di laboratorio, FC, ecc.) vanno INCORPORATI nel testo, mai elencati.
Descrivi come i valori sono CAMBIATI NEL TEMPO: usa frasi come "si è mantenuta stabile",
"ha mostrato una lieve riduzione da X a Y", "è progressivamente aumentato fino a",
"dopo il picco di X nel mese Y, è tornato nella norma".
Se hai un solo dato, descrivi il contesto: "L'unica misurazione disponibile, risalente a...".
Non usare MAI valori che non sono presenti nei dati forniti.
Se un dato è assente, scrivi "Non sono disponibili misurazioni per questo parametro".
Le date in formato GG/MM o GG/MM/AAAA non sono valori di pressione: non usarle come sistolica/diastolica.
Ogni lesione (angioma, cisti, nodulo) va descritta separatamente per tipo, sede anatomica e dimensione in mm.
Il confronto temporale è valido solo con almeno due misurazioni della stessa entità e date certe.
Se ti viene spontaneo usare un elenco, fermati e riformula come frase completa con "inoltre", "mentre", "al contrario", ecc.

STRUTTURA DEL DOCUMENTO (usa --- come separatore tra blocchi; titoli sezione in MAIUSCOLO su una riga sola):
1) Prima riga: CARTELLA CLINICA — NOME COGNOME
2) Righe anagrafiche in prosa breve (data di nascita, età, residenza, gruppo sanguigno se presenti)
3) --- STATO ATTUALE DELLE CURE (paragrafo sulle terapie in corso, senza elenchi)
4) --- per ogni area clinica rilevante (CARDIOLOGIA con anche pressione arteriosa, GASTROENTEROLOGIA, UROLOGIA, LABORATORIO…): titolo in maiuscolo, poi un solo paragrafo narrativo con quadro, evoluzione temporale e conclusione.
VIETATA sezione standalone «PRESSIONE ARTERIOSA».
5) --- ESAMI IN ATTESA (se presenti)
6) --- RIEPILOGO (massimo 6 frasi)

Rispondi SOLO con il testo della cartella, senza commenti meta.
Vietato Markdown: niente asterischi, cancelletti, backtick o simboli */ /*.`;

function buildUserContent(nativeReport, healthContext) {
  return `Redigi la cartella clinica narrativa per ${nativeReport.subjectName}.
Integra la bozza nativa e i dati grezzi; sostituisci ogni elenco con prosa continua.

BOZZA NATIVA (riferimento strutturato, da trasformare in narrativa):
${nativeReport.fullDocumentLines.join("\n")}

DATI GREZZI APP (fonte primaria per numeri e date):
${healthContext}`;
}

/**
 * Riscrive la bozza nativa in prosa. Il costo lo applica il server: la cartella
 * clinica gira su Sonnet e ha un minimo fisso di unità, che il chiamante mostra
 * all'utente prima di lanciare la generazione.
 */
export async function enhanceWithAI({
  familyId,
  subjectName,
  nativeReport,
  visits,
  exams,
  treatments,
  vaccines,
  profile,
  locale = "it",
}) {
  const healthContext = buildHealthContext({
    subjectName,
    visits,
    exams,
    treatments,
    vaccines,
    profile,
    locale,
  });

  const callable = httpsCallable(functions, "askAI", { timeout: 300_000 });
  const { data } = await callable({
    messages: [{ role: "user", content: buildUserContent(nativeReport, healthContext) }],
    systemPrompt: SYSTEM_PROMPT,
    familyId,
    purpose: "clinicalRecord",
  });

  if (!data || typeof data.reply !== "string" || !data.reply.trim()) {
    throw new Error("INVALID_REPLY");
  }

  const report = parseReport({
    text: collapseStrayListLines(sanitize(data.reply)),
    subjectName,
    source: "aiEnhanced",
  });

  return {
    report,
    usage: {
      messageUnitsConsumed: Number(data.messageUnitsConsumed) || 0,
      usageToday: Number(data.usageToday) || 0,
      dailyLimit: Number(data.dailyLimit) || 0,
    },
  };
}

/** Unisce le righe residue da elenchi AI in paragrafi continui. */
function collapseStrayListLines(text) {
  const blocks = [];
  let current = [];
  const isCapsSection = (line) =>
    line === line.toUpperCase() && line.length > 6 && !line.startsWith("CARTELLA CLINICA");

  for (const raw of text.split("\n")) {
    const line = raw.trim();
    if (!line) {
      if (current.length) blocks.push(current.join(" "));
      current = [];
      continue;
    }
    if (line === "---" || isCapsSection(line)) {
      if (current.length) blocks.push(current.join(" "));
      current = [];
      blocks.push(line);
      continue;
    }
    current.push(line);
  }
  if (current.length) blocks.push(current.join(" "));
  return blocks.join("\n\n");
}

/* ── Esportazione ────────────────────────────────────────────────────────── */

/**
 * Apre la stampa del browser su una finestra dedicata: da lì si salva in PDF.
 * È l'equivalente web di `ClinicalRecordPDFService`, senza dover imbarcare una
 * libreria PDF per un documento che è solo testo.
 */
export function printReport(report) {
  const win = window.open("", "_blank", "noopener,width=900,height=1000");
  if (!win) return false;

  const escape = (s) =>
    s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c]);

  const body = report.areas
    .map(
      (a) =>
        `<section><h2>${escape(a.title)}</h2>${a.narrative
          .split("\n")
          .filter(Boolean)
          .map((p) => `<p>${escape(p)}</p>`)
          .join("")}</section>`
    )
    .join("");

  win.document.write(`<!doctype html><html lang="it"><head><meta charset="utf-8">
<title>Cartella clinica — ${escape(report.subjectName)}</title>
<style>
  body { font-family: -apple-system, system-ui, sans-serif; margin: 32px; color: #111; line-height: 1.55; }
  h1 { font-size: 20px; margin-bottom: 4px; }
  .meta { color: #666; font-size: 12px; margin-bottom: 24px; }
  h2 { font-size: 14px; text-transform: uppercase; letter-spacing: .04em; margin: 22px 0 6px; border-bottom: 1px solid #ddd; padding-bottom: 4px; }
  p { margin: 0 0 8px; font-size: 13px; }
  section { break-inside: avoid; }
</style></head><body>
<h1>Cartella clinica — ${escape(report.subjectName)}</h1>
<div class="meta">Generata il ${fmtDate(report.generatedAt)} · ${
    report.source === "aiEnhanced" ? "sintesi AI" : "bozza nativa"
  } · documento educativo, da validare con il medico curante</div>
${body}
</body></html>`);
  win.document.close();
  win.focus();
  win.print();
  return true;
}
