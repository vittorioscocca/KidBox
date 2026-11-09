/**
 * getKeyVaultStats — quanti utenti hanno la cassaforte v2 della chiave di
 * famiglia (piano `internal/cifratura-chiave-di-riserva-v2.md`, Fase 2 → 3).
 *
 * Solo admin, solo conteggi: niente uid, niente contenuti. Le rules non
 * lasciano leggere a nessuno le cassaforti altrui, quindi il conto lo fa
 * l'Admin SDK qui. È il numero che decide quando chiudere la v1 (Fase 3).
 *
 * Letture: slot della cassaforte (pochi) + documenti memberKeyBackups (uno per
 * membro, solo i campi selezionati) + 2 documenti di config/adminStats.
 */
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const DAY = 24 * 60 * 60 * 1000;

/**
 * @param {string[]} adminUids uid ammessi.
 * @return {object} la callable.
 */
function makeGetKeyVaultStats(adminUids) {
  return onCall(
      {region: "europe-west1", maxInstances: 5, timeoutSeconds: 120},
      async (request) => {
        const caller = request.auth?.uid;
        if (!caller) {
          throw new HttpsError("unauthenticated", "Autenticazione richiesta.");
        }
        if (!adminUids.includes(caller)) {
          throw new HttpsError("permission-denied", "Non autorizzato.");
        }

        const db = admin.firestore();
        const [cfgSnap, internalSnap, lastOpenSnap, slotsSnap, backupsSnap] =
          await Promise.all([
            db.collection("config").doc("keyVault").get(),
            db.collection("config").doc("internalUsers").get(),
            db.collection("adminStats").doc("lastOpen").get(),
            db.collectionGroup("keyVault").select("type").get(),
            db.collectionGroup("memberKeyBackups")
                .select("version", "cipher", "v2.rkId").get(),
          ]);

        const internal = new Set((internalSnap.data() || {}).uids || []);
        const byUid = (lastOpenSnap.data() || {}).byUid || {};
        const now = Date.now();
        const openedWithin = (uid, days) => {
          const t = byUid[uid];
          return !!t && typeof t.toMillis === "function" &&
            now - t.toMillis() <= days * DAY;
        };

        // Cassaforti: users/{uid}/keyVault/{slot}
        const vault = new Map(); // uid -> {code, passkeys}
        for (const d of slotsSnap.docs) {
          const userRef = d.ref.parent.parent;
          if (!userRef || userRef.parent.id !== "users") continue;
          const v = vault.get(userRef.id) || {code: false, passkeys: 0};
          if (d.get("type") === "recoveryCode") v.code = true;
          if (d.get("type") === "passkey") v.passkeys += 1;
          vault.set(userRef.id, v);
        }

        // Copie della chiave: families/{fid}/memberKeyBackups/{uid}
        const members = new Map(); // uid -> {docs, v2}
        const docs = {total: 0, v1Only: 0, v1AndV2: 0, v2Only: 0};
        const docsInternal = {total: 0, withV2: 0};
        for (const d of backupsSnap.docs) {
          const uid = d.id;
          const hasV1 = typeof d.get("cipher") === "string";
          const hasV2 = typeof d.get("v2.rkId") === "string";
          if (internal.has(uid)) {
            docsInternal.total += 1;
            if (hasV2) docsInternal.withV2 += 1;
            continue;
          }
          docs.total += 1;
          if (hasV1 && hasV2) docs.v1AndV2 += 1;
          else if (hasV2) docs.v2Only += 1;
          else docs.v1Only += 1;
          const m = members.get(uid) || {docs: 0, v2: 0};
          m.docs += 1;
          if (hasV2) m.v2 += 1;
          members.set(uid, m);
        }

        // Utenti (esclusi gli interni): membri di almeno una famiglia.
        const summarize = (filter) => {
          let users = 0; let withVault = 0;
          let withPasskey = 0; let allV2 = 0;
          for (const [uid, m] of members) {
            if (!filter(uid)) continue;
            users += 1;
            const v = vault.get(uid);
            if (v) withVault += 1;
            if (v && v.passkeys > 0) withPasskey += 1;
            if (m.v2 === m.docs) allV2 += 1;
          }
          return {users, withVault, withPasskey, allV2};
        };

        let internalVaults = 0;
        for (const uid of vault.keys()) {
          if (internal.has(uid)) internalVaults += 1;
        }

        const cfg = cfgSnap.data() || {};
        return {
          computedAt: now,
          flags: {
            exists: cfgSnap.exists,
            enabled: cfg.enabled === true,
            internal: cfg.internal === true,
            enforce: cfg.enforce === true,
          },
          // «allV2» = ogni famiglia dell'utente ha la sua copia v2: è chi
          // non perde niente se la v1 sparisce (Fase 3).
          active7: summarize((uid) => openedWithin(uid, 7)),
          active30: summarize((uid) => openedWithin(uid, 30)),
          all: summarize(() => true),
          docs,
          internal: {
            users: internal.size, vaults: internalVaults, docs: docsInternal,
          },
        };
      },
  );
}

module.exports = {makeGetKeyVaultStats};
