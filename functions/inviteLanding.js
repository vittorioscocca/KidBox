/**
 * Contatore della pagina d'invito (`kidboxapp.com/join`), il passaggio cieco
 * del funnel inviti: chi riceve un link senza avere l'app arriva lì, e da lì
 * o va allo store o sparisce.
 *
 * Perché un contatore nostro e non GA4: sulla landing Google parte solo dopo
 * il consenso al banner (scelta del 13/09/2026), e chi arriva da un invito
 * tocca lo store senza rispondere — in 28 giorni `invite_landing_shown` è
 * rimasto a zero con 106 inviti generati. Il Consent Mode non aiuta: i ping
 * senza consenso servono solo alla modellazione, che non entra nei report a
 * questi volumi (verificato sul realtime il 15/09/2026).
 *
 * Qui non c'è niente da proteggere: si contano quattro tipi di evento, senza
 * cookie, senza identificativi, senza IP salvato. Il segreto dell'invito sta
 * nel fragment dell'URL e non arriva mai né qui né a Google.
 *
 * Firestore: `inviteLanding/{YYYY-MM-DD}` (giorno Europe/Rome, come i rollup)
 * con campi `shown_ios|shown_android|shown_other|store_ios|store_android|web`
 * incrementati atomicamente. Legge `scripts/console-daily-report.js`; nessun
 * client vi accede (le rules non lo aprono).
 *
 * Abuso: un curl in loop gonfia i contatori. È accettato — il danno è un
 * numero sbagliato in un report interno, e la difesa (App Check, rate limit)
 * costerebbe più del rischio. `maxInstances: 2` limita comunque il costo.
 */

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

const EVENTS = new Set(["shown", "store_ios", "store_android", "web"]);
const PLATFORMS = new Set(["ios", "android", "other"]);

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

/**
 * Campo da incrementare per un ping, o null se il ping non è valido.
 * @param {unknown} body
 * @return {string|null}
 */
function fieldFor(body) {
  if (!body || typeof body !== "object") return null;
  const {event, platform} = body;
  if (typeof event !== "string" || !EVENTS.has(event)) return null;
  if (event !== "shown") return event;
  const known = typeof platform === "string" && PLATFORMS.has(platform);
  return `shown_${known ? platform : "other"}`;
}

exports.inviteLandingPing = onRequest(
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
      const field = fieldFor(body);
      if (!field) {
        res.status(400).send("");
        return;
      }
      try {
        const {FieldValue} = admin.firestore;
        await admin.firestore().collection("inviteLanding").doc(romeDay()).set(
            {
              [field]: FieldValue.increment(1),
              updatedAt: FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      } catch (e) {
        // Un contatore che non incrementa non deve far fallire nulla lato
        // pagina: 204 comunque, il guasto lo dice il log.
        logger.error("inviteLandingPing: increment failed", {
          field, error: e.message,
        });
      }
      res.status(204).send("");
    },
);

exports._fieldFor = fieldFor;
