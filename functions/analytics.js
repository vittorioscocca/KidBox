// ─────────────────────────────────────────────────────────────────────────────
// ANALYTICS — utenti attivi
//
// Design: internal/analytics-active-users.md
//
// Registra le AZIONI DI VALORE su una collection top-level append-only
// (`analyticsEvents`), da cui i rollup notturni ricavano DAU/WAU/MAU e le
// metriche di famiglia.
//
// Due vincoli non negoziabili:
//
// 1) PRIVACY — si registra la FORMA dell'azione, mai l'OGGETTO. Niente id
//    documento, titoli, nomi file, testo libero, coordinate. Le domande sono
//    aggregate: sapere *quale* documento ha aperto chi non serve, e
//    creerebbe un registro di sorveglianza interno alla famiglia. Vale a
//    maggior ragione per
//    `passwords` (E2E) e `health`.
//
// 2) NON INVASIVO — questi trigger sono separati da quelli di notifica. Non
//    toccano `index.js` e non possono romperne la logica: un errore qui non
//    deve mai impedire l'invio di una notifica. Per questo `logEvent` non
//    solleva mai.
//
// Copre solo le SCRITTURE. Le letture (`content_retrieved`) il server non può
// vederle — richiedono il logger client, fase 3.
// ─────────────────────────────────────────────────────────────────────────────

const {
  onDocumentWritten,
  onDocumentCreated,
} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

const REGION = "europe-west1";
const EVENTS_COLLECTION = "analyticsEvents";

// Ritenzione degli eventi grezzi. Servono solo a calcolare i rollup giornalieri
// (`metrics/daily/{date}`), che sono l'artefatto durevole; 90 giorni bastano a
// ricalcolare all'indietro se la definizione cambia o si trova un bug.
const RETENTION_DAYS = 90;

// Collection tracciate. `feature` deve restare allineata alla tassonomia del
// documento di design: aggiungere una feature = aggiungere una riga qui.
const TRACKED = [
  {coll: "documents", feature: "documents"},
  {coll: "chatMessages", feature: "chat"},
  {coll: "photos", feature: "photoVideo"},
  {coll: "medicalVisits", feature: "health"},
  {coll: "todos", feature: "todo", completedField: "isDone"},
  {coll: "groceries", feature: "grocery", completedField: "isPurchased"},
  {coll: "notes", feature: "note"},
  {coll: "calendarEvents", feature: "calendar"},
  {coll: "expenses", feature: "expenses"},
  {coll: "walletTickets", feature: "wallet"},
  {coll: "passwords", feature: "passwords"},
  {coll: "vehicles", feature: "vehicles"},
  {coll: "pets", feature: "pets"},
  {coll: "homeItems", feature: "homeItems"},
  {coll: "trips", feature: "travel"},
];

const SOURCES = ["manual", "ai", "import", "shareExt"];

/**
 * Scadenza dell'evento, per la TTL policy.
 * @return {FirebaseFirestore.Timestamp} ora + RETENTION_DAYS
 */
function expiryTimestamp() {
  const d = new Date();
  d.setDate(d.getDate() + RETENTION_DAYS);
  return admin.firestore.Timestamp.fromDate(d);
}

/**
 * Scrive un evento. Non solleva mai: l'analytics non deve poter rompere nulla.
 * @param {{name: string, uid: ?string, familyId: ?string, feature: string,
 *          persistent: ?boolean, props: ?Object}} evt evento da registrare.
 *          `persistent: true` omette `expiresAt`: la TTL policy ignora i
 *          documenti senza quel campo, quindi l'evento sopravvive ai 90gg.
 *          Da usare per gli eventi di STATO (es. un join famiglia), che
 *          interessano anche fra un anno — non per quelli di flusso.
 * @return {Promise<void>}
 */
async function logEvent(evt) {
  try {
    // Senza uid o familyId l'evento è inutilizzabile: le metriche di famiglia
    // non sarebbero ricostruibili a posteriori. Meglio scartarlo.
    if (!evt.uid || !evt.familyId) return;

    const doc = {
      name: evt.name,
      uid: evt.uid,
      familyId: evt.familyId,
      feature: evt.feature,
      ts: admin.firestore.FieldValue.serverTimestamp(),
      props: evt.props || {},
    };
    if (!evt.persistent) {
      // Campo della TTL policy: è la data di MORTE, non di nascita. Puntare
      // la policy su `ts` cancellerebbe ogni evento appena scritto.
      doc.expiresAt = expiryTimestamp();
    }
    await admin.firestore().collection(EVENTS_COLLECTION).add(doc);
  } catch (err) {
    logger.warn("logEvent failed", {
      name: evt.name,
      feature: evt.feature,
      err: String(err),
    });
  }
}

/**
 * Estrae l'uid dell'autore. La convenzione del data model è `createdBy` /
 * `updatedBy`; `expenses` usa `createdByUid`.
 * @param {?Object} data documento Firestore
 * @param {boolean} isCreate se true privilegia il creatore
 * @return {?string} uid oppure null
 */
function resolveUid(data, isCreate) {
  if (!data) return null;
  const created = data.createdBy || data.createdByUid || null;
  const updated = data.updatedBy || null;
  return isCreate ? (created || updated) : (updated || created);
}

/**
 * Classifica la scrittura. Ritorna null se non è un'azione di valore.
 * @param {?Object} before stato precedente
 * @param {?Object} after stato successivo
 * @param {?string} completedField campo di completamento, se presente
 * @return {?string} nome evento
 */
function classify(before, after, completedField) {
  // Hard delete: fuori dalla definizione di azione di valore.
  if (!after) return null;
  // Soft delete: idem. Va intercettato prima di `content_updated`, altrimenti
  // una cancellazione verrebbe contata come modifica.
  if (after.isDeleted === true) return null;

  if (!before) return "content_created";

  if (completedField &&
      before[completedField] !== true &&
      after[completedField] === true) {
    return "content_completed";
  }

  return "content_updated";
}

/**
 * Costruisce il trigger analytics per una collection.
 * @param {{coll: string, feature: string, completedField: ?string}} spec
 *     voce di TRACKED
 * @return {Object} trigger Firestore
 */
function makeTrigger(spec) {
  return onDocumentWritten(
      {
        document: `families/{familyId}/${spec.coll}/{docId}`,
        region: REGION,
      },
      async (event) => {
        const familyId = event.params.familyId;

        const beforeSnap = event.data && event.data.before;
        const afterSnap = event.data && event.data.after;
        const before =
          beforeSnap && beforeSnap.exists ? beforeSnap.data() : null;
        const after = afterSnap && afterSnap.exists ? afterSnap.data() : null;

        const name = classify(before, after, spec.completedField);
        if (!name) return;

        const isCreate = name === "content_created";

        // Su `content_completed` l'attore è chi ha completato, che può non
        // essere chi ha creato: è proprio il caso interessante (un membro
        // spunta la spesa aggiunta da un altro).
        let uid = resolveUid(after, isCreate);
        if (name === "content_completed" &&
            spec.completedField === "isPurchased") {
          uid = after.purchasedBy || uid;
        }

        const props = {};
        if (isCreate) {
          // Whitelist: `source` arriva dal client, non ci si fida del valore.
          props.source =
            SOURCES.includes(after.source) ? after.source : "manual";
        }

        await logEvent({
          name,
          uid,
          familyId,
          feature: spec.feature,
          props,
        });
      },
  );
}

// ── Join famiglia ────────────────────────────────────────────────────────────
// L'evento che segnala l'intento di condivisione: chi invita ha già deciso che
// l'app vale per la famiglia. Scatta per ogni membro che NON è l'owner — il
// confronto con `ownerUid` (campo stabile del doc famiglia) è atomico, a
// differenza di un conteggio dei membri, che con due join quasi simultanei
// darebbe risultati sbagliati.
//
// PERSISTENTE: niente `expiresAt`. È un evento di stato, non di flusso —
// "questa famiglia è cresciuta" interessa anche fra un anno, e il TTL dei
// 90 giorni lo cancellerebbe.
//
// Nota: uscire dalla famiglia è un hard delete del doc membro, quindi un
// rientro fa scattare di nuovo il trigger. Voluto: un rientro È un join;
// eventuali duplicati sono distinguibili a posteriori (stesso familyId+uid).
const familyMemberJoined = onDocumentCreated(
    {
      document: "families/{familyId}/members/{uid}",
      region: REGION,
    },
    async (event) => {
      const {familyId, uid} = event.params;
      const data = event.data ? event.data.data() : null;
      if (!data || data.isDeleted === true) return;

      const famSnap = await admin.firestore()
          .collection("families").doc(familyId).get();
      const ownerUid = famSnap.exists ? famSnap.data().ownerUid : null;
      // Senza ownerUid non si distingue il fondatore da un invitato: meglio
      // perdere un evento che contare il fondatore come join.
      if (!ownerUid || uid === ownerUid) return;

      await logEvent({
        name: "family_member_joined",
        uid,
        familyId,
        feature: "family",
        persistent: true,
        props: data.role ? {role: String(data.role)} : {},
      });
    },
);

// Export: `analyticsDocuments`, `analyticsTodos`, …
const triggers = {};
for (const spec of TRACKED) {
  const suffix = spec.coll.charAt(0).toUpperCase() + spec.coll.slice(1);
  triggers[`analytics${suffix}`] = makeTrigger(spec);
}
triggers.analyticsFamilyMemberJoined = familyMemberJoined;

module.exports = {
  triggers,
  logEvent,
  // esportati per i test
  classify,
  resolveUid,
  TRACKED,
};
