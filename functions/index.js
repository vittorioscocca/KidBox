/* eslint-disable max-len */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentWritten} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const STORAGE_BUCKET = "kidbox-42cd7-eu";

/** Stima foto visita pediatrica (allineata a initStorageUsage / client). */
const VISIT_PHOTO_ESTIMATE_BYTES = 200 * 1024;

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
 * Aggiorna usedBytes e il breakdown per sezione con un delta atomico.
 * @param {string} familyId
 * @param {number} delta - Byte da aggiungere (positivo) o sottrarre (negativo).
 * @param {string|null} section - Sezione da aggiornare.
 * @return {Promise<void>}
 */
async function updateStorageBytes(familyId, delta, section = null) {
  if (delta === 0) return;

  const update = {
    usedBytes: admin.firestore.FieldValue.increment(delta),
    lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (section) {
    update[`sections.${section}`] = admin.firestore.FieldValue.increment(delta);
  }

  await storageStatsRef(familyId).set(update, {merge: true});
}

/**
 * Returns wallet ticket PDF size in bytes (>= 0).
 * @param {object|null} data
 * @return {number}
 */
function walletPdfBytes(data) {
  const raw = data?.pdfStorageBytes;
  if (typeof raw !== "number" || !Number.isFinite(raw) || raw <= 0) return 0;
  return Math.round(raw);
}

/**
 * Resolves wallet PDF size, with fallback to Storage metadata for legacy docs.
 * @param {string} familyId
 * @param {string} ticketId
 * @param {object|null} data
 * @return {Promise<number>}
 */
async function resolveWalletPdfBytes(familyId, ticketId, data) {
  const explicit = walletPdfBytes(data);
  if (explicit > 0) return explicit;

  const path = `families/${familyId}/wallet/${ticketId}/ticket.pdf.kbenc`;
  try {
    const bucket = admin.storage().bucket(STORAGE_BUCKET);
    const [meta] = await bucket.file(path).getMetadata();
    const size = Number(meta?.size || 0);
    if (!Number.isFinite(size) || size <= 0) return 0;
    return Math.round(size);
  } catch (e) {
    logger.warn("resolveWalletPdfBytes: metadata lookup failed", {familyId, ticketId, path, err: e.message});
    return 0;
  }
}

/**
 * Ricalcola byte “media” (Firebase Storage + stime visite) dalla sola Firestore,
 * escludendo record con isDeleted === true. Allineato a initStorageUsage.
 * @param {string} familyId
 * @return {Promise<{docBytes: number, walletBytes: number, chatBytes: number, photoBytes: number, saluteBytes: number}>}
 */
async function computeMediaStorageBytesForFamily(familyId) {
  const kb = 1024;
  const mediaTypes = ["photo", "video", "audio", "document"];
  const db = admin.firestore();

  const [docsSnap, walletSnap, chatSnap, photosSnap, visitsSnap] = await Promise.all([
    db.collection("families").doc(familyId).collection("documents").where("isDeleted", "==", false).get(),
    db.collection("families").doc(familyId).collection("walletTickets").where("isDeleted", "==", false).get(),
    db.collection("families").doc(familyId).collection("chatMessages").where("isDeleted", "==", false).get(),
    db.collection("families").doc(familyId).collection("photos").where("isDeleted", "==", false).get(),
    db.collection("families").doc(familyId).collection("medicalVisits").where("isDeleted", "==", false).get(),
  ]);

  let docBytes = 0;
  docsSnap.forEach((d) => {
    const size = d.get("fileSize");
    if (typeof size === "number" && size > 0) docBytes += size;
  });

  let walletBytes = 0;
  for (const d of walletSnap.docs) {
    walletBytes += await resolveWalletPdfBytes(familyId, d.id, d.data());
  }

  let chatBytes = 0;
  chatSnap.forEach((d) => {
    const hasMedia = d.get("mediaStoragePath");
    const type = d.get("type") || "";
    if (hasMedia && mediaTypes.includes(type)) {
      const size = d.get("mediaFileSize");
      chatBytes += (typeof size === "number" && size > 0) ? size : 512 * kb;
    }
  });

  let photoBytes = 0;
  photosSnap.forEach((d) => {
    const size = d.get("fileSize");
    if (typeof size === "number" && size > 0) photoBytes += size;
  });

  let saluteBytes = 0;
  visitsSnap.forEach((d) => {
    const photoURLs = d.get("photoURLs");
    if (Array.isArray(photoURLs) && photoURLs.length > 0) {
      saluteBytes += photoURLs.length * VISIT_PHOTO_ESTIMATE_BYTES;
    }
  });

  return {
    docBytes,
    walletBytes,
    chatBytes,
    photoBytes,
    saluteBytes,
  };
}

/**
 * Sums notification counters from the given data.
 * @param {object} data - The counter data object.
 * @return {object}
 */
function sumCounters(data) {
  const chat = data?.chat || 0;
  const documents = data?.documents || 0;
  const location = data?.location || 0;
  const todos = data?.todos || 0;
  const shopping = data?.shopping || 0;
  const notes = data?.notes || 0;
  const calendar = data?.calendar || 0;
  const expenses = data?.expenses || 0;
  const wallet = data?.wallet || 0;

  const total = chat + documents + location + todos + shopping + notes + calendar + expenses + wallet;
  return {chat, documents, location, todos, shopping, notes, calendar, expenses, wallet, total};
}

/**
 * Increments a notification counter and returns the updated badge count.
 * @param {object} params
 * @param {string} params.familyId
 * @param {string} params.uid
 * @param {string} params.field
 * @return {Promise<number>}
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
      expenses: counters.expenses + (field === "expenses" ? 1 : 0),
      wallet: counters.wallet + (field === "wallet" ? 1 : 0),
    };

    let badge = Math.floor(
        next.chat + next.documents + next.location + next.todos + next.shopping + next.notes + next.calendar + next.expenses + next.wallet,
    );

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
 * @param {string} uid
 * @param {string} prefField
 * @return {Promise<string[]>}
 */
async function getUserTokensIfEnabled(uid, prefField) {
  const userRef = admin.firestore().collection("users").doc(uid);
  const userSnap = await userRef.get();

  const prefs = userSnap.exists ? userSnap.get("notificationPrefs") : null;

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

// ─────────────────────────────────────────────────────────────────────────────
// DOCUMENTI
// ─────────────────────────────────────────────────────────────────────────────

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

      // ── Storage tracking: fileSize reale ──
      if (!docData.isDeleted && typeof docData.fileSize === "number" && docData.fileSize > 0) {
        await updateStorageBytes(familyId, docData.fileSize, "documents");
      }

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

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

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewDocs");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "documents"});

        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {type: "new_document", familyId, docId},
          apns: {payload: {aps: {sound: "default", badge}}},
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewDocument: no per-user notifications to send");
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

      logger.info("notifyNewDocument: send result", {successCount: totalSuccess, failureCount: totalFailure});
    },
);

exports.onDocumentHardDeleted = onDocumentWritten(
    {
      document: "families/{familyId}/documents/{docId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      if (!before || after) return;

      // Soft-delete aveva già sottratto i byte; alla cancellazione fisica non ricalcolare.
      if (before.isDeleted === true) return;

      const sizeBefore = typeof before.fileSize === "number" ? before.fileSize : 0;
      if (sizeBefore <= 0) return;

      logger.info("onDocumentHardDeleted: removing bytes", {familyId, sizeBefore});
      await updateStorageBytes(familyId, -sizeBefore, "documents");
    },
);

/** Soft-delete documento (isDeleted → true): toglie subito byte da stats (come iOS dopo init/live). */
exports.onDocumentSoftDeleted = onDocumentWritten(
    {
      document: "families/{familyId}/documents/{docId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      if (!before || !after) return;
      if (before.isDeleted === true) return;
      if (after.isDeleted !== true) return;

      const size = typeof before.fileSize === "number" ? before.fileSize : 0;
      if (size <= 0) return;

      logger.info("onDocumentSoftDeleted: removing bytes", {familyId, size});
      await updateStorageBytes(familyId, -size, "documents");
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// CHAT
// ─────────────────────────────────────────────────────────────────────────────

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

      // ── Storage tracking: solo file media, dimensione reale ──────────────
      // I messaggi di testo NON occupano Firebase Storage → non contati.
      // mediaFileSize è il campo aggiunto a KBChatMessage: contiene la dimensione
      // reale del file caricato su Storage. Fallback 512KB per messaggi precedenti.
      if (msgData.mediaStoragePath) {
        const mediaTypes = ["photo", "video", "audio", "document"];
        if (mediaTypes.includes(msgData.type || "")) {
          const mediaFileSize = (typeof msgData.mediaFileSize === "number" && msgData.mediaFileSize > 0) ?
            msgData.mediaFileSize :
            512 * 1024;
          await updateStorageBytes(familyId, mediaFileSize, "chat");
          logger.info("notifyNewChatMessage: storage tracked", {
            familyId,
            messageId,
            bytes: mediaFileSize,
            source: msgData.mediaFileSize ? "real" : "fallback",
          });
        }
      }

      const senderUid = msgData.senderId;
      const senderName = msgData.senderName || "Qualcuno";
      if (!senderUid) {
        logger.warn("notifyNewChatMessage: missing senderId");
        return;
      }

      logger.info("notifyNewChatMessage triggered", {familyId, messageId, senderUid});

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

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

      const msgType = msgData.type || "text";
      let body;
      switch (msgType) {
        case "text":
          body = msgData.text || "Nuovo messaggio";
          if (body.length > 100) body = body.substring(0, 97) + "…";
          break;
        case "photo": body = "📷 Ha inviato una foto"; break;
        case "video": body = "🎥 Ha inviato un video"; break;
        case "audio": body = "🎤 Ha inviato un messaggio vocale"; break;
        case "document": body = "📎 Ha inviato un documento"; break;
        default: body = "Nuovo messaggio";
      }

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewMessages");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "chat"});
        const data = {
          type: "new_chat_message",
          familyId,
          messageId,
          senderId: senderUid,
          senderName,
          msgType,
          fallbackBody: body, // used by the iOS extension if decryption fails
        };
        if (typeof msgData.textEnc === "string" && msgData.textEnc.length > 0) {
          data.textEnc = msgData.textEnc;
        }

        messagesToSend.push({
          tokens,
          notification: {title: senderName, body},
          data,
          apns: {
            payload: {
              aps: {
                // mutable-content tells iOS to invoke the Notification Service Extension
                // so it can decrypt textEnc client-side before the notification is displayed.
                "mutable-content": 1,
                alert: {title: senderName, body},
                sound: "default",
                badge,
              },
            },
          },
          android: {
            notification: {sound: "default"},
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

// Sottrae i bytes quando un messaggio con media viene soft-deleted.
// Usa mediaFileSize reale; fallback 512KB per messaggi precedenti al campo.
exports.onChatMessageSoftDeleted = onDocumentWritten(
    {
      document: "families/{familyId}/chatMessages/{messageId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      if (!before || !after) return;
      if (before.isDeleted === true) return;
      if (after.isDeleted !== true) return;

      const mediaPath = after.mediaStoragePath || before.mediaStoragePath || "";
      if (!mediaPath) return;

      const mediaTypes = ["photo", "video", "audio", "document"];
      const type = after.type || before.type || "";
      if (!mediaTypes.includes(type)) return;

      // Usa il fileSize reale registrato sul messaggio.
      // Fallback 512KB per messaggi anteriori all'introduzione del campo.
      const mediaFileSize = after.mediaFileSize || before.mediaFileSize || null;
      const delta = (typeof mediaFileSize === "number" && mediaFileSize > 0) ?
        -mediaFileSize :
        -(512 * 1024);

      logger.info("onChatMessageSoftDeleted: freeing bytes", {
        familyId,
        messageId: event.params.messageId,
        bytes: Math.abs(delta),
        source: mediaFileSize ? "real" : "fallback",
      });

      await updateStorageBytes(familyId, delta, "chat");
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// FOTO ALBUM CONDIVISO
// ─────────────────────────────────────────────────────────────────────────────

exports.onPhotoCreated = onDocumentCreated(
    {
      document: "families/{familyId}/photos/{photoId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const data = event.data ? event.data.data() : null;
      if (!data) return;

      if (!data.isDeleted && typeof data.fileSize === "number" && data.fileSize > 0) {
        logger.info("onPhotoCreated: adding bytes", {familyId, fileSize: data.fileSize});
        await updateStorageBytes(familyId, data.fileSize, "photos");
      }
    },
);

exports.onPhotoHardDeleted = onDocumentWritten(
    {
      document: "families/{familyId}/photos/{photoId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      if (!before || after) return;

      // Stesso comportamento dei documenti: soft-delete aveva già liberato byte.
      if (before.isDeleted === true) return;

      const sizeBefore = typeof before.fileSize === "number" ? before.fileSize : 0;
      if (sizeBefore <= 0) return;

      logger.info("onPhotoHardDeleted: removing bytes", {familyId, sizeBefore});
      await updateStorageBytes(familyId, -sizeBefore, "photos");
    },
);

/** Soft-delete foto album (isDeleted → true): allinea stats a Firebase (solo hard delete decrementava prima). */
exports.onPhotoSoftDeleted = onDocumentWritten(
    {
      document: "families/{familyId}/photos/{photoId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      if (!before || !after) return;
      if (before.isDeleted === true) return;
      if (after.isDeleted !== true) return;

      const sizeBefore = typeof before.fileSize === "number" ? before.fileSize : 0;
      if (sizeBefore <= 0) return;

      logger.info("onPhotoSoftDeleted: removing bytes", {familyId, sizeBefore});
      await updateStorageBytes(familyId, -sizeBefore, "photos");
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// SALUTE — foto visite pediatriche
// Quando una visita viene creata/aggiornata con photoURLs, aggiorna lo storage.
// Stima 200KB per foto (compressa, media mobile) perché non c'è fileSize nel modello.
// ─────────────────────────────────────────────────────────────────────────────

exports.onMedicalVisitWritten = onDocumentWritten(
    {
      document: "families/{familyId}/medicalVisits/{visitId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      // Hard delete: rimuovi i bytes delle foto che c'erano
      if (before && !after) {
        const photosBefore = Array.isArray(before.photoURLs) ? before.photoURLs.length : 0;
        if (photosBefore > 0) {
          const delta = -(photosBefore * VISIT_PHOTO_ESTIMATE_BYTES);
          logger.info("onMedicalVisitWritten: hard delete, freeing photo bytes", {familyId, delta});
          await updateStorageBytes(familyId, delta, "salute");
        }
        return;
      }

      if (!after) return;

      const photosAfter = Array.isArray(after.photoURLs) ? after.photoURLs.length : 0;
      const photosBefore = before && Array.isArray(before.photoURLs) ? before.photoURLs.length : 0;
      const photoDelta = photosAfter - photosBefore;

      if (photoDelta === 0) return;

      const bytesDelta = photoDelta * VISIT_PHOTO_ESTIMATE_BYTES;
      logger.info("onMedicalVisitWritten: photo delta", {familyId, photoDelta, bytesDelta});
      await updateStorageBytes(familyId, bytesDelta, "salute");
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// POSIZIONE
// ─────────────────────────────────────────────────────────────────────────────

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

      if (!after) return;

      const beforeIsSharing = before?.isSharing === true;
      const afterIsSharing = after?.isSharing === true;

      if (beforeIsSharing === afterIsSharing) return;

      logger.info("notifyLocationSharingChanged triggered", {familyId, subjectUid, from: beforeIsSharing, to: afterIsSharing});

      const locRef = admin.firestore()
          .collection("families").doc(familyId)
          .collection("locations").doc(subjectUid);

      const COOLDOWN_MS = 15 * 1000;
      let shouldSend = false;

      await admin.firestore().runTransaction(async (tx) => {
        const snap = await tx.get(locRef);
        const data = snap.exists ? snap.data() : {};
        const last = data?.lastNotifyAt?.toDate ? data.lastNotifyAt.toDate() : null;

        const now = new Date();
        if (!last || (now.getTime() - last.getTime()) >= COOLDOWN_MS) {
          shouldSend = true;
          tx.set(locRef, {lastNotifyAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
        }
      });

      if (!shouldSend) {
        logger.info("notifyLocationSharingChanged skipped (cooldown)", {familyId, subjectUid});
        return;
      }

      const subjectName = after.name || "Qualcuno";

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

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

      const mode = after.mode || null;
      const expiresAt = after.expiresAt || null;
      const messagesToSend = [];

      for (const uid of targetUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnLocationSharing");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "location"});

        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {
            type: afterIsSharing ? "location_sharing_started" : "location_sharing_stopped",
            familyId,
            uid: subjectUid,
            name: subjectName,
            mode: mode ? String(mode) : "",
            expiresAt: expiresAt ? String(expiresAt.seconds || "") : "",
          },
          apns: {payload: {aps: {sound: "default", badge}}},
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

      logger.info("notifyLocationSharingChanged: send result", {successCount: totalSuccess, failureCount: totalFailure});
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

// ─────────────────────────────────────────────────────────────────────────────
// TODO
// ─────────────────────────────────────────────────────────────────────────────

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

      if (!after) return;
      if (after.isDeleted === true) return;

      const newAssignee = after.assignedTo || null;
      const oldAssignee = before?.assignedTo || null;
      const updatedBy = after.updatedBy;

      if (!newAssignee) return;
      if (newAssignee === updatedBy) return;

      let shouldNotify = false;
      let notificationType = "todo_assigned";

      if (!before) {
        shouldNotify = true;
      }
      if (before && oldAssignee !== newAssignee) {
        shouldNotify = true;
      }
      if (before && oldAssignee === newAssignee) {
        const beforeDue = before.dueAt?.toMillis?.() || null;
        const afterDue = after.dueAt?.toMillis?.() || null;
        if (beforeDue !== afterDue) {
          shouldNotify = true;
          notificationType = "todo_due_changed";
        }
      }

      if (!shouldNotify) return;

      logger.info("notifyTodoAssigned triggered", {familyId, todoId, newAssignee});

      const tokens = await getUserTokensIfEnabled(newAssignee, "notifyOnTodoAssigned");
      if (tokens.length === 0) return;

      const badge = await incrementCounterAndGetBadge({familyId, uid: newAssignee, field: "todos"});

      const payload = {
        tokens,
        notification: {title: "Nuovo To-Do", body: after.title || "Hai un nuovo promemoria"},
        data: {type: notificationType, familyId, childId: after.childId || "", listId: after.listId || "", todoId},
        apns: {payload: {aps: {sound: "default", badge}}},
      };

      const result = await admin.messaging().sendEachForMulticast(payload);
      result.responses.forEach((resp) => {
        if (!resp.success) {
          console.error("FCM error detail:", resp.error?.code, resp.error?.message);
        }
      });

      logger.info("notifyTodoAssigned send result", {successCount: result.successCount, failureCount: result.failureCount});
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Resolves a display name for a uid within a family.
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

    const userSnap = await admin.firestore().collection("users").doc(uid).get();
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
// SPESA
// ─────────────────────────────────────────────────────────────────────────────

exports.notifyNewGroceryItem = onDocumentCreated(
    {
      document: "families/{familyId}/groceries/{itemId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const itemId = event.params.itemId;

      const itemData = event.data ? event.data.data() : null;
      if (!itemData) {
        logger.warn("notifyNewGroceryItem: missing item data"); return;
      }
      if (itemData.isDeleted === true) return;

      const creatorUid = itemData.createdBy || itemData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewGroceryItem: missing creatorUid"); return;
      }

      logger.info("notifyNewGroceryItem triggered", {familyId, itemId, creatorUid});

      const creatorName = await resolveMemberName(familyId, creatorUid);

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewGroceryItem: members subcollection is empty"); return;
      }

      const memberUids = membersSnap.docs.map((d) => d.id).filter((uid) => uid && uid !== creatorUid);
      if (memberUids.length === 0) {
        logger.info("notifyNewGroceryItem: no targets"); return;
      }

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
          data: {type: "new_grocery_item", familyId, itemId},
          apns: {payload: {aps: {sound: "default", badge}}},
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewGroceryItem: no per-user notifications to send"); return;
      }

      const results = await Promise.allSettled(messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)));
      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount; totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });
      logger.info("notifyNewGroceryItem: send result", {successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// NOTE
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
        logger.warn("notifyNewNote: missing note data"); return;
      }
      if (noteData.isDeleted === true) return;

      const creatorUid = noteData.createdBy || noteData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewNote: missing creatorUid"); return;
      }

      logger.info("notifyNewNote triggered", {familyId, noteId, creatorUid});

      const creatorName = await resolveMemberName(familyId, creatorUid);

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewNote: members subcollection is empty"); return;
      }

      const memberUids = membersSnap.docs.map((d) => d.id).filter((uid) => uid && uid !== creatorUid);
      if (memberUids.length === 0) {
        logger.info("notifyNewNote: no targets"); return;
      }

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
          data: {type: "new_note", familyId, noteId},
          apns: {payload: {aps: {sound: "default", badge}}},
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewNote: no per-user notifications to send"); return;
      }

      const results = await Promise.allSettled(messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)));
      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount; totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });
      logger.info("notifyNewNote: send result", {successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// AI — askAI + getAIUsage
// ─────────────────────────────────────────────────────────────────────────────

const {defineSecret} = require("firebase-functions/params");
const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const GOOGLE_PLACES_API_KEY = defineSecret("GOOGLE_PLACES_API_KEY");
/** Chat, note, todo e task non clinici. */
const ANTHROPIC_MODEL_DEFAULT = "claude-haiku-4-5-20251001";
const ANTHROPIC_INPUT_USD_PER_1M_HAIKU = 1.0;
const ANTHROPIC_OUTPUT_USD_PER_1M_HAIKU = 5.0;
/**
 * Cartella clinica + PDF: richiede ragionamento contestuale (non summarization).
 * NON usare Haiku — confonde date GG/MM con pressione e fonde lesioni distinte.
 */
const ANTHROPIC_MODEL_CLINICAL_RECORD = "claude-sonnet-4-5";
const ANTHROPIC_INPUT_USD_PER_1M_SONNET = 3.0;
const ANTHROPIC_OUTPUT_USD_PER_1M_SONNET = 15.0;
const CLINICAL_RECORD_MAX_TOKENS = 4096;

/** Regole server aggiunte al system prompt cartella clinica (affiancano il prompt client). */
const CLINICAL_RECORD_SYSTEM_RULES = `
VINCOLI SERVER (cartella clinica):
Prosa narrativa continua per ogni sezione: vietati bullet, trattini elenco, elenchi numerati.
NON inferire valori assenti nei dati. Date GG/MM non sono pressione arteriosa.
Lesioni distinte per tipo, sede e mm. Confronto temporale solo con ≥2 misure della stessa entità.
Se manca un dato: "Non sono disponibili misurazioni per questo parametro".
Se tendi a elencare, riformula con "inoltre", "mentre", "al contrario".
UNITÀ FARMACI: compresse/capsule → mg o mcg (mai ml); liquidi orali → ml; iniettabili → mg/ml o UI (es. Ezetimibe 10 mg, NON 10 ml).
TRANSAMINASI+STATINA: se terapia sospesa e rialzo GOT/GPT nello stesso periodo, esplicita il nesso causale in prosa.
NO sezione standalone PRESSIONE ARTERIOSA: i dati PA solo in CARDIOLOGIA.
Se >4 misure PA nello stesso anno: range min-max, ultimo valore, tendenza (non elencare tutte).
APPLE HEALTH: sezione opzionale con disclaimer wearable consumer; FC a riposo, VO2, minuti attività, SpO2 notturna, passi, HRV; fasce età per VO2; sintesi attività fisica.
`.trim();

/**
 * Sonnet solo per generazione cartella clinica (non chat Salute: visite, esami, home).
 * Il client deve inviare purpose esplicito; niente euristica su testo/prompt.
 * @param {object} data body della callable
 * @return {boolean}
 */
function isClinicalRecordAskAI(data) {
  return data?.purpose === "clinicalRecord";
}

/**
 * Returns today's date as YYYY-MM-DD in Europe/Rome timezone.
 * @return {string}
 */
function aiTodayKey() {
  return new Date().toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"});
}

const KB = 1024;

/**
 * Piano effettivo per quote (AI giornaliero, storage): allineato a iOS KBSubscriptionManager.
 * Preferisce families/{familyId}.planOverride se "pro" | "max", altrimenti families.plan,
 * altrimenti users/{uid}.plan.
 * @param {string|null|undefined} uid
 * @param {string|null|undefined} familyId
 * @return {Promise<string>}
 */
async function resolveFamilyPlanForQuotas(uid, familyId) {
  let plan = "free";
  try {
    if (familyId) {
      const familySnap = await admin.firestore().collection("families").doc(familyId).get();
      if (familySnap.exists) {
        const d = familySnap.data() || {};
        const ov = d.planOverride;
        if (ov === "pro" || ov === "max") {
          plan = ov;
        } else {
          plan = d.plan || "free";
        }
      }
    }
    if (plan === "free" && uid) {
      const userSnap = await admin.firestore().collection("users").doc(uid).get();
      if (userSnap.exists) {
        plan = userSnap.data().plan || "free";
      }
    }
    return plan;
  } catch (e) {
    logger.warn("resolveFamilyPlanForQuotas failed", {uid, familyId, error: e.message});
    return "free";
  }
}

/** Quota storage in byte (stessi valori dell'app iOS KBPlan.storageQuota). */
function storageQuotaBytesForPlan(plan) {
  switch (plan) {
    case "max": return 20 * KB * KB * KB;
    case "pro": return 5 * KB * KB * KB;
    case "free":
    default: return 200 * KB * KB;
  }
}

/**
 * Limite messaggi AI al giorno per famiglia (Pro = 30, Max = 100, Free = 0).
 * Usa [resolveFamilyPlanForQuotas] così rispetta planOverride da console admin.
 * @param {string|null|undefined} uid
 * @param {string|null|undefined} familyId
 * @return {Promise<number>}
 */
async function resolveAIDailyLimit(uid, familyId = null) {
  try {
    const plan = await resolveFamilyPlanForQuotas(uid, familyId);
    switch (plan) {
      case "pro": return 30;
      case "max": return 100;
      case "free":
      default: return 0;
    }
  } catch (e) {
    logger.warn("resolveAIDailyLimit failed, using default", {uid, familyId, error: e.message});
    return 0;
  }
}

/** Caratteri payload (system + messages) considerati 1 messaggio sul contatore giornaliero. */
const AI_STANDARD_PAYLOAD_CHARS = 50000;
/** Limite assoluto anti-abuso / errori API (oltre questo si rifiuta la richiesta). */
const AI_ABSOLUTE_MAX_PAYLOAD_CHARS = 500000;

/**
 * @param {Array<{content: string}>} messages
 * @param {string} systemPrompt
 * @return {number}
 */
function totalAskAIPayloadChars(messages, systemPrompt) {
  const msgChars = messages.reduce((acc, m) => acc + (m.content?.length || 0), 0);
  return msgChars + (systemPrompt?.length || 0);
}

/**
 * Messaggi da scalare sul contatore: 1 fino a 50k caratteri, poi +1 ogni blocco da 50k.
 * @param {number} totalChars
 * @return {number}
 */
function askAIMessageUnitsForPayload(totalChars) {
  const chars = Math.max(0, Math.floor(Number(totalChars)) || 0);
  return Math.max(1, Math.ceil(chars / AI_STANDARD_PAYLOAD_CHARS));
}

/**
 * Checks the daily counter and increments it atomically.
 * Il contatore è per famiglia (family_{familyId}) così tutti i membri
 * condividono il limite giornaliero del piano famiglia.
 * @param {string} familyId
 * @param {string} uid
 * @param {number} limit
 * @param {number} incrementBy messaggi da scalare (default 1; itinerario viaggio = 2 ogni 3 giorni)
 * @return {Promise<number>} nuovo totale giornaliero dopo l'incremento
 */
async function checkAndIncrementAIUsage(familyId, uid, limit, incrementBy = 1) {
  const delta = Math.max(1, Math.floor(Number(incrementBy) || 1));

  // Free = 0 messaggi → blocca subito senza toccare il contatore
  if (limit <= 0) {
    throw new HttpsError(
        "resource-exhausted",
        "L'assistente AI è disponibile con i piani Pro e Max. Passa a Pro per 30 messaggi al giorno.",
    );
  }

  const ref = admin.firestore()
      .collection("ai_usage").doc(`family_${familyId}`)
      .collection("daily").doc(aiTodayKey());

  return await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? (snap.data().count || 0) : 0;

    if (current + delta > limit) {
      throw new HttpsError(
          "resource-exhausted",
          `La famiglia ha raggiunto il limite di ${limit} messaggi AI per oggi. Riprova domani.`,
      );
    }

    tx.set(ref, {
      count: admin.firestore.FieldValue.increment(delta),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      familyId,
      lastUid: uid,
    }, {merge: true});

    return current + delta;
  });
}

exports.askAI = onCall(
    {
      region: "europe-west1",
      invoker: "public",
      secrets: [ANTHROPIC_API_KEY],
      timeoutSeconds: 120,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");

      const {messages, systemPrompt, familyId, purpose} = request.data || {};

      if (!Array.isArray(messages) || messages.length === 0) {
        throw new HttpsError("invalid-argument", "messages è richiesto.");
      }
      const validRoles = ["user", "assistant"];
      const allValid = messages.every(
          (m) => typeof m.role === "string" && typeof m.content === "string" && validRoles.includes(m.role),
      );
      if (!allValid) throw new HttpsError("invalid-argument", "messages non valido.");
      if (typeof systemPrompt !== "string" || systemPrompt.trim().length === 0) {
        throw new HttpsError("invalid-argument", "systemPrompt è richiesto.");
      }
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId è richiesto.");
      }

      const totalChars = totalAskAIPayloadChars(messages, systemPrompt);
      if (totalChars > AI_ABSOLUTE_MAX_PAYLOAD_CHARS) {
        throw new HttpsError(
            "invalid-argument",
            "Contesto troppo grande per l'assistente AI. Riduci i referti allegati o avvia una nuova conversazione.",
        );
      }

      const messageUnits = askAIMessageUnitsForPayload(totalChars);
      const isLargeContext = messageUnits > 1;

      const dailyLimit = await resolveAIDailyLimit(uid, familyId);
      const usageCount = await checkAndIncrementAIUsage(familyId, uid, dailyLimit, messageUnits);

      const clinicalRecord = isClinicalRecordAskAI({purpose});
      const anthropicModel = clinicalRecord ? ANTHROPIC_MODEL_CLINICAL_RECORD : ANTHROPIC_MODEL_DEFAULT;
      const maxTokens = clinicalRecord ? CLINICAL_RECORD_MAX_TOKENS : 1024;
      const effectiveSystemPrompt = clinicalRecord ?
        `${systemPrompt.trim()}\n\n${CLINICAL_RECORD_SYSTEM_RULES}` :
        systemPrompt;
      const inputUsdPer1M = clinicalRecord ?
        ANTHROPIC_INPUT_USD_PER_1M_SONNET :
        ANTHROPIC_INPUT_USD_PER_1M_HAIKU;
      const outputUsdPer1M = clinicalRecord ?
        ANTHROPIC_OUTPUT_USD_PER_1M_SONNET :
        ANTHROPIC_OUTPUT_USD_PER_1M_HAIKU;

      logger.info("askAI request", {
        uid, familyId, usageCount, dailyLimit, msgCount: messages.length,
        totalChars, messageUnits, isLargeContext, clinicalRecord, anthropicModel,
      });

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
            model: anthropicModel,
            max_tokens: maxTokens,
            system: effectiveSystemPrompt,
            messages: messages.map((m) => ({role: m.role, content: m.content})),
          }),
        });

        if (res.status === 429) {
          throw new HttpsError("resource-exhausted", "Servizio AI temporaneamente sovraccarico. Riprova tra qualche secondo.");
        }
        if (!res.ok) {
          const errText = await res.text();
          logger.error("askAI: Anthropic error", {status: res.status, body: errText});
          throw new HttpsError("internal", "Errore dal servizio AI.");
        }

        const json = await res.json();
        reply = json?.content?.[0]?.text;
        if (!reply) throw new HttpsError("internal", "Risposta AI non valida.");

        // ── Tracking costi Anthropic ────────────────────────────────────────
        const inputTokens = json?.usage?.input_tokens || 0;
        const outputTokens = json?.usage?.output_tokens || 0;
        const costUsd = (inputTokens / 1000000) * inputUsdPer1M +
          (outputTokens / 1000000) * outputUsdPer1M;

        const monthKey = new Date().toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"}).slice(0, 7); // YYYY-MM
        const costRef = admin.firestore()
            .collection("ai_costs").doc(monthKey)
            .collection("families").doc(familyId);

        // Fire-and-forget: non blocchiamo la risposta per il tracking
        costRef.set({
          calls: admin.firestore.FieldValue.increment(1),
          inputTokens: admin.firestore.FieldValue.increment(inputTokens),
          outputTokens: admin.firestore.FieldValue.increment(outputTokens),
          costUsd: admin.firestore.FieldValue.increment(costUsd),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}).catch((e) => logger.warn("ai_costs write failed", {error: e.message}));

        // Totale mensile globale (per dashboard)
        const totalRef = admin.firestore().collection("ai_costs").doc(monthKey);
        totalRef.set({
          calls: admin.firestore.FieldValue.increment(1),
          inputTokens: admin.firestore.FieldValue.increment(inputTokens),
          outputTokens: admin.firestore.FieldValue.increment(outputTokens),
          costUsd: admin.firestore.FieldValue.increment(costUsd),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, {merge: true}).catch((e) => logger.warn("ai_costs total write failed", {error: e.message}));

        logger.info("askAI tokens", {
          uid, familyId, inputTokens, outputTokens,
          costUsd: costUsd.toFixed(6), clinicalRecord, model: anthropicModel,
        });
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        logger.error("askAI: fetch failed", {error: e.message});
        throw new HttpsError("internal", "Impossibile contattare il servizio AI.");
      }

      logger.info("askAI success", {
        uid, usageCount, messageUnits, clinicalRecord,
        totalPayloadChars: totalChars,
      });
      return {
        reply,
        usageToday: usageCount,
        dailyLimit,
        messageUnitsConsumed: messageUnits,
        isLargeContext,
        totalPayloadChars: totalChars,
        purpose: clinicalRecord ? "clinicalRecord" : undefined,
      };
    },
);

/**
 * System prompt per generateTravelPlan (Travel Card).
 * @param {object} wizardData
 * @param {object|null|undefined} familyContext
 * @return {string}
 */
/**
 * Giorni di viaggio inclusivi tra due date ISO (stesso giorno = 1).
 * @param {string} startDate
 * @param {string} endDate
 * @return {number}
 */
function inclusiveTripDayCount(startDate, endDate) {
  const start = new Date(startDate);
  const end = new Date(endDate);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return 1;
  start.setHours(0, 0, 0, 0);
  end.setHours(0, 0, 0, 0);
  const diffMs = end.getTime() - start.getTime();
  const days = Math.floor(diffMs / (24 * 3600 * 1000));
  return Math.max(days + 1, 1);
}

/** Allineato a TravelPlanningCountdown su iOS/Android: 1 blocco ogni 3 giorni di itinerario. */
const TRAVEL_PLANNING_MESSAGES_PER_BLOCK = 2;

/**
 * @param {number} plannedDayCount
 * @return {number}
 */
function travelPlanningBlocks(plannedDayCount) {
  const days = Math.max(1, Math.floor(Number(plannedDayCount)) || 1);
  return Math.max(1, Math.floor((days + 2) / 3));
}

/**
 * @param {object} wizardData
 * @return {number}
 */
function plannedDayCountFromWizard(wizardData) {
  const fromDates = wizardData?.startDate && wizardData?.endDate ?
    inclusiveTripDayCount(wizardData.startDate, wizardData.endDate) : 0;
  let fromLegs = 0;
  if (Array.isArray(wizardData?.legs)) {
    fromLegs = wizardData.legs.reduce((sum, leg) => {
      return sum + Math.max(0, Math.floor(Number(leg?.days) || 0));
    }, 0);
  }
  return Math.max(fromDates, fromLegs, 1);
}

/**
 * Costo in messaggi sul contatore giornaliero famiglia (Pro 30 / Max 100).
 * @param {number} plannedDayCount
 * @return {number}
 */
function travelMessageCostForPlannedDays(plannedDayCount) {
  return travelPlanningBlocks(plannedDayCount) * TRAVEL_PLANNING_MESSAGES_PER_BLOCK;
}

function buildTravelSystemPrompt(wizardData, familyContext, regenerateSingleDay = false) {
  const totalDays = wizardData?.startDate && wizardData?.endDate ?
    inclusiveTripDayCount(wizardData.startDate, wizardData.endDate) :
    1;
  const ctx = familyContext || {};
  const participants = ctx.participants;
  const children = ctx.children;
  const travelProfile = ctx.travelProfile;

  let travelPrefsInfo = "";
  if (travelProfile && typeof travelProfile === "object") {
    const styles = Array.isArray(travelProfile.styles) ? travelProfile.styles.join(", ") : "";
    const pace = travelProfile.pace || "";
    const ageGroup = travelProfile.ageGroup || "";
    travelPrefsInfo = `
PREFERENZE VIAGGIO (profilo utente):
- Stili preferiti: ${styles || "non specificati"}
- Ritmo: ${pace || "non specificato"}
- Fascia d'età: ${ageGroup || "non specificata"}
Adatta attività, tempi e suggerimenti a questo profilo.`;
  }

  let childrenInfo = "";
  if (children && children.length > 0) {
    childrenInfo = children.map((c) => {
      const age = Math.floor(
          (Date.now() - new Date(c.birthDate).getTime()) / (365.25 * 24 * 3600 * 1000),
      );
      let info = `- ${c.name}, ${age} anni`;
      if (c.allergies) info += `. ALLERGIE: ${c.allergies}`;
      if (c.medicalNotes) info += `. Note mediche: ${c.medicalNotes}`;
      if (c.medications && c.medications.length > 0) {
        info += `. Farmaci: ${c.medications.map((m) => `${m.name} ${m.dose}`).join(", ")}`;
      }
      return info;
    }).join("\n");
  }

  if (regenerateSingleDay) {
    return `Sei un esperto pianificatore di viaggi in famiglia. Conosci la famiglia:

BAMBINI:
${childrenInfo || "Nessun bambino"}

ADULTI PARTECIPANTI: ${participants?.join(", ") || "famiglia"}
${travelPrefsInfo}

RIGENERA UN SOLO GIORNO del viaggio "${wizardData?.tripName || "viaggio"}".
Data da rigenerare: ${wizardData?.startDate || ""}.

Restituisci SEMPRE:
1. Una breve introduzione in italiano (1-2 frasi) sulle novità del giorno
2. JSON dentro \`\`\`json ... \`\`\` con ESATTAMENTE 1 elemento in dayPlans

Lo schema OBBLIGATORIO del dayPlan è:
{
  "dayPlans": [{
    "date": "${wizardData?.startDate || ""}",
    "location": string (nome città/zona),
    "morningPlan": string (riepilogo testuale della mattina con luoghi e orari),
    "afternoonPlan": string,
    "eveningPlan": string,
    "morningStops": [{ "time": "HH:mm", "title": string (NOME REALE del luogo, MAI vuoto), "durationMinutes": number, "costLabel": string, "category": "flight"|"transport"|"food"|"hotel"|"culture"|"beach"|"shopping"|"other" }],
    "afternoonStops": [ ... stessa forma ... ],
    "eveningStops": [ ... stessa forma ... ],
    "accommodationName": string (opzionale),
    "accommodationType": "hotel"|"bb"|"camping"|"airbnb"|"other" (opzionale),
    "accommodationCostPerNight": number (opzionale),
    "weatherBackupPlan": string,
    "estimatedDailyCost": number
  }]
}

REGOLE TASSATIVE:
- Ogni elemento di morningStops/afternoonStops/eveningStops DEVE avere "title" non vuoto con il NOME REALE del luogo (es. "Trattoria da Maria", "Castello di Procida"). MAI omettere "title" e MAI usare placeholder come "Pranzo" o "Visita".
- Per category "food" usa SEMPRE il nome reale del locale.
- Minimo 2 tappe per fascia oraria quando possibile.
- morningPlan/afternoonPlan/eveningPlan devono elencare gli stessi luoghi con i loro orari (es. "10:00 Castello di Procida · ingresso 8€").
- NON ripetere i luoghi già citati negli altri giorni (vedi messaggio utente).
- Puoi omettere trip, legs, packingList, diningPlaces.

Rispondi in italiano.`;
  }

  return `Sei un esperto pianificatore di viaggi in famiglia. Conosci la famiglia:

BAMBINI:
${childrenInfo || "Nessun bambino"}

ADULTI PARTECIPANTI: ${participants?.join(", ") || "famiglia"}
${travelPrefsInfo}

Il tuo compito è generare un piano di viaggio dettagliato e SEMPRE restituire la risposta
in questo formato ESATTO:

1. Una breve introduzione narrativa in italiano (2-3 frasi)
2. Il piano strutturato come JSON dentro un blocco \`\`\`json ... \`\`\`

Il JSON deve seguire ESATTAMENTE questo schema:
{
  "trip": {
    "estimatedTotalCost": number,
    "currency": "EUR",
    "summary": string,
    "budgetBreakdown": {
      "hotels": number,
      "flights": number,
      "restaurants": number,
      "activities": number
    }
  },
  "legs": [{
    "order": number,
    "fromLocation": string,
    "toLocation": string,
    "transportMode": "flight"|"train"|"ship"|"car"|"walk"|"bike",
    "notes": string
  }],
  "dayPlans": [{
    "date": "YYYY-MM-DD",
    "location": string,
    "morningPlan": string,
    "afternoonPlan": string,
    "eveningPlan": string,
    "morningStops": [{ "time": string, "title": string, "durationMinutes": number, "costLabel": string, "category": "flight"|"transport"|"food"|"hotel"|"culture"|"beach"|"shopping"|"other" }],
    "afternoonStops": [{ "time": string, "title": string, "durationMinutes": number, "costLabel": string, "category": string }],
    "eveningStops": [{ "time": string, "title": string, "durationMinutes": number, "costLabel": string, "category": string }],
    "accommodationName": string,
    "accommodationType": "hotel"|"bb"|"camping"|"airbnb"|"other",
    "accommodationCostPerNight": number,
    "weatherBackupPlan": string,
    "estimatedDailyCost": number
  }],
  "diningPlaces": [{
    "name": string,
    "cuisine": string,
    "day": "YYYY-MM-DD",
    "meal": "colazione"|"pranzo"|"cena"|"aperitivo",
    "location": string,
    "estimatedCost": number,
    "notes": string
  }],
  "packingList": [{
    "label": string,
    "category": "documents"|"clothing"|"health"|"kids"|"other",
    "fromMedicalProfile": boolean
  }],
  "healthNotes": [string],
  "emergencyContacts": {
    "country": string,
    "emergencyNumber": string,
    "italianEmbassy": string,
    "nearestHospital": string
  }
}

REGOLE IMPORTANTI:
- Le attività devono essere adatte alle età dei bambini presenti
- Segnala SEMPRE le allergie nei piani pasto con "⚠️ ALLERGIA:"
- Includi i farmaci abituali nella packing list con fromMedicalProfile=true
- I tempi di percorrenza devono essere realistici con bambini (aggiungi 30% al tempo adulti)
- Il piano B per maltempo deve essere sempre al coperto e adatto ai bimbi
- Per mattina/pomeriggio/sera compila SEMPRE morningStops, afternoonStops, eveningStops (minimo 2 tappe per fascia quando possibile)
- Ogni tappa: orario realistico, titolo del luogo, durata in minuti, costo stimato e costLabel ("Gratis" se 0)
- Per category "food" usa SEMPRE il nome reale del locale (es. "Trattoria da Maria", "Ristorante Il Gabbiano") — MAI solo "Cena" o "Pranzo"
- Includi almeno 1 tappa food al giorno (pranzo e/o cena) con nomi di locali plausibili per la destinazione
- Compila diningPlaces con TUTTI i ristoranti/trattorie/osterie citati (minimo 1 per giorno di viaggio), con name, cuisine, day, meal, location, estimatedCost
- morningPlan/afternoonPlan/eveningPlan devono elencare gli stessi locali con nomi reali (es. "13:00 Trattoria X — pesce · ~35€")
- Compila trip.budgetBreakdown con stime coerenti con estimatedTotalCost
- Il viaggio dura ${totalDays} giorni INCLUSIVI: dayPlans DEVE contenere ESATTAMENTE ${totalDays} elementi
- Le date in dayPlans devono essere consecutive dal ${wizardData?.startDate || "startDate"} al ${wizardData?.endDate || "endDate"} (un piano per ogni giorno, senza salti)
- Rispondi SEMPRE in italiano`;
}

/**
 * Estrae il piano strutturato e lascia solo l'introduzione narrativa (senza blocco JSON).
 * @param {string} raw
 * @return {{travelPlan: object|null, narrativeText: string}}
 */
/**
 * @param {string} text
 * @return {object|null}
 */
function tryParseTravelPlanJson(text) {
  const trimmed = (text || "").trim();
  if (!trimmed) return null;
  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && (parsed.trip || (Array.isArray(parsed.dayPlans) && parsed.dayPlans.length > 0))) {
      return parsed;
    }
  } catch (parseErr) {
    logger.warn("tryParseTravelPlanJson: parse failed", {error: parseErr.message});
  }
  const repaired = extractJSONObject(trimmed);
  if (repaired && repaired !== trimmed) {
    try {
      const parsed = JSON.parse(repaired);
      if (parsed && (parsed.trip || (Array.isArray(parsed.dayPlans) && parsed.dayPlans.length > 0))) {
        return parsed;
      }
    } catch (repairErr) {
      logger.warn("tryParseTravelPlanJson: repaired parse failed", {error: repairErr.message});
    }
  }
  return null;
}

/**
 * @param {string} source
 * @return {string|null}
 */
function extractJSONObject(source) {
  let depth = 0;
  let started = false;
  let start = -1;
  for (let i = 0; i < source.length; i++) {
    const ch = source[i];
    if (ch === "{") {
      if (!started) {
        started = true;
        start = i;
      }
      depth++;
    } else if (ch === "}" && started) {
      depth--;
      if (depth === 0 && start >= 0) {
        return source.slice(start, i + 1);
      }
    }
  }
  if (started && depth > 0 && start >= 0) {
    return source.slice(start) + "}".repeat(depth);
  }
  return null;
}

/**
 * @param {string} raw
 * @return {{travelPlan: object|null, narrativeText: string}}
 */
function parseTravelPlanResponse(raw) {
  let narrativeText = (raw || "").trim();
  let travelPlan = null;

  const fenced = narrativeText.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/i);
  if (fenced) {
    travelPlan = tryParseTravelPlanJson(fenced[1]);
    if (travelPlan) {
      narrativeText = narrativeText.replace(/```(?:json)?\s*[\s\S]*?```/gi, "").trim();
    }
  }

  if (!travelPlan) {
    const unclosed = narrativeText.match(/```(?:json)?\s*\n?([\s\S]+)/i);
    if (unclosed) {
      travelPlan = tryParseTravelPlanJson(unclosed[1]);
      if (travelPlan) {
        narrativeText = narrativeText.replace(/```(?:json)?[\s\S]*/i, "").trim();
      }
    }
  }

  if (!travelPlan) {
    const jsonStart = narrativeText.search(/\{\s*"(?:trip|dayPlans)"\s*:/);
    if (jsonStart >= 0) {
      const candidate = extractJSONObject(narrativeText.slice(jsonStart));
      if (candidate) {
        travelPlan = tryParseTravelPlanJson(candidate);
        if (travelPlan) {
          narrativeText = narrativeText.slice(0, jsonStart).trim();
        }
      }
    }
  }

  narrativeText = narrativeText
      .replace(/```(?:json)?\s*/gi, "")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  return {travelPlan, narrativeText};
}

/**
 * User message per generateTravelPlan.
 * @param {object} wizardData
 * @param {string|null|undefined} freeTextPrompt
 * @return {string}
 */
function buildTravelUserMessage(wizardData, freeTextPrompt, regenerateSingleDay = false) {
  if (regenerateSingleDay) {
    return (freeTextPrompt && freeTextPrompt.trim()) ?
      freeTextPrompt.trim() :
      `Rigenera il piano per il giorno ${wizardData?.startDate || ""}.`;
  }

  const {tripName, startDate, endDate, legs, budgetTotal, currency} = wizardData;
  const days = inclusiveTripDayCount(startDate, endDate);

  const legsText = (legs || []).map((l, i) =>
    `${i + 1}. ${l.fromLocation} → ${l.toLocation} (${l.transportMode}, ${l.days || 1} giorni)`,
  ).join("\n");

  let msg = `Pianifica il viaggio "${tripName}":
- Date: ${startDate} → ${endDate} (${days} giorni totali)
- Tappe:
${legsText}
- Budget totale: ${budgetTotal} ${currency || "EUR"}`;

  if (freeTextPrompt && freeTextPrompt.trim()) {
    msg += `\n\nPreferenze aggiuntive: ${freeTextPrompt.trim()}`;
  }

  return msg;
}

/**
 * Scrive i costi Anthropic su Firestore (stesso schema di askAI).
 * @param {string} familyId
 * @param {number} inputTokens
 * @param {number} outputTokens
 * @return {void}
 */
function trackAnthropicCosts(
    familyId,
    inputTokens,
    outputTokens,
    inputUsdPer1M = ANTHROPIC_INPUT_USD_PER_1M_HAIKU,
    outputUsdPer1M = ANTHROPIC_OUTPUT_USD_PER_1M_HAIKU,
) {
  const costUsd = (inputTokens / 1000000) * inputUsdPer1M +
    (outputTokens / 1000000) * outputUsdPer1M;
  const monthKey = new Date().toLocaleDateString("sv-SE", {timeZone: "Europe/Rome"}).slice(0, 7);

  const costRef = admin.firestore()
      .collection("ai_costs").doc(monthKey)
      .collection("families").doc(familyId);

  costRef.set({
    calls: admin.firestore.FieldValue.increment(1),
    inputTokens: admin.firestore.FieldValue.increment(inputTokens),
    outputTokens: admin.firestore.FieldValue.increment(outputTokens),
    costUsd: admin.firestore.FieldValue.increment(costUsd),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true}).catch((e) => logger.warn("ai_costs write failed", {error: e.message}));

  const totalRef = admin.firestore().collection("ai_costs").doc(monthKey);
  totalRef.set({
    calls: admin.firestore.FieldValue.increment(1),
    inputTokens: admin.firestore.FieldValue.increment(inputTokens),
    outputTokens: admin.firestore.FieldValue.increment(outputTokens),
    costUsd: admin.firestore.FieldValue.increment(costUsd),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true}).catch((e) => logger.warn("ai_costs total write failed", {error: e.message}));
}

exports.generateTravelPlan = onCall(
    {
      region: "europe-west1",
      invoker: "public",
      secrets: [ANTHROPIC_API_KEY],
      timeoutSeconds: 120,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Login required");

      const {familyId, wizardData, freeTextPrompt, familyContext, regenerateSingleDay} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId è richiesto.");
      }
      if (!wizardData || typeof wizardData !== "object") {
        throw new HttpsError("invalid-argument", "Missing required fields");
      }
      const {tripName, startDate, endDate, legs} = wizardData;
      const isSingleDayRegeneration = regenerateSingleDay === true;
      if (!tripName || !startDate || !endDate || !Array.isArray(legs)) {
        throw new HttpsError("invalid-argument", "wizardData non valido.");
      }
      if (!isSingleDayRegeneration && legs.length === 0) {
        throw new HttpsError("invalid-argument", "wizardData non valido: almeno una tappa richiesta.");
      }

      const dailyLimit = await resolveAIDailyLimit(uid, familyId);
      if (dailyLimit === 0) {
        throw new HttpsError("permission-denied", "AI not available on free plan");
      }
      const plannedDayCount = plannedDayCountFromWizard(wizardData);
      const travelMessageCost = travelMessageCostForPlannedDays(plannedDayCount);
      const usageCount = await checkAndIncrementAIUsage(
          familyId, uid, dailyLimit, travelMessageCost,
      );

      logger.info("generateTravelPlan request", {
        uid, familyId, usageCount, dailyLimit, tripName, plannedDayCount, travelMessageCost,
      });

      const apiKey = ANTHROPIC_API_KEY.value();
      if (!apiKey) {
        logger.error("generateTravelPlan: ANTHROPIC_API_KEY secret non configurato");
        throw new HttpsError("internal", "Configurazione AI non disponibile.");
      }

      const systemPrompt = buildTravelSystemPrompt(wizardData, familyContext, isSingleDayRegeneration);
      const userMessage = buildTravelUserMessage(wizardData, freeTextPrompt, isSingleDayRegeneration);

      let narrativeText;
      let travelPlan = null;
      let inputTokens = 0;
      let outputTokens = 0;

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
            model: ANTHROPIC_MODEL_DEFAULT,
            max_tokens: 8192,
            system: systemPrompt,
            messages: [{role: "user", content: userMessage}],
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
          logger.error("generateTravelPlan: Anthropic error", {status: res.status, body: errText});
          throw new HttpsError("internal", "Errore dal servizio AI.");
        }

        const json = await res.json();
        const rawText = json?.content?.[0]?.text ?? "";
        if (!rawText) throw new HttpsError("internal", "Risposta AI non valida.");

        const parsed = parseTravelPlanResponse(rawText);
        narrativeText = parsed.narrativeText;
        travelPlan = parsed.travelPlan;

        inputTokens = json?.usage?.input_tokens || 0;
        outputTokens = json?.usage?.output_tokens || 0;
        trackAnthropicCosts(familyId, inputTokens, outputTokens);
        logger.info("generateTravelPlan tokens", {
          uid, familyId, inputTokens, outputTokens,
          costUsd: ((inputTokens / 1000000) * ANTHROPIC_INPUT_USD_PER_1M_HAIKU +
            (outputTokens / 1000000) * ANTHROPIC_OUTPUT_USD_PER_1M_HAIKU).toFixed(6),
        });
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        logger.error("generateTravelPlan: fetch failed", {error: e.message});
        throw new HttpsError("internal", "Impossibile contattare il servizio AI.");
      }

      logger.info("generateTravelPlan success", {uid, familyId, hasPlan: !!travelPlan});
      return {
        travelPlan,
        narrativeText,
        usageToday: usageCount,
        dailyLimit,
        plannedDayCount,
        messageCost: travelMessageCost,
      };
    },
);

/**
 * @param {string} raw
 * @return {{destinations: object[], profileSummary: string}|null}
 */
function parseTravelSuggestionsResponse(raw) {
  let text = (raw || "").trim();
  const fenced = text.match(/```(?:json)?\s*\n?([\s\S]*?)\n?```/i);
  if (fenced) {
    text = fenced[1].trim();
  }
  try {
    const parsed = JSON.parse(text);
    if (parsed && Array.isArray(parsed.destinations)) {
      return {
        destinations: parsed.destinations,
        profileSummary: typeof parsed.profileSummary === "string" ? parsed.profileSummary : "",
      };
    }
  } catch (e) {
    logger.warn("parseTravelSuggestionsResponse failed", {error: e.message});
  }
  return null;
}

/**
 * @param {object|null|undefined} travelProfile
 * @return {string}
 */
function buildTravelSuggestionsSystemPrompt(travelProfile) {
  const profile = travelProfile && typeof travelProfile === "object" ? travelProfile : {};
  const styles = Array.isArray(profile.styles) ? profile.styles.join(", ") : "";
  const pace = profile.pace || "";
  const ageGroup = profile.ageGroup || "";
  return `Sei un consulente di viaggi per famiglie italiane. Suggerisci destinazioni in Europa (e Mediterraneo) adatte al profilo.

PROFILO UTENTE:
- Stili: ${styles || "non specificati"}
- Ritmo: ${pace || "non specificato"}
- Fascia d'età: ${ageGroup || "non specificata"}

Rispondi SOLO con JSON valido (nessun testo fuori dal JSON) nel formato:
{
  "profileSummary": "breve frase in italiano es. ritmo equilibrato, coppia",
  "destinations": [
    {
      "id": "slug-unico",
      "name": "Nome città",
      "region": "Paese, area",
      "tagline": "una riga teaser",
      "whyForYou": "2-3 frasi perché è adatta al profilo",
      "aiHeadline": "titolo breve card AI",
      "estimatedCost": "~€1,100",
      "durationDays": "4-6",
      "bestTime": "Apr-Giu",
      "bestTimeNote": "nota breve periodo migliore",
      "isTopMatch": true,
      "previewPlan": {
        "trip": {
          "estimatedTotalCost": 950,
          "currency": "EUR",
          "summary": "titolo breve del viaggio",
          "budgetBreakdown": {
            "hotels": 340,
            "flights": 210,
            "restaurants": 220,
            "activities": 180
          }
        },
        "dayPlans": [
          {
            "date": "2026-06-01",
            "location": "Nome città",
            "estimatedDailyCost": 160,
            "morningStops": [
              {
                "time": "09:30",
                "title": "Attività mattina",
                "durationMinutes": 90,
                "costLabel": "Gratis",
                "category": "culture"
              }
            ],
            "afternoonStops": [
              {
                "time": "14:00",
                "title": "Attività pomeriggio",
                "durationMinutes": 120,
                "costLabel": "~35",
                "category": "food"
              }
            ],
            "eveningStops": [
              {
                "time": "19:30",
                "title": "Cena",
                "durationMinutes": 90,
                "costLabel": "~45",
                "category": "food"
              }
            ]
          }
        ]
      }
    }
  ]
}

REGOLE:
- Esattamente 3 destinazioni; la prima con isTopMatch true, le altre false.
- Costi e durate realistici per viaggi da Italia.
- Ogni destinazione DEVE includere previewPlan con 2-4 dayPlans e tappe strutturate (morningStops, afternoonStops, eveningStops) con time, title, durationMinutes, costLabel, category (flight|transport|food|hotel|culture|beach|shopping|other).
- Le tappe food devono usare nomi reali di locali (trattoria/osteria/ristorante), non titoli generici come "Cena".
- estimatedTotalCost in previewPlan.trip deve essere coerente con estimatedCost della card.
- Tutto in italiano.`;
}

exports.suggestTravelDestinations = onCall(
    {
      region: "europe-west1",
      invoker: "public",
      secrets: [ANTHROPIC_API_KEY],
      timeoutSeconds: 90,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Login required");

      const {familyId, travelProfile} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId è richiesto.");
      }

      const dailyLimit = await resolveAIDailyLimit(uid, familyId);
      if (dailyLimit === 0) {
        throw new HttpsError("permission-denied", "AI not available on free plan");
      }
      const usageCount = await checkAndIncrementAIUsage(familyId, uid, dailyLimit, 1);

      const apiKey = ANTHROPIC_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("internal", "Configurazione AI non disponibile.");
      }

      const systemPrompt = buildTravelSuggestionsSystemPrompt(travelProfile);
      const userMessage = "Suggerisci 3 destinazioni personalizzate per questo profilo.";

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
            model: ANTHROPIC_MODEL_DEFAULT,
            max_tokens: 2048,
            system: systemPrompt,
            messages: [{role: "user", content: userMessage}],
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
          logger.error("suggestTravelDestinations: Anthropic error", {status: res.status, body: errText});
          throw new HttpsError("internal", "Errore dal servizio AI.");
        }

        const json = await res.json();
        const rawText = json?.content?.[0]?.text ?? "";
        const parsed = parseTravelSuggestionsResponse(rawText);
        if (!parsed || !parsed.destinations.length) {
          throw new HttpsError("internal", "Risposta suggerimenti non valida.");
        }

        const inputTokens = json?.usage?.input_tokens || 0;
        const outputTokens = json?.usage?.output_tokens || 0;
        trackAnthropicCosts(familyId, inputTokens, outputTokens);

        return {
          destinations: parsed.destinations,
          profileSummary: parsed.profileSummary,
          usageToday: usageCount,
          dailyLimit,
        };
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        logger.error("suggestTravelDestinations failed", {error: e.message});
        throw new HttpsError("internal", "Impossibile contattare il servizio AI.");
      }
    },
);

/**
 * Risolve URL foto Places (redirect) senza esporre la API key al client.
 * @param {string} photoName
 * @param {string} apiKey
 * @return {Promise<string|null>}
 */
async function resolveGooglePlacePhotoUrl(photoName, apiKey) {
  if (!photoName || !apiKey) return null;
  const mediaUrl =
    `https://places.googleapis.com/v1/${photoName}/media` +
    `?maxWidthPx=800&skipHttpRedirect=true&key=${encodeURIComponent(apiKey)}`;
  try {
    const res = await fetch(mediaUrl);
    if (!res.ok) return null;
    const json = await res.json();
    return json.photoUri || null;
  } catch (e) {
    logger.warn("resolveGooglePlacePhotoUrl failed", {photoName, err: e.message});
    return null;
  }
}

/** Campi Text Search (Pro). Evitare reviews/editorialSummary qui (SKU Enterprise). */
const PLACES_SEARCH_FIELD_MASK = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.location",
  "places.rating",
  "places.userRatingCount",
  "places.photos",
  "places.types",
  "places.primaryType",
  "places.primaryTypeDisplayName",
  "places.googleMapsUri",
].join(",");

/** Dettaglio luogo localizzato (italiano) incluso recensioni e descrizione. */
const PLACE_DETAILS_FIELD_MASK = [
  "id",
  "displayName",
  "formattedAddress",
  "location",
  "rating",
  "userRatingCount",
  "photos",
  "types",
  "primaryType",
  "primaryTypeDisplayName",
  "googleMapsUri",
  "reviews",
  "reviews.publishTime",
  "editorialSummary",
].join(",");

/** Etichette italiane per tipi Google (fallback se l'API non localizza). */
const IT_PLACE_TYPE_LABELS = {
  restaurant: "Ristorante",
  food: "Ristorante",
  meal_takeaway: "Asporto",
  meal_delivery: "Consegna a domicilio",
  cafe: "Caffè",
  bar: "Bar",
  bakery: "Panetteria",
  hotel: "Hotel",
  lodging: "Alloggio",
  bed_and_breakfast: "Bed and breakfast",
  guest_house: "Ospitalità",
  hostel: "Ostello",
  resort_hotel: "Resort",
  motel: "Motel",
  tourist_attraction: "Attrazione turistica",
  museum: "Museo",
  art_gallery: "Galleria d'arte",
  park: "Parco",
  church: "Chiesa",
  shopping_mall: "Centro commerciale",
  store: "Negozio",
  supermarket: "Supermercato",
  night_club: "Discoteca",
  spa: "Spa",
  gym: "Palestra",
  beach: "Spiaggia",
};

const DEFAULT_PLACES_LANGUAGE_CODE = "it";
const DEFAULT_PLACES_REGION_CODE = "IT";

/**
 * Lingua Places richiesta dal client (iOS/Android); default italiano.
 * @param {string|undefined} raw
 * @return {string}
 */
function resolvePlacesLanguageCode(raw) {
  const code = (typeof raw === "string" ? raw : "").trim().toLowerCase();
  if (code.startsWith("it")) return "it";
  return DEFAULT_PLACES_LANGUAGE_CODE;
}

/**
 * @param {string} languageCode
 * @return {string}
 */
function placesAcceptLanguageHeader(languageCode) {
  const code = resolvePlacesLanguageCode(languageCode);
  return code === "it" ? "it-IT,it;q=0.9" : `${code};q=0.9`;
}

/**
 * @param {string} languageCode
 * @return {string|undefined}
 */
function placesRegionCode(languageCode) {
  return resolvePlacesLanguageCode(languageCode) === "it" ?
    DEFAULT_PLACES_REGION_CODE :
    undefined;
}

/**
 * Data recensione in forma relativa localizzata (es. «2 settimane fa»).
 * @param {string|undefined} publishTime
 * @param {string} languageCode
 * @return {string}
 */
function formatRelativePublishTime(publishTime, languageCode) {
  if (!publishTime) return "";
  const date = new Date(publishTime);
  if (Number.isNaN(date.getTime())) return "";
  const locale = resolvePlacesLanguageCode(languageCode) === "it" ? "it-IT" : languageCode;
  const diffMs = date.getTime() - Date.now();
  try {
    const rtf = new Intl.RelativeTimeFormat(locale, {numeric: "auto"});
    const diffSec = Math.round(diffMs / 1000);
    if (Math.abs(diffSec) < 60) return rtf.format(diffSec, "second");
    const diffMin = Math.round(diffMs / 60000);
    if (Math.abs(diffMin) < 60) return rtf.format(diffMin, "minute");
    const diffHour = Math.round(diffMs / 3600000);
    if (Math.abs(diffHour) < 24) return rtf.format(diffHour, "hour");
    const diffDay = Math.round(diffMs / 86400000);
    if (Math.abs(diffDay) < 30) return rtf.format(diffDay, "day");
    const diffMonth = Math.round(diffMs / (86400000 * 30.4375));
    if (Math.abs(diffMonth) < 12) return rtf.format(diffMonth, "month");
    const diffYear = Math.round(diffMs / (86400000 * 365.25));
    return rtf.format(diffYear, "year");
  } catch (e) {
    return "";
  }
}

/**
 * Query di ricerca dal più specifico al più generico.
 * @param {string} placeName
 * @param {string} locationContext
 * @return {string[]}
 */
function buildPlaceSearchQueries(placeName, locationContext) {
  const queries = [];
  const ctx = (locationContext || "").trim();
  if (ctx) {
    queries.push(`${placeName}, ${ctx}, Italia`);
    queries.push(`${placeName}, ${ctx}`);
  }
  queries.push(`${placeName}, Italia`);
  queries.push(placeName);
  const seen = new Set();
  return queries.filter((q) => {
    const key = q.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * Text Search (New) — un singolo tentativo.
 * @param {string} textQuery
 * @param {string} apiKey
 * @return {Promise<object|null>}
 */
async function googlePlacesSearchText(textQuery, apiKey, languageCode) {
  const lang = resolvePlacesLanguageCode(languageCode);
  const region = placesRegionCode(lang);
  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": PLACES_SEARCH_FIELD_MASK,
      "Accept-Language": placesAcceptLanguageHeader(lang),
    },
    body: JSON.stringify({
      textQuery,
      languageCode: lang,
      ...(region ? {regionCode: region} : {}),
      maxResultCount: 1,
    }),
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logger.warn("googlePlacesSearchText failed", {
      textQuery,
      status: res.status,
      body: bodyText.slice(0, 500),
    });
    if (res.status === 401 || res.status === 403) {
      const err = new Error("Google Places: chiave non valida o API non abilitata.");
      err.code = "PLACES_API_ERROR";
      throw err;
    }
    return null;
  }

  let json;
  try {
    json = JSON.parse(bodyText);
  } catch (e) {
    logger.warn("googlePlacesSearchText: invalid JSON", {textQuery, err: e.message});
    return null;
  }
  return json?.places?.[0] || null;
}

/**
 * @param {string} code
 * @return {boolean}
 */
function isItalianLanguageCode(code) {
  return (code || "").toLowerCase().startsWith("it");
}

/**
 * @param {object|undefined} field
 * @return {string}
 */
function localizedFieldText(field) {
  return (field?.text || "").trim();
}

/**
 * @param {object|undefined} field
 * @return {string}
 */
function localizedFieldLanguage(field) {
  return (field?.languageCode || "").toLowerCase();
}

/**
 * Categoria/tipo luogo in italiano.
 * @param {object} place
 * @return {string}
 */
function italianCategoryFromPlace(place) {
  const display = place.primaryTypeDisplayName;
  const displayText = localizedFieldText(display);
  const displayLang = localizedFieldLanguage(display);
  if (displayText && (isItalianLanguageCode(displayLang) || !displayLang)) {
    return displayText;
  }
  const primary = place.primaryType || (place.types && place.types[0]) || "";
  if (primary && IT_PLACE_TYPE_LABELS[primary]) {
    return IT_PLACE_TYPE_LABELS[primary];
  }
  if (primary) {
    return primary
        .replace(/_/g, " ")
        .replace(/\b\w/g, (c) => c.toUpperCase());
  }
  return displayText || "Luogo di interesse";
}

/**
 * Dettaglio Places (New) con languageCode=it.
 * @param {string} placeResourceId
 * @param {string} apiKey
 * @return {Promise<object|null>}
 */
async function googlePlacesGetDetails(placeResourceId, apiKey, languageCode) {
  if (!placeResourceId) return null;
  const lang = resolvePlacesLanguageCode(languageCode);
  const region = placesRegionCode(lang);
  const resource = placeResourceId.startsWith("places/") ?
    placeResourceId :
    `places/${placeResourceId}`;
  try {
    const params = new URLSearchParams({languageCode: lang});
    if (region) params.set("regionCode", region);
    const detailsUrl =
      `https://places.googleapis.com/v1/${resource}?${params.toString()}`;
    const res = await fetch(detailsUrl, {
      method: "GET",
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": PLACE_DETAILS_FIELD_MASK,
        "Accept-Language": placesAcceptLanguageHeader(lang),
      },
    });
    if (!res.ok) {
      const body = await res.text();
      logger.warn("googlePlacesGetDetails failed", {
        resource,
        status: res.status,
        body: body.slice(0, 400),
      });
      return null;
    }
    return await res.json();
  } catch (e) {
    logger.warn("googlePlacesGetDetails error", {resource, err: e.message});
    return null;
  }
}

/**
 * Traduce in batch i campi testuali non italiani del luogo.
 * @param {object} fields
 * @param {string} apiKey
 * @return {Promise<object>}
 */
async function localizePlaceDisplayFields(fields, apiKey) {
  const out = {...fields};
  const pending = [];
  const keys = [];

  const queue = (key, value, lang) => {
    const text = (value || "").trim();
    if (!text) return;
    if (lang && isItalianLanguageCode(lang)) return;
    pending.push(text);
    keys.push(key);
  };

  queue("name", fields.name, fields.nameLang);
  queue("address", fields.address, fields.addressLang);
  queue("category", fields.category, fields.categoryLang);
  queue("about", fields.about, fields.aboutLang);

  if (!pending.length) return out;

  const translated = await translateTextsToItalian(pending, apiKey);
  if (translated) {
    keys.forEach((key, index) => {
      if (translated[index]) out[key] = translated[index];
    });
  }
  return out;
}

/**
 * Testo recensione da tradurre: preferisce italiano, altrimenti testo più utile per traduzione.
 * @param {object} review
 * @return {{text: string, lang: string}}
 */
function pickReviewText(review) {
  const localized = (review.text?.text || "").trim();
  const localizedLang = (review.text?.languageCode || "").toLowerCase();
  const original = (review.originalText?.text || "").trim();
  const originalLang = (review.originalText?.languageCode || "").toLowerCase();

  if (localized && isItalianLanguageCode(localizedLang)) {
    return {text: localized, lang: localizedLang};
  }
  if (original && isItalianLanguageCode(originalLang)) {
    return {text: original, lang: originalLang};
  }
  const fallback = localized || original;
  const lang = localized ? localizedLang : originalLang;
  return {text: fallback, lang};
}

/**
 * @param {string} text
 * @return {string}
 */
function decodeTranslationEntities(text) {
  return (text || "")
      .replace(/&amp;/g, "&")
      .replace(/&lt;/g, "<")
      .replace(/&gt;/g, ">")
      .replace(/&quot;/g, "\"")
      .replace(/&#39;/g, "'")
      .replace(/&apos;/g, "'");
}

/**
 * Traduce in italiano (Cloud Translation API) se abilitata sulla stessa chiave progetto.
 * @param {string[]} texts
 * @param {string} apiKey
 * @return {Promise<string[]|null>}
 */
async function translateTextsToItalian(texts, apiKey) {
  const payload = texts.map((t) => (t || "").trim()).filter(Boolean);
  if (!payload.length || !apiKey) return null;
  try {
    const res = await fetch(
        `https://translation.googleapis.com/language/translate/v2?key=${encodeURIComponent(apiKey)}`,
        {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({q: payload, target: "it", format: "text"}),
        },
    );
    if (!res.ok) {
      const body = await res.text();
      logger.warn("translateTextsToItalian skipped (abilita Cloud Translation API)", {
        status: res.status,
        body: body.slice(0, 200),
      });
      return null;
    }
    const json = await res.json();
    const out = (json?.data?.translations || []).map((t) =>
      decodeTranslationEntities(t.translatedText || ""),
    );
    return out.length === payload.length ? out : null;
  } catch (e) {
    logger.debug("translateTextsToItalian failed", {err: e.message});
    return null;
  }
}

/**
 * Recensioni in italiano: Places (languageCode=it) + traduzione opzionale.
 * @param {object[]} rawReviews
 * @param {string} apiKey
 * @return {Promise<object[]>}
 */
async function buildItalianReviews(rawReviews, apiKey, languageCode) {
  const lang = resolvePlacesLanguageCode(languageCode);
  const slice = (rawReviews || []).slice(0, 5);
  const drafts = slice.map((r, index) => {
    const picked = pickReviewText(r);
    const relativeFromPublish = formatRelativePublishTime(r.publishTime, lang);
    return {
      id: `review-${index}`,
      authorName: r.authorAttribution?.displayName || "Utente Google",
      text: picked.text,
      rating: r.rating || 0,
      relativeTime: relativeFromPublish ||
        r.relativePublishTimeDescription || "",
      profilePhotoUrl: r.authorAttribution?.photoUri || null,
      lang: picked.lang,
    };
  }).filter((r) => r.text.length > 0);

  const toTranslateIdx = [];
  const toTranslateTexts = [];
  const relativeIdx = [];
  const relativeTexts = [];

  drafts.forEach((d, i) => {
    if (!isItalianLanguageCode(d.lang)) {
      toTranslateIdx.push(i);
      toTranslateTexts.push(d.text);
    }
    const rel = (d.relativeTime || "").trim();
    if (rel && /\b(ago|week|month|year|day|hour|minute)\b/i.test(rel)) {
      relativeIdx.push(i);
      relativeTexts.push(rel);
    }
  });

  if (toTranslateTexts.length > 0) {
    const translated = await translateTextsToItalian(toTranslateTexts, apiKey);
    if (translated) {
      toTranslateIdx.forEach((draftIndex, j) => {
        if (translated[j]) drafts[draftIndex].text = translated[j];
      });
    }
  }

  if (relativeTexts.length > 0) {
    const translatedRel = await translateTextsToItalian(relativeTexts, apiKey);
    if (translatedRel) {
      relativeIdx.forEach((draftIndex, j) => {
        if (translatedRel[j]) drafts[draftIndex].relativeTime = translatedRel[j];
      });
    }
  }

  return drafts.map(({lang, ...rest}) => rest);
}

/**
 * Cerca un luogo su Google Places (New) e restituisce dettagli per la scheda viaggio.
 * @param {string} placeName
 * @param {string} locationContext
 * @param {string} apiKey
 * @return {Promise<object|null>}
 */
async function fetchGooglePlaceDetails(placeName, locationContext, apiKey, languageCode) {
  const lang = resolvePlacesLanguageCode(languageCode);
  const queries = buildPlaceSearchQueries(placeName, locationContext);
  let place = null;

  for (const textQuery of queries) {
    const hit = await googlePlacesSearchText(textQuery, apiKey, lang);
    if (hit) {
      place = hit;
      logger.info("fetchGooglePlaceDetails: match", {textQuery, placeId: hit.id});
      break;
    }
  }

  if (!place) return null;

  const detailed = await googlePlacesGetDetails(place.id, apiKey, lang);
  if (detailed) place = detailed;

  const photoNames = (place.photos || []).slice(0, 10).map((p) => p.name).filter(Boolean);
  const photoUrls = [];
  for (const name of photoNames.slice(0, 6)) {
    const url = await resolveGooglePlacePhotoUrl(name, apiKey);
    if (url) photoUrls.push(url);
  }

  const reviews = await buildItalianReviews(place.reviews, apiKey, lang);

  let name = localizedFieldText(place.displayName) || placeName;
  let category = italianCategoryFromPlace(place);
  let address = place.formattedAddress || "";
  let about = localizedFieldText(place.editorialSummary);

  const localized = await localizePlaceDisplayFields({
    name,
    nameLang: localizedFieldLanguage(place.displayName),
    address,
    addressLang: "",
    category,
    categoryLang: localizedFieldLanguage(place.primaryTypeDisplayName),
    about,
    aboutLang: localizedFieldLanguage(place.editorialSummary),
  }, apiKey);

  name = localized.name || name;
  category = localized.category || category;
  address = localized.address || address;
  about = localized.about || about;

  return {
    placeId: place.id || "",
    name,
    category,
    address,
    latitude: place.location?.latitude ?? 0,
    longitude: place.location?.longitude ?? 0,
    rating: place.rating ?? null,
    reviewCount: place.userRatingCount ?? 0,
    about,
    photoUrls,
    reviews,
    googleMapsUri: place.googleMapsUri || null,
  };
}

const PLACES_AUTOCOMPLETE_FIELD_MASK = [
  "suggestions.placePrediction.placeId",
  "suggestions.placePrediction.text",
  "suggestions.placePrediction.structuredFormat",
].join(",");

/**
 * Autocomplete destinazioni viaggio (Places API New).
 * @param {string} input
 * @param {string} apiKey
 * @return {Promise<object[]>}
 */
async function googlePlacesAutocomplete(input, apiKey, languageCode) {
  const lang = resolvePlacesLanguageCode(languageCode);
  const region = placesRegionCode(lang);
  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": PLACES_AUTOCOMPLETE_FIELD_MASK,
      "Accept-Language": placesAcceptLanguageHeader(lang),
    },
    body: JSON.stringify({
      input,
      languageCode: lang,
      ...(region ? {regionCode: region} : {}),
    }),
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logger.warn("googlePlacesAutocomplete failed", {
      input,
      status: res.status,
      body: bodyText.slice(0, 400),
    });
    if (res.status === 401 || res.status === 403) {
      const err = new Error("Google Places: chiave non valida o API non abilitata.");
      err.code = "PLACES_API_ERROR";
      throw err;
    }
    return [];
  }

  let json;
  try {
    json = JSON.parse(bodyText);
  } catch (e) {
    logger.warn("googlePlacesAutocomplete: invalid JSON", {input, err: e.message});
    return [];
  }

  return (json?.suggestions || [])
      .map((s) => s.placePrediction)
      .filter(Boolean)
      .slice(0, 6)
      .map((prediction) => {
        const main = prediction.structuredFormat?.mainText?.text ||
          prediction.text?.text || "";
        const secondary = prediction.structuredFormat?.secondaryText?.text || "";
        return {
          placeId: prediction.placeId || "",
          title: main.trim(),
          subtitle: secondary.trim(),
        };
      })
      .filter((item) => item.title.length > 0);
}

exports.searchTravelDestinations = onCall(
    {
      region: "europe-west1",
      invoker: "public",
      secrets: [GOOGLE_PLACES_API_KEY],
      timeoutSeconds: 20,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Login required");

      const {familyId, query, languageCode} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId è richiesto.");
      }
      const input = typeof query === "string" ? query.trim() : "";
      if (input.length < 2) {
        return {suggestions: []};
      }
      const lang = resolvePlacesLanguageCode(languageCode);

      const apiKey = GOOGLE_PLACES_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("failed-precondition", "Google Places non configurato.");
      }

      try {
        const suggestions = await googlePlacesAutocomplete(input, apiKey, lang);
        return {suggestions};
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        if (e && e.code === "PLACES_API_ERROR") {
          throw new HttpsError(
              "failed-precondition",
              "Google Places non configurato correttamente (API o chiave).",
          );
        }
        logger.error("searchTravelDestinations failed", {error: e.message});
        throw new HttpsError("internal", "Impossibile cercare la destinazione.");
      }
    },
);

exports.getTravelPlaceDetails = onCall(
    {
      region: "europe-west1",
      invoker: "public",
      secrets: [GOOGLE_PLACES_API_KEY],
      timeoutSeconds: 30,
    },
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Login required");

      const {familyId, placeName, locationContext, languageCode} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId è richiesto.");
      }
      const name = typeof placeName === "string" ? placeName.trim() : "";
      if (!name) {
        throw new HttpsError("invalid-argument", "placeName è richiesto.");
      }
      const context = typeof locationContext === "string" ? locationContext.trim() : "";
      const lang = resolvePlacesLanguageCode(languageCode);

      const apiKey = GOOGLE_PLACES_API_KEY.value();
      if (!apiKey) {
        throw new HttpsError("failed-precondition", "Google Places non configurato.");
      }

      try {
        const details = await fetchGooglePlaceDetails(name, context, apiKey, lang);
        if (!details) {
          logger.info("getTravelPlaceDetails: no match", {placeName: name, locationContext: context});
          return {found: false};
        }
        return {found: true, place: details};
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        if (e && e.code === "PLACES_API_ERROR") {
          throw new HttpsError(
              "failed-precondition",
              "Google Places non configurato correttamente (API o chiave).",
          );
        }
        logger.error("getTravelPlaceDetails failed", {error: e.message});
        throw new HttpsError("internal", "Impossibile recuperare i dettagli del luogo.");
      }
    },
);

exports.getAIUsage = onCall(
    {region: "europe-west1", invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");

      const {familyId} = request.data || {};
      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId è richiesto.");
      }

      const ref = admin.firestore()
          .collection("ai_usage").doc(`family_${familyId}`)
          .collection("daily").doc(aiTodayKey());

      const snap = await ref.get();
      const count = snap.exists ? (snap.data().count || 0) : 0;
      const dailyLimit = await resolveAIDailyLimit(uid, familyId);

      return {usageToday: count, dailyLimit};
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// CALENDARIO
// ─────────────────────────────────────────────────────────────────────────────

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
        logger.warn("notifyNewCalendarEvent: missing event data"); return;
      }
      if (eventData.isDeleted === true) return;

      const creatorUid = eventData.createdBy || eventData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewCalendarEvent: missing creatorUid"); return;
      }

      logger.info("notifyNewCalendarEvent triggered", {familyId, eventId, creatorUid});

      const creatorName = await resolveMemberName(familyId, creatorUid);

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewCalendarEvent: members subcollection is empty"); return;
      }

      const memberUids = membersSnap.docs.map((d) => d.id).filter((uid) => uid && uid !== creatorUid);
      if (memberUids.length === 0) {
        logger.info("notifyNewCalendarEvent: no targets (only creator)"); return;
      }

      const eventTitle = eventData.title || "Nuovo evento";
      const startDate = eventData.startDate?.toDate?.();
      let dateStr = "";
      if (startDate) {
        dateStr = startDate.toLocaleDateString("it-IT", {timeZone: "Europe/Rome", day: "numeric", month: "long"});
      }

      const title = "📅 Calendario";
      const body = dateStr ?
        `${creatorName} ha aggiunto: ${eventTitle} — ${dateStr}` :
        `${creatorName} ha aggiunto: ${eventTitle}`;

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewCalendarEvent");
        if (tokens.length === 0) continue;

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "calendar"});
        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {type: "new_calendar_event", familyId, eventId},
          apns: {payload: {aps: {sound: "default", badge}}},
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewCalendarEvent: no per-user notifications to send"); return;
      }

      const results = await Promise.allSettled(messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)));
      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount; totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });
      logger.info("notifyNewCalendarEvent: send result", {successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// SPESE
// ─────────────────────────────────────────────────────────────────────────────

exports.notifyNewExpense = onDocumentCreated(
    {
      document: "families/{familyId}/expenses/{expenseId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const expenseId = event.params.expenseId;

      const expenseData = event.data ? event.data.data() : null;
      if (!expenseData) {
        logger.warn("notifyNewExpense: missing expense data"); return;
      }
      if (expenseData.isDeleted) {
        logger.info("notifyNewExpense: isDeleted=true, skip", {familyId, expenseId}); return;
      }

      const creatorUid = expenseData.createdByUid || expenseData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewExpense: missing creatorUid", {familyId, expenseId}); return;
      }

      logger.info("notifyNewExpense triggered", {familyId, expenseId, creatorUid});

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewExpense: members subcollection is empty", {familyId}); return;
      }

      const memberUids = membersSnap.docs.map((d) => d.id).filter((uid) => uid && uid !== creatorUid);
      if (memberUids.length === 0) {
        logger.info("notifyNewExpense: no targets (only creator)", {familyId}); return;
      }

      const title = "💸 Nuova spesa registrata";
      const expenseTitle = expenseData.title || "Spesa";
      const amount = typeof expenseData.amount === "number" ?
        `${expenseData.amount.toFixed(2).replace(".", ",")} €` : "";
      const body = amount ? `${expenseTitle} · ${amount}` : expenseTitle;

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewExpense");
        if (tokens.length === 0) {
          logger.info("notifyNewExpense: user opted out or no tokens", {uid}); continue;
        }

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "expenses"});
        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {type: "new_expense", familyId, expenseId},
          apns: {payload: {aps: {badge, sound: "default"}}},
          android: {notification: {sound: "default"}},
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewExpense: no per-user notifications to send", {familyId}); return;
      }

      const results = await Promise.allSettled(messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)));
      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount; totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });
      logger.info("notifyNewExpense: send result", {familyId, expenseId, successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// STORAGE — getStorageUsage
// ─────────────────────────────────────────────────────────────────────────────

exports.getStorageUsage = onCall(
    {region: "europe-west1", invoker: "public"},
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

      const snap = await storageStatsRef(familyId).get();
      const legacy = snap.exists ? snap.data() : {};
      const legacyUsed = Math.max(0, Math.round(legacy.usedBytes || 0));
      const rawSections = legacy.sections || {};

      const db = admin.firestore();
      const fam = db.collection("families").doc(familyId);

      // Documenti/media/salute: sempre da Firestore con isDeleted == false (allineato a iOS dopo merge + somma sezioni).
      const [
        media,
        notesSnap,
        calendarSnap,
        todoSnap,
        expensesSnap,
      ] = await Promise.all([
        computeMediaStorageBytesForFamily(familyId),
        fam.collection("notes").where("isDeleted", "==", false).get(),
        fam.collection("calendarEvents").where("isDeleted", "==", false).get(),
        fam.collection("todos").where("isDeleted", "==", false).get(),
        fam.collection("expenses").where("isDeleted", "==", false).get(),
      ]);

      const documentsSection = Math.max(0, Math.round(media.docBytes));
      const walletSection = Math.max(0, Math.round(media.walletBytes));
      const chatSection = Math.max(0, Math.round(media.chatBytes));
      const photosSection = Math.max(0, Math.round(media.photoBytes));
      const saluteSection = Math.max(0, Math.round(media.saluteBytes));

      const notesCount = notesSnap.size;
      const calendarCount = calendarSnap.size;
      const todoCount = todoSnap.size;
      const expensesCount = expensesSnap.size;

      const estimatedNotesBytes = notesCount * 3 * 1024;
      const estimatedCalendarBytes = calendarCount * 1024;
      const estimatedTodoBytes = todoCount * 1024;
      const estimatedExpensesBytes = expensesCount * 1024;

      const notesBytes = Math.max(
          0,
          Math.round(rawSections.notes || 0),
          estimatedNotesBytes,
      );
      const calendarBytes = Math.max(
          0,
          Math.round(rawSections.calendar || 0),
          estimatedCalendarBytes,
      );
      const todoBytes = Math.max(
          0,
          Math.round(rawSections.todo || 0),
          estimatedTodoBytes,
      );
      const expensesBytes = Math.max(
          0,
          Math.round(rawSections.expenses || 0),
          estimatedExpensesBytes,
      );

      /** Totale coerente con la somma delle sezioni esposte (come la UI iOS dopo merge). */
      const usedBytes = Math.round(
          documentsSection +
        walletSection +
        chatSection +
        photosSection +
        saluteSection +
        expensesBytes +
        notesBytes +
        calendarBytes +
        todoBytes,
      );

      const plan = await resolveFamilyPlanForQuotas(uid, familyId);
      const quotaBytes = storageQuotaBytesForPlan(plan);
      logger.info("getStorageUsage", {
        uid,
        familyId,
        usedBytes,
        legacyStoredUsed: legacyUsed,
        plan,
        quotaBytes,
        sectionsLive: media,
      });

      return {
        usedBytes,
        quotaBytes,
        sections: {
          documents: documentsSection,
          wallet: walletSection,
          chat: chatSection,
          photos: photosSection,
          salute: saluteSection,
          expenses: expensesBytes,
          notes: notesBytes,
          calendar: calendarBytes,
          todo: todoBytes,
        },
        counts: {
          notes: notesCount,
          calendar: calendarCount,
          todo: todoCount,
          expenses: expensesCount,
        },
      };
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// STORAGE — initStorageUsage (ricalcolo completo da zero)
//
// Conteggio per sezione:
// • documents → fileSize reale da KBDocument
// • wallet    → pdfStorageBytes reale da walletTickets (PDF cifrato su Storage)
// • chat      → mediaFileSize reale per ogni messaggio con media;
//               fallback 512KB per messaggi senza il campo (retrocompatibilità)
//               I messaggi di testo NON occupano Firebase Storage.
// • photos    → fileSize reale da KBFamilyPhoto (album condiviso)
// • salute    → foto visite pediatriche (photoURLs), stima 200KB/foto.
//               KBMedicalExam, KBTreatment, KBVaccine non hanno allegati su Storage.
// • expenses  → KBExpense.attachedDocumentId punta a KBDocument (già in documents).
//               KBExpense.receiptThumbnailData è Data locale SwiftData, non su Storage.
//               → expenses = 0 per Storage.
// • notes/calendar/todo → solo Firestore, niente file su Storage.
// ─────────────────────────────────────────────────────────────────────────────

exports.initStorageUsage = onCall(
    {region: "europe-west1", invoker: "public"},
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

      logger.info("initStorageUsage: starting", {uid, familyId});

      const {
        docBytes,
        walletBytes,
        chatBytes,
        photoBytes,
        saluteBytes,
      } = await computeMediaStorageBytesForFamily(familyId);

      const expensesBytes = 0;

      const totalBytes = docBytes + walletBytes + chatBytes + photoBytes + saluteBytes + expensesBytes;

      await storageStatsRef(familyId).set({
        usedBytes: totalBytes,
        sections: {
          documents: docBytes,
          wallet: walletBytes,
          chat: chatBytes,
          photos: photoBytes,
          salute: saluteBytes,
          expenses: expensesBytes,
        },
        lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        initializedAt: admin.firestore.FieldValue.serverTimestamp(),
        initializedBy: uid,
      }, {merge: false});

      const plan = await resolveFamilyPlanForQuotas(uid, familyId);
      const quotaBytes = storageQuotaBytesForPlan(plan);

      logger.info("initStorageUsage: completed", {
        familyId,
        plan,
        quotaBytes,
        docBytes,
        walletBytes,
        chatBytes,
        photoBytes,
        saluteBytes,
        expensesBytes,
        totalBytes,
      });

      return {
        docBytes,
        walletBytes,
        chatBytes,
        photoBytes,
        saluteBytes,
        expensesBytes,
        totalBytes,
        quotaBytes,
      };
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// STORAGE — initStorageUsageAdmin (reset globale per tutte le famiglie)
//
// Chiamata solo dalla console admin. Non verifica la membership.
// Itera su tutte le famiglie e ricalcola stats/storage per ognuna.
// ─────────────────────────────────────────────────────────────────────────────

const ADMIN_UIDS = ["efw85HN41nb1rmslevC3wkFpVUo1"]; // aggiungi il tuo UID Firebase Auth

exports.initStorageUsageAdmin = onCall(
    {region: "europe-west1", invoker: "public", timeoutSeconds: 540, memory: "512MiB"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
      if (!ADMIN_UIDS.includes(uid)) throw new HttpsError("permission-denied", "Non autorizzato.");

      const db = admin.firestore();

      logger.info("initStorageUsageAdmin: start", {uid});

      const familiesSnap = await db.collection("families").get();
      let totalFamilies = 0;
      let grandTotalBytes = 0;

      for (const familyDoc of familiesSnap.docs) {
        const familyId = familyDoc.id;

        const {
          docBytes,
          walletBytes,
          chatBytes,
          photoBytes,
          saluteBytes,
        } = await computeMediaStorageBytesForFamily(familyId);

        const totalBytes = docBytes + walletBytes + chatBytes + photoBytes + saluteBytes;
        grandTotalBytes += totalBytes;

        await storageStatsRef(familyId).set({
          usedBytes: totalBytes,
          sections: {
            documents: docBytes,
            wallet: walletBytes,
            chat: chatBytes,
            photos: photoBytes,
            salute: saluteBytes,
            expenses: 0,
          },
          lastUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          initializedAt: admin.firestore.FieldValue.serverTimestamp(),
          initializedBy: uid,
        }, {merge: false});

        logger.info("initStorageUsageAdmin: family done", {familyId, totalBytes});
        totalFamilies++;
      }

      logger.info("initStorageUsageAdmin: complete", {totalFamilies, grandTotalBytes});
      return {totalFamilies, grandTotalBytes};
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// ACCOUNT DELETION
// ─────────────────────────────────────────────────────────────────────────────

const FAMILY_SUBCOLLECTIONS = [
  // ── Famiglia & accesso ──────────────────────────────────────────
  "members",
  "children",
  "invites",
  // ── Documenti ──────────────────────────────────────────────────
  "documents",
  "documentCategories",
  // ── Todo & lista spesa ─────────────────────────────────────────
  "todos",
  "groceries",
  // ── Calendario ─────────────────────────────────────────────────
  "calendarEvents",
  // ── Spese ──────────────────────────────────────────────────────
  "expenses",
  // ── Salute ─────────────────────────────────────────────────────
  "medicalVisits",
  "medicalExams",
  "treatments",
  "vaccines",
  "pediatricProfiles",
  // ── Localizzazione ─────────────────────────────────────────────
  "locations",
  // ── Foto album condiviso ────────────────────────────────────────
  "photos",
  // ── Note ───────────────────────────────────────────────────────
  "notes",
  // ── Chat ───────────────────────────────────────────────────────
  "chatMessages",
  // ── Routine ────────────────────────────────────────────────────
  "routines",
  "routineChecks",
  // ── Contatori e statistiche ─────────────────────────────────────
  "counters",
  "stats",
  // ── Animali ────────────────────────────────────────────────────
  "pets",
  "petEvents",
  // ── Casa ───────────────────────────────────────────────────────
  "homeItems",
  "housePayments",
  // ── Garage ─────────────────────────────────────────────────────
  "vehicles",
  "vehicleEvents",
];

/**
 * Deletes all documents in a Firestore collection.
 * @param {object} colRef
 * @param {number} batchSize
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
 * @param {string} prefix
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
 * @param {string} familyId
 * @return {Promise<number>}
 */
async function countActiveMembers(familyId) {
  const snap = await admin.firestore()
      .collection("families").doc(familyId).collection("members").get();
  return snap.docs.filter((d) => d.get("isDeleted") !== true).length;
}

/**
 * Completely deletes a family and all its data.
 * @param {string} familyId
 * @return {Promise<void>}
 */
async function deleteFamilyCompletely(familyId) {
  const db = admin.firestore();
  for (const sub of FAMILY_SUBCOLLECTIONS) {
    await deleteCollection(db.collection(`families/${familyId}/${sub}`));
  }
  await db.collection("families").doc(familyId).delete().catch(() => {});
  await deleteStoragePrefix(`families/${familyId}/`);

  // Rimuovi contatore AI famiglia
  await deleteCollection(db.collection(`ai_usage/family_${familyId}/daily`)).catch(() => {});
  await db.collection("ai_usage").doc(`family_${familyId}`).delete().catch(() => {});
}

exports.deleteAccount = onCall(
    {region: "europe-west1", invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Not authenticated");

      const db = admin.firestore();
      logger.info("deleteAccount started", {uid});

      const membershipsRef = db.collection("users").doc(uid).collection("memberships");
      const membershipsSnap = await membershipsRef.get();
      const familyIds = membershipsSnap.docs.map((d) => d.id);

      for (const familyId of familyIds) {
        let memberCount = 0;
        try {
          memberCount = await countActiveMembers(familyId);
        } catch (e) {
          memberCount = 0;
        }

        if (memberCount > 1) {
          await db.collection("families").doc(familyId).collection("members").doc(uid).delete().catch(() => {});
        } else {
          await deleteFamilyCompletely(familyId);
        }

        await membershipsRef.doc(familyId).delete().catch(() => {});
      }

      await deleteCollection(db.collection(`users/${uid}/fcmTokens`)).catch(() => {});
      await deleteCollection(db.collection(`users/${uid}/memberships`)).catch(() => {});
      await db.collection("users").doc(uid).delete().catch(() => {});
      await deleteStoragePrefix(`users/${uid}/`).catch(() => {});

      // ── AI usage: rimuovi contatore utente e, se ultimo membro, anche quello famiglia ──
      await deleteCollection(db.collection(`ai_usage/${uid}/daily`)).catch(() => {});
      await db.collection("ai_usage").doc(uid).delete().catch(() => {});
      // Il contatore famiglia (family_{familyId}) viene rimosso da deleteFamilyCompletely
      // se l'utente era l'ultimo membro — altrimenti resta per gli altri.

      await admin.auth().deleteUser(uid);

      logger.info("deleteAccount completed", {uid, families: familyIds.length});
      return {ok: true, familiesProcessed: familyIds.length};
    },
);

exports.deleteFamily = onCall(
    {region: "europe-west1", invoker: "public"},
    async (request) => {
      const uid = request.auth?.uid;
      if (!uid) throw new HttpsError("unauthenticated", "Not authenticated");

      const familyId = request.data?.familyId;
      if (!familyId) throw new HttpsError("invalid-argument", "familyId is required");

      const db = admin.firestore();
      logger.info("deleteFamily started", {uid, familyId});

      // Verify family exists
      const familySnap = await db.collection("families").doc(familyId).get();
      if (!familySnap.exists) {
        logger.warn("deleteFamily: family not found", {uid, familyId});
        return {ok: true, skipped: true};
      }

      // Anche se isDeleted=true, completa la pulizia (membership + subcollections)
      logger.info("deleteFamily: proceeding with cleanup", {uid, familyId});

      const memberCount = await countActiveMembers(familyId);
      if (memberCount > 1) {
        logger.error("TENTATIVO DI CANCELLAZIONE ILLEGALE", {familyId, memberCount, callerUid: uid});
        throw new HttpsError(
            "failed-precondition",
            "La famiglia ha ancora altri membri attivi. Rimuovili prima di eliminare la famiglia.",
        );
      }

      // Delete everything server-side
      await deleteFamilyCompletely(familyId);

      // Remove membership index for caller (best effort)
      await db.collection("users").doc(uid)
          .collection("memberships").doc(familyId)
          .delete().catch(() => {});

      logger.info("deleteFamily completed", {uid, familyId});
      return {ok: true};
    },
);

exports.setFamilyPlanOverride = onCall(
    {region: "europe-west1", invoker: "public"},
    async (request) => {
      const callerUid = request.auth?.uid;
      if (!callerUid) throw new HttpsError("unauthenticated", "Login richiesto.");

      if (!ADMIN_UIDS.includes(callerUid)) {
        throw new HttpsError("permission-denied", "Non autorizzato.");
      }

      const {familyId, plan, note} = request.data || {};

      if (!familyId || typeof familyId !== "string") {
        throw new HttpsError("invalid-argument", "familyId richiesto.");
      }
      if (plan !== null && plan !== "pro" && plan !== "max") {
        throw new HttpsError("invalid-argument", "plan deve essere 'pro', 'max' o null.");
      }

      await admin.firestore()
          .collection("families").doc(familyId)
          .set({
            planOverride: plan,
            planOverrideNote: note || "",
            planOverrideSetAt: admin.firestore.FieldValue.serverTimestamp(),
            planOverrideSetBy: callerUid,
          }, {merge: true});

      logger.info("setFamilyPlanOverride", {callerUid, familyId, plan, note});
      return {success: true};
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// GARBAGE COLLECTOR NOTTURNO
// ─────────────────────────────────────────────────────────────────────────────

exports.garbageCollectDeleted = onSchedule(
    {
      schedule: "0 3 */5 * *",
      timeZone: "Europe/Rome",
      region: "europe-west1",
      timeoutSeconds: 540,
      memory: "512MiB",
    },
    async () => {
      const bucket = admin.storage().bucket(STORAGE_BUCKET);
      const db = admin.firestore();

      logger.info("garbageCollectDeleted: start");

      const familiesSnap = await db.collection("families").get();
      logger.info("garbageCollectDeleted: families to scan", {count: familiesSnap.size});

      let totalDocsDeleted = 0;
      let totalChatDeleted = 0;
      let totalPhotosDeleted = 0;
      let totalWalletDeleted = 0;

      for (const familyDoc of familiesSnap.docs) {
        const familyId = familyDoc.id;

        // ── 1. Documenti soft-deleted ──────────────────────────────────────────
        // onDocumentHardDeleted aggiorna già il contatore storage quando il doc
        // viene eliminato da Firestore — non serve chiamare updateStorageBytes qui.
        const docsSnap = await db.collection("families").doc(familyId)
            .collection("documents")
            .where("isDeleted", "==", true)
            .get();

        logger.info("GC: documents to delete", {familyId, count: docsSnap.size});

        for (const doc of docsSnap.docs) {
          const data = doc.data();
          const storagePath = data.storagePath || data.firebasePath || "";

          if (storagePath) {
            try {
              await bucket.file(storagePath).delete();
              logger.info("GC: deleted Storage blob", {familyId, storagePath});
            } catch (e) {
              if (e.code !== 404) logger.warn("GC: Storage delete failed", {familyId, storagePath, err: e.message});
            }
          }

          await doc.ref.delete();
          totalDocsDeleted++;
        }

        // ── 2. Chat media soft-deleted ─────────────────────────────────────────
        // onChatMessageSoftDeleted ha già sottratto i bytes al momento della
        // soft-deletion. Qui solo pulizia del blob su Storage e del doc Firestore.
        const chatSnap = await db.collection("families").doc(familyId)
            .collection("chatMessages")
            .where("isDeleted", "==", true)
            .get();

        logger.info("GC: chatMessages to delete", {familyId, count: chatSnap.size});

        for (const msg of chatSnap.docs) {
          const data = msg.data();
          const mediaPath = data.mediaStoragePath || "";

          if (mediaPath) {
            try {
              await bucket.file(mediaPath).delete();
              logger.info("GC: deleted chat media blob", {familyId, mediaPath});
              totalChatDeleted++;
            } catch (e) {
              if (e.code !== 404) logger.warn("GC: chat media delete failed", {familyId, mediaPath, err: e.message});
            }
          }
          await msg.ref.delete();
        }

        // ── 3. Foto album condiviso soft-deleted ───────────────────────────────
        // onPhotoHardDeleted aggiorna già il contatore storage quando la foto
        // viene eliminata da Firestore — non serve chiamare updateStorageBytes qui.
        const photosSnap = await db.collection("families").doc(familyId)
            .collection("photos")
            .where("isDeleted", "==", true)
            .get();

        logger.info("GC: photos to delete", {familyId, count: photosSnap.size});

        for (const photo of photosSnap.docs) {
          const data = photo.data();
          const storagePath = data.storagePath || "";

          if (storagePath) {
            try {
              await bucket.file(storagePath).delete();
              logger.info("GC: deleted photo blob", {familyId, storagePath});
            } catch (e) {
              if (e.code !== 404) logger.warn("GC: photo delete failed", {familyId, storagePath, err: e.message});
            }
          }

          await photo.ref.delete();
          totalPhotosDeleted++;
        }

        // ── 4. Wallet tickets soft-deleted ─────────────────────────────────────
        // Cleanup del PDF cifrato su Storage (path:
        // families/{familyId}/wallet/{ticketId}/ticket.pdf.kbenc) e del doc Firestore.
        const walletSnap = await db.collection("families").doc(familyId)
            .collection("walletTickets")
            .where("isDeleted", "==", true)
            .get();

        logger.info("GC: walletTickets to delete", {familyId, count: walletSnap.size});

        for (const ticket of walletSnap.docs) {
          const ticketId = ticket.id;
          const pdfPath = `families/${familyId}/wallet/${ticketId}/ticket.pdf.kbenc`;

          try {
            await bucket.file(pdfPath).delete();
            logger.info("GC: deleted wallet PDF blob", {familyId, ticketId, pdfPath});
          } catch (e) {
            if (e.code !== 404) logger.warn("GC: wallet PDF delete failed", {familyId, ticketId, pdfPath, err: e.message});
          }

          await ticket.ref.delete();
          totalWalletDeleted++;
        }
      }

      logger.info("garbageCollectDeleted: complete", {
        totalDocsDeleted,
        totalChatDeleted,
        totalPhotosDeleted,
        totalWalletDeleted,
        families: familiesSnap.size,
      });
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// WALLET
// ─────────────────────────────────────────────────────────────────────────────

// Tracking storage wallet (PDF cifrati):
// - create/restore ticket   -> +pdfStorageBytes
// - soft/hard delete ticket -> -pdfStorageBytes
// - update ticket live      -> delta(after-before)
exports.onWalletTicketStorageChanged = onDocumentWritten(
    {
      document: "families/{familyId}/walletTickets/{ticketId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const ticketId = event.params.ticketId;
      const before = event.data?.before?.exists ? event.data.before.data() : null;
      const after = event.data?.after?.exists ? event.data.after.data() : null;

      const beforeLive = !!before && before.isDeleted !== true;
      const afterLive = !!after && after.isDeleted !== true;
      const beforeBytes = beforeLive ? await resolveWalletPdfBytes(familyId, ticketId, before) : 0;
      const afterBytes = afterLive ? await resolveWalletPdfBytes(familyId, ticketId, after) : 0;

      let delta = 0;
      if (!beforeLive && afterLive) {
        delta = afterBytes;
      } else if (beforeLive && !afterLive) {
        delta = -beforeBytes;
      } else if (beforeLive && afterLive) {
        delta = afterBytes - beforeBytes;
      }

      if (delta === 0) return;

      if (afterLive && after && walletPdfBytes(after) === 0 && afterBytes > 0) {
        await event.data.after.ref.set({pdfStorageBytes: afterBytes}, {merge: true});
      }

      logger.info("onWalletTicketStorageChanged: tracking delta", {
        familyId,
        ticketId,
        delta,
        beforeBytes,
        afterBytes,
      });
      await updateStorageBytes(familyId, delta, "wallet");
    },
);

/**
 * Returns a short, human-readable label for a wallet ticket kind.
 * Keep in sync with iOS `KBWalletTicketKind.displayName`.
 * @param {string|null|undefined} kindRaw
 * @return {string}
 */
function walletKindLabel(kindRaw) {
  switch ((kindRaw || "").toLowerCase()) {
    case "train": return "Treno";
    case "flight": return "Volo";
    case "ferry": return "Traghetto";
    case "bus": return "Autobus";
    case "concert": return "Concerto";
    case "cinema": return "Cinema";
    case "parking": return "Parcheggio";
    case "museum": return "Museo";
    default: return "Biglietto";
  }
}

/**
 * Formats a Date as "dd/MM HH:mm" in Europe/Rome.
 * @param {Date} date
 * @return {string}
 */
function formatWalletDate(date) {
  try {
    return new Intl.DateTimeFormat("it-IT", {
      day: "2-digit", month: "2-digit",
      hour: "2-digit", minute: "2-digit",
      timeZone: "Europe/Rome",
    }).format(date);
  } catch (_) {
    return date.toISOString();
  }
}

// Notifica i membri della famiglia all'aggiunta di un nuovo biglietto wallet.
// I campi testuali (title, location, ecc.) sono cifrati end-to-end lato client,
// quindi il body usa solo metadati plaintext (kind, eventDate, createdByName).
exports.notifyNewWalletTicket = onDocumentCreated(
    {
      document: "families/{familyId}/walletTickets/{ticketId}",
      region: "europe-west1",
    },
    async (event) => {
      const familyId = event.params.familyId;
      const ticketId = event.params.ticketId;

      const ticketData = event.data ? event.data.data() : null;
      if (!ticketData) {
        logger.warn("notifyNewWalletTicket: missing ticket data"); return;
      }
      if (ticketData.isDeleted) {
        logger.info("notifyNewWalletTicket: isDeleted=true, skip", {familyId, ticketId}); return;
      }

      const creatorUid = ticketData.createdBy || ticketData.updatedBy || null;
      if (!creatorUid) {
        logger.warn("notifyNewWalletTicket: missing creatorUid", {familyId, ticketId}); return;
      }

      logger.info("notifyNewWalletTicket triggered", {familyId, ticketId, creatorUid});

      const membersSnap = await admin.firestore()
          .collection("families").doc(familyId).collection("members").get();

      if (membersSnap.empty) {
        logger.warn("notifyNewWalletTicket: members subcollection is empty", {familyId}); return;
      }

      const memberUids = membersSnap.docs.map((d) => d.id).filter((uid) => uid && uid !== creatorUid);
      if (memberUids.length === 0) {
        logger.info("notifyNewWalletTicket: no targets (only creator)", {familyId}); return;
      }

      const creatorName = (ticketData.createdByName || "").trim();
      const kindLabel = walletKindLabel(ticketData.kind);
      const emitter = (ticketData.emitter || "").toString().trim();
      // "Trenitalia · Treno" se emitter presente, altrimenti "Treno"
      const kindWithEmitter = emitter ? `${emitter} · ${kindLabel}` : kindLabel;
      const eventDate = ticketData.eventDate?.toDate ? ticketData.eventDate.toDate() : null;

      const title = "🎟️ Nuovo biglietto nel Wallet";
      const bodyPrefix = creatorName ? `${creatorName} · ${kindWithEmitter}` : kindWithEmitter;
      const body = eventDate ? `${bodyPrefix} — ${formatWalletDate(eventDate)}` : bodyPrefix;

      const messagesToSend = [];

      for (const uid of memberUids) {
        const tokens = await getUserTokensIfEnabled(uid, "notifyOnNewWalletTicket");
        if (tokens.length === 0) {
          logger.info("notifyNewWalletTicket: user opted out or no tokens", {uid}); continue;
        }

        const badge = await incrementCounterAndGetBadge({familyId, uid, field: "wallet"});
        messagesToSend.push({
          tokens,
          notification: {title, body},
          data: {type: "new_wallet_ticket", familyId, ticketId},
          apns: {payload: {aps: {badge, sound: "default"}}},
          android: {notification: {sound: "default"}},
        });
      }

      if (messagesToSend.length === 0) {
        logger.info("notifyNewWalletTicket: no per-user notifications to send", {familyId}); return;
      }

      const results = await Promise.allSettled(messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)));
      let totalSuccess = 0; let totalFailure = 0;
      results.forEach((r) => {
        if (r.status === "fulfilled") {
          totalSuccess += r.value.successCount; totalFailure += r.value.failureCount;
        } else {
          totalFailure += 1;
        }
      });
      logger.info("notifyNewWalletTicket: send result", {familyId, ticketId, successCount: totalSuccess, failureCount: totalFailure, userTargets: messagesToSend.length});
    },
);

// Scheduler orario: invia promemoria per biglietti wallet imminenti.
// Finestre: T-24h (23h30–24h30) e T-2h (1h30–2h30). Usa i flag
// `reminded24h` / `reminded2h` sul doc per evitare duplicati (idempotenza
// garantita a livello di documento, indipendentemente dal numero di membri).
exports.notifyUpcomingWalletTickets = onSchedule(
    {
      schedule: "every 60 minutes",
      region: "europe-west1",
      timeZone: "Europe/Rome",
    },
    async () => {
      const db = admin.firestore();
      const now = new Date();
      const nowTs = admin.firestore.Timestamp.fromDate(now);

      // Finestra massima: i prossimi 25 ore (copre 24h +30min).
      const upperBound = admin.firestore.Timestamp.fromDate(
          new Date(now.getTime() + 25 * 60 * 60 * 1000),
      );

      logger.info("notifyUpcomingWalletTickets: start", {now: now.toISOString()});

      const snap = await db.collectionGroup("walletTickets")
          .where("isDeleted", "==", false)
          .where("eventDate", ">=", nowTs)
          .where("eventDate", "<=", upperBound)
          .get();

      if (snap.empty) {
        logger.info("notifyUpcomingWalletTickets: no upcoming tickets");
        return;
      }

      logger.info("notifyUpcomingWalletTickets: scanning", {count: snap.size});

      let total24h = 0; let total2h = 0;

      for (const doc of snap.docs) {
        const data = doc.data();
        const ref = doc.ref;

        // Parent path: families/{familyId}/walletTickets/{ticketId}
        const pathParts = ref.path.split("/");
        const familyId = pathParts[1];
        const ticketId = doc.id;

        const eventDate = data.eventDate?.toDate?.();
        if (!eventDate) continue;

        const diffMs = eventDate.getTime() - now.getTime();
        const diffH = diffMs / (60 * 60 * 1000);

        let windowType = null;
        if (diffH >= 23.5 && diffH <= 24.5 && !data.reminded24h) {
          windowType = "24h";
        } else if (diffH >= 1.5 && diffH <= 2.5 && !data.reminded2h) {
          windowType = "2h";
        } else {
          continue;
        }

        const kindLabel = walletKindLabel(data.kind);
        const emitter = (data.emitter || "").toString().trim();
        const kindWithEmitter = emitter ? `${emitter} · ${kindLabel}` : kindLabel;
        const title = windowType === "24h" ?
          "⏰ Biglietto domani" :
          "⏰ Biglietto tra 2 ore";
        const body = `${kindWithEmitter} — ${formatWalletDate(eventDate)}`;

        const membersSnap = await db.collection("families").doc(familyId).collection("members").get();
        if (membersSnap.empty) {
          logger.warn("notifyUpcomingWalletTickets: no members", {familyId, ticketId}); continue;
        }

        const memberUids = membersSnap.docs.map((d) => d.id).filter(Boolean);
        if (memberUids.length === 0) continue;

        const messagesToSend = [];
        for (const uid of memberUids) {
          const tokens = await getUserTokensIfEnabled(uid, "notifyOnWalletReminder");
          if (tokens.length === 0) continue;

          // NOTA: niente incrementCounterAndGetBadge qui — un reminder non è
          // un nuovo elemento in app, quindi il contatore wallet non cresce.
          // Il badge sistema verrà rinfrescato dal client all'apertura.
          messagesToSend.push({
            tokens,
            notification: {title, body},
            data: {type: "wallet_ticket_reminder", familyId, ticketId, window: windowType},
            apns: {payload: {aps: {sound: "default"}}},
            android: {notification: {sound: "default"}},
          });
        }

        if (messagesToSend.length > 0) {
          const results = await Promise.allSettled(
              messagesToSend.map((msg) => admin.messaging().sendEachForMulticast(msg)),
          );
          let ok = 0; let ko = 0;
          results.forEach((r) => {
            if (r.status === "fulfilled") {
              ok += r.value.successCount; ko += r.value.failureCount;
            } else {
              ko += 1;
            }
          });
          logger.info("notifyUpcomingWalletTickets: sent", {familyId, ticketId, window: windowType, ok, ko, targets: messagesToSend.length});
        }

        // Idempotenza: flag il doc come promemoria inviato per questa finestra.
        const flagField = windowType === "24h" ? "reminded24h" : "reminded2h";
        try {
          await ref.set({
            [flagField]: true,
            [`${flagField}At`]: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        } catch (e) {
          logger.warn("notifyUpcomingWalletTickets: flag write failed", {familyId, ticketId, window: windowType, err: e.message});
        }

        if (windowType === "24h") total24h++; else total2h++;
      }

      logger.info("notifyUpcomingWalletTickets: complete", {total24h, total2h});
    },
);
