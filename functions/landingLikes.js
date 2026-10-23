/* eslint-disable max-len */
/**
 * «Mi piace l'idea» della landing (`kidboxapp.com`): un cuore nella barra in
 * alto con il numero di persone a cui KidBox piace.
 *
 * Un like per indirizzo IP, per contare le persone e non i click. L'IP non si
 * salva: entra solo in un HMAC con un segreto casuale che la funzione genera
 * al primo uso e tiene in `landingLikes/secret` (le rules non lo aprono a
 * nessun client). Senza il segreto l'impronta non si ricollega all'indirizzo,
 * nemmeno provando tutti gli IPv4.
 *
 * Il contatore parte da 0 e conta solo like veri.
 *
 * Firestore (scrive solo questa funzione):
 *   landingLikes/total           {count, updatedAt}
 *   landingLikes/secret          {key}
 *   landingLikeVoters/{impronta} {createdAt}
 *
 * Si chiama attraverso il rewrite di Hosting `/api/like`, stessa origine della
 * pagina: niente CORS. Body JSON:
 *   {action: "get"}  → {count, liked}
 *   {action: "like"} → {count, liked: true}; un secondo like dallo stesso IP
 *                      non conta e risponde lo stesso.
 */

const {onRequest} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {FieldValue} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const crypto = require("node:crypto");

let secretPromise = null;

/**
 * Segreto dell'HMAC: creato una volta sola, in transazione, poi in memoria.
 * @return {Promise<string>}
 */
function likeSecret() {
  if (!secretPromise) {
    const db = admin.firestore();
    const ref = db.collection("landingLikes").doc("secret");
    secretPromise = db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists && snap.get("key")) return snap.get("key");
      const key = crypto.randomBytes(32).toString("hex");
      tx.set(ref, {key, createdAt: FieldValue.serverTimestamp()});
      return key;
    }).catch((e) => {
      secretPromise = null;
      throw e;
    });
  }
  return secretPromise;
}

/**
 * IP del visitatore: dietro Hosting è il primo di `x-forwarded-for`.
 * @param {object} req
 * @return {string}
 */
function clientIp(req) {
  const fwd = String(req.headers["x-forwarded-for"] || "").split(",")[0].trim();
  return fwd || req.ip || "unknown";
}

/**
 * Impronta dell'IP: la chiave del votante.
 * @param {string} ip
 * @param {string} secret
 * @return {string}
 */
function voterKey(ip, secret) {
  return crypto.createHmac("sha256", secret).update(ip).digest("hex").slice(0, 40);
}

/**
 * Body JSON, anche quando arriva come testo.
 * @param {object} req
 * @return {object|null}
 */
function parseBody(req) {
  let body = req.body;
  if (typeof body === "string") {
    try {
      body = JSON.parse(body);
    } catch {
      return null;
    }
  }
  return body && typeof body === "object" ? body : null;
}

/**
 * Registra il like se l'impronta è nuova. Contatore e votante nella stessa
 * transazione: due click insieme dallo stesso IP contano una volta.
 * @param {string} key
 * @return {Promise<number>} il totale dopo il like
 */
async function addLike(key) {
  const db = admin.firestore();
  const totalRef = db.collection("landingLikes").doc("total");
  const voterRef = db.collection("landingLikeVoters").doc(key);
  return db.runTransaction(async (tx) => {
    const [voter, total] = await Promise.all([tx.get(voterRef), tx.get(totalRef)]);
    const count = total.exists ? total.get("count") || 0 : 0;
    if (voter.exists) return count;
    tx.set(voterRef, {createdAt: FieldValue.serverTimestamp()});
    tx.set(totalRef, {count: count + 1, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    return count + 1;
  });
}

exports.landingLike = onRequest(
    {
      region: "europe-west1",
      cors: false,
      maxInstances: 2,
      // Come landingPing: il processo carica tutto index.js, 128MiB non basta.
      memory: "256MiB",
    },
    async (req, res) => {
      if (req.method !== "POST") {
        res.status(405).send("");
        return;
      }
      const body = parseBody(req);
      const action = body && body.action;
      if (action !== "get" && action !== "like") {
        res.status(400).json({error: "bad_request"});
        return;
      }
      try {
        const db = admin.firestore();
        const key = voterKey(clientIp(req), await likeSecret());
        if (action === "like") {
          const count = await addLike(key);
          res.set("Cache-Control", "no-store").json({count, liked: true});
          return;
        }
        const [total, voter] = await Promise.all([
          db.collection("landingLikes").doc("total").get(),
          db.collection("landingLikeVoters").doc(key).get(),
        ]);
        res.set("Cache-Control", "no-store").json({
          count: total.exists ? total.get("count") || 0 : 0,
          liked: voter.exists,
        });
      } catch (e) {
        logger.error("landingLike: failed", {action, error: e.message});
        res.status(500).json({error: "internal"});
      }
    },
);

exports._voterKey = voterKey;
