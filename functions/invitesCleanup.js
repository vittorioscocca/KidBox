// ─────────────────────────────────────────────────────────────────────────────
// INVITI — svuotare quelli scaduti del materiale crittografico
//
// Un invito `families/{familyId}/invites/{inviteId}` porta la chiave di
// famiglia wrappata (`kdfSalt`, `wrappedKeyCipher/Nonce/Tag`) e l'hash del
// segreto; il segreto sta nel link. Chi ha il link apre l'invito per id — il
// `get` è aperto a ogni utente autenticato, perché chi lo riceve non è ancora
// membro — e da quei campi ricava la chiave OFFLINE, senza consumare nulla.
//
// La scadenza la controllavano solo i client, al momento del join: un invito
// scaduto e mai usato restava lì con la chiave dentro per sempre, e un vecchio
// link ritrovato in una chat apriva ancora la famiglia. Il 13/09/2026 erano
// ~199 documenti. Anche i client precedenti a settembre 2026 consumavano
// l'invito senza svuotarlo.
//
// Qui si TOLGONO i campi, non il documento:
// - l'app, trovando `expiresAt` passato, mostra «invito scaduto» invece di
//   «invito non valido» (il controllo di scadenza viene prima dell'hash);
// - un invito consumato è la prova che `firestore.rules.next` chiede per
//   l'iscrizione a `members/{uid}`: cancellarlo negherebbe quel join.
//
// Non si toccano gli inviti ancora validi, e c'è un'ora di margine dopo la
// scadenza: un telefono con l'orologio indietro può essere a metà di un join
// proprio a cavallo della scadenza.
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");

/** Campi che servono solo a sbloccare la chiave di famiglia. */
const INVITE_CRYPTO_FIELDS = [
  "kdfSalt",
  "secretHash",
  "wrappedKeyCipher",
  "wrappedKeyNonce",
  "wrappedKeyTag",
];

const EXPIRY_GRACE_MS = 60 * 60 * 1000;

/** Sotto il limite di 500 scritture per batch. */
const BATCH_SIZE = 400;

/**
 * Svuota del materiale crittografico gli inviti scaduti da più di un'ora.
 *
 * Scorre le famiglie una per una con una query per sottocollezione: una query
 * `collectionGroup("invites")` filtrata su `expiresAt` richiederebbe un indice
 * di collection group da deployare a parte, e il costo in letture è comunque
 * minimo (una per famiglia più gli inviti scaduti). `listDocuments()` include
 * anche le famiglie il cui documento non esiste più ma le sottocollezioni sì.
 *
 * @param {object} opts
 * @param {FirebaseFirestore.Firestore} [opts.db]
 * @param {number} [opts.nowMs] - Adesso, iniettabile nei test.
 * @param {number} [opts.deadlineAt] - Ms epoch oltre cui fermarsi.
 * @param {boolean} [opts.dryRun] - Conta senza scrivere.
 * @return {Promise<{families: number, scanned: number, stripped: number,
 *                   complete: boolean}>}
 */
async function stripExpiredInviteSecrets({
  db = admin.firestore(),
  nowMs = Date.now(),
  deadlineAt = Infinity,
  dryRun = false,
} = {}) {
  const cutoff = admin.firestore.Timestamp.fromMillis(nowMs - EXPIRY_GRACE_MS);
  const clear = Object.fromEntries(
      INVITE_CRYPTO_FIELDS.map((f) => [f, admin.firestore.FieldValue.delete()]),
  );

  const familyRefs = await db.collection("families").listDocuments();
  let scanned = 0;
  let stripped = 0;
  let complete = true;
  let batch = db.batch();
  let pending = 0;

  for (const familyRef of familyRefs) {
    if (Date.now() > deadlineAt) {
      complete = false;
      break;
    }
    const snap = await familyRef.collection("invites")
        .where("expiresAt", "<", cutoff)
        .get();
    scanned += snap.size;

    for (const doc of snap.docs) {
      const data = doc.data();
      if (!INVITE_CRYPTO_FIELDS.some((f) => data[f] !== undefined)) continue;
      stripped++;
      if (dryRun) continue;
      batch.update(doc.ref, clear);
      pending++;
      if (pending >= BATCH_SIZE) {
        await batch.commit();
        batch = db.batch();
        pending = 0;
      }
    }
  }

  if (pending > 0) await batch.commit();

  return {families: familyRefs.length, scanned, stripped, complete};
}

module.exports = {
  stripExpiredInviteSecrets,
  INVITE_CRYPTO_FIELDS,
  EXPIRY_GRACE_MS,
};
