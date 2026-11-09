"use strict";
/**
 * Testo dei documenti cancellati: si svuota.
 *
 * To-do, liste, animali ed eventi degli animali si cancellano «soft»
 * (`isDeleted: true`) e i client li leggono con `isDeleted == false`: nessuno
 * li rilegge, quindi nessuno li ricifra (`internal/cifratura-sezioni.md`,
 * «Prova su device»). Restavano su Firestore con titolo e note in chiaro, per
 * sempre. Il contenuto di un documento cancellato non serve a nessuno: lo si
 * svuota qui, per tutti i client, vecchi compresi. `secure` resta (è cifrato,
 * e un client che rilegge il documento lo trova uguale), `updatedAt` e
 * `updatedBy` non si toccano.
 *
 * Lo storico si ripulisce una volta con `scripts/blank-deleted-content.js`.
 */
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");

// Campi di testo per collezione: gli stessi di SECURE_FIELDS dei client.
const DELETED_BLANK_FIELDS = {
  todos: ["title", "notes"],
  todoLists: ["name"],
  pets: ["name", "breed", "color", "chipCode", "notes"],
  petEvents: ["title", "vetName", "notes"],
};

const filled = (v) => typeof v === "string" && v.trim() !== "";

/**
 * Se `data` è un documento cancellato con testo in chiaro, lo svuota.
 * Restituisce il numero di campi svuotati (0 se non c'era niente da fare,
 * così la scrittura di ritorno non rientra qui all'infinito).
 */
async function blankDeletedContent(collection, ref, data) {
  const fields = DELETED_BLANK_FIELDS[collection];
  if (!fields || !data || data.isDeleted !== true) return 0;
  const toBlank = fields.filter((f) => filled(data[f]));
  if (toBlank.length === 0) return 0;
  await ref.update(Object.fromEntries(toBlank.map((f) => [f, ""])));
  logger.info("blankDeletedContent", {path: ref.path, fields: toBlank.length});
  return toBlank.length;
}

/**
 * Trigger per una collezione senza altri trigger sulle scritture.
 * @param {string} collection nome della sottocollezione di families/
 * @return {Function} la Cloud Function
 */
function trigger(collection) {
  return onDocumentWritten(
      {
        document: `families/{familyId}/${collection}/{docId}`,
        region: "europe-west1",
        maxInstances: 5,
      },
      async (event) => {
        const after = event.data?.after;
        if (!after?.exists) return;
        try {
          await blankDeletedContent(collection, after.ref, after.data());
        } catch (e) {
          logger.warn("blankDeletedContent failed",
              {path: after.ref.path, error: e.message});
        }
      },
  );
}

module.exports = {
  DELETED_BLANK_FIELDS,
  blankDeletedContent,
  // to-do e liste passano dai trigger che esistono già (notifyTodoAssigned,
  // cascadeDeleteTodosOfList): una function in più costerebbe un'invocazione
  // per ogni scrittura di to-do.
  triggers: {
    blankDeletedPets: trigger("pets"),
    blankDeletedPetEvents: trigger("petEvents"),
  },
};
