/**
 * Contatore del traffico della landing (`kidboxapp.com`, blog e strumenti
 * compresi): quante pagine si aprono, da dove arriva chi le apre, quanti
 * restano almeno dieci secondi e quanti toccano un link allo store.
 *
 * Perché un contatore nostro accanto a GA4: sulla landing Google parte solo
 * dopo il consenso al banner (dal 13/09/2026), e chi arriva da un'inserzione
 * spesso chiude prima di rispondere. Il 13-15/09 Meta contava 224 «landing
 * viste» e GA4 vedeva 4-6 utenti al giorno: senza un numero indipendente non
 * si può dire se i click pagati portano persone o tap accidentali. Il
 * fratello `inviteLanding.js` fa lo stesso per la pagina /join.
 *
 * Cosa NON c'è: cookie, identificativi, IP, URL completi, referrer completi.
 * Il client riduce tutto a un vocabolario chiuso — sorgente (meta, google,
 * direct, referral, other), pagina (home, blog, strumenti, scarica, other),
 * piattaforma (ios, android, other), store (ios, android, web) — e qui si
 * accetta solo quel vocabolario. Il conteggio è per apertura di pagina, non
 * per persona: si confronta con le «landing viste» di Meta, non con gli
 * utenti di GA4.
 *
 * Firestore: `landingTraffic/{YYYY-MM-DD}` (giorno Europe/Rome) con campi
 *   view, view_src_*, view_page_*, view_plat_*
 *   engaged, engaged_src_*            (pagina visibile per 10 secondi)
 *   store_<store>, store_src_*, store_page_*
 * incrementati atomicamente. Legge `scripts/console-daily-report.js`; nessun
 * client vi accede (le rules non lo aprono).
 *
 * Abuso: come per inviteLanding, un curl in loop sporca un report interno e
 * niente altro. `maxInstances: 2` limita il costo.
 */

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const EVENTS = new Set(["view", "engaged", "store"]);
const SOURCES = new Set(["meta", "google", "direct", "referral", "other"]);
const PAGES = new Set(["home", "blog", "strumenti", "scarica", "other"]);
const PLATFORMS = new Set(["ios", "android", "other"]);
const STORES = new Set(["ios", "android", "web"]);

const ALLOWED_ORIGINS = [
  "https://kidboxapp.com",
  "https://www.kidboxapp.com",
  "https://kidbox-landing.web.app",
  "https://kidbox-landing.firebaseapp.com",
  "http://localhost:5050",
];

/** Giorno solare in Europe/Rome, lo stesso confine del rollup analytics. */
function romeDay(d = new Date()) {
  return d.toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"});
}

const pick = (value, allowed, fallback) =>
  (typeof value === "string" && allowed.has(value) ? value : fallback);

/**
 * Campi da incrementare per un ping, o null se il ping non è valido.
 * @param {unknown} body
 * @return {string[]|null}
 */
function fieldsFor(body) {
  if (!body || typeof body !== "object") return null;
  const {event} = body;
  if (typeof event !== "string" || !EVENTS.has(event)) return null;
  const src = pick(body.src, SOURCES, "other");
  const page = pick(body.page, PAGES, "other");
  if (event === "view") {
    const plat = pick(body.platform, PLATFORMS, "other");
    return [
      "view", `view_src_${src}`, `view_page_${page}`, `view_plat_${plat}`,
    ];
  }
  if (event === "engaged") return ["engaged", `engaged_src_${src}`];
  const store = pick(body.store, STORES, null);
  if (!store) return null;
  return [`store_${store}`, `store_src_${src}`, `store_page_${page}`];
}

exports.landingPing = onRequest(
    {
      region: "europe-west1",
      cors: ALLOWED_ORIGINS,
      maxInstances: 2,
      // Non scendere a 128MiB: il processo carica tutto index.js e a freddo
      // pesa ~135 MiB: l'istanza moriva in OOM prima del readiness (16/09).
      memory: "256MiB",
    },
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("");
        return;
      }
      // sendBeacon manda text/plain: il body arriva come stringa, non parsato.
      let body = req.body;
      if (typeof body === "string") {
        try {
          body = JSON.parse(body);
        } catch {
          body = null;
        }
      }
      const fields = fieldsFor(body);
      if (!fields) {
        res.status(400).send("");
        return;
      }
      try {
        const {FieldValue} = admin.firestore;
        const update = {updatedAt: FieldValue.serverTimestamp()};
        for (const f of fields) update[f] = FieldValue.increment(1);
        await admin.firestore().collection("landingTraffic").doc(romeDay())
            .set(update, {merge: true});
      } catch (e) {
        // Un contatore che non incrementa non deve far fallire nulla lato
        // pagina: 204 comunque, il guasto lo dice il log.
        logger.error("landingPing: increment failed", {
          fields, error: e.message,
        });
      }
      res.status(204).send("");
    },
);

exports._fieldsFor = fieldsFor;
