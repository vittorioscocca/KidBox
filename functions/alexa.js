/* eslint-disable max-len */
/**
 * Skill Alexa "KidBox" — lista della spesa a voce.
 *
 * Perché una custom skill e non la lista nativa: il 1° luglio 2024 Amazon ha
 * chiuso la List Management REST API e le List Skills, cioè l'unico modo che
 * un'app terza aveva di leggere e scrivere la lista della spesa integrata di
 * Alexa. Da allora "Alexa, aggiungi il latte alla lista della spesa" scrive
 * SOLO nella lista interna di Amazon, che nessuno può più leggere. L'unica via
 * rimasta — quella che hanno preso AnyList e Bring — è una skill con nome di
 * invocazione proprio: "Alexa, chiedi a KidBox di aggiungere il latte".
 *
 * Perché niente account linking OAuth: Alexa lo pretende solo se vuoi
 * l'identità Amazon dell'utente. A noi basta sapere QUALE famiglia KidBox sta
 * parlando, e per quello è sufficiente lo `userId` che Alexa manda a ogni
 * richiesta (stabile per coppia skill+utente). Quindi: l'app genera un codice
 * a 6 cifre, l'utente lo detta una volta sola, e da lì in poi la mappatura
 * alexaUserId → (uid, familyId) vive su Firestore. Questo evita di dover
 * scrivere e mantenere un authorization server OAuth2, che era il 70% del
 * lavoro di questa integrazione.
 *
 * Collezioni (entrambe top-level e chiuse a chiave: le rules non le nominano,
 * quindi ricadono nel default-deny e solo l'Admin SDK ci arriva):
 *   alexaPairings/{code}   → codice usa-e-getta, TTL 10 minuti
 *   alexaLinks/{sha256(alexaUserId)} → collegamento permanente
 *   alexaLinkAttempts/{sha256(alexaUserId)} → antibruteforce sul codice
 */

const crypto = require("crypto");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

/**
 * Application id della skill (`amzn1.ask.skill.…`), dalla console Amazon.
 * Non è un segreto in senso stretto, ma è il solo dato che impedisce a una
 * skill altrui di parlare con questo endpoint: sta fra i secrets perché così
 * non finisce nel repo e cambia senza un redeploy del codice.
 */
const ALEXA_SKILL_ID = defineSecret("ALEXA_SKILL_ID");

/** Validità del codice di accoppiamento. */
const PAIRING_TTL_MS = 10 * 60 * 1000;
/** Tentativi di codice sbagliato tollerati prima del blocco. */
const MAX_PAIRING_ATTEMPTS = 5;
/** Finestra dell'antibruteforce. */
const PAIRING_ATTEMPT_WINDOW_MS = 15 * 60 * 1000;
/** Quanti articoli legge al massimo ad alta voce: oltre diventa illeggibile. */
const READ_LIST_MAX_ITEMS = 25;
/** Tolleranza sul timestamp della richiesta Alexa (requisito Amazon: 150s). */
const REQUEST_MAX_AGE_MS = 150 * 1000;

/** Lista to-do in cui finiscono i promemoria dettati: creata al primo uso. */
const ALEXA_TODO_LIST_NAME = "Alexa";
/** Ora usata quando si dice il giorno ma non l'orario ("ricordamelo domani"). */
const DEFAULT_REMIND_HOUR = 9;
/**
 * Fuso in cui si interpreta quello che l'utente dice.
 *
 * Alexa consegna la data e l'ora già risolte ma SENZA fuso ("2026-09-11",
 * "18:30"): sono ore locali di chi parla, e vanno ancorate a un fuso per
 * diventare un istante. Si usa Europe/Rome come tutto il resto del backend —
 * `notifyDueTodoReminders`, i rollup, i testi delle notifiche. L'alternativa
 * sarebbe chiedere il fuso del dispositivo alle Settings API di Alexa, cioè
 * una chiamata HTTP in più dentro gli 8 secondi concessi, per un'app che oggi
 * dà per scontata l'Italia ovunque.
 */
const TODO_TZ = "Europe/Rome";

// ─────────────────────────────────────────────────────────────────────────────
// UTILITY
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Id documento per un `alexaUserId`: l'originale è una stringa di 200+
 * caratteri con dei punti dentro, scomoda e inutile da leggere in console.
 * @param {string} alexaUserId
 * @return {string} Digest esadecimale.
 */
function linkKey(alexaUserId) {
  return crypto.createHash("sha256").update(alexaUserId).digest("hex");
}

/**
 * Articoli e partitivi che l'ASR restituisce ma che in lista non si scrivono.
 *
 * Lista UNICA per le due funzioni che li tolgono — quella che confronta i
 * duplicati e quella che scrive il nome. Erano due elenchi separati e sono
 * divergiti: il dedup conosceva già `the|a|an`, il nome salvato no, quindi
 * «the milk» risultava doppione di «milk» ma finiva in lista come «The milk».
 * Tenerli in un posto solo è ciò che impedisce che succeda di nuovo.
 */
const ARTICLES = [
  "il", "lo", "la", "i", "gli", "le", "un", "uno", "una",
  "del", "dello", "della", "dei", "degli", "delle",
  // La skill risponde anche in inglese: gli articoli inglesi vanno tolti con
  // gli stessi criteri, non con una regola a parte.
  "the", "a", "an", "some",
];
const ARTICLE_ALT = ARTICLES.join("|");

/**
 * Lo spazio obbligatorio dopo la forma piena non è un dettaglio: con `\s*`
 * l'alternativa `la` divorava l'inizio di «latte» («Tte») e `un` quello di
 * «una» («A scatola»). Le forme elise stanno in un ramo separato perché
 * l'apostrofo fa già da confine.
 */
const LEADING_ARTICLE = new RegExp(
    `^(?:(?:${ARTICLE_ALT})\\s+|(?:l|un)['’]\\s*)`, "i");

/**
 * Come sopra, ma sul testo già normalizzato: lì l'apostrofo è diventato uno
 * spazio, quindi «l'acqua» arriva come «l acqua». Da qui la `l` isolata in
 * coda all'alternativa — senza, `l'acqua` e `acqua` non risultavano doppioni.
 *
 * Sta solo qui e non nella lista condivisa: nel nome SALVATO una `l` seguita da
 * spazio può essere l'inizio legittimo di qualcosa, e sbagliare lì si vede in
 * lista; sbagliare nel confronto produce al massimo una riga doppia.
 */
const LEADING_ARTICLE_NORMALIZED = new RegExp(`^(?:${ARTICLE_ALT}|l)\\s+`);

/**
 * Forma normalizzata di un nome articolo, usata SOLO per il confronto: senza
 * accenti, senza articoli iniziali, minuscola. Serve perché l'ASR restituisce
 * "Il Latte" dove in lista c'è "latte", e senza questo si creano duplicati.
 * @param {string} raw
 * @return {string}
 */
function normalizeItemName(raw) {
  const base = String(raw || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  return base.replace(LEADING_ARTICLE_NORMALIZED, "");
}

/**
 * Ripulisce il nome pronunciato prima di scriverlo in lista.
 *
 * Due cose: l'articolo iniziale via — si dice «aggiungi IL latte» ma in lista
 * si scrive «Latte», come farebbe chiunque a mano — e la maiuscola iniziale,
 * perché Alexa manda tutto minuscolo e una riga minuscola in mezzo a quelle
 * scritte dagli altri membri stona.
 *
 * L'articolo si toglieva già in `normalizeItemName`, ma quella serve solo al
 * confronto: il nome salvato passa di qui, e restava «Il latte».
 * @param {string} raw
 * @return {string}
 */
function displayItemName(raw) {
  let clean = String(raw || "").replace(/\s+/g, " ").trim();
  // Solo se resta qualcosa: «aggiungi il» non deve produrre una riga vuota.
  const stripped = clean.replace(LEADING_ARTICLE, "").trim();
  if (stripped) clean = stripped;
  if (!clean) return "";
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// CATEGORIE
// ─────────────────────────────────────────────────────────────────────────────
//
// Le stringhe sono quelle di KBGroceryCategory (iOS) e SUGGESTED (Spesa.jsx):
// il valore salvato è l'italiano, che fa da chiave, e ogni client lo traduce
// per la UI. Vanno scritte identiche o l'articolo finisce in una categoria
// fantasma che nessuna schermata mostra.
//
// Perché una tabella e non l'AI: la categoria va decisa dentro gli 8 secondi
// che Alexa concede, e una chiamata al modello aggiungerebbe latenza, costo e
// il gating per piano (l'AI è una feature a pagamento). Per la spesa di tutti i
// giorni un dizionario copre la quasi totalità dei casi. Quando non riconosce,
// lascia `null` — che i client mostrano come "Altro" — invece di tirare a
// indovinare: una categoria sbagliata è peggio di nessuna categoria, perché
// l'articolo finisce dove non lo si cerca.

/** Parole chiave per categoria, al singolare: il confronto passa dalla radice. */
const CATEGORY_KEYWORDS = {
  "Frutta e Verdura": [
    "mela", "pera", "banana", "arancia", "mandarino", "clementina", "limone",
    "pesca", "albicocca", "susina", "prugna", "uva", "fragola", "ciliegia",
    "melone", "anguria", "kiwi", "ananas", "avocado", "frutta",
    "insalata", "lattuga", "rucola", "spinaci", "pomodoro", "zucchina",
    "melanzana", "peperone", "carota", "patata", "cipolla", "aglio", "sedano",
    "finocchio", "broccolo", "cavolo", "cavolfiore", "verza", "zucca",
    "fagiolino", "pisello", "cetriolo", "porro", "ravanello", "verdura",
    "prezzemolo", "basilico", "rosmarino", "salvia", "funghi", "fungo",
  ],
  "Carne e Pesce": [
    "carne", "pollo", "tacchino", "manzo", "vitello", "maiale", "agnello",
    "salsiccia", "hamburger", "bistecca", "fettina", "macinato", "arrosto",
    "prosciutto", "salame", "mortadella", "bresaola", "speck", "pancetta",
    "wurstel", "pesce", "salmone", "tonno", "merluzzo", "orata", "branzino",
    "gambero", "gamberetto", "cozze", "vongole", "calamaro", "polpo", "alici",
    "acciughe", "sogliola", "platessa",
  ],
  "Latticini": [
    "latte", "yogurt", "burro", "panna", "formaggio", "mozzarella", "ricotta",
    "stracchino", "philadelphia", "mascarpone", "parmigiano", "grana",
    "pecorino", "gorgonzola", "provola", "scamorza", "emmental", "fontina",
    "asiago", "caciotta", "uovo", "uova", "besciamella",
  ],
  "Pane e Cereali": [
    "pane", "pancarre", "panino", "michetta", "baguette", "piadina", "focaccia",
    "grissini", "cracker", "fette", "biscottate", "pasta", "spaghetti", "penne",
    "fusilli", "rigatoni", "farfalle", "lasagne", "gnocchi", "riso", "risotto",
    "orzo", "farro", "quinoa", "cuscus", "polenta", "farina", "lievito",
    "cereali", "avena", "muesli", "cornflakes", "tortilla", "couscous",
  ],
  "Surgelati": [
    "surgelato", "surgelati", "gelato", "ghiaccio", "minestrone", "bastoncini",
    "sofficini", "pizza",
  ],
  "Bevande": [
    "acqua", "vino", "birra", "succo", "aranciata", "cola", "coca", "gassosa",
    "chinotto", "te", "the", "tisana", "caffe", "orzo", "spremuta", "bibita",
    "prosecco", "spumante", "amaro", "liquore", "aperitivo", "tonica",
  ],
  "Dolci e Snack": [
    "biscotto", "biscotti", "merendina", "brioche", "cornetto", "crostata",
    "torta", "cioccolato", "cioccolata", "caramella", "gomma", "nutella",
    "marmellata", "confettura", "miele", "zucchero", "patatine", "snack",
    "wafer", "budino", "creme", "dolce", "dolci", "pandoro", "panettone",
    "colomba", "gelatine", "popcorn", "noccioline", "arachidi", "mandorle",
    "noci",
  ],
  "Pulizia": [
    "detersivo", "detersivi", "ammorbidente", "candeggina", "sgrassatore",
    "anticalcare", "sapone", "piatti", "lavatrice", "lavastoviglie", "spugna",
    "spugne", "scottex", "carta", "igienica", "tovaglioli", "sacchetti",
    "sacchi", "immondizia", "spazzolone", "straccio", "guanti", "alluminio",
    "pellicola", "forno", "vetri", "pavimenti",
  ],
  "Cura Personale": [
    "shampoo", "balsamo", "bagnoschiuma", "docciaschiuma", "dentifricio",
    "spazzolino", "collutorio", "filo", "interdentale", "deodorante",
    "rasoio", "schiuma", "crema", "profumo", "assorbenti", "pannolini",
    "salviette", "cotone", "cerotti", "fazzoletti", "cerotto",
  ],
};

/**
 * Radice grezza di una parola italiana: si toglie la vocale finale, che è
 * quella che cambia al plurale (mela/mele, pomodoro/pomodori). Non è uno
 * stemmer serio, ma per una lista della spesa basta e non ha dipendenze.
 * @param {string} word
 * @return {string}
 */
function stem(word) {
  return word.length >= 4 ? word.replace(/[aeio]$/, "") : word;
}

/** Indice radice → categoria, costruito una volta sola. */
const CATEGORY_BY_STEM = (() => {
  const map = new Map();
  for (const [category, words] of Object.entries(CATEGORY_KEYWORDS)) {
    for (const w of words) {
      // Il primo che occupa la radice vince: "orzo" sta sia in Pane e Cereali
      // sia in Bevande (caffè d'orzo), e il cereale è il caso più probabile.
      if (!map.has(stem(w))) map.set(stem(w), category);
    }
  }
  return map;
})();

/**
 * Categoria indovinata dal nome dell'articolo, o null se non si riconosce.
 * @param {string} rawName
 * @return {string|null}
 */
function guessCategory(rawName) {
  const words = normalizeItemName(rawName).split(" ").filter(Boolean);

  // "Surgelati" prima di tutto: è una qualifica che vince sull'alimento, non
  // una categoria alla pari. "piselli surgelati" sta nel banco dei surgelati,
  // non con la verdura fresca — e senza questa precedenza vincerebbe la prima
  // parola trovata, cioè "piselli".
  for (const w of words) {
    if (CATEGORY_BY_STEM.get(stem(w)) === "Surgelati") return "Surgelati";
  }

  for (const w of words) {
    const hit = CATEGORY_BY_STEM.get(stem(w));
    if (hit) return hit;
  }
  return null;
}

/**
 * Lingua della risposta. La skill nasce italiana; l'inglese c'è perché un
 * Echo configurato en-GB in casa non deve rispondere in italiano.
 * @param {string|undefined} locale
 * @return {"it"|"en"}
 */
function langOf(locale) {
  return String(locale || "").toLowerCase().startsWith("en") ? "en" : "it";
}

/** Testi delle risposte vocali. */
const SPEECH = {
  it: {
    welcome: "Ciao! Dimmi cosa aggiungere alla lista della spesa.",
    welcomeUnlinked: "Per usare KidBox devi prima collegare l'account. Apri KidBox, vai in Impostazioni, Alexa, e detta il codice che vedi.",
    help: "Puoi dire: aggiungi il latte. Oppure: togli il pane. Oppure: cosa manca. Oppure: ricordami di chiamare la scuola.",
    notLinked: "Questo dispositivo non è ancora collegato a KidBox. Apri l'app, vai in Impostazioni, Alexa, e detta il codice che vedi.",
    codePrompt: "Qual è il codice? Dimmi le sei cifre.",
    linkOk: "Perfetto, ho collegato KidBox. Ora puoi dirmi cosa aggiungere alla lista.",
    linkBadCode: "Questo codice non è valido o è scaduto. Generane uno nuovo dall'app, in Impostazioni, Alexa.",
    linkNoCode: "Non ho capito il codice. Riprova dicendo: collegati con, e poi le sei cifre.",
    linkTooManyAttempts: "Troppi tentativi. Riprova fra un quarto d'ora.",
    linkAlready: "KidBox è già collegato su questo dispositivo.",
    linkVoiceOk: "Perfetto, ora riconosco la tua voce: quello che detti risulterà aggiunto da te.",
    addOk: (name) => `Ho aggiunto ${name} alla lista.`,
    addDuplicate: (name) => `${displayItemName(name)} è già in lista.`,
    addNoItem: "Non ho capito cosa aggiungere. Prova a dire: aggiungi il latte.",
    removeOk: (name) => `Ho tolto ${name} dalla lista.`,
    removeMissing: (name) => `Non trovo ${name} in lista.`,
    removeNoItem: "Non ho capito cosa togliere.",
    checkOk: (name) => `Segnato ${name} come comprato.`,
    listEmpty: "La lista della spesa è vuota.",
    listOne: (name) => `In lista c'è solo ${name}.`,
    listMany: (count, names) => `In lista ci sono ${count} articoli: ${names}.`,
    listTruncated: (count, shown, names) => `In lista ci sono ${count} articoli. I primi ${shown}: ${names}.`,
    error: "Qualcosa non ha funzionato. Riprova fra poco.",
    remindAskTitle: "Che cosa devo ricordarti? Dillo per intero, per esempio: ricordami di comprare il pane.",
    remindAskAssignee: (title) => `${title}. A chi lo assegno? Dimmi il nome, oppure di': a nessuno.`,
    remindAskWhen: "Per quando? Dimmi il giorno e l'ora, oppure di': senza promemoria.",
    remindMemberUnknown: (spoken, names) => `Non trovo ${spoken} fra i membri della famiglia. Ci sono ${names}. A chi lo assegno?`,
    remindMemberAmbiguous: (names) => `Ci sono più membri che si chiamano così: ${names}. Assegnalo dall'app, oppure di': a nessuno.`,
    remindNoMembers: "Non riesco a leggere i membri della famiglia, quindi lo lascio a tutti. Per quando?",
    remindWhenUnclear: "Non ho capito quando. Prova con: domani alle otto. Oppure di': senza promemoria.",
    remindWhenPast: "Quel momento è già passato. Dimmi un giorno e un'ora futuri, oppure di': senza promemoria.",
    remindDone: (title) => `Fatto: ${title}, nella lista Alexa.`,
    remindDoneFor: (title, who) => `Fatto: ${title}, nella lista Alexa, per ${who}.`,
    remindDoneAt: (title, when) => `Fatto: te lo ricordo ${when}. ${title}.`,
    remindDoneForAt: (title, who, when) => `Fatto: lo ricordo a ${who} ${when}. ${title}.`,
    remindNoFlow: "Per un promemoria di': ricordami di comprare il pane.",
    remindToday: "oggi",
    remindTomorrow: "domani",
    remindAt: (day, time) => `${day} alle ${time}`,
    bye: "A posto.",
    and: "e",
  },
  en: {
    welcome: "Hi! Tell me what to add to the shopping list.",
    welcomeUnlinked: "To use KidBox you need to link your account first. Open KidBox, go to Settings, Alexa, and read out the code you see.",
    help: "You can say: add milk. Or: remove bread. Or: what's on the list. Or: remind me to call the school.",
    notLinked: "This device isn't linked to KidBox yet. Open the app, go to Settings, Alexa, and read out the code you see.",
    codePrompt: "What's the code? Tell me the six digits.",
    linkOk: "Great, KidBox is linked. Now tell me what to add to the list.",
    linkBadCode: "That code is invalid or expired. Generate a new one in the app, under Settings, Alexa.",
    linkNoCode: "I didn't catch the code. Try saying: link with, then the six digits.",
    linkTooManyAttempts: "Too many attempts. Try again in fifteen minutes.",
    linkAlready: "KidBox is already linked on this device.",
    linkVoiceOk: "Great, I recognise your voice now: what you dictate will show up as added by you.",
    addOk: (name) => `I added ${name} to the list.`,
    addDuplicate: (name) => `${displayItemName(name)} is already on the list.`,
    addNoItem: "I didn't catch what to add. Try saying: add milk.",
    removeOk: (name) => `I removed ${name} from the list.`,
    removeMissing: (name) => `I can't find ${name} on the list.`,
    removeNoItem: "I didn't catch what to remove.",
    checkOk: (name) => `Marked ${name} as bought.`,
    listEmpty: "The shopping list is empty.",
    listOne: (name) => `There's only ${name} on the list.`,
    listMany: (count, names) => `There are ${count} items on the list: ${names}.`,
    listTruncated: (count, shown, names) => `There are ${count} items on the list. The first ${shown}: ${names}.`,
    error: "Something went wrong. Try again shortly.",
    remindAskTitle: "What should I remind you about? Say the whole thing, for example: remind me to buy bread.",
    remindAskAssignee: (title) => `${title}. Who is it for? Tell me the name, or say: nobody.`,
    remindAskWhen: "When? Tell me the day and the time, or say: no reminder.",
    remindMemberUnknown: (spoken, names) => `I can't find ${spoken} among the family members. There are ${names}. Who is it for?`,
    remindMemberAmbiguous: (names) => `More than one member goes by that name: ${names}. Assign it from the app, or say: nobody.`,
    remindNoMembers: "I can't read the family members, so I'll leave it for everyone. When?",
    remindWhenUnclear: "I didn't catch when. Try: tomorrow at eight. Or say: no reminder.",
    remindWhenPast: "That moment has already passed. Tell me a day and time in the future, or say: no reminder.",
    remindDone: (title) => `Done: ${title}, on the Alexa list.`,
    remindDoneFor: (title, who) => `Done: ${title}, on the Alexa list, for ${who}.`,
    remindDoneAt: (title, when) => `Done: I'll remind you ${when}. ${title}.`,
    remindDoneForAt: (title, who, when) => `Done: I'll remind ${who} ${when}. ${title}.`,
    remindNoFlow: "For a reminder say: remind me to buy bread.",
    remindToday: "today",
    remindTomorrow: "tomorrow",
    remindAt: (day, time) => `${day} at ${time}`,
    bye: "Done.",
    and: "and",
  },
};

/**
 * Risposta vocale nel formato che Alexa si aspetta.
 *
 * Il quarto parametro è la memoria del dialogo. Alexa NON conserva niente per
 * conto suo: quello che non rimandiamo indietro in `sessionAttributes` è perso
 * al turno successivo. Che è anche il motivo per cui gli altri intent non lo
 * passano — chiudere il flusso del promemoria non richiede una riga di codice,
 * basta rispondere senza attributi e la macchina a stati si azzera da sola.
 * @param {string} text
 * @param {boolean} [endSession=true]
 * @param {string|null} [reprompt=null]
 * @param {object|null} [attributes=null] Stato da ritrovare al turno dopo.
 * @return {object}
 */
function speak(text, endSession = true, reprompt = null, attributes = null) {
  const response = {
    outputSpeech: {type: "PlainText", text},
    shouldEndSession: endSession,
  };
  if (reprompt) {
    response.reprompt = {outputSpeech: {type: "PlainText", text: reprompt}};
  }
  const payload = {version: "1.0", response};
  if (attributes) payload.sessionAttributes = attributes;
  return payload;
}

// ─────────────────────────────────────────────────────────────────────────────
// VERIFICA DELLA RICHIESTA
// ─────────────────────────────────────────────────────────────────────────────
//
// Questo endpoint è HTTP puro e NON passa da App Check: lo chiama Amazon, non
// un nostro client. Al posto di App Check valgono tre controlli, tutti
// obbligatori — senza, chiunque conosca l'URL può scrivere nella spesa di
// chiunque altro:
//   1. la firma RSA del corpo, con il certificato pubblicato da Amazon;
//   2. il timestamp, contro il replay di una richiesta già firmata;
//   3. l'application id, contro una skill altrui che punti qui.

/** Cache dei certificati già scaricati e validati (per URL). */
const certCache = new Map();

/**
 * Il chain URL deve stare nel bucket di Amazon: è la prima linea di difesa,
 * perché senza questo controllo basterebbe firmare il corpo con un certificato
 * proprio e indicarne l'URL.
 * @param {string|undefined} rawUrl
 * @return {boolean}
 */
function isValidCertChainUrl(rawUrl) {
  let url;
  try {
    url = new URL(String(rawUrl));
  } catch {
    return false;
  }
  if (url.protocol !== "https:") return false;
  if (url.hostname.toLowerCase() !== "s3.amazonaws.com") return false;
  if (url.port && url.port !== "443") return false;
  // Normalizza i `..` prima del confronto: `/echo.api/../evil` passerebbe.
  const path = url.pathname.replace(/\/+/g, "/");
  return path.startsWith("/echo.api/");
}

/**
 * Scarica la catena di certificati, la valida e restituisce la chiave pubblica
 * della foglia.
 *
 * Nota onesta sul livello di verifica: si controllano validità temporale, SAN
 * `echo-api.amazon.com` e il concatenamento firma-per-firma fino alla radice
 * della catena. NON si ancora la radice a un trust store: l'ancoraggio pratico
 * è che il PEM arriva in HTTPS da un bucket S3 di Amazon (verificato sopra),
 * quindi per sostituirlo servirebbe già il controllo di quel bucket.
 * @param {string} certChainUrl
 * @return {Promise<crypto.KeyObject>}
 */
async function loadSigningKey(certChainUrl) {
  const cached = certCache.get(certChainUrl);
  if (cached && cached.expiresAt > Date.now()) return cached.key;

  const res = await fetch(certChainUrl);
  if (!res.ok) throw new Error(`cert fetch HTTP ${res.status}`);
  const pem = await res.text();

  const blocks = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g);
  if (!blocks || blocks.length === 0) throw new Error("cert chain vuota");

  const chain = blocks.map((b) => new crypto.X509Certificate(b));
  const leaf = chain[0];

  const now = Date.now();
  if (Date.parse(leaf.validFrom) > now || Date.parse(leaf.validTo) < now) {
    throw new Error("certificato foglia fuori validità");
  }

  const sans = String(leaf.subjectAltName || "")
      .split(",")
      .map((s) => s.trim().replace(/^DNS:/, ""));
  if (!sans.includes("echo-api.amazon.com")) {
    throw new Error("SAN echo-api.amazon.com assente");
  }

  for (let i = 0; i < chain.length - 1; i++) {
    if (!chain[i].verify(chain[i + 1].publicKey)) {
      throw new Error(`catena interrotta al livello ${i}`);
    }
  }

  const key = leaf.publicKey;
  // Un'ora: i certificati Amazon durano mesi, ma una cache troppo lunga
  // ritarderebbe la reazione a una revoca.
  certCache.set(certChainUrl, {key, expiresAt: now + 60 * 60 * 1000});
  return key;
}

/**
 * Verifica firma e timestamp. Lancia se qualcosa non torna: il chiamante
 * risponde 400 senza dettagli, perché un messaggio d'errore preciso qui
 * aiuterebbe solo chi sta sondando l'endpoint.
 * @param {import("express").Request} req
 * @param {object} body
 * @return {Promise<void>}
 */
async function verifyAlexaRequest(req, body) {
  const certChainUrl = req.get("SignatureCertChainUrl");
  // Amazon firma in SHA-256 (`Signature-256`); `Signature` è il vecchio SHA-1,
  // tenuto solo come rete di sicurezza per i device non aggiornati.
  const signature256 = req.get("Signature-256");
  const signatureLegacy = req.get("Signature");

  if (!isValidCertChainUrl(certChainUrl)) throw new Error("cert chain url non valido");
  if (!signature256 && !signatureLegacy) throw new Error("firma assente");
  if (!req.rawBody) throw new Error("rawBody assente");

  const key = await loadSigningKey(certChainUrl);
  const algo = signature256 ? "RSA-SHA256" : "RSA-SHA1";
  const signature = signature256 || signatureLegacy;

  const verifier = crypto.createVerify(algo);
  verifier.update(req.rawBody);
  if (!verifier.verify(key, Buffer.from(signature, "base64"))) {
    throw new Error("firma non valida");
  }

  const timestamp = Date.parse(body?.request?.timestamp || "");
  if (!Number.isFinite(timestamp)) throw new Error("timestamp assente");
  if (Math.abs(Date.now() - timestamp) > REQUEST_MAX_AGE_MS) {
    throw new Error("timestamp fuori tolleranza");
  }
}

/**
 * Application id della richiesta, da `session` o da `context` a seconda che la
 * sessione sia aperta o no.
 * @param {object} body
 * @return {string|null}
 */
function applicationIdOf(body) {
  return body?.session?.application?.applicationId ||
    body?.context?.System?.application?.applicationId ||
    null;
}

/**
 * `personId` di chi ha parlato, quando Alexa riconosce la voce.
 *
 * È diverso dallo `userId`: quello identifica l'ACCOUNT Amazon, questo la
 * PERSONA. In una casa con un solo account e tre profili vocali addestrati,
 * lo userId è sempre lo stesso e il personId cambia a ogni voce — ed è l'unico
 * modo di attribuire correttamente chi ha dettato cosa.
 *
 * Arriva solo se la Personalization è abilitata per la skill e la voce è
 * riconosciuta. Ospiti, profili non addestrati o riconoscimento incerto danno
 * null, e si ricade sull'account.
 * @param {object} body
 * @return {string|null}
 */
function personIdOf(body) {
  return body?.context?.System?.person?.personId || null;
}

/**
 * `userId` Alexa, stabile per coppia skill+utente.
 * @param {object} body
 * @return {string|null}
 */
function alexaUserIdOf(body) {
  return body?.session?.user?.userId ||
    body?.context?.System?.user?.userId ||
    null;
}

// ─────────────────────────────────────────────────────────────────────────────
// COLLEGAMENTO
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Collegamento attivo per questo dispositivo Alexa, o null.
 * @param {string} alexaUserId
 * @return {Promise<{uid: string, familyId: string}|null>}
 */
async function resolveLink(alexaUserId) {
  const snap = await admin.firestore().collection("alexaLinks").doc(linkKey(alexaUserId)).get();
  if (!snap.exists) return null;
  const data = snap.data();
  if (!data.uid || !data.familyId) return null;
  return {uid: data.uid, familyId: data.familyId};
}

/**
 * Membro associato a una voce riconosciuta, o null.
 *
 * Volutamente separato da `resolveLink`: l'accesso alla lista lo dà l'account
 * collegato, la voce serve solo a dire CHI ha parlato. Una voce sconosciuta
 * non deve togliere l'accesso a nessuno, deve solo far ricadere
 * l'attribuzione sull'account.
 * @param {string|null} personId
 * @param {string} familyId
 * @return {Promise<string|null>} uid del membro.
 */
async function resolveVoiceUid(personId, familyId) {
  if (!personId) return null;
  const snap = await admin.firestore().collection("alexaPersonLinks").doc(linkKey(personId)).get();
  if (!snap.exists) return null;
  const data = snap.data();
  // Il vincolo sulla famiglia non è formale: senza, una voce registrata in
  // un'altra famiglia attribuirebbe articoli a un uid che qui non è membro.
  if (!data.uid || data.familyId !== familyId) return null;
  return data.uid;
}

/**
 * Registra un tentativo di codice sbagliato e dice se si è oltre soglia.
 * Il codice è di sole 6 cifre: senza questo, dettarne un milione a voce è
 * lento ma un client HTTP che parli il protocollo Alexa no.
 * @param {string} alexaUserId
 * @return {Promise<boolean>} true se il tentativo va rifiutato a priori.
 */
async function isRateLimited(alexaUserId) {
  const ref = admin.firestore().collection("alexaLinkAttempts").doc(linkKey(alexaUserId));
  const snap = await ref.get();
  const now = Date.now();
  const data = snap.exists ? snap.data() : null;
  const windowStart = data?.windowStart?.toMillis ? data.windowStart.toMillis() : 0;
  if (data && now - windowStart < PAIRING_ATTEMPT_WINDOW_MS) {
    return (data.count || 0) >= MAX_PAIRING_ATTEMPTS;
  }
  return false;
}

/**
 * Incrementa il contatore dei tentativi falliti, aprendo una nuova finestra se
 * la precedente è scaduta.
 * @param {string} alexaUserId
 * @return {Promise<void>}
 */
async function recordFailedAttempt(alexaUserId) {
  const ref = admin.firestore().collection("alexaLinkAttempts").doc(linkKey(alexaUserId));
  const now = Date.now();
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : null;
    const windowStart = data?.windowStart?.toMillis ? data.windowStart.toMillis() : 0;
    if (data && now - windowStart < PAIRING_ATTEMPT_WINDOW_MS) {
      tx.update(ref, {count: (data.count || 0) + 1});
    } else {
      tx.set(ref, {count: 1, windowStart: admin.firestore.Timestamp.fromMillis(now)});
    }
  });
}

/**
 * Consuma un codice di accoppiamento e crea il collegamento.
 * @param {string} alexaUserId
 * @param {string} code
 * @param {string|null} [personId] Voce riconosciuta, se c'è.
 * @return {Promise<boolean>} true se il codice era valido.
 */
async function consumePairingCode(alexaUserId, code, personId = null) {
  const db = admin.firestore();
  const pairingRef = db.collection("alexaPairings").doc(code);
  const linkRef = db.collection("alexaLinks").doc(linkKey(alexaUserId));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(pairingRef);
    if (!snap.exists) return false;
    const data = snap.data();
    if (data.usedAt) return false;
    const expiresAt = data.expiresAt?.toMillis ? data.expiresAt.toMillis() : 0;
    if (expiresAt < Date.now()) return false;

    // Se la voce è riconosciuta, lo stesso codice lega anche quella. È il modo
    // in cui un secondo membro si fa attribuire i propri articoli senza dover
    // collegare un account Amazon suo: gli basta dettare il proprio codice una
    // volta dall'Echo di casa.
    if (personId) {
      tx.set(db.collection("alexaPersonLinks").doc(linkKey(personId)), {
        uid: data.uid,
        familyId: data.familyId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    tx.set(linkRef, {
      alexaUserId,
      uid: data.uid,
      familyId: data.familyId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // Il codice si brucia all'uso: resta come traccia (chi/quando) finché non
    // lo raccoglie la pulizia, ma non è più spendibile.
    tx.update(pairingRef, {usedAt: admin.firestore.FieldValue.serverTimestamp(), usedByAlexa: linkKey(alexaUserId)});
    return true;
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SPESA
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Ref alla collezione della spesa di una famiglia.
 * Stesso percorso di GroceryRemoteStore (iOS) e Spesa.jsx (web): la skill è
 * solo un client in più sopra lo stesso documento, quindi ciò che detti a voce
 * compare in tempo reale sugli altri dispositivi e fa scattare la push di
 * `notifyNewGroceryItem`.
 * @param {string} familyId
 * @return {FirebaseFirestore.CollectionReference}
 */
function groceriesRef(familyId) {
  return admin.firestore().collection("families").doc(familyId).collection("groceries");
}

/**
 * Articoli ancora da comprare.
 * @param {string} familyId
 * @return {Promise<Array<{id: string, name: string}>>}
 */
async function pendingItems(familyId) {
  // Due filtri di sola uguaglianza: Firestore li serve dagli indici a campo
  // singolo, nessun indice composito da creare. L'ordinamento è in memoria
  // proprio per non introdurne uno.
  const snap = await groceriesRef(familyId)
      .where("isDeleted", "==", false)
      .where("isPurchased", "==", false)
      .get();

  return snap.docs
      .map((d) => ({id: d.id, name: d.data().name || "", createdAt: d.data().createdAt}))
      .filter((i) => i.name)
      .sort((a, b) => {
        const av = a.createdAt?.toMillis ? a.createdAt.toMillis() : 0;
        const bv = b.createdAt?.toMillis ? b.createdAt.toMillis() : 0;
        return av - bv;
      });
}

/**
 * Elenco parlato: "pane, latte e uova". La congiunzione finale non è un
 * vezzo — una lista letta con le sole virgole suona come se fosse troncata.
 * @param {string[]} names
 * @param {"it"|"en"} lang
 * @return {string}
 */
function spokenList(names, lang) {
  if (names.length <= 1) return names.join("");
  return `${names.slice(0, -1).join(", ")} ${SPEECH[lang].and} ${names[names.length - 1]}`;
}

/**
 * Aggiunge un articolo, saltando i duplicati già in lista.
 * @param {{uid: string, familyId: string, authorUid: string}} link
 * @param {string} rawName
 * @return {Promise<{added: boolean, name: string}>}
 */
async function addItem(link, rawName) {
  const name = displayItemName(rawName);
  const normalized = normalizeItemName(name);

  const existing = await pendingItems(link.familyId);
  const duplicate = existing.find((i) => normalizeItemName(i.name) === normalized);
  if (duplicate) return {added: false, name: duplicate.name};

  const id = crypto.randomUUID();
  await groceriesRef(link.familyId).doc(id).set({
    name,
    category: guessCategory(name),
    notes: null,
    quantity: null,
    isPurchased: false,
    isDeleted: false,
    purchasedAt: null,
    purchasedBy: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdBy: link.authorUid,
    updatedBy: link.authorUid,
  });
  return {added: true, name};
}

/**
 * Toglie un articolo dalla lista (soft delete, come fanno gli altri client).
 * @param {{uid: string, familyId: string, authorUid: string}} link
 * @param {string} rawName
 * @return {Promise<{removed: boolean, name: string}>}
 */
async function removeItem(link, rawName) {
  const normalized = normalizeItemName(rawName);
  const match = (await pendingItems(link.familyId))
      .find((i) => normalizeItemName(i.name) === normalized);
  if (!match) return {removed: false, name: displayItemName(rawName)};

  await groceriesRef(link.familyId).doc(match.id).set({
    isDeleted: true,
    updatedBy: link.authorUid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {removed: true, name: match.name};
}

/**
 * Segna un articolo come comprato.
 * @param {{uid: string, familyId: string, authorUid: string}} link
 * @param {string} rawName
 * @return {Promise<{checked: boolean, name: string}>}
 */
async function checkItem(link, rawName) {
  const normalized = normalizeItemName(rawName);
  const match = (await pendingItems(link.familyId))
      .find((i) => normalizeItemName(i.name) === normalized);
  if (!match) return {checked: false, name: displayItemName(rawName)};

  await groceriesRef(link.familyId).doc(match.id).set({
    isPurchased: true,
    purchasedAt: admin.firestore.FieldValue.serverTimestamp(),
    purchasedBy: link.authorUid,
    updatedBy: link.authorUid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
  return {checked: true, name: match.name};
}

// ─────────────────────────────────────────────────────────────────────────────
// PROMEMORIA A VOCE
// ─────────────────────────────────────────────────────────────────────────────
//
// Scrive un to-do in `families/{familyId}/todos`, dentro una lista chiamata
// "Alexa", e — se è stata detta una data — anche `remindAt`, che è l'ordine di
// suonare letto da `notifyDueTodoReminders` ogni 5 minuti.
//
// PERCHÉ IL DIALOGO È IN PIÙ TURNI, E NON UNA FRASE SOLA.
// `AMAZON.SearchQuery` è l'unico slot che accetta testo libero — serve per il
// titolo, che è una frase qualsiasi — ma Amazon lo ammette solo come ULTIMO
// elemento del sample e da SOLO: nessun altro slot può stare nella stessa
// frase. Quindi «ricordami di {task} e assegnalo a {member}» non è
// esprimibile, e non è un limite del nostro modello ma della piattaforma. Le
// due strade possibili sono due sample separati (uno col titolo, uno con
// l'assegnatario) oppure il multiturno. Qui si fa il multiturno: chiedere «a
// chi?» e «per quando?» costa due turni ma raccoglie i tre pezzi senza
// costringere l'utente a imparare due frasi diverse.
//
// PERCHÉ LA MACCHINA A STATI È NOSTRA E NON IL DIALOG MODEL DI AMAZON.
// Il Dialog model (elicitation + `Dialog.Delegate`) saprebbe chiedere gli slot
// mancanti da solo, ma non può elicitare uno `AMAZON.SearchQuery` — proprio lo
// slot che qui serve — e sposterebbe in console una logica che dipende dai
// membri della famiglia, che la console non conosce. Con `sessionAttributes`
// tutto lo stato sta in questo file, si legge in ordine e si prova a mano.
//
// I DUE CAMPI DEL MOTORE VANNO SEMPRE IN COPPIA, E SOLO SE C'È UN PROMEMORIA.
// Vedi `createReminderTodo`: è la parte che si sbaglia in silenzio.

/**
 * Campi calendariali di un istante, letti nel fuso di riferimento.
 *
 * Passa da `Intl` e non da `getHours()` perché il processo delle Functions gira
 * in UTC: `new Date().getHours()` a Roma in estate sbaglia di due ore, e non se
 * ne accorge nessuno finché un promemoria non suona a colazione invece che a
 * pranzo.
 * @param {number} ms Epoch in millisecondi.
 * @return {{y: number, mo: number, d: number, h: number, mi: number, s: number}}
 */
function tzFields(ms) {
  const text = new Intl.DateTimeFormat("sv-SE", {
    timeZone: TODO_TZ,
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    hourCycle: "h23",
  }).format(new Date(ms));
  const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/.exec(text);
  if (!m) throw new Error(`formato data inatteso: ${text}`);
  return {y: +m[1], mo: +m[2], d: +m[3], h: +m[4], mi: +m[5], s: +m[6]};
}

/**
 * Scarto fra il fuso di riferimento e UTC in un dato istante.
 * @param {number} ms
 * @return {number} Millisecondi da sommare a UTC per ottenere l'ora locale.
 */
function tzOffsetMs(ms) {
  const f = tzFields(ms);
  return Date.UTC(f.y, f.mo - 1, f.d, f.h, f.mi, f.s) - Math.floor(ms / 1000) * 1000;
}

/**
 * Istante corrispondente a una data e un'ora LOCALI del fuso di riferimento.
 *
 * Le due passate non sono prudenza: la prima usa l'offset dell'istante
 * sbagliato (quello letto come se fosse UTC), e nelle due notti del cambio
 * d'ora quello è l'offset dell'altro regime. Con una passata sola, un
 * promemoria per le 3 dell'ultima domenica di ottobre finisce un'ora fuori.
 * @param {number} y
 * @param {number} mo Mese 1-12.
 * @param {number} d
 * @param {number} h
 * @param {number} mi
 * @return {Date}
 */
function tzInstant(y, mo, d, h, mi) {
  const naive = Date.UTC(y, mo - 1, d, h, mi);
  const first = naive - tzOffsetMs(naive);
  return new Date(naive - tzOffsetMs(first));
}

/**
 * Orari convenzionali per i momenti della giornata che `AMAZON.TIME` non
 * risolve in un'ora precisa: «domani mattina» arriva come `MO`, non come
 * `09:00`. Senza questa tabella metà delle frasi naturali cadrebbe nel ramo
 * "non ho capito quando".
 */
const TIME_OF_DAY = {MO: [9, 0], AF: [15, 0], EV: [20, 0], NI: [22, 0]};

/**
 * Data detta a voce, se è un giorno preciso.
 *
 * `AMAZON.DATE` risolve anche cose che un giorno preciso non sono — «questa
 * settimana» dà `2026-W38`, «a settembre» dà `2026-09`, «adesso» dà
 * `PRESENT_REF`. Si accetta solo `YYYY-MM-DD`: da un intervallo non si ricava
 * un istante senza inventarselo, ed è meglio richiedere che indovinare.
 * @param {string} raw
 * @return {{y: number, mo: number, d: number}|null}
 */
function parseSpokenDate(raw) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(raw || "").trim());
  if (!m) return null;
  return {y: +m[1], mo: +m[2], d: +m[3]};
}

/**
 * Ora detta a voce, in ore e minuti.
 * @param {string} raw
 * @return {{h: number, mi: number}|null}
 */
function parseSpokenTime(raw) {
  const value = String(raw || "").trim().toUpperCase();
  if (TIME_OF_DAY[value]) {
    return {h: TIME_OF_DAY[value][0], mi: TIME_OF_DAY[value][1]};
  }
  const m = /^(\d{1,2}):(\d{2})/.exec(value);
  if (!m) return null;
  const h = +m[1];
  const mi = +m[2];
  if (h > 23 || mi > 59) return null;
  return {h, mi};
}

/**
 * Trasforma gli slot `date` e `time` nell'istante in cui suonare.
 *
 * Le regole sui pezzi mancanti, tutte pensate perché la risposta resti sempre
 * confermabile ad alta voce — l'utente sente cosa è stato capito:
 *   - giorno senza ora   → `DEFAULT_REMIND_HOUR` di quel giorno;
 *   - ora senza giorno   → oggi se non è ancora passata, altrimenti domani.
 *     È l'interpretazione ovvia di «alle otto» detto alle nove di sera, e
 *     l'unica che non produce un promemoria già scaduto in partenza;
 *   - niente             → nessun promemoria, il to-do resta e basta.
 * @param {string} dateRaw
 * @param {string} timeRaw
 * @param {number} nowMs
 * @return {{status: "none"|"unclear"|"past"|"ok", at?: Date}}
 */
function resolveRemindAt(dateRaw, timeRaw, nowMs) {
  const hasDate = String(dateRaw || "").trim() !== "";
  const hasTime = String(timeRaw || "").trim() !== "";
  if (!hasDate && !hasTime) return {status: "none"};

  const date = hasDate ? parseSpokenDate(dateRaw) : null;
  const time = hasTime ? parseSpokenTime(timeRaw) : null;
  // Detto ma non capito è diverso da non detto: «questa settimana» deve far
  // richiedere, non far cadere silenziosamente il promemoria.
  if ((hasDate && !date) || (hasTime && !time)) return {status: "unclear"};

  const today = tzFields(nowMs);
  const day = date || {y: today.y, mo: today.mo, d: today.d};
  const clock = time || {h: DEFAULT_REMIND_HOUR, mi: 0};

  let at = tzInstant(day.y, day.mo, day.d, clock.h, clock.mi);
  if (!date && at.getTime() <= nowMs) {
    // Solo l'ora, e per oggi è già passata: si intende domani.
    at = tzInstant(day.y, day.mo, day.d + 1, clock.h, clock.mi);
  }
  if (at.getTime() <= nowMs) return {status: "past"};
  return {status: "ok", at};
}

/**
 * Come si dice ad alta voce il momento del promemoria: «domani alle 18:30».
 *
 * L'ora resta in cifre a due posizioni perché la TTS la legge già bene («alle
 * 09:00» → «alle nove») e perché scriverla a parole in italiano vuol dire
 * gestire «all'una», che è l'unico caso in cui l'articolo cambia.
 * @param {Date} at
 * @param {number} nowMs
 * @param {"it"|"en"} lang
 * @return {string}
 */
function spokenWhen(at, nowMs, lang) {
  const t = SPEECH[lang];
  const locale = lang === "en" ? "en-GB" : "it-IT";
  const target = tzFields(at.getTime());
  const today = tzFields(nowMs);
  const dayKey = (f) => `${f.y}-${f.mo}-${f.d}`;
  const tomorrow = tzFields(tzInstant(today.y, today.mo, today.d + 1, 12, 0).getTime());

  let day;
  if (dayKey(target) === dayKey(today)) {
    day = t.remindToday;
  } else if (dayKey(target) === dayKey(tomorrow)) {
    day = t.remindTomorrow;
  } else {
    day = new Intl.DateTimeFormat(locale, {
      timeZone: TODO_TZ, weekday: "long", day: "numeric", month: "long",
    }).format(at);
  }
  const clock = `${String(target.h).padStart(2, "0")}:${String(target.mi).padStart(2, "0")}`;
  return t.remindAt(day, clock);
}

/**
 * Titolo del to-do come va scritto.
 *
 * Diverso da `displayItemName` di proposito: lì l'articolo iniziale si toglie
 * perché in una lista della spesa si scrive «Latte», non «Il latte». Qui il
 * titolo è una frase, e togliere l'articolo la storpia — «ricordami la
 * riunione con la maestra» diventerebbe «Riunione con la maestra», che passa,
 * ma «ricordami l'esame di Anna» diventerebbe «Esame di Anna» perdendo il
 * senso di quale esame. Si tolgono solo gli spazi doppi e si alza l'iniziale,
 * perché l'ASR consegna tutto minuscolo.
 * @param {string} raw
 * @return {string}
 */
function displayTodoTitle(raw) {
  const clean = String(raw || "").replace(/\s+/g, " ").trim();
  if (!clean) return "";
  return clean.charAt(0).toUpperCase() + clean.slice(1);
}

// ── Momento detto dentro il titolo ──────────────────────────────────────────
//
// «ricordami di pagare la mensa domani alle otto» consegna a `task` TUTTA la
// frase, data compresa: `AMAZON.SearchQuery` prende quello che trova e non
// esiste modo di dirgli dove fermarsi. Il titolo nasceva quindi «Pagare la
// mensa domani alle otto», e il momento andava ridetto al turno dopo.
//
// La regola che rende sicuro tagliare: **si toglie dal titolo SOLO ciò che si è
// riusciti a trasformare in una data.** Non è una raffinatezza, è ciò che
// elimina i due modi di sbagliare in un colpo solo:
//   - non si taglia mai un pezzo di titolo legittimo, perché quello che non si
//     capisce non si tocca;
//   - non si perde mai un momento detto, perché ciò che si taglia diventa
//     `remindAt` — e se poi risulta impossibile (già passato) si torna a
//     chiedere invece di ingoiarlo.
//
// L'uscita ha la forma degli slot `AMAZON.DATE` e `AMAZON.TIME` di proposito:
// così il momento estratto dal titolo e quello detto rispondendo a «per
// quando?» passano dalla STESSA `resolveRemindAt`. Una regola sola sui pezzi
// mancanti, una sola sul passato, un solo insieme di test.
//
// Solo italiano: il modello di interazione con questi intent esiste solo in
// it-IT, e una grammatica inglese scritta a occhi chiusi taglierebbe titoli
// veri per riconoscere frasi che nessuno può pronunciare.

/** Numeri a lettere che possono comparire in un orario, 1-24. */
const HOUR_WORDS = {
  "una": 1, "uno": 1, "due": 2, "tre": 3, "quattro": 4, "cinque": 5,
  "sei": 6, "sette": 7, "otto": 8, "nove": 9, "dieci": 10, "undici": 11,
  "dodici": 12, "tredici": 13, "quattordici": 14, "quindici": 15,
  "sedici": 16, "diciassette": 17, "diciotto": 18, "diciannove": 19,
  "venti": 20, "ventuno": 21, "ventidue": 22, "ventitre": 23,
  "ventitré": 23, "ventiquattro": 24,
};
const HOUR_WORD_ALT = Object.keys(HOUR_WORDS).join("|");

/** Mesi, per «il 15 settembre». */
const MONTHS = [
  "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno",
  "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre",
];

/** Giorni della settimana, indice 0 = domenica come `Date.getUTCDay()`. */
const WEEKDAYS = [
  "domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato",
];

/**
 * Momenti della giornata, nei codici che `AMAZON.TIME` userebbe: così
 * `parseSpokenTime` li risolve già e non serve una seconda tabella di orari.
 */
const DAYPART_CODE = {
  mattina: "MO", mattino: "MO", stamattina: "MO", stamane: "MO",
  pomeriggio: "AF",
  sera: "EV", stasera: "EV",
  notte: "NI", stanotte: "NI",
};

/** Minuti delle frazioni d'ora dette a parole. */
const FRACTIONS = {"mezza": 30, "mezzo": 30, "un quarto": 15, "tre quarti": 45};

/**
 * Data nella forma dello slot `AMAZON.DATE`.
 * Il giro da `Date.UTC` normalizza gli sconfinamenti — «+1 giorno» il 31
 * dicembre deve dare il 1° gennaio dell'anno dopo, non il 32 dicembre.
 * @param {number} y
 * @param {number} mo Mese 1-12.
 * @param {number} d
 * @return {string} `YYYY-MM-DD`.
 */
function dateSlot(y, mo, d) {
  const at = new Date(Date.UTC(y, mo - 1, d));
  return at.toISOString().slice(0, 10);
}

/**
 * Ora nella forma dello slot `AMAZON.TIME`.
 * @param {number} h
 * @param {number} mi
 * @return {string} `HH:MM`.
 */
function timeSlot(h, mi) {
  return `${String(h).padStart(2, "0")}:${String(mi).padStart(2, "0")}`;
}

/**
 * Ore da un gruppo di regex che può essere cifre o parola.
 * @param {string} raw
 * @return {number|null}
 */
function hourFrom(raw) {
  const word = String(raw || "").toLowerCase();
  if (Object.prototype.hasOwnProperty.call(HOUR_WORDS, word)) return HOUR_WORDS[word];
  const n = Number(word);
  return Number.isInteger(n) && n >= 0 && n <= 24 ? n : null;
}

/**
 * Coda oraria: «alle otto», «alle 8:30», «alle sette e mezza», «a mezzogiorno»,
 * «di sera», «stasera».
 */
const TAIL_TIME = new RegExp(
    "(?:^|\\s)(?:" +
    // «a mezzogiorno» / «a mezzanotte»
    "(?<midday>a\\s+mezzogiorno|a\\s+mezzanotte)" +
    "|" +
    // «alle 8», «alle otto e mezza», «per le 20:30», «all'una»
    "(?:alle|all['’]|a\\s+le|per\\s+le|verso\\s+le)\\s*" +
    `(?<hour>\\d{1,2}|${HOUR_WORD_ALT})` +
    "(?:\\s*[:.]\\s*(?<min>\\d{2})|\\s+e\\s+(?<frac>mezza|mezzo|un\\s+quarto|tre\\s+quarti))?" +
    "(?:\\s+in\\s+punto)?" +
    "|" +
    // «di sera», «del pomeriggio», «stasera»
    "(?:(?:di|del|della|la|in)\\s+)?(?<part>mattina|mattino|pomeriggio|sera|notte|stamattina|stamane|stasera|stanotte)" +
    ")\\s*$", "i");

/**
 * Coda del giorno: «domani», «giovedì», «il 15 settembre», «fra due ore».
 */
const TAIL_DAY = new RegExp(
    "(?:^|\\s)(?:" +
    "(?<rel>dopodomani|domani|oggi|stamattina|stamane|stasera|stanotte)" +
    "|" +
    `(?:(?:questo|questa|il|lo|la)\\s+)?(?<wd>${WEEKDAYS.join("|")})(?:\\s+(?:prossimo|prossima))?` +
    "|" +
    `(?:il\\s+|lo\\s+)?(?<dom>\\d{1,2}|primo)\\s+(?<month>${MONTHS.join("|")})` +
    "|" +
    // Lo spazio fra quantità e unità è `\\s*` e non `\\s+`: in «un'ora» e
    // «mezz'ora» l'apostrofo fa già da confine e spazio non ce n'è.
    "(?:fra|tra)\\s+(?<qty>\\d{1,3}|un['’]|mezz['’]|" + HOUR_WORD_ALT + ")\\s*(?<unit>minuti|minuto|ore|ora|giorni|giorno|settimane|settimana)" +
    ")\\s*$", "i");

/**
 * Preposizione che trasforma un giorno da momento in aggettivo del titolo.
 * Si guarda il testo che PRECEDE il pezzo temporale, apostrofi inclusi.
 */
const ADJECTIVAL_DAY = /(?:^|\s)(?:di|del|dello|della|dell['’])\s*$/i;

/** Connettivi che restano appesi in coda dopo aver tolto un pezzo temporale. */
const TAIL_CONNECTOR = /(?:^|\s)(?:di|del|dello|della|per|entro|verso)\s*$/i;

/**
 * Estrae dal titolo il momento detto, se c'è, e restituisce il titolo ripulito.
 *
 * Si consuma da destra e a giri: «domani alle otto» toglie prima l'ora e poi il
 * giorno, «alle otto di domani» prima il giorno e poi l'ora più il connettivo.
 * Un solo ordine non basterebbe, e due grammatiche separate per i due ordini
 * sarebbero due cose da tenere allineate.
 *
 * Se dopo il taglio non resta niente, si annulla tutto e il titolo torna quello
 * di partenza: «ricordami domani» vuol dire che il titolo È «domani», per
 * quanto strano, e un to-do senza titolo non lo vuole nessuno.
 * @param {string} raw Titolo grezzo dallo slot `task`.
 * @param {number} nowMs
 * @return {{title: string, date: string, time: string}}
 */
function extractWhenFromTitle(raw, nowMs) {
  let rest = String(raw || "").replace(/\s+/g, " ").trim();
  const original = rest;
  const now = tzFields(nowMs);

  let date = "";
  let time = "";
  // Alcune parole («stasera») dicono giorno e ora insieme: il codice del
  // momento della giornata va ricordato anche quando a matchare è stato il
  // ramo del giorno.
  let pendingPart = "";

  for (let pass = 0; pass < 4; pass++) {
    let consumed = false;

    if (!time) {
      const m = TAIL_TIME.exec(rest);
      if (m) {
        const g = m.groups;
        if (g.midday) {
          time = /mezzanotte/i.test(g.midday) ? "00:00" : "12:00";
        } else if (g.part) {
          time = DAYPART_CODE[g.part.toLowerCase()];
          if (/^sta/i.test(g.part)) pendingPart = "oggi";
        } else {
          const h = hourFrom(g.hour);
          if (h === null) break;
          const mi = g.min ? Number(g.min) :
            (g.frac ? FRACTIONS[g.frac.toLowerCase().replace(/\s+/g, " ")] : 0);
          if (mi > 59) break;
          time = timeSlot(h % 24, mi);
        }
        rest = rest.slice(0, m.index).trim();
        consumed = true;
      }
    }

    if (!date) {
      const m = TAIL_DAY.exec(rest);
      // «il giornale di oggi», «la lezione di giovedì»: dopo un `di` il giorno
      // qualifica il titolo invece di datarlo, e tagliarlo storpierebbe il
      // to-do. Ma in «alle otto di domani» quello stesso `di` è il legame fra
      // ora e giorno: a distinguerli è cosa sta PRIMA della preposizione — un
      // orario, o una parola qualunque del titolo. Non basta chiedersi se
      // un'ora è già stata consumata, perché qui l'ora sta a monte del `di` e
      // il giro che consuma da destra non l'ha ancora vista.
      const beforeDay = m ? rest.slice(0, m.index + 1) : "";
      const conn = m ? ADJECTIVAL_DAY.exec(beforeDay) : null;
      const adjectival = !!conn && !TAIL_TIME.test(beforeDay.slice(0, conn.index));
      if (m && !adjectival) {
        const g = m.groups;
        const resolved = resolveDayGroups(g, now, nowMs, time);
        if (resolved) {
          date = resolved.date;
          if (resolved.time && !time) time = resolved.time;
          if (resolved.part && !time) time = resolved.part;
          rest = rest.slice(0, m.index).trim();
          consumed = true;
        }
      }
    }

    if (consumed) {
      const c = TAIL_CONNECTOR.exec(rest);
      if (c) rest = rest.slice(0, c.index).trim();
    } else {
      break;
    }
  }

  if (pendingPart === "oggi" && !date) {
    date = dateSlot(now.y, now.mo, now.d);
  }
  // Niente riconosciuto, o riconosciuto tutto: il titolo resta com'era e il
  // momento si chiede al turno dopo, come prima.
  if ((!date && !time) || !rest) {
    return {title: original, date: "", time: ""};
  }
  return {title: rest, date, time};
}

/**
 * Traduce i gruppi catturati dal ramo "giorno" in una data.
 *
 * Il giorno della settimana e il giorno del mese si risolvono SEMPRE in avanti:
 * «giovedì» detto di giovedì sera vuol dire il giovedì prossimo, non quello
 * appena passato. L'ora già estratta serve proprio a decidere questo, ed è il
 * motivo per cui l'ora si consuma prima del giorno.
 * @param {object} g Gruppi della regex.
 * @param {object} now Campi calendariali di adesso nel fuso di riferimento.
 * @param {number} nowMs
 * @param {string} knownTime Ora già estratta, in forma di slot, o "".
 * @return {{date: string, time?: string, part?: string}|null}
 */
function resolveDayGroups(g, now, nowMs, knownTime) {
  if (g.rel) {
    const word = g.rel.toLowerCase();
    const shift = word === "domani" ? 1 : (word === "dopodomani" ? 2 : 0);
    const out = {date: dateSlot(now.y, now.mo, now.d + shift)};
    if (DAYPART_CODE[word]) out.part = DAYPART_CODE[word];
    return out;
  }

  if (g.wd) {
    const want = WEEKDAYS.indexOf(g.wd.toLowerCase());
    if (want < 0) return null;
    const clock = parseSpokenTime(knownTime) || {h: DEFAULT_REMIND_HOUR, mi: 0};
    for (let k = 0; k < 8; k++) {
      const probe = new Date(Date.UTC(now.y, now.mo - 1, now.d + k));
      if (probe.getUTCDay() !== want) continue;
      const at = tzInstant(probe.getUTCFullYear(), probe.getUTCMonth() + 1,
          probe.getUTCDate(), clock.h, clock.mi);
      if (at.getTime() > nowMs) return {date: dateSlot(now.y, now.mo, now.d + k)};
    }
    return null;
  }

  if (g.dom && g.month) {
    const day = /primo/i.test(g.dom) ? 1 : Number(g.dom);
    const month = MONTHS.indexOf(g.month.toLowerCase()) + 1;
    if (!day || day > 31 || month < 1) return null;
    const clock = parseSpokenTime(knownTime) || {h: DEFAULT_REMIND_HOUR, mi: 0};
    // Senza anno si intende il prossimo passaggio: «il 3 gennaio» detto a
    // dicembre è l'anno dopo, non dieci mesi fa.
    for (const y of [now.y, now.y + 1]) {
      if (tzInstant(y, month, day, clock.h, clock.mi).getTime() > nowMs) {
        return {date: dateSlot(y, month, day)};
      }
    }
    return null;
  }

  if (g.qty && g.unit) {
    const unit = g.unit.toLowerCase();
    const raw = g.qty.replace(/['’]$/, "");
    const qty = /^mezz/i.test(raw) ? 0.5 : (/^un$/i.test(raw) ? 1 : hourFrom(raw));
    if (qty === null || qty <= 0) return null;
    const perUnit = unit.startsWith("minut") ? 60000 :
      (unit.startsWith("or") ? 3600000 :
        (unit.startsWith("giorn") ? 86400000 : 604800000));
    const at = tzFields(nowMs + qty * perUnit);
    return {
      date: dateSlot(at.y, at.mo, at.d),
      // Un «fra» è un istante, non un giorno: l'ora fa parte della risposta e
      // non va sostituita dalle 9 di default.
      time: timeSlot(at.h, at.mi),
    };
  }

  return null;
}

/**
 * Forma confrontabile di un nome di persona: senza accenti, senza
 * punteggiatura, minuscola.
 *
 * NON riusa `normalizeItemName`: quella toglie anche l'articolo iniziale, e
 * fra gli articoli c'è `a`. Un membro che si chiama «Aurora» resterebbe
 * «Aurora» (l'articolo vuole lo spazio dopo), ma la regola è troppo vicina al
 * disastro per condividerla — e sui nomi non c'è nessun articolo da togliere.
 * @param {string} raw
 * @return {string}
 */
function normalizePersonName(raw) {
  return String(raw || "")
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
}

/**
 * Preposizione iniziale che l'ASR lascia dentro lo slot quando la frase la
 * contiene ma il sample no («assegnalo a Marco» → a volte «a marco»).
 */
const LEADING_PREPOSITION = /^(?:a|ad|al|allo|alla|ai|agli|alle|per|to|for)\s+/;

/**
 * Membri della famiglia con un nome pronunciabile.
 *
 * La lettura di ripiego su `users/{uid}` non è difensiva: i documenti in
 * `members` possono non avere `displayName` — è la stessa ragione per cui
 * `memberName` e `resolveMemberName` in `index.js` hanno lo stesso ripiego. Una
 * famiglia ha pochi membri, quindi il costo è qualche lettura per richiesta e
 * solo per chi non ha il nome in `members`.
 * @param {string} familyId
 * @return {Promise<Array<{uid: string, name: string}>>}
 */
async function familyMembers(familyId) {
  const snap = await admin.firestore()
      .collection("families").doc(familyId).collection("members").get();
  const out = [];
  for (const doc of snap.docs) {
    if (doc.get("isDeleted") === true) continue;
    let name = doc.get("displayName") || doc.get("name") || "";
    if (!name) {
      const user = await admin.firestore().collection("users").doc(doc.id).get();
      name = user.exists ? (user.get("displayName") || user.get("name") || "") : "";
    }
    name = String(name || "").trim();
    if (name) out.push({uid: doc.id, name});
  }
  return out;
}

/**
 * Trova il membro corrispondente a un nome detto a voce.
 *
 * Tre passate, dalla più stretta alla più larga, e a ogni passata si accetta
 * SOLO se il candidato è uno. È la parte che decide cosa succede coi nomi
 * simili, e la regola è: al primo dubbio si chiede, non si sceglie.
 *   1. nome completo uguale — distingue «Marco» da «Marco Rossi» quando
 *      esistono entrambi, perché il primo fa match esatto e il secondo no;
 *   2. primo nome uguale — in famiglia il cognome quasi non si dice;
 *   3. primo nome che comincia per quello detto — recupera i troncamenti
 *      dell'ASR («Ale» per «Alessandra»), ma solo se resta uno solo.
 *
 * `ambiguous` non è un errore da nascondere: due «Marco» in famiglia sono
 * indistinguibili a voce e nessuna euristica può risolverli. Meglio dirlo e
 * lasciare che l'assegnazione si faccia dall'app.
 * @param {string} spoken
 * @param {Array<{uid: string, name: string}>} members
 * @return {{status: "ok"|"ambiguous"|"none", member?: object, candidates?: Array<object>}}
 */
function matchMember(spoken, members) {
  const query = normalizePersonName(String(spoken || "").replace(LEADING_PREPOSITION, ""));
  if (!query) return {status: "none"};

  const firstNameOf = (m) => normalizePersonName(m.name).split(" ")[0];
  const passes = [
    members.filter((m) => normalizePersonName(m.name) === query),
    members.filter((m) => firstNameOf(m) === query),
    members.filter((m) => firstNameOf(m).startsWith(query)),
  ];
  for (const hits of passes) {
    if (hits.length === 1) return {status: "ok", member: hits[0]};
    if (hits.length > 1) return {status: "ambiguous", candidates: hits};
  }
  return {status: "none"};
}

/**
 * Id della lista "Alexa" della famiglia, creandola se non c'è.
 *
 * Il confronto è sul nome normalizzato e non sull'id perché la lista può
 * essere stata creata a mano dall'app: cercarla per nome è l'unico modo di non
 * crearne una seconda identica. Il to-do senza `listId` valido sarebbe orfano —
 * esiste su Firestore, i riepiloghi lo contano, il motore lo notifica, ma
 * nessuna schermata lo mostra perché iOS e Android elencano i to-do DENTRO le
 * liste. Stessa ragione per cui esiste `resolveTodoListId` nella webapp.
 *
 * I campi scritti sono esattamente quelli di `NewListModal.jsx`: una lista con
 * campi in meno viene filtrata via da `where("isDeleted", "==", false)`.
 * @param {string} familyId
 * @param {string} authorUid
 * @return {Promise<string>}
 */
async function ensureAlexaTodoList(familyId, authorUid) {
  const col = admin.firestore()
      .collection("families").doc(familyId).collection("todoLists");
  const snap = await col.where("isDeleted", "==", false).get();
  const wanted = normalizePersonName(ALEXA_TODO_LIST_NAME);
  const found = snap.docs.find(
      (d) => normalizePersonName(d.get("name") || "") === wanted);
  if (found) return found.id;

  const id = crypto.randomUUID();
  await col.doc(id).set({
    childId: "",
    name: ALEXA_TODO_LIST_NAME,
    isDeleted: false,
    updatedBy: authorUid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  logger.info("alexaSkill: lista Alexa creata", {familyId, listId: id});
  return id;
}

/**
 * Scrive il to-do dettato, con o senza promemoria.
 *
 * ⚠️ I DUE CAMPI DEL MOTORE, che sono la parte facile da sbagliare in silenzio.
 *
 * `notifyDueTodoReminders` interroga `remindSentAt == null` E
 * `remindAt <= now`. Da questo discendono due regole opposte, e servono
 * entrambe:
 *
 *   1. CON promemoria: `remindSentAt: null` va scritto ESPLICITO. In Firestore
 *      un campo assente non è `null`: il documento non entrerebbe nell'indice
 *      composto e resterebbe invisibile alla query per sempre, senza errori e
 *      senza una riga di log. Il promemoria semplicemente non suona mai.
 *
 *   2. SENZA promemoria: i due campi NON vanno scritti affatto, nemmeno a
 *      `null`. Le query di intervallo di Firestore attraversano i tipi, e nel
 *      loro ordinamento `null` viene PRIMA di qualunque Timestamp: un
 *      documento con `remindAt: null` soddisfa `remindAt <= now` ed entra
 *      nella query. Risultato: un to-do per cui nessuno ha chiesto niente fa
 *      partire una notifica al primo giro dello scheduler. È l'immagine
 *      speculare del punto 1 — lì il campo assente nasconde, qui il campo
 *      presente a `null` espone — ed è il motivo per cui questi campi si
 *      aggiungono all'oggetto invece di stare nel letterale.
 *
 * Gli altri campi sono quelli di `TodoEditModal.jsx`: la skill è un client come
 * gli altri sopra la stessa collezione.
 * @param {{familyId: string, authorUid: string}} link
 * @param {{title: string, assignedTo: string, remindAt: Date|null}} data
 * @return {Promise<{id: string, listId: string}>}
 */
async function createReminderTodo(link, {title, assignedTo, remindAt}) {
  const listId = await ensureAlexaTodoList(link.familyId, link.authorUid);
  const id = crypto.randomUUID();

  const payload = {
    childId: "",
    title,
    listId,
    isDone: false,
    isDeleted: false,
    notes: null,
    // `dueAt` è la scadenza mostrata in app, `remindAt` l'ordine di suonare.
    // Detto a voce sono la stessa cosa, ma restano due campi: chi poi sposta la
    // scadenza dall'app non deve per forza spostare anche la sveglia.
    dueAt: remindAt || null,
    assignedTo: assignedTo || "",
    priority: 0,
    visibilityScope: "family",
    visibilityMemberIds: [],
    doneAt: null,
    doneBy: null,
    createdBy: link.authorUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedBy: link.authorUid,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (remindAt) {
    payload.remindAt = admin.firestore.Timestamp.fromDate(remindAt);
    payload.remindSentAt = null;
  }

  await admin.firestore()
      .collection("families").doc(link.familyId)
      .collection("todos").doc(id).set(payload);
  logger.info("alexaSkill: promemoria creato", {
    familyId: link.familyId,
    todoId: id,
    listId,
    assegnato: assignedTo ? "sì" : "no",
    remindAt: remindAt ? remindAt.toISOString() : null,
  });
  return {id, listId};
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOGO DEL PROMEMORIA
// ─────────────────────────────────────────────────────────────────────────────

/** Chiave del flusso negli attributi di sessione. */
const REMINDER_FLOW = "reminder";

/**
 * Stato del promemoria in costruzione, o null se non ce n'è uno.
 * @param {object} body
 * @return {{stage: string, title: string, assignedTo: string, assigneeName: string}|null}
 */
function reminderState(body) {
  const attrs = body?.session?.attributes;
  if (!attrs || attrs.flow !== REMINDER_FLOW) return null;
  return {
    stage: String(attrs.stage || ""),
    title: String(attrs.title || ""),
    assignedTo: String(attrs.assignedTo || ""),
    assigneeName: String(attrs.assigneeName || ""),
    // Momento già detto dentro la frase iniziale, in forma di slot. Se c'è, la
    // domanda «per quando?» non si fa: sarebbe richiedere una cosa appena
    // sentita, che è il modo più veloce di far sembrare stupido un assistente.
    date: String(attrs.date || ""),
    time: String(attrs.time || ""),
  };
}

/**
 * Gli attributi da rimandare indietro per ritrovare lo stato al turno dopo.
 * @param {object} state
 * @param {string} stage
 * @return {object}
 */
function reminderAttrs(state, stage) {
  return {
    flow: REMINDER_FLOW,
    stage,
    title: state.title,
    assignedTo: state.assignedTo,
    assigneeName: state.assigneeName,
    date: state.date || "",
    time: state.time || "",
  };
}

/**
 * Chiude il flusso: scrive il to-do e dice cosa è stato salvato.
 *
 * La conferma nomina sempre tutti i pezzi capiti — titolo, destinatario,
 * momento — perché è l'unico controllo che l'utente ha: a voce non c'è una
 * schermata da rileggere, e un promemoria capito male si scopre quando non
 * suona.
 * @param {object} link
 * @param {object} state
 * @param {Date|null} remindAt
 * @param {object} t
 * @param {"it"|"en"} lang
 * @param {number} nowMs
 * @return {Promise<object>}
 */
async function finishReminder(link, state, remindAt, t, lang, nowMs) {
  await createReminderTodo(link, {
    title: state.title,
    assignedTo: state.assignedTo,
    remindAt,
  });

  const who = state.assigneeName;
  if (!remindAt) {
    return speak(who ? t.remindDoneFor(state.title, who) : t.remindDone(state.title));
  }
  const when = spokenWhen(remindAt, nowMs, lang);
  return speak(who ?
    t.remindDoneForAt(state.title, who, when) :
    t.remindDoneAt(state.title, when));
}

/**
 * Primo turno: «ricordami di comprare il pane».
 * @param {object} body
 * @param {object} t
 * @return {object}
 */
function startReminder(body, t, lang) {
  // L'estrazione precede la ripulitura: la maiuscola iniziale va messa sul
  // titolo DEFINITIVO, non su uno che poi perde la coda.
  const raw = slotValue(body.request.intent, "task");
  const parsed = lang === "it" ?
    extractWhenFromTitle(raw, Date.now()) :
    {title: raw, date: "", time: ""};
  const title = displayTodoTitle(parsed.title);
  if (!title) {
    // La sessione resta aperta e il reprompt chiede la frase INTERA, non solo
    // il titolo: il titolo da solo non ha un intent che lo raccolga, perché un
    // sample fatto del solo `{task}` intercetterebbe qualunque cosa si dica
    // nella skill, «aggiungi il latte» compreso.
    return speak(t.remindAskTitle, false, t.remindAskTitle,
        {flow: REMINDER_FLOW, stage: "title", title: "", assignedTo: "",
          assigneeName: "", date: "", time: ""});
  }
  const state = {title, assignedTo: "", assigneeName: "",
    date: parsed.date, time: parsed.time};
  return speak(t.remindAskAssignee(title), false, t.remindAskAssignee(title),
      reminderAttrs(state, "assignee"));
}

/**
 * Passo dopo l'assegnatario: chiedere il momento, o chiudere se era già dentro
 * la frase iniziale.
 *
 * Quando il momento estratto non regge — non risolvibile, oppure già passato —
 * si torna a chiedere, ma il titolo resta ripulito e gli slot estratti si
 * buttano: tenerli farebbe ripetere lo stesso errore a ogni giro.
 * @param {object} link
 * @param {object} state
 * @param {object} t
 * @param {"it"|"en"} lang
 * @return {Promise<object>}
 */
async function askWhenOrFinish(link, state, t, lang) {
  const nowMs = Date.now();
  if (state.date || state.time) {
    const resolved = resolveRemindAt(state.date, state.time, nowMs);
    if (resolved.status === "ok") {
      return finishReminder(link, state, resolved.at, t, lang, nowMs);
    }
    const clean = {...state, date: "", time: ""};
    return speak(
        resolved.status === "past" ? t.remindWhenPast : t.remindAskWhen,
        false, t.remindAskWhen, reminderAttrs(clean, "when"));
  }
  return speak(t.remindAskWhen, false, t.remindAskWhen, reminderAttrs(state, "when"));
}

/**
 * Turno dell'assegnatario.
 * @param {object} body
 * @param {object} link
 * @param {object} state
 * @param {object} t
 * @param {"it"|"en"} lang
 * @return {Promise<object>}
 */
async function handleReminderAssignee(body, link, state, t, lang) {
  if (!state.title) {
    return speak(t.remindAskTitle, false, t.remindAskTitle, reminderAttrs(state, "title"));
  }
  const spoken = slotValue(body.request.intent, "member");
  const members = await familyMembers(link.familyId);

  if (members.length === 0) {
    // Nessun nome leggibile: non è il caso di insistere con una domanda a cui
    // l'utente non può rispondere. Si tira dritto senza assegnatario, che è
    // comunque un promemoria che raggiunge tutta la famiglia.
    return askWhenOrFinish(link, state, t, lang);
  }

  const match = matchMember(spoken, members);
  const names = spokenList(members.map((m) => m.name), lang);

  if (match.status === "none") {
    return speak(t.remindMemberUnknown(spoken || "", names), false, t.remindAskAssignee(state.title),
        reminderAttrs(state, "assignee"));
  }
  if (match.status === "ambiguous") {
    return speak(
        t.remindMemberAmbiguous(spokenList(match.candidates.map((m) => m.name), lang)),
        false, t.remindAskAssignee(state.title),
        reminderAttrs(state, "assignee"));
  }

  const next = {...state, assignedTo: match.member.uid, assigneeName: match.member.name};
  return askWhenOrFinish(link, next, t, lang);
}

/**
 * Turno della data e dell'ora.
 * @param {object} body
 * @param {object} link
 * @param {object} state
 * @param {object} t
 * @param {"it"|"en"} lang
 * @return {Promise<object>}
 */
async function handleReminderWhen(body, link, state, t, lang) {
  if (!state.title) {
    return speak(t.remindAskTitle, false, t.remindAskTitle, reminderAttrs(state, "title"));
  }
  const nowMs = Date.now();
  const intent = body.request.intent;
  const resolved = resolveRemindAt(
      slotValue(intent, "date"), slotValue(intent, "time"), nowMs);

  if (resolved.status === "unclear") {
    return speak(t.remindWhenUnclear, false, t.remindAskWhen, reminderAttrs(state, "when"));
  }
  if (resolved.status === "past") {
    return speak(t.remindWhenPast, false, t.remindAskWhen, reminderAttrs(state, "when"));
  }
  // "none" qui significa che l'utente ha risposto senza dire nulla di
  // temporale: il to-do si salva comunque, senza sveglia.
  return finishReminder(link, state, resolved.at || null, t, lang, nowMs);
}

// ─────────────────────────────────────────────────────────────────────────────
// DISPATCH DEGLI INTENT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Valore di uno slot, già ripulito.
 * @param {object} intent
 * @param {string} slotName
 * @return {string}
 */
function slotValue(intent, slotName) {
  return String(intent?.slots?.[slotName]?.value || "").trim();
}

/**
 * Gestisce l'intent di collegamento.
 * @param {object} body
 * @param {string} alexaUserId
 * @param {object} t
 * @return {Promise<object>}
 */
async function handleLink(body, alexaUserId, t) {
  const personId = personIdOf(body);
  const accountLink = await resolveLink(alexaUserId);
  const voiceUid = accountLink ?
    await resolveVoiceUid(personId, accountLink.familyId) :
    null;

  // "Già collegato" solo se non c'è più niente da legare. Con la voce
  // riconosciuta e non ancora associata il codice serve eccome: è così che un
  // secondo membro si fa attribuire i propri articoli, senza collegare un
  // account Amazon suo. Prima questo ramo lo bloccava sul nascere.
  if (accountLink && (!personId || voiceUid)) {
    logger.info("alexaSkill: link non necessario", {
      motivo: voiceUid ? "voce già associata" : "voce non riconosciuta",
    });
    return speak(t.linkAlready);
  }

  if (await isRateLimited(alexaUserId)) return speak(t.linkTooManyAttempts);

  // L'ASR restituisce il numero in forme diverse ("482915", "48 29 15"):
  // conta solo la sequenza di cifre.
  const code = slotValue(body.request.intent, "code").replace(/\D/g, "");
  if (code.length !== 6) return speak(t.linkNoCode, false, t.linkNoCode);

  const ok = await consumePairingCode(alexaUserId, code, personId);
  if (!ok) {
    await recordFailedAttempt(alexaUserId);
    return speak(t.linkBadCode);
  }
  logger.info("alexaSkill: link creato", {
    alexaUser: linkKey(alexaUserId),
    voce: personId ? "riconosciuta" : "assente",
    accountGiaCollegato: accountLink !== null,
  });
  // Se l'account c'era già, la novità è solo la voce: dirlo aiuta a capire che
  // cosa è cambiato, invece di ripetere che KidBox è collegato.
  return speak(accountLink ? t.linkVoiceOk : t.linkOk);
}

/**
 * Instrada una richiesta già verificata.
 * @param {object} body
 * @param {"it"|"en"} lang
 * @return {Promise<object>}
 */
async function dispatch(body, lang) {
  const t = SPEECH[lang];
  const type = body?.request?.type;
  const alexaUserId = alexaUserIdOf(body);

  if (!alexaUserId) return speak(t.error);
  if (type === "SessionEndedRequest") return {version: "1.0", response: {}};

  const intentName = body?.request?.intent?.name;

  if (intentName === "LinkAccountIntent") {
    return handleLink(body, alexaUserId, t);
  }

  const accountLink = await resolveLink(alexaUserId);
  // L'accesso alla lista lo dà l'account; l'attribuzione la dà la voce. Se la
  // voce non è riconosciuta o non è mai stata associata, si ricade su chi ha
  // collegato l'account: è il comportamento di prima, quindi nessuna
  // regressione per chi non usa i profili vocali.
  const link = accountLink && {
    ...accountLink,
    authorUid: (await resolveVoiceUid(personIdOf(body), accountLink.familyId)) || accountLink.uid,
  };
  if (!link) {
    // Sessione APERTA, non chiusa: chiudendola, le sei cifre dette subito dopo
    // uscirebbero dalla skill e finirebbero ad Alexa come frase generica —
    // nessuno le raccoglie e l'utente non riceve alcuna risposta. Tenendola
    // aperta con un reprompt, basta dire il codice.
    return speak(
        type === "LaunchRequest" ? t.welcomeUnlinked : t.notLinked,
        false,
        t.codePrompt,
    );
  }

  if (type === "LaunchRequest") return speak(t.welcome, false, t.help);

  switch (intentName) {
    case "AMAZON.HelpIntent":
      return speak(t.help, false, t.help);

    case "AMAZON.StopIntent":
    case "AMAZON.CancelIntent":
    case "AMAZON.NavigateHomeIntent":
      return speak(t.bye);

    case "AddItemIntent": {
      const raw = slotValue(body.request.intent, "item");
      if (!raw) return speak(t.addNoItem, false, t.addNoItem);
      const {added, name} = await addItem(link, raw);
      return speak(added ? t.addOk(name) : t.addDuplicate(name));
    }

    case "RemoveItemIntent": {
      const raw = slotValue(body.request.intent, "item");
      if (!raw) return speak(t.removeNoItem, false, t.removeNoItem);
      const {removed, name} = await removeItem(link, raw);
      return speak(removed ? t.removeOk(name) : t.removeMissing(name));
    }

    case "CheckItemIntent": {
      const raw = slotValue(body.request.intent, "item");
      if (!raw) return speak(t.removeNoItem, false, t.removeNoItem);
      const {checked, name} = await checkItem(link, raw);
      return speak(checked ? t.checkOk(name) : t.removeMissing(name));
    }

    case "ReadListIntent": {
      const items = await pendingItems(link.familyId);
      if (items.length === 0) return speak(t.listEmpty);
      if (items.length === 1) return speak(t.listOne(items[0].name));
      const shown = items.slice(0, READ_LIST_MAX_ITEMS).map((i) => i.name);
      if (items.length > READ_LIST_MAX_ITEMS) {
        return speak(t.listTruncated(items.length, shown.length, spokenList(shown, lang)));
      }
      return speak(t.listMany(items.length, spokenList(shown, lang)));
    }

    // ── Promemoria ───────────────────────────────────────────────────────────
    // Il primo turno riparte sempre da zero, anche a flusso aperto: chi ridice
    // «ricordami di…» a metà dialogo sta ricominciando, non rispondendo.
    case "AddReminderIntent":
      return startReminder(body, t, lang);

    case "ReminderAssigneeIntent": {
      const state = reminderState(body);
      if (!state) return speak(t.remindNoFlow, false, t.help);
      return handleReminderAssignee(body, link, state, t, lang);
    }

    case "ReminderAssignSelfIntent": {
      const state = reminderState(body);
      if (!state) return speak(t.remindNoFlow, false, t.help);
      // «a me» è chi sta parlando: `authorUid` è già l'uid della voce
      // riconosciuta quando c'è un profilo vocale, e quello dell'account
      // collegato quando non c'è. La stessa regola dell'attribuzione della
      // spesa, quindi «a me» significa la stessa persona che risulta autrice.
      const name = await memberName(link.familyId, link.authorUid);
      const next = {...state, assignedTo: link.authorUid, assigneeName: name || ""};
      return askWhenOrFinish(link, next, t, lang);
    }

    case "ReminderWhenIntent": {
      const state = reminderState(body);
      if (!state) return speak(t.remindNoFlow, false, t.help);
      return handleReminderWhen(body, link, state, t, lang);
    }

    // «a nessuno» e «senza promemoria» sono la stessa frase in due punti
    // diversi del dialogo: cosa vogliano dire lo decide lo stadio, non le
    // parole. Tenerli in un intent solo evita di dover distinguere a voce due
    // rifiuti che l'utente pronuncia allo stesso modo.
    case "ReminderSkipIntent":
    case "AMAZON.NoIntent": {
      const state = reminderState(body);
      if (!state) return speak(t.bye);
      // Senza titolo non c'è niente da salvare: saltare l'assegnatario a
      // questo stadio significherebbe scrivere un to-do vuoto.
      if (!state.title) {
        return speak(t.remindAskTitle, false, t.remindAskTitle, reminderAttrs(state, "title"));
      }
      if (state.stage === "when") {
        return finishReminder(link, state, null, t, lang, Date.now());
      }
      return askWhenOrFinish(link, state, t, lang);
    }

    // Una parola non capita non deve costare il promemoria già a metà: si
    // ripete la domanda e si tengono gli attributi. Fuori dal flusso resta il
    // comportamento di prima, l'aiuto.
    case "AMAZON.FallbackIntent": {
      const state = reminderState(body);
      if (!state) return speak(t.help, false, t.help);
      const question = state.stage === "when" ?
        t.remindAskWhen :
        (state.stage === "title" ? t.remindAskTitle : t.remindAskAssignee(state.title));
      return speak(question, false, question, reminderAttrs(state, state.stage));
    }

    default:
      return speak(t.help, false, t.help);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENDPOINT DELLA SKILL
// ─────────────────────────────────────────────────────────────────────────────

exports.alexaSkill = onRequest(
    {
      region: "europe-west1",
      maxInstances: 10,
      secrets: [ALEXA_SKILL_ID],
      // Alexa chiama senza credenziali Google: l'endpoint deve essere
      // raggiungibile in anonimo. L'autenticazione vera è la firma verificata
      // in `verifyAlexaRequest`, non l'IAM.
      invoker: "public",
      cors: false,
    },
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const body = req.body || {};

      try {
        await verifyAlexaRequest(req, body);
      } catch (err) {
        logger.warn("alexaSkill: richiesta rifiutata", {reason: err.message});
        res.status(400).send("Bad Request");
        return;
      }

      const expectedSkillId = ALEXA_SKILL_ID.value();
      if (!expectedSkillId || applicationIdOf(body) !== expectedSkillId) {
        logger.warn("alexaSkill: applicationId inatteso", {got: applicationIdOf(body)});
        res.status(400).send("Bad Request");
        return;
      }

      const lang = langOf(body?.request?.locale);

      try {
        const payload = await dispatch(body, lang);
        // Si logga anche il successo, non solo il rifiuto: senza questa riga
        // una richiesta servita correttamente non lascia traccia, e non si
        // riesce a distinguere "l'Echo non ci ha chiamati" da "ci ha chiamati
        // e ha funzionato". È costato mezza giornata di diagnosi al buio.
        logger.info("alexaSkill: richiesta servita", {
          type: body?.request?.type,
          intent: body?.request?.intent?.name || null,
          locale: body?.request?.locale || null,
          deviceId: body?.context?.System?.device?.deviceId ? "presente" : "assente",
          // Senza questo, "voce non riconosciuta" e "già collegato" sono
          // indistinguibili dall'esterno: la skill risponde uguale e i log
          // tacciono. È esattamente il buco che ci ha fatto perdere tempo.
          voce: body?.context?.System?.person?.personId ? "riconosciuta" : "assente",
        });
        res.status(200).json(payload);
      } catch (err) {
        logger.error("alexaSkill: errore nel dispatch", {
          type: body?.request?.type,
          intent: body?.request?.intent?.name,
          error: err.message,
        });
        // 200 e non 500: con un 5xx Alexa risponde all'utente con il suo
        // messaggio d'errore generico, che non spiega niente. Meglio dire noi
        // che è andata male.
        res.status(200).json(speak(SPEECH[lang].error));
      }
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// API PER L'APP
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Genera un codice a 6 cifre non ancora in uso.
 * @return {Promise<string>}
 */
async function allocatePairingCode() {
  const db = admin.firestore();
  for (let attempt = 0; attempt < 10; attempt++) {
    const code = String(crypto.randomInt(0, 1000000)).padStart(6, "0");
    const snap = await db.collection("alexaPairings").doc(code).get();
    if (!snap.exists) return code;
    const expiresAt = snap.data().expiresAt?.toMillis ? snap.data().expiresAt.toMillis() : 0;
    if (expiresAt < Date.now()) return code;
  }
  throw new HttpsError("resource-exhausted", "Impossibile generare un codice, riprova.");
}

exports.createAlexaPairingCode = onCall(
    {region: "europe-west1", maxInstances: 10, invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");

      const {familyId} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }

      const memberSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").doc(uid).get();
      if (!memberSnap.exists) throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.");

      const code = await allocatePairingCode();
      const expiresAtMs = Date.now() + PAIRING_TTL_MS;

      await admin.firestore().collection("alexaPairings").doc(code).set({
        uid,
        familyId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
        usedAt: null,
      });

      logger.info("createAlexaPairingCode", {uid, familyId});
      return {code, expiresAt: expiresAtMs};
    },
);

/**
 * Nome leggibile di un membro. Mirror ridotto di `resolveMemberName` in
 * index.js: quel file richiede QUESTO modulo, quindi importarlo da qui
 * chiuderebbe un ciclo. Dieci righe duplicate costano meno di una
 * ristrutturazione dei due file.
 * @param {string} familyId
 * @param {string} uid
 * @return {Promise<string|null>}
 */
async function memberName(familyId, uid) {
  try {
    const memberSnap = await admin.firestore()
        .collection("families").doc(familyId)
        .collection("members").doc(uid).get();
    if (memberSnap.exists) {
      const name = memberSnap.get("displayName") || memberSnap.get("name");
      if (name) return name;
    }
    const userSnap = await admin.firestore().collection("users").doc(uid).get();
    if (userSnap.exists) {
      const name = userSnap.get("displayName") || userSnap.get("name");
      if (name) return name;
    }
  } catch (e) {
    logger.warn("memberName failed", {uid, error: e.message});
  }
  return null;
}

// Lo stato è di FAMIGLIA, non del singolo: se un membro ha già collegato Alexa,
// gli altri devono vederlo. Altrimenti il secondo che apre la schermata la
// trova identica alla prima volta e rifà un accoppiamento che spesso non gli
// serve — gli Echo di casa, se stanno sullo stesso account Amazon, sono già
// coperti dal collegamento del primo.
exports.getAlexaLinkStatus = onCall(
    {region: "europe-west1", maxInstances: 10, invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");

      const {familyId} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }

      // Stessa verifica di `createAlexaPairingCode`: senza, basterebbe passare
      // un familyId altrui per sapere chi in quella famiglia usa Alexa.
      const memberSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").doc(uid).get();
      if (!memberSnap.exists) throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.");

      const db = admin.firestore();
      const [accounts, voices] = await Promise.all([
        db.collection("alexaLinks").where("familyId", "==", familyId).get(),
        db.collection("alexaPersonLinks").where("familyId", "==", familyId).get(),
      ]);

      /**
       * @param {FirebaseFirestore.QueryDocumentSnapshot} doc
       * @param {"account"|"voice"} kind
       * @return {Promise<object>}
       */
      const toLink = async (doc, kind) => {
        const data = doc.data();
        return {
          uid: data.uid || null,
          name: data.uid ? await memberName(familyId, data.uid) : null,
          isMe: data.uid === uid,
          // "account" dà accesso alla lista, "voice" dà solo l'attribuzione:
          // sono cose diverse e il client deve poterle distinguere.
          kind,
          linkedAt: data.createdAt?.toMillis ? data.createdAt.toMillis() : null,
        };
      };

      const links = await Promise.all([
        ...accounts.docs.map((d) => toLink(d, "account")),
        ...voices.docs.map((d) => toLink(d, "voice")),
      ]);

      const mineAccount = links.find((l) => l.isMe && l.kind === "account") || null;
      const mineVoice = links.find((l) => l.isMe && l.kind === "voice") || null;

      return {
        linked: mineAccount !== null,
        linkedAt: mineAccount ? mineAccount.linkedAt : null,
        // Voce riconosciuta e associata a me: senza, i miei articoli dettati
        // risultano di chi ha collegato l'account.
        voiceLinked: mineVoice !== null,
        // Tutti i collegamenti della famiglia, il proprio incluso: il client
        // decide cosa mostrare, il server non nasconde nulla a un membro.
        familyLinks: links,
      };
    },
);

exports.unlinkAlexa = onCall(
    {region: "europe-west1", maxInstances: 10, invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");

      // Tutti i collegamenti dell'utente, non solo il primo: se ha parlato da
      // due account Amazon diversi, "scollega" deve scollegare davvero tutto.
      const db = admin.firestore();
      // Anche i legami di voce: lasciarli sarebbe peggio che inutile, perché
      // continuerebbero ad attribuire articoli a un account scollegato.
      const [accounts, voices] = await Promise.all([
        db.collection("alexaLinks").where("uid", "==", uid).get(),
        db.collection("alexaPersonLinks").where("uid", "==", uid).get(),
      ]);
      const docs = [...accounts.docs, ...voices.docs];
      if (docs.length === 0) return {removed: 0};

      const batch = db.batch();
      docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();

      logger.info("unlinkAlexa", {uid, account: accounts.size, voci: voices.size});
      return {removed: docs.length};
    },
);

// Esposte per i test: sono le uniche funzioni pure del file, cioè l'unica parte
// verificabile senza Firestore e senza Amazon davanti. Il resto è I/O.
exports.__testables = {
  normalizeItemName, displayItemName, spokenList, isValidCertChainUrl, guessCategory,
  displayTodoTitle, normalizePersonName, matchMember,
  parseSpokenDate, parseSpokenTime, tzInstant, resolveRemindAt, spokenWhen,
  extractWhenFromTitle,
  // `dispatch` sta qui perché il promemoria è un dialogo in più turni: le
  // funzioni pure coprono i pezzi, ma è la sequenza dei turni — con gli
  // attributi di sessione che passano avanti e indietro — la parte che si
  // rompe, e da fuori non sarebbe raggiungibile senza firmare una richiesta
  // con la chiave di Amazon.
  dispatch,
};
