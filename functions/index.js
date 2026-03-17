/* eslint-disable max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const STORAGE_BUCKET = "kidbox-42cd7-eu";

admin.initializeApp();

/**
 * Ref al documento stats/storage di una famiglia.
 * @param {string} familyId
 * @return {FirebaseFirestore.DocumentReference}
 */
function storageStatsRef(familyId) {
  return admin.firestore()
      .collection("families").doc(familyId)
      .collection("stats").doc("storage");
}

/**
 * Aggiorna usedBytes con un delta atomico.
 * @param {string} familyId
 * @param {number} delta - Byte da aggiungere (positivo) o sottrarre (negativo).
 * @return {Promise<void>}
 */
async function updateStorageBytes(familyId, delta) {
  if (delta === 0) return;
  await storageStatsRef(familyId).set({
    usedBytes: admin.firestore.FieldValue.increment(delta),
    lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});
}

/**
 * Sums chat, documents and location counters from the given data.
 * @param {object} data - The counter data object.
 * @return {{chat: number, documents: number, location: number, total: number}}
 */
function sumCounters(data) {
  const chat = data?.chat || 0;
  const documents = data?.documents || 0;
  const location = data?.location || 0;
  const todos = data?.todos || 0;
  const shopping = data?.shopping || 0;
  const notes = data?.notes || 0;
  const calendar = data?.calendar || 0; // ← NUOVO

  const total = chat + documents + location + todos + shopping + notes + calendar;
  return {chat, documents, location, todos, shopping, notes, calendar, total};
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
      .collection("families").doc(familyId)
      .collection("counters").doc(uid);

  const now = admin.firestore.FieldValue.serverTimestamp();

  return await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    const counters = sumCounters(data);

    const next = {
      chat: counters.chat + (field === "chat" ? 1 : 0),
      documents: counters.documents + (field === "documents" ? 1 : 0),
      location: counters.location + (field === "location" ? 1 : 0),
      todos: counters.todos + (field === "todos" ? 1 : 0),
      shopping: counters.shopping + (field === "shopping" ? 1 : 0),
      notes: counters.notes + (field === "notes" ? 1 : 0),
      calendar: counters.calendar + (field === "calendar" ? 1 : 0),
    };

    let badge = Math.floor(
        next.chat + next.documents + next.location + next.todos + next.shopping + next.notes + next.calendar,
    );

    // safety net: APNS vuole un intero valido
    if (!Number.isFinite(badge) || badge < 0) badge = 0;

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

      // ── Storage tracking ──
      if (!docData.isDeleted && typeof docData.fileSize === "number" && docData.fileSize > 0) {
        await updateStorageBytes(familyId, docData.fileSize);
      }

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
  const bucket = admin.storage().bucket(STORAGE_BUCKET);
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
      invoker: "public",
    },
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

      // ── Storage tracking: solo messaggi con media ──
      if (msgData.mediaStoragePath) {
        const mediaTypes = ["photo", "video", "audio", "document"];
        if (mediaTypes.includes(msgData.typeRaw || "")) {
          await updateStorageBytes(familyId, 512 * 1024);
        }
      }

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
exports.notifyTodoAssigned = onDocumentWritten(
    {
      document: "families/{familyId}/todos/{todoId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const todoId = event.params.todoId;

      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      if (!after) return; // ignore delete
      if (after.isDeleted === true) return;

      const newAssignee = after.assignedTo || null;
      const oldAssignee = before?.assignedTo || null;
      const updatedBy = after.updatedBy;

      if (!newAssignee) return;
      if (newAssignee === updatedBy) return;

      let shouldNotify = false;
      let notificationType = "todo_assigned";

      // 1️⃣ Nuovo todo
      if (!before) {
        shouldNotify = true;
      }

      // 2️⃣ Cambio assegnatario
      if (before && oldAssignee !== newAssignee) {
        shouldNotify = true;
      }

      // 3️⃣ Cambio scadenza
      if (before && oldAssignee === newAssignee) {
        const beforeDue = before.dueAt?.toMillis?.() || null;
        const afterDue = after.dueAt?.toMillis?.() || null;

        if (beforeDue !== afterDue) {
          shouldNotify = true;
          notificationType = "todo_due_changed";
        }
      }

      if (!shouldNotify) return;

      logger.info("notifyTodoAssigned triggered", {
        familyId,
        todoId,
        newAssignee,
      });

      const tokens = await getUserTokensIfEnabled(
          newAssignee,
          "notifyOnTodoAssigned",
      );

      if (tokens.length === 0) return;

      const badge = await incrementCounterAndGetBadge({
        familyId,
        uid: newAssignee,
        field: "todos",
      });

      const payload = {
        tokens,
        notification: {
          title: "Nuovo To-Do",
          body: after.title || "Hai un nuovo promemoria",
        },
        data: {
          type: notificationType,
          familyId,
          childId: after.childId || "",
          listId: after.listId || "",
          todoId,
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: badge,
            },
          },
        },
      };

      const result = await admin.messaging().sendEachForMulticast(payload);

      logger.info("notifyTodoAssigned send result", {
        successCount: result.successCount,
        failureCount: result.failureCount,
      });

      result.responses.forEach((resp, idx) => {
        if (!resp.success) {
          console.error("FCM error detail:", resp.error?.code, resp.error?.message);
        }
      });

      logger.info("notifyTodoAssigned send result", {
        successCount: result.successCount,
        failureCount: result.failureCount,
      });
    },
);
/**
 * Resolves a display name for a uid within a family.
 * 1st: families/{familyId}/members/{uid}.displayName
 * 2nd: users/{uid}.displayName
 * Fallback: "Un membro della famiglia"
 *
 * Needed because GroceryRemoteDTO / NoteRemoteDTO do not carry a *ByName field.
 *
 * @param {string} familyId
 * @param {string} uid
 * @return {Promise<string>}
 */
async function resolveMemberName(familyId, uid) {
  try {
    const memberSnap = await admin.firestore()
        .collection("families").doc(familyId)
        .collection("members").doc(uid)
        .get();

    if (memberSnap.exists) {
      const name = memberSnap.get("displayName") || memberSnap.get("name");
      if (name) return name;
    }

    const userSnap = await admin.firestore()
        .collection("users").doc(uid)
        .get();

    if (userSnap.exists) {
      const name = userSnap.get("displayName") || userSnap.get("name");
      if (name) return name;
    }
  } catch (e) {
    logger.warn("resolveMemberName failed", {uid, error: e.message});
  }

  return "Un membro della famiglia";
}

// ─────────────────────────────────────────────────────────────────────────────
// notifyNewGroceryItem
//
// Path reale Firestore: families/{familyId}/groceries/{itemId}
// Fonte: GroceryRemoteStore.swift → col(familyId:) usa .collection("groceries")
//
// Counter : shopping
// Pref key: notifyOnNewGroceryItem  (default ON se prefs assente)
// ─────────────────────────────────────────────────────────────────────────────

exports.notifyNewGroceryItem = onDocumentCreated(
    {
      document: "families/{familyId}/groceries/{itemId}", // ← "groceries" non "groceryItems"
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const itemId = event.params.itemId;

      const itemData = event.data ? event.data.data() : null;
      if (!itemData) {
        logger.warn("notifyNewGroceryItem: missing item data");
        return;
      }

      // Skip se già soft-deleted alla creazione (edge case)
      if (itemData.isDeleted === true) return;

      // createdBy è il campo canonico — vedi GroceryRemoteStore.upsert()
      const creatorUid = itemData.createdBy || itemData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewGroceryItem: missing creatorUid");
        return;
      }

      logger.info("notifyNewGroceryItem triggered", {familyId, itemId, creatorUid});

      // GroceryRemoteDTO non ha *ByName → risolviamo da members subcollection
      // (admin SDK bypassa le Firestore security rules, nessuna regola aggiuntiva necessaria)
      const creatorName = await resolveMemberName(familyId, creatorUid);

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewGroceryItem: members subcollection is empty");
        return;
      }

      const memberUids = membersSnap.docs
          .map((d) => d.id)
          .filter((uid) => uid && uid !== creatorUid);

      if (memberUids.length === 0) {
        logger.info("notifyNewGroceryItem: no targets");
        return;
      }

      // item.name corrisponde a KBGroceryItem.name / GroceryRemoteDTO.name
      const itemName = itemData.name || "Prodotto";
      const title = "Lista della spesa 🛒";
      const body = `${creatorName} ha aggiunto: ${itemName}`;

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewGroceryItem");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "shopping"});

        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {
            type: "new_grocery_item",
            familyId: familyId,
            itemId: itemId,
          },
          apns: {
            payload: {aps: {sound: "default", badge}},
          },
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewGroceryItem: no per-user notifications to send");
        return;
      }

      const results = await Promise.allSettled(
          messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)),
      );

      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount;
          totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });

      logger.info("notifyNewGroceryItem: send result",
          {successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// notifyNewNote
// Trigger : families/{familyId}/notes/{noteId}  — onDocumentCreated
// Counter : notes
// Pref key: notifyOnNewNote  (default ON)
//
// IMPORTANT: note title/body are E2E-encrypted (NoteCryptoService).
// The function intentionally uses a generic body — encrypted content
// must never be sent in plain text via push payload.
// ─────────────────────────────────────────────────────────────────────────────

exports.notifyNewNote = onDocumentCreated(
    {
      document: "families/{familyId}/notes/{noteId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const noteId = event.params.noteId;

      const noteData = event.data ? event.data.data() : null;
      if (!noteData) {
        logger.warn("notifyNewNote: missing note data");
        return;
      }

      if (noteData.isDeleted === true) return;

      // createdBy matches KBNote / NoteRemoteDTO
      const creatorUid = noteData.createdBy || noteData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewNote: missing creatorUid");
        return;
      }

      logger.info("notifyNewNote triggered", {familyId, noteId, creatorUid});

      const creatorName = await resolveMemberName(familyId, creatorUid);

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewNote: members subcollection is empty");
        return;
      }

      const memberUids = membersSnap.docs
          .map((d) => d.id)
          .filter((uid) => uid && uid !== creatorUid);

      if (memberUids.length === 0) {
        logger.info("notifyNewNote: no targets");
        return;
      }

      // Generic body — title is encrypted, never readable server-side
      const title = "📝 Nuova nota";
      const body = `${creatorName} ha aggiunto una nuova nota`;

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewNote");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "notes"});

        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {
            type: "new_note",
            familyId,
            noteId,
          },
          apns: {
            payload: {aps: {sound: "default", badge}},
          },
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewNote: no per-user notifications to send");
        return;
      }

      const results = await Promise.allSettled(
          messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)),
      );

      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount;
          totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });

      logger.info("notifyNewNote: send result",
          {successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);
// ─────────────────────────────────────────────────────────────────────────────
// AI Assistant — askAI + getAIUsage
//
// Incolla questo blocco in fondo al tuo index.js esistente.
//
// Prima del deploy, imposta il secret:
//   firebase functions:secrets:set ANTHROPIC_API_KEY
//
// Firestore path usato:
//   ai_usage/{uid}/daily/{YYYY-MM-DD}  →  { count, updatedAt, uid }
// ─────────────────────────────────────────────────────────────────────────────

const {defineSecret} = require("firebase-functions/params");
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Returns today's date as YYYY-MM-DD in Europe/Rome timezone.
 * @return {string}
 */
function aiTodayKey() {
  return new Date().toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"});
}

/**
 * Reads the user's plan from Firestore and returns the daily message limit.
 * free=20 / family=50 / pro=100
 * @param {string} uid
 * @return {Promise<number>}
 */
async function resolveAIDailyLimit(uid) {
  try {
    const snap = await admin.firestore().collection("users").doc(uid).get();
    const plan = snap.exists ? (snap.data().plan || "free") : "free";
    switch (plan) {
      case "pro": return 100;
      case "family": return 50;
      case "free":
      default: return 20;
    }
  } catch (e) {
    logger.warn("resolveAIDailyLimit failed, using default", {uid, error: e.message});
    return 20;
  }
}

/**
 * Checks the daily counter and increments it atomically.
 * Throws HttpsError("resource-exhausted") if the limit is reached.
 * @param {string} uid
 * @param {number} limit
 * @return {Promise<number>} updated count
 */
async function checkAndIncrementAIUsage(uid, limit) {
  const ref = admin.firestore()
      .collection("ai_usage").doc(uid)
      .collection("daily").doc(aiTodayKey());

  return await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? (snap.data().count || 0) : 0;

    if (current >= limit) {
      throw new HttpsError(
          "resource-exhausted",
          `Hai raggiunto il limite di ${limit} messaggi AI per oggi. Riprova domani.`,
      );
    }

    tx.set(ref, {
      count: admin.firestore.FieldValue.increment(1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      uid,
    }, {merge: true});

    return current + 1;
  });
}

// ─── askAI ───────────────────────────────────────────────────────────────────

exports.askAI = onCall(
    {
      region: "europe-west1",
      invoker: "public",
      secrets: [ANTHROPIC_API_KEY],
      timeoutSeconds: 60,
    },
    async (request) => {
      // 1. Auth
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      }

      // 2. Validazione input
      const {messages, systemPrompt} = request.data || {};

      if (!Array.isArray(messages) || messages.length === 0) {
        throw new HttpsError("invalid-argument", "messages è richiesto.");
      }
      const validRoles = ["user", "assistant"];
      const allValid = messages.every(
          (m) => typeof m.role === "string" &&
                 typeof m.content === "string" &&
                 validRoles.includes(m.role),
      );
      if (!allValid) {
        throw new HttpsError("invalid-argument", "messages non valido.");
      }
      if (typeof systemPrompt !== "string" || systemPrompt.trim().length === 0) {
        throw new HttpsError("invalid-argument", "systemPrompt è richiesto.");
      }

      // Protezione dimensione payload
      const totalChars = messages.reduce((acc, m) => acc + m.content.length, 0) + systemPrompt.length;
      if (totalChars > 50000) {
        throw new HttpsError("invalid-argument", "Payload troppo grande.");
      }

      // 3. Rate limiting
      const dailyLimit = await resolveAIDailyLimit(uid);
      const usageCount = await checkAndIncrementAIUsage(uid, dailyLimit);

      logger.info("askAI request", {uid, usageCount, dailyLimit, msgCount: messages.length});

      // 4. Chiama Anthropic
      const apiKey = ANTHROPIC_API_KEY.value();
      if (!apiKey) {
        logger.error("askAI: ANTHROPIC_API_KEY secret non configurato");
        throw new HttpsError("internal", "Configurazione AI non disponibile.");
      }

      let reply;
      try {
        const fetch = (await import("node-fetch")).default;

        const res = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
          },
          body: JSON.stringify({
            model: "claude-sonnet-4-20250514",
            max_tokens: 1024,
            system: systemPrompt,
            messages: messages.map((m) => ({role: m.role, content: m.content})),
          }),
        });

        if (res.status === 429) {
          throw new HttpsError(
              "resource-exhausted",
              "Servizio AI temporaneamente sovraccarico. Riprova tra qualche secondo.",
          );
        }
        if (!res.ok) {
          const errText = await res.text();
          logger.error("askAI: Anthropic error", {status: res.status, body: errText});
          throw new HttpsError("internal", "Errore dal servizio AI.");
        }

        const json = await res.json();
        reply = json?.content?.[0]?.text;

        if (!reply) {
          throw new HttpsError("internal", "Risposta AI non valida.");
        }
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        logger.error("askAI: fetch failed", {error: e.message});
        throw new HttpsError("internal", "Impossibile contattare il servizio AI.");
      }

      logger.info("askAI success", {uid, usageCount});

      return {reply, usageToday: usageCount, dailyLimit};
    },
);

// ─── getAIUsage ───────────────────────────────────────────────────────────────

exports.getAIUsage = onCall(
    {
      region: "europe-west1",
      invoker: "public",
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");

      const ref = admin.firestore()
          .collection("ai_usage").doc(uid)
          .collection("daily").doc(aiTodayKey());

      const snap = await ref.get();
      const count = snap.exists ? (snap.data().count || 0) : 0;
      const dailyLimit = await resolveAIDailyLimit(uid);

      return {usageToday: count, dailyLimit};
    },
);
// ── NUOVA FUNCTION: notifyNewCalendarEvent ────────────────────────────────────
// Trigger: creazione di un evento in families/{familyId}/calendarEvents/{eventId}
// Counter: calendar
// Pref:    notifyOnNewCalendarEvent (default ON)
// Badge:   somma di tutti i contatori (incluso calendar)

exports.notifyNewCalendarEvent = onDocumentCreated(
    {
      document: "families/{familyId}/calendarEvents/{eventId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const eventId = event.params.eventId;

      const eventData = event.data ? event.data.data() : null;
      if (!eventData) {
        logger.warn("notifyNewCalendarEvent: missing event data");
        return;
      }

      // Ignora eventi soft-deleted alla creazione (edge case)
      if (eventData.isDeleted === true) return;

      const creatorUid = eventData.createdBy || eventData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewCalendarEvent: missing creatorUid");
        return;
      }

      logger.info("notifyNewCalendarEvent triggered", {familyId, eventId, creatorUid});

      // Risolvi il nome del creatore
      const creatorName = await resolveMemberName(familyId, creatorUid);

      // Leggi tutti i membri della famiglia
      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewCalendarEvent: members subcollection is empty");
        return;
      }

      // Notifica a tutti tranne chi ha creato l'evento
      const memberUids = membersSnap.docs
          .map((d) => d.id)
          .filter((uid) => uid && uid !== creatorUid);

      if (memberUids.length === 0) {
        logger.info("notifyNewCalendarEvent: no targets (only creator)");
        return;
      }

      // Componi titolo e body
      const eventTitle = eventData.title || "Nuovo evento";
      const startDate = eventData.startDate?.toDate?.();
      let dateStr = "";
      if (startDate) {
        dateStr = startDate.toLocaleDateString("it-IT", {
          timeZone: "Europe/Rome",
          day: "numeric",
          month: "long",
        });
      }

      const title = "📅 Calendario";
      const body = dateStr ?
        `${creatorName} ha aggiunto: ${eventTitle} — ${dateStr}` :
        `${creatorName} ha aggiunto: ${eventTitle}`;

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewCalendarEvent");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({
          familyId,
          uid,
          field: "calendar",
        });

        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {
            type: "new_calendar_event",
            familyId: familyId,
            eventId: eventId,
          },
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge,
              },
            },
          },
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewCalendarEvent: no per-user notifications to send");
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

      logger.info("notifyNewCalendarEvent: send result", {
        successCount: totalSuccess,
        failureCount: totalFailure,
        userTargets: messagesToSend.length,
      });
    },
);

// ── Hard-delete documento → sottrai fileSize dal contatore storage ────────────

exports.onDocumentHardDeleted = onDocumentWritten(
    {
      document: "families/{familyId}/documents/{docId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      // Solo hard-delete: documento esisteva prima e non esiste più
      if (!before || after) return;

      const sizeBefore = typeof before.fileSize === "number" ? before.fileSize : 0;
      if (sizeBefore <= 0) return;

      logger.info("onDocumentHardDeleted: removing bytes", {familyId, sizeBefore});
      await updateStorageBytes(familyId, -sizeBefore);
    },
);

// ── Callable: il client legge usedBytes e quotaBytes ─────────────────────────

exports.getStorageUsage = onCall(
    {
      region: "europe-west1",
      invoker: "public",
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      }
      const {familyId} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }
      const memberSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").doc(uid)
          .get();
      if (!memberSnap.exists) {
        throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.");
      }
      const snap = await storageStatsRef(familyId).get();
      const usedBytes = snap.exists ? (snap.data().usedBytes || 0) : 0;
      logger.info("getStorageUsage", {uid, familyId, usedBytes});
      return {
        usedBytes: Math.max(0, Math.round(usedBytes)),
        quotaBytes: 200 * 1024 * 1024,
      };
    },
);

// ── Inizializzazione contatore storage per dati storici ───────────────────────
// Chiamare UNA VOLTA SOLA per famiglia dopo il deploy.
// Calcola lo stato attuale leggendo Firestore e sovrascrive usedBytes.

exports.initStorageUsage = onCall(
    {
      region: "europe-west1",
      invoker: "public",
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) {
        throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      }
      const {familyId} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }

      // Verifica membership
      const memberSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("members").doc(uid)
          .get();
      if (!memberSnap.exists) {
        throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.");
      }

      logger.info("initStorageUsage: starting", {uid, familyId});

      // 1. Somma fileSize di tutti i documenti non eliminati
      const docsSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("documents")
          .where("isDeleted", "==", false)
          .get();

      let docBytes = 0;
      docsSnap.forEach((d) => {
        const size = d.get("fileSize");
        if (typeof size === "number" && size > 0) docBytes += size;
      });

      // 2. Conta messaggi chat con media (non eliminati)
      const chatSnap = await admin.firestore()
          .collection("families").doc(familyId)
          .collection("chatMessages")
          .where("isDeleted", "==", false)
          .get();

      const mediaTypes = ["photo", "video", "audio", "document"];
      let chatMediaCount = 0;
      chatSnap.forEach((d) => {
        const hasMedia = d.get("mediaStoragePath");
        const type = d.get("typeRaw") || "";
        if (hasMedia && mediaTypes.includes(type)) chatMediaCount++;
      });

      const chatBytes = chatMediaCount * 512 * 1024;
      const totalBytes = docBytes + chatBytes;

      // 3. Sovrascrive il contatore (non increment, set diretto)
      await storageStatsRef(familyId).set({
        usedBytes: totalBytes,
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        initializedAt: admin.firestore.FieldValue.serverTimestamp(),
        initializedBy: uid,
      }, {merge: false});

      logger.info("initStorageUsage: completed", {
        familyId,
        docBytes,
        chatBytes,
        chatMediaCount,
        totalBytes,
      });

      return {
        docBytes,
        chatBytes,
        chatMediaCount,
        totalBytes,
        quotaBytes: 200 * 1024 * 1024,
      };
    },
);
