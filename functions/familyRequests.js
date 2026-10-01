/* eslint-disable max-len */
// ─────────────────────────────────────────────────────────────────────────────
// RICHIESTE («Chi prende Marco giovedì?»)
//
// Una domanda con destinatari e scadenza: il primo «Io» la chiude e fa nascere
// da sé il to-do assegnato, visibile a tutta la famiglia. Il destinatario può
// essere FUORI dall'app: riceve un link, risponde dal browser
// (`kidboxapp.com/r`) e sotto trova l'invito alla famiglia. Disegno completo e
// perché in internal/richieste-disegno.md.
//
// Documento `families/{familyId}/requests/{requestId}`. Il client di chi
// chiede lo CREA (le rules ne vincolano la forma) e può solo ritirarlo finché
// è aperto; tutto il resto lo scrive questo file:
//   responses: {uid | ext_<id>: {answer, type, name, at}}
//   status: open → claimed | expired | cancelled
//   claimedBy: {type: "member", uid, name} | {type: "external", name}
//   claimedAt, resolvedAt, todoId, allDeclinedAt
//   external.openedAt, external.answeredAt  (prima apertura e prima risposta)
//
// Perché le risposte passano dal server e non dal client:
//   1. «il primo Io vince» si decide in UNA transazione, in un posto solo;
//   2. il to-do nasce con l'Admin SDK in quella stessa transazione, uguale per
//      iOS, Android e web (stessi campi di `createReminderTodo` di Alexa);
//   3. chi risponde dal link non ha un client né un account.
//
// Il link esterno segue lo schema degli inviti: il token sta nel FRAMMENTO
// dell'URL (dopo il #), che non arriva mai al server né finisce nei log o nelle
// anteprime di WhatsApp; la pagina lo manda nel corpo della POST. Sul
// documento c'è solo l'impronta SHA-256 (`external.tokenHash`).
// ─────────────────────────────────────────────────────────────────────────────

const admin = require("firebase-admin");
const crypto = require("node:crypto");
const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const {t: tn, intlLocale} = require("./notificationsI18n");

const REGION = "europe-west1";
const TZ = "Europe/Rome";
/** Id di Firestore come li generano i client (UUID, push id). */
const ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
/** Token del link: 32 byte in base64url sono 43 caratteri. */
const TOKEN_RE = /^[A-Za-z0-9_-]{32,128}$/;
const NAME_MAX = 40;
/** Lista in cui finisce il to-do se quella scelta è sparita e non ce n'è altra. */
const FALLBACK_LIST_NAME = "To-do";
/** Preferenza dedicata (non ancora nelle impostazioni), poi quella dei to-do assegnati. */
const NOTIFY_PREFS = ["notifyOnFamilyRequest", "notifyOnTodoAssigned"];
/** Categoria APNs: i client aggiornati vi registrano le azioni «Io» / «Non posso». */
const IOS_CATEGORY = "FAMILY_REQUEST";

/** Origini della landing da cui la pagina `/r` chiama `requestPublic`. */
const ALLOWED_ORIGINS = [
  "https://kidboxapp.com",
  "https://www.kidboxapp.com",
  "https://kidbox-landing.web.app",
  "https://kidbox-landing.firebaseapp.com",
  "http://localhost:5050",
];

/** Errore con un codice che client e pagina sanno tradurre. */
class RequestError extends Error {
  /**
   * @param {string} code not_found | own_request | name_required | bad_request
   */
  constructor(code) {
    super(code);
    this.code = code;
  }
}

/**
 * SHA-256 esadecimale di un token.
 * @param {string} token
 * @return {string}
 */
function sha256hex(token) {
  return crypto.createHash("sha256").update(token, "utf8").digest("hex");
}

/**
 * Confronto a tempo costante fra il token presentato e l'impronta salvata.
 * @param {string} token
 * @param {*} storedHash
 * @return {boolean}
 */
function tokenMatches(token, storedHash) {
  if (typeof storedHash !== "string" || storedHash.length !== 64) return false;
  const a = Buffer.from(sha256hex(token), "hex");
  const b = Buffer.from(storedHash, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/**
 * Nome di battesimo, per mostrarlo a chi è fuori dalla famiglia.
 * @param {*} displayName
 * @return {string}
 */
function firstName(displayName) {
  const s = typeof displayName === "string" ? displayName.trim() : "";
  return s ? s.split(/\s+/)[0] : "";
}

/**
 * Nome scritto da chi risponde dal link: ripulito e accorciato.
 * @param {*} raw
 * @return {string}
 */
function cleanName(raw) {
  if (typeof raw !== "string") return "";
  // eslint-disable-next-line no-control-regex
  return raw.replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim().slice(0, NAME_MAX);
}

/**
 * Millisecondi di un Timestamp (o null).
 * @param {*} ts
 * @return {?number}
 */
function msOf(ts) {
  return ts && typeof ts.toMillis === "function" ? ts.toMillis() : null;
}

/**
 * Vero se tutti i membri a cui si è chiesto hanno detto «Non posso».
 * Con un link esterno aperto non vale: qualcuno fuori può ancora rispondere.
 * @param {object} data
 * @return {boolean}
 */
function allRecipientsDeclined(data) {
  if (data.external) return false;
  const recipients = (Array.isArray(data.recipients) ? data.recipients : [])
      .filter((uid) => uid && uid !== data.createdBy);
  if (recipients.length === 0) return false;
  const responses = data.responses || {};
  return recipients.every((uid) => responses[uid]?.answer === "no");
}

/**
 * Quando, nella lingua del destinatario: «gio 2 ott, 16:30» o «gio 2 ott».
 * @param {Date} date
 * @param {boolean} hasTime
 * @param {string} lang
 * @return {string}
 */
function formatWhen(date, hasTime, lang) {
  const opts = {timeZone: TZ, weekday: "short", day: "numeric", month: "short"};
  if (hasTime) Object.assign(opts, {hour: "2-digit", minute: "2-digit"});
  try {
    return new Intl.DateTimeFormat(intlLocale(lang), opts).format(date);
  } catch (_) {
    return date.toISOString();
  }
}

/**
 * Lista in cui far nascere il to-do, letta DENTRO la transazione.
 *
 * Un to-do con `listId` vuoto o di una lista inesistente su Android non si vede
 * (foreign key di Room) e su iOS non compare in nessuna schermata, perché i
 * to-do si elencano dentro le liste. Se la lista scelta è sparita nel
 * frattempo si usa la più recente; se non ce n'è nessuna se ne crea una, con
 * i campi di `ensureAlexaTodoList`.
 * @param {FirebaseFirestore.Transaction} tx
 * @param {FirebaseFirestore.DocumentReference} famRef
 * @param {string} wanted
 * @return {Promise<{listId: string, create: ?object}>}
 */
async function resolveListId(tx, famRef, wanted) {
  const lists = famRef.collection("todoLists");
  if (typeof wanted === "string" && wanted) {
    const snap = await tx.get(lists.doc(wanted));
    if (snap.exists && snap.get("isDeleted") !== true) return {listId: wanted, create: null};
  }
  const alive = await tx.get(lists.where("isDeleted", "==", false));
  if (!alive.empty) {
    const newest = alive.docs
        .slice()
        .sort((a, b) => (msOf(b.get("updatedAt")) || 0) - (msOf(a.get("updatedAt")) || 0))[0];
    return {listId: newest.id, create: null};
  }
  return {listId: crypto.randomUUID(), create: {name: FALLBACK_LIST_NAME}};
}

/**
 * Ciò che si mostra di una richiesta a chi la vede dal link: niente uid,
 * niente destinatari, niente risposte altrui.
 * @param {object} data
 * @param {string} requesterName
 * @param {?string} viewerKey `ext_<id>` del browser che chiede, per dirgli
 *     «l'hai presa tu» anche se ricarica la pagina.
 * @return {object}
 */
function publicView(data, requesterName, viewerKey = null) {
  const expiresAt = msOf(data.expiresAt);
  const lazilyExpired = data.status === "open" && expiresAt !== null && expiresAt <= Date.now();
  return {
    status: lazilyExpired ? "expired" : data.status,
    kind: data.kind || "todo",
    title: data.title || "",
    dueAt: msOf(data.dueAt),
    dueHasTime: data.dueHasTime !== false,
    expiresAt,
    requesterName: firstName(requesterName),
    claimedByName: data.claimedBy ? firstName(data.claimedBy.name) : null,
    claimedByYou: !!viewerKey && data.claimedBy?.key === viewerKey,
    inviteId: data.external?.inviteId || null,
  };
}

/**
 * Il cuore comune: applica una risposta in transazione.
 *
 * Solo `open` accetta risposte. Il primo «yes» porta a `claimed` e crea il
 * to-do; un «no» si registra e basta (se era l'ultimo membro a cui si era
 * chiesto, si segna `allDeclinedAt`, che fa partire la push a chi ha chiesto).
 *
 * `updatedBy` del to-do è chi ha risposto: così `notifyTodoAssigned`
 * (che esce se `assignedTo === updatedBy`) non manda «Nuovo To-Do» a chi si è
 * appena preso la cosa da solo.
 * @param {{familyId: string, requestId: string, answer: string,
 *     responder: {key: string, type: string, uid?: string, name: string}}} p
 * @return {Promise<{outcome: string, data: object}>}
 */
async function applyResponse({familyId, requestId, answer, responder}) {
  const db = admin.firestore();
  const {FieldValue, FieldPath, Timestamp} = admin.firestore;
  const famRef = db.collection("families").doc(familyId);
  const reqRef = famRef.collection("requests").doc(requestId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    if (!snap.exists) throw new RequestError("not_found");
    const data = snap.data();

    if (data.status === "open" && (msOf(data.expiresAt) ?? Infinity) <= Date.now()) {
      tx.update(reqRef, {
        status: "expired",
        resolvedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {outcome: "expired", data: {...data, status: "expired"}};
    }
    if (data.status !== "open") return {outcome: data.status, data};
    if (responder.type === "member" && responder.uid === data.createdBy) {
      throw new RequestError("own_request");
    }

    // In una transazione tutte le letture vanno prima delle scritture.
    const list = answer === "yes" ? await resolveListId(tx, famRef, data.listId) : null;

    const response = {answer, type: responder.type, name: responder.name, at: Timestamp.now()};
    const pairs = [
      new FieldPath("responses", responder.key), response,
      "updatedAt", FieldValue.serverTimestamp(),
    ];
    if (responder.type === "external" && data.external && !data.external.answeredAt) {
      pairs.push(new FieldPath("external", "answeredAt"), FieldValue.serverTimestamp());
    }

    const after = {...data, responses: {...(data.responses || {}), [responder.key]: response}};

    if (answer === "no") {
      if (!data.allDeclinedAt && allRecipientsDeclined(after)) {
        pairs.push("allDeclinedAt", FieldValue.serverTimestamp());
      }
      tx.update(reqRef, ...pairs);
      return {outcome: "declined", data: after};
    }

    const claimedBy = responder.type === "member" ?
      {type: "member", uid: responder.uid, name: responder.name} :
      {type: "external", name: responder.name, key: responder.key};
    const todoId = crypto.randomUUID();
    const todosRef = famRef.collection("todos").doc(todoId);
    const author = responder.uid || data.createdBy;

    if (list.create) {
      tx.set(famRef.collection("todoLists").doc(list.listId), {
        childId: "",
        name: list.create.name,
        isDeleted: false,
        createdBy: data.createdBy,
        updatedBy: author,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    // Gli stessi campi di `createReminderTodo` (Alexa) e di `TodoRemoteStore`
    // (iOS). Niente `remindAt`/`remindSentAt`: senza promemoria non vanno
    // scritti nemmeno a null, o il motore li pescherebbe.
    tx.set(todosRef, {
      childId: data.childId || "",
      title: data.title,
      listId: list.listId,
      isDone: false,
      isDeleted: false,
      notes: null,
      dueAt: data.dueAt || null,
      dueHasTime: data.dueAt ? data.dueHasTime !== false : false,
      assignedTo: responder.type === "member" ? responder.uid : "",
      assignedExternalName: responder.type === "external" ? responder.name : null,
      priority: 0,
      visibilityScope: "family",
      visibilityMemberIds: [],
      doneAt: null,
      doneBy: null,
      createdBy: data.createdBy,
      createdAt: FieldValue.serverTimestamp(),
      updatedBy: author,
      updatedAt: FieldValue.serverTimestamp(),
      requestId,
    });
    pairs.push(
        "status", "claimed",
        "claimedBy", claimedBy,
        "claimedAt", FieldValue.serverTimestamp(),
        "resolvedAt", FieldValue.serverTimestamp(),
        "todoId", todoId,
    );
    tx.update(reqRef, ...pairs);
    return {outcome: "claimed", data: {...after, status: "claimed", claimedBy, todoId}};
  });
}

/**
 * Le function delle richieste. Gli helper delle push vivono in index.js e
 * arrivano da lì, così c'è una sola implementazione di token, lingua e pulizia.
 * @param {{getTokensForUsers: Function, buildDataOnlyMessage: Function,
 *     sendMulticastAndPrune: Function, resolveMemberName: Function,
 *     isActiveMember: Function, notFamilyMemberReason: string}} deps
 * @return {object} le function da esportare
 */
function build(deps) {
  const {
    getTokensForUsers, buildDataOnlyMessage, sendMulticastAndPrune,
    resolveMemberName, isActiveMember, notFamilyMemberReason,
  } = deps;

  /**
   * Una push a una lista di uid, ciascuno nella sua lingua.
   * @param {string[]} uids
   * @param {function(string): {title: string, body: string}} textFor
   * @param {Object<string, string>} data
   * @param {string} label
   * @return {Promise<void>}
   */
  async function pushTo(uids, textFor, data, label) {
    const tokensByUid = await getTokensForUsers(uids, NOTIFY_PREFS);
    const messages = [];
    const owners = [];
    for (const uid of uids) {
      const entry = tokensByUid.get(uid);
      if (!entry || entry.tokens.length === 0) continue;
      const {title, body} = textFor(entry.lang);
      const msg = buildDataOnlyMessage({tokens: entry.tokens, title, body, data});
      // Senza la categoria registrata (client vecchi) iOS mostra la notifica
      // normale, senza bottoni: innocuo.
      if (data.type === "family_request") msg.apns.payload.aps.category = IOS_CATEGORY;
      messages.push(msg);
      owners.push({uid, tokens: entry.tokens, refsByToken: entry.refsByToken});
    }
    if (messages.length === 0) {
      logger.info(`${label}: nessun destinatario con notifiche attive`);
      return;
    }
    const res = await sendMulticastAndPrune(messages, owners, label);
    logger.info(`${label}: inviate`, res);
  }

  const respondToRequest = onCall(
      {region: REGION, maxInstances: 20, invoker: "public", memory: "256MiB"},
      async (request) => {
        const uid = request.auth?.uid;
        if (!uid) throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
        const {familyId, requestId, answer} = request.data || {};
        if (!ID_RE.test(familyId || "") || !ID_RE.test(requestId || "") ||
            !["yes", "no"].includes(answer)) {
          throw new HttpsError("invalid-argument", "familyId, requestId e answer (yes|no) richiesti.");
        }
        const memberSnap = await admin.firestore()
            .collection("families").doc(familyId)
            .collection("members").doc(uid).get();
        if (!isActiveMember(memberSnap.exists ? memberSnap.data() : null)) {
          throw new HttpsError("permission-denied", "Non sei membro di questa famiglia.",
              {reason: notFamilyMemberReason, familyId});
        }
        const name = await resolveMemberName(familyId, uid);
        try {
          const {outcome, data} = await applyResponse({
            familyId, requestId, answer,
            responder: {key: uid, type: "member", uid, name},
          });
          logger.info("respondToRequest", {familyId, requestId, answer, outcome});
          return {
            outcome,
            status: data.status,
            todoId: data.todoId || null,
            claimedBy: data.claimedBy ?
              {type: data.claimedBy.type, name: data.claimedBy.name || ""} : null,
            mine: data.claimedBy?.uid === uid,
          };
        } catch (e) {
          if (e instanceof RequestError) {
            throw new HttpsError(e.code === "not_found" ? "not-found" : "failed-precondition",
                e.code, {reason: e.code});
          }
          throw e;
        }
      },
  );

  const requestPublic = onRequest(
      {
        region: REGION,
        cors: ALLOWED_ORIGINS,
        maxInstances: 3,
        // Non 128MiB: il processo carica tutto index.js (vedi inviteLanding).
        memory: "256MiB",
      },
      async (req, res) => {
        if (req.method !== "POST") {
          res.status(405).json({error: "method"});
          return;
        }
        let body = req.body;
        if (typeof body === "string") {
          try {
            body = JSON.parse(body);
          } catch {
            body = null;
          }
        }
        const {action, familyId, requestId, token} = body || {};
        if (!["preview", "respond"].includes(action) || !ID_RE.test(familyId || "") ||
            !ID_RE.test(requestId || "") || !TOKEN_RE.test(token || "")) {
          res.status(400).json({error: "bad_request"});
          return;
        }

        const db = admin.firestore();
        const reqRef = db.collection("families").doc(familyId).collection("requests").doc(requestId);
        const snap = await reqRef.get();
        const data = snap.exists ? snap.data() : null;
        // Stessa risposta per «non esiste», «niente link» e «token sbagliato»:
        // chi tira a indovinare non impara nulla.
        if (!data || !data.external || !tokenMatches(token, data.external.tokenHash)) {
          res.status(404).json({error: "not_found"});
          return;
        }
        const requesterName = await resolveMemberName(familyId, data.createdBy);
        // Id del browser (salvato dalla pagina): chiave della risposta esterna.
        const clientId = typeof body.clientId === "string" && ID_RE.test(body.clientId) ?
          body.clientId.slice(0, 40) : null;
        const viewerKey = clientId ? `ext_${clientId}` : null;

        if (action === "preview") {
          if (!data.external.openedAt) {
            await reqRef.update({"external.openedAt": admin.firestore.FieldValue.serverTimestamp()})
                .catch((e) => logger.warn("requestPublic: openedAt non scritto", {error: e.message}));
          }
          res.status(200).json({request: publicView(data, requesterName, viewerKey)});
          return;
        }

        const answer = body.answer;
        const name = cleanName(body.name);
        if (!["yes", "no"].includes(answer)) {
          res.status(400).json({error: "bad_request"});
          return;
        }
        if (answer === "yes" && !name) {
          res.status(400).json({error: "name_required"});
          return;
        }
        try {
          const {outcome, data: after} = await applyResponse({
            familyId, requestId, answer,
            responder: {key: viewerKey || `ext_${crypto.randomUUID()}`, type: "external", name: name || "?"},
          });
          logger.info("requestPublic: risposta", {familyId, requestId, answer, outcome});
          res.status(200).json({outcome, request: publicView(after, requesterName, viewerKey)});
        } catch (e) {
          if (e instanceof RequestError) {
            res.status(e.code === "not_found" ? 404 : 409).json({error: e.code});
            return;
          }
          logger.error("requestPublic: risposta non applicata", {familyId, requestId, error: e.message});
          res.status(500).json({error: "internal"});
        }
      },
  );

  const onFamilyRequestCreated = onDocumentCreated(
      {document: "families/{familyId}/requests/{requestId}", region: REGION, maxInstances: 10},
      async (event) => {
        const {familyId, requestId} = event.params;
        const data = event.data?.data();
        if (!data || data.status !== "open") return;

        const famRef = admin.firestore().collection("families").doc(familyId);
        const asked = [...new Set((Array.isArray(data.recipients) ? data.recipients : [])
            .filter((uid) => typeof uid === "string" && uid && uid !== data.createdBy))];
        if (asked.length === 0) return;
        // Solo membri veri: stesso criterio di `isMember` nelle rules.
        const memberSnaps = await admin.firestore().getAll(
            ...asked.map((uid) => famRef.collection("members").doc(uid)));
        const targets = asked.filter((uid, i) =>
          isActiveMember(memberSnaps[i].exists ? memberSnaps[i].data() : null));
        if (targets.length === 0) {
          logger.info("onFamilyRequestCreated: nessun destinatario membro", {familyId, requestId});
          return;
        }

        const requesterName = await resolveMemberName(familyId, data.createdBy);
        const due = data.dueAt ? data.dueAt.toDate() : null;
        await pushTo(targets, (lang) => ({
          title: tn(lang, "request.title", {name: firstName(requesterName) || requesterName}),
          body: due ?
            tn(lang, "request.bodyWhen", {title: data.title, when: formatWhen(due, data.dueHasTime !== false, lang)}) :
            data.title,
        }), {type: "family_request", familyId, requestId}, "onFamilyRequestCreated");
      },
  );

  const onFamilyRequestUpdated = onDocumentUpdated(
      {document: "families/{familyId}/requests/{requestId}", region: REGION, maxInstances: 10},
      async (event) => {
        const {familyId, requestId} = event.params;
        const before = event.data?.before?.data();
        const after = event.data?.after?.data();
        if (!before || !after || !after.createdBy) return;
        const data = {type: "family_request_resolved", familyId, requestId, todoId: after.todoId || ""};

        if (before.status === "open" && after.status === "claimed") {
          // Chi ha chiesto non si avvisa di una cosa fatta da sé (non succede:
          // il server rifiuta `own_request`, ma il trigger non lo dà per scontato).
          if (after.claimedBy?.uid === after.createdBy) return;
          const who = firstName(after.claimedBy?.name) || "?";
          await pushTo([after.createdBy], (lang) => ({
            title: tn(lang, "request.claimedTitle", {name: who}),
            body: after.title,
          }), data, "onFamilyRequestUpdated:claimed");
          return;
        }
        if (before.status === "open" && after.status === "expired") {
          await pushTo([after.createdBy], (lang) => ({
            title: tn(lang, "request.expiredTitle"),
            body: after.title,
          }), data, "onFamilyRequestUpdated:expired");
          return;
        }
        if (after.status === "open" && !before.allDeclinedAt && after.allDeclinedAt) {
          await pushTo([after.createdBy], (lang) => ({
            title: tn(lang, "request.allDeclinedTitle"),
            body: tn(lang, "request.allDeclinedBody", {title: after.title}),
          }), data, "onFamilyRequestUpdated:allDeclined");
        }
      },
  );

  const expireFamilyRequests = onSchedule(
      {schedule: "every 15 minutes", timeZone: TZ, region: REGION, timeoutSeconds: 120},
      async () => {
        const db = admin.firestore();
        const {FieldValue, Timestamp} = admin.firestore;
        const snap = await db.collectionGroup("requests")
            .where("status", "==", "open")
            .where("expiresAt", "<=", Timestamp.now())
            .limit(200)
            .get();
        let expired = 0;
        for (const doc of snap.docs) {
          // Solo le richieste di famiglia: `families/{id}/requests/{id}`.
          if (doc.ref.parent.parent?.parent?.id !== "families") continue;
          // Riverifica in transazione: un «Io» arrivato nel frattempo vince.
          const done = await db.runTransaction(async (tx) => {
            const fresh = await tx.get(doc.ref);
            const d = fresh.data();
            if (!d || d.status !== "open" || (msOf(d.expiresAt) ?? Infinity) > Date.now()) return false;
            tx.update(doc.ref, {
              status: "expired",
              resolvedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            });
            return true;
          }).catch((e) => {
            logger.warn("expireFamilyRequests: non chiusa", {path: doc.ref.path, error: e.message});
            return false;
          });
          if (done) expired++;
        }
        if (snap.size > 0) logger.info("expireFamilyRequests", {candidate: snap.size, expired});
      },
  );

  return {
    respondToRequest,
    requestPublic,
    onFamilyRequestCreated,
    onFamilyRequestUpdated,
    expireFamilyRequests,
  };
}

module.exports = {
  build,
  // Per i test: la logica pura senza Firestore.
  _internals: {applyResponse, sha256hex, tokenMatches, firstName, cleanName, allRecipientsDeclined, formatWhen, publicView},
};
