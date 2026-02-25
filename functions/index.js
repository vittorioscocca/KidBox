/* eslint-disable max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");

admin.initializeApp();

/**
 * Sums chat, documents and location counters from the given data.
 * @param {object} data - The counter data object.
 * @return {{chat: number, documents: number, location: number, total: number}}
 */
function sumCounters(data) {
  const chat = data?.chat || 0;
  const documents = data?.documents || 0;
  const location = data?.location || 0;
  return {chat, documents, location, total: chat + documents + location};
}

/**
 * Increments a notification counter and returns the updated badge count.
 * @param {object} params - The parameters.
 * @param {string} params.familyId - The family ID.
 * @param {string} params.uid - The user ID.
 * @param {string} params.field - The counter field to increment.
 * @return {Promise<number>} The updated badge total.
 */
async function incrementCounterAndGetBadge({familyId, uid, field}) {
  const ref = admin.firestore()
      .collection("families")
      .doc(familyId)
      .collection("counters")
      .doc(uid);

  const now = admin.firestore.FieldValue.serverTimestamp();

  return await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    const counters = sumCounters(data);

    // calcolo "post increment" senza dover rileggere
    const next = {
      chat: counters.chat + (field === "chat" ? 1 : 0),
      documents: counters.documents + (field === "documents" ? 1 : 0),
      location: counters.location + (field === "location" ? 1 : 0),
    };
    const badge = next.chat + next.documents + next.location;

    tx.set(ref, {
      [field]: admin.firestore.FieldValue.increment(1),
      updatedAt: now,
    }, {merge: true});

    return badge;
  });
}

/**
 * Returns FCM tokens for a user if the given notification preference is enabled.
 * @param {string} uid - The user ID.
 * @param {string} prefField - The notification preference field to check.
 * @return {Promise<string[]>} The list of FCM tokens.
 */
async function getUserTokensIfEnabled(uid, prefField) {
  const userRef = admin.firestore().collection("users").doc(uid);
  const userSnap = await userRef.get();

  const prefs = userSnap.exists ? userSnap.get("notificationPrefs") : null;

  // default ON se non c'è prefs (come già fai per i messaggi)
  const enabled = !prefs || prefs[prefField] !== false;
  if (!enabled) return [];

  const tokensSnap = await userRef.collection("fcmTokens").get();
  const tokens = [];
  tokensSnap.forEach((t) => {
    const tok = t.get("token");
    if (tok) tokens.push(tok);
  });

  return tokens;
}

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

      // 1️⃣ Leggi membri
      const membersSnap = await admin.firestore()
          .collection("families")
          .doc(familyId)
          .collection("members")
          .get();

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

      const title = "Nuovo documento caricato";
      const body = docData.title || docData.fileName || "Documento";

      const messagesToSend = [];

      // 2️⃣ Per ogni membro: incrementa counter + badge corretto
      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewDocs");
        if (tokens.length === 0) continue;

        // Incrementa SOLO documents, ma badge = totale
        const badge = await incrementCounterAndGetBadge({
          familyId,
          uid,
          field: "documents",
        });

        messagesToSend.push({
          tokens,
          notification: {
            title,
            body,
          },
          data: {
            type: "new_document",
            familyId: familyId,
            docId: docId,
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: badge, // ✅ badge corretto (chat + documents)
              },
            },
          },
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewDocument: no per-user notifications to send");
        return;
      }

      // 3️⃣ Invio parallelo per-utente
      const results = await Promise.allSettled(
          messagesToSend.map((msg) =>
            admin.messaging().sendEachForMulticast(msg),
          ),
      );

      let totalSuccess = 0;
      let totalFailure = 0;

      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount;
          totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });

      logger.info("notifyNewDocument: send result", {
        successCount: totalSuccess,
        failureCount: totalFailure,
        userTargets: messagesToSend.length,
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

exports.notifyNewChatMessage = onDocumentCreated(
    {
      document: "families/{familyId}/chatMessages/{messageId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const messageId = event.params.messageId;

      const msgData = event.data ? event.data.data() : null;
      if (!msgData) {
        logger.warn("notifyNewChatMessage: missing message data");
        return;
      }

      if (msgData.isDeleted === true) return;

      const senderUid = msgData.senderId;
      const senderName = msgData.senderName || "Qualcuno";
      if (!senderUid) {
        logger.warn("notifyNewChatMessage: missing senderId");
        return;
      }

      logger.info("notifyNewChatMessage triggered", {familyId, messageId, senderUid});

      // 1) Membri
      const membersSnap = await admin.firestore()
          .collection("families")
          .doc(familyId)
          .collection("members")
          .get();

      if (membersSnap.empty) {
        logger.warn("notifyNewChatMessage: no members found");
        return;
      }

      const memberUids = membersSnap.docs
          .map((d) => d.id)
          .filter((uid) => uid && uid !== senderUid);

      if (memberUids.length === 0) {
        logger.info("notifyNewChatMessage: no targets (only sender in family)");
        return;
      }

      // 2) Body in base al tipo
      const msgType = msgData.typeRaw || "text";
      let body;

      switch (msgType) {
        case "text":
          body = msgData.text || "Nuovo messaggio";
          if (body.length > 100) body = body.substring(0, 97) + "…";
          break;
        case "photo":
          body = "📷 Ha inviato una foto";
          break;
        case "video":
          body = "🎥 Ha inviato un video";
          break;
        case "audio":
          body = "🎤 Ha inviato un messaggio vocale";
          break;
        case "document":
          body = "📎 Ha inviato un documento";
          break;
        default:
          body = "Nuovo messaggio";
      }

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewMessages");
        if (tokens.length === 0) continue;

        // Incrementa SOLO chat, badge = totale
        const badge = await incrementCounterAndGetBadge({
          familyId,
          uid,
          field: "chat",
        });

        messagesToSend.push({
          tokens,
          notification: {
            title: senderName,
            body,
          },
          data: {
            type: "new_chat_message",
            familyId: familyId,
            messageId: messageId,
            senderId: senderUid,
            msgType: msgType,
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: badge, // ✅ badge corretto (chat + documents)
              },
            },
          },
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewChatMessage: no per-user notifications to send");
        return;
      }

      const results = await Promise.allSettled(
          messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)),
      );

      let totalSuccess = 0;
      let totalFailure = 0;

      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount;
          totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });

      logger.info("notifyNewChatMessage: send result", {
        successCount: totalSuccess,
        failureCount: totalFailure,
        userTargets: messagesToSend.length,
      });
    },
);
exports.notifyLocationSharingChanged = onDocumentWritten(
    {
      document: "families/{familyId}/locations/{uid}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const subjectUid = event.params.uid;

      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      // Se documento cancellato o creato senza after, ignora
      if (!after) return;

      const beforeIsSharing = before?.isSharing === true;
      const afterIsSharing = after?.isSharing === true;

      // Trigger solo se cambia isSharing (false->true o true->false)
      if (beforeIsSharing === afterIsSharing) return;

      logger.info("notifyLocationSharingChanged triggered", {
        familyId,
        subjectUid,
        from: beforeIsSharing,
        to: afterIsSharing,
      });

      const locRef = admin.firestore()
          .collection("families")
          .doc(familyId)
          .collection("locations")
          .doc(subjectUid);

      const COOLDOWN_MS = 15 * 1000;
      let shouldSend = false;

      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(locRef);
        const data = snap.exists ? snap.data() : {};
        const last = data?.lastNotifyAt?.toDate ? data.lastNotifyAt.toDate() : null;

        const now = new Date();
        if (!last || (now.getTime() - last.getTime()) >= COOLDOWN_MS) {
          shouldSend = true;
          tx.set(locRef, {
            lastNotifyAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      });

      if (!shouldSend) {
        logger.info("notifyLocationSharingChanged skipped (cooldown)", {
          familyId,
          subjectUid,
        });
        return;
      }

      // Nome da after (se mancante fallback)
      const subjectName = after.name || "Qualcuno";

      // Leggi membri famiglia
      const membersSnap = await admin.firestore()
          .collection("families")
          .doc(familyId)
          .collection("members")
          .get();

      if (membersSnap.empty) {
        logger.warn("notifyLocationSharingChanged: members subcollection is empty");
        return;
      }

      const targetUids = membersSnap.docs
          .map((d) => d.id)
          .filter((uid) => uid && uid !== subjectUid);

      if (targetUids.length === 0) {
        logger.info("notifyLocationSharingChanged: no targets (only subject?)");
        return;
      }

      const title = "Posizione";
      const body = afterIsSharing ?
        `${subjectName} sta condividendo la posizione` :
        `${subjectName} ha smesso di condividere la posizione`;

      const mode = after.mode || null; // "realtime" / "temporary"
      const expiresAt = after.expiresAt || null; // Timestamp o null

      const messagesToSend = [];

      for (const uid of targetUids) {
        // Pref: notifyOnLocationSharing (default ON se non esiste prefs)
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnLocationSharing");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({
          familyId,
          uid,
          field: "location",
        });

        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {
            type: afterIsSharing ? "location_sharing_started" : "location_sharing_stopped",
            familyId: familyId,
            uid: subjectUid,
            name: subjectName,
            mode: mode ? String(mode) : "",
            expiresAt: expiresAt ? String(expiresAt.seconds || "") : "",
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: badge,
              },
            },
          },
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyLocationSharingChanged: no per-user notifications to send");
        return;
      }

      const results = await Promise.allSettled(
          messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)),
      );

      let totalSuccess = 0;
      let totalFailure = 0;

      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount;
          totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });

      logger.info("notifyLocationSharingChanged: send result", {
        successCount: totalSuccess,
        failureCount: totalFailure,
        userTargets: messagesToSend.length,
      });
    },
);
exports.expireTemporaryLocations = onSchedule(
    {
      schedule: "every 5 minutes",
      region: "europe-west1",
      timeZone: "Europe/Rome",
    },
    async () => {
      const now = admin.firestore.Timestamp.now();

      // collectionGroup per /families/{familyId}/locations/{uid}
      const q = admin.firestore()
          .collectionGroup("locations")
          .where("isSharing", "==", true)
          .where("mode", "==", "temporary")
          .where("expiresAt", "<=", now);

      const snap = await q.get();
      if (snap.empty) {
        logger.info("expireTemporaryLocations: nothing to expire");
        return;
      }

      logger.info("expireTemporaryLocations: expiring count=" + snap.size);

      const batchSize = 300;
      let batch = admin.firestore().batch();
      let i = 0;

      for (const doc of snap.docs) {
        batch.set(doc.ref, {
          isSharing: false,
          stoppedReason: "expired",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true});

        i++;
        if (i % batchSize === 0) {
          await batch.commit();
          batch = admin.firestore().batch();
        }
      }

      if (i % batchSize !== 0) {
        await batch.commit();
      }

      logger.info("expireTemporaryLocations: completed expired=" + i);
    },
);
