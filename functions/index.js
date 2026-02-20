/* eslint-disable max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();

exports.notifyNewDocument = onDocumentCreated(
    {
      document: "families/{familyId}/documents/{docId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const docId = event.params.docId;

      const docData = event.data ? event.data.data() : null;
      if (!docData) {
        logger.warn("notifyNewDocument: missing doc data");
        return;
      }

      const uploaderUid = docData.updatedBy || docData.createdBy || null;
      if (!uploaderUid) {
        logger.warn("notifyNewDocument: missing uploader uid");
        return;
      }

      logger.info("notifyNewDocument triggered", {familyId, docId, uploaderUid});

      // 1) Leggi membri dalla subcollection: families/{familyId}/members/*
      const membersRef = admin.firestore()
          .collection("families")
          .doc(familyId)
          .collection("members");

      const membersSnap = await membersRef.get();

      logger.info("members snapshot", {size: membersSnap.size});

      if (membersSnap.empty) {
        logger.warn("notifyNewDocument: members subcollection is empty");
        return;
      }

      const memberUids = membersSnap.docs
          .map((d) => d.id)
          .filter((uid) => uid && uid !== uploaderUid);

      if (memberUids.length === 0) {
        logger.info("notifyNewDocument: no targets (only uploader?)");
        return;
      }

      // 2) Per ogni membro: controlla pref + leggi tokens
      const allTokens = [];

      for (const uid of memberUids) {
        const userRef = admin.firestore().collection("users").doc(uid);
        const userSnap = await userRef.get();

        const prefs = userSnap.exists ? userSnap.get("notificationPrefs") : null;
        const enabled = prefs && prefs.notifyOnNewDocs === true;

        logger.info("user prefs", {uid, enabled});

        if (!enabled) continue;

        const tokensSnap = await userRef.collection("fcmTokens").get();
        tokensSnap.forEach((t) => {
          const tok = t.get("token");
          if (tok) allTokens.push(tok);
        });
      }

      if (allTokens.length === 0) {
        logger.info("notifyNewDocument: no tokens to notify");
        return;
      }

      // 3) Costruisci notifica
      const title = "Nuovo documento caricato";
      const body = docData.title || docData.fileName || "Documento";

      const message = {
        notification: {title, body},
        data: {
          type: "new_document",
          familyId: familyId,
          docId: docId,
        },
        tokens: allTokens,
      };

      // 4) Invia
      const res = await admin.messaging().sendEachForMulticast(message);

      logger.info("notifyNewDocument: send result", {
        successCount: res.successCount,
        failureCount: res.failureCount,
        tokenCount: allTokens.length,
      });
    },
);

const FAMILY_SUBCOLLECTIONS = [
  "members",
  "children",
  "documents",
  "documentCategories",
  "todos",
  "invites",
];

/**
 * Deletes all documents in a Firestore collection.
 * @param {object} colRef - The Firestore collection reference.
 * @param {number} batchSize - The number of documents to delete per batch.
 * @return {Promise<void>}
 */
async function deleteCollection(colRef, batchSize = 300) {
  let snap = await colRef.limit(batchSize).get();
  while (!snap.empty) {
    const batch = admin.firestore().batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    snap = await colRef.limit(batchSize).get();
  }
}

/**
 * Deletes all files in Cloud Storage with a given prefix.
 * @param {string} prefix - The storage path prefix.
 * @return {Promise<void>}
 */
async function deleteStoragePrefix(prefix) {
  const bucket = admin.storage().bucket();
  const [files] = await bucket.getFiles({prefix});
  if (!files.length) return;

  const chunkSize = 50;
  for (let i = 0; i < files.length; i += chunkSize) {
    const chunk = files.slice(i, i + chunkSize);
    await Promise.allSettled(chunk.map((f) => f.delete()));
  }
}

/**
 * Counts the number of active members in a family.
 * @param {string} familyId - The family ID.
 * @return {Promise<number>} The count of active members.
 */
async function countActiveMembers(familyId) {
  const snap = await admin.firestore()
      .collection("families")
      .doc(familyId)
      .collection("members")
      .get();

  // Se non usi isDeleted, conta tutti. Se lo usi, filtra.
  return snap.docs.filter((d) => d.get("isDeleted") !== true).length;
}

/**
 * Completely deletes a family and all its data.
 * @param {string} familyId - The family ID.
 * @return {Promise<void>}
 */
async function deleteFamilyCompletely(familyId) {
  const db = admin.firestore();

  for (const sub of FAMILY_SUBCOLLECTIONS) {
    await deleteCollection(db.collection(`families/${familyId}/${sub}`));
  }

  await db.collection("families").doc(familyId).delete().catch(() => {});
  await deleteStoragePrefix(`families/${familyId}/`);
}

exports.deleteAccount = onCall(
    {region: "europe-west1",
      invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Not authenticated");
      }

      const db = admin.firestore();
      logger.info("deleteAccount started", {uid});

      // 1) Leggi memberships index -> familyIds
      const membershipsRef = db.collection("users").doc(uid).collection("memberships");
      const membershipsSnap = await membershipsRef.get();
      const familyIds = membershipsSnap.docs.map((d) => d.id);

      // 2) Per ogni famiglia: se solo -> delete family; se >1 -> remove membership
      for (const familyId of familyIds) {
        let memberCount = 0;
        try {
          memberCount = await countActiveMembers(familyId);
        } catch (e) {
          memberCount = 0;
        }

        if (memberCount > 1) {
          await db.collection("families")
              .doc(familyId)
              .collection("members")
              .doc(uid)
              .delete()
              .catch(() => {});
        } else {
          await deleteFamilyCompletely(familyId);
        }

        // rimuovi sempre membership index
        await membershipsRef.doc(familyId).delete().catch(() => {});
      }

      // 3) Cancella dati utente: user doc + subcollections note
      // notificationPrefs sta nel doc users/{uid} (campo), ok con delete doc
      await deleteCollection(db.collection(`users/${uid}/fcmTokens`)).catch(() => {});
      await deleteCollection(db.collection(`users/${uid}/memberships`)).catch(() => {});
      await db.collection("users").doc(uid).delete().catch(() => {});

      // 4) Cancella storage utente (se presente)
      await deleteStoragePrefix(`users/${uid}/`).catch(() => {});

      // 5) Cancella Firebase Auth user (ultimo)
      await admin.auth().deleteUser(uid);

      logger.info("deleteAccount completed", {uid, families: familyIds.length});
      return {ok: true, familiesProcessed: familyIds.length};
    },
);
