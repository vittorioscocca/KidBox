/* eslint-disable max-len */

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
