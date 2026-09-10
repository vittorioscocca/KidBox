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
    help: "Puoi dire: aggiungi il latte. Oppure: togli il pane. Oppure: cosa manca.",
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
    bye: "A posto.",
    and: "e",
  },
  en: {
    welcome: "Hi! Tell me what to add to the shopping list.",
    welcomeUnlinked: "To use KidBox you need to link your account first. Open KidBox, go to Settings, Alexa, and read out the code you see.",
    help: "You can say: add milk. Or: remove bread. Or: what's on the list.",
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
    bye: "Done.",
    and: "and",
  },
};

/**
 * Risposta vocale nel formato che Alexa si aspetta.
 * @param {string} text
 * @param {boolean} [endSession=true]
 * @param {string|null} [reprompt=null]
 * @return {object}
 */
function speak(text, endSession = true, reprompt = null) {
  const response = {
    outputSpeech: {type: "PlainText", text},
    shouldEndSession: endSession,
  };
  if (reprompt) {
    response.reprompt = {outputSpeech: {type: "PlainText", text: reprompt}};
  }
  return {version: "1.0", response};
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
exports.__testables = {normalizeItemName, displayItemName, spokenList, isValidCertChainUrl, guessCategory};
