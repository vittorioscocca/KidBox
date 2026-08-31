const fs = require("fs");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const PROJECT_ID = "kidbox-rules-test";
const RULES = fs.readFileSync("/Users/vscocca/KidBox/firestore.rules", "utf8");

let env;
let pass = 0;
let fail = 0;

async function check(nome, promessa) {
  try {
    await promessa;
    console.log(`  ✅ ${nome}`);
    pass++;
  } catch (e) {
    console.log(`  ❌ ${nome}\n       ${String(e.message).slice(0, 140)}`);
    fail++;
  }
}

(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {rules: RULES, host: "127.0.0.1", port: 8080},
  });

  const UID = "utente1";
  const FAM = "famiglia1";

  // Stato iniziale scritto scavalcando le rules (come farebbe l'Admin SDK).
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc(`families/${FAM}`).set({
      name: "Rossi", ownerUid: UID, plan: "free",
    });
    await db.doc(`families/${FAM}/members/${UID}`).set({uid: UID, role: "owner"});
    await db.doc(`users/${UID}`).set({nome: "Mario"});
    await db.doc(`user_quotas/${UID}`).set({ownedFamilies: 1});
  });

  const db = env.authenticatedContext(UID).firestore();

  console.log("\n── L'ATTACCO deve fallire ─────────────────────────");
  await check("famiglia: NON può auto-assegnarsi plan max",
      assertFails(db.doc(`families/${FAM}`).update({plan: "max"})));
  await check("famiglia: NON può scrivere planOverride",
      assertFails(db.doc(`families/${FAM}`).update({planOverride: "max"})));
  await check("famiglia: NON può falsificare planExpiresAt",
      assertFails(db.doc(`families/${FAM}`).update({planExpiresAt: new Date(2099, 0, 1)})));
  await check("utente: NON può scrivere plan su users/{uid}",
      assertFails(db.doc(`users/${UID}`).update({plan: "max"})));
  await check("utente: NON può creare users/{uid} già con plan",
      assertFails(db.doc("users/nuovo").set({plan: "max"})));
  await check("famiglia: NON può nascere già Pro",
      assertFails(db.doc("families/nuova").set({name: "X", ownerUid: UID, plan: "pro"})));
  await check("contatore famiglie: NON è falsificabile",
      assertFails(db.doc(`user_quotas/${UID}`).set({ownedFamilies: 0})));

  await check("famiglia: NON può scrivere plan via set+merge",
      assertFails(db.doc(`families/${FAM}`).set({plan: "max"}, {merge: true})));

  console.log("\n── L'USO NORMALE deve continuare a funzionare ─────");
  await check("sottocollezioni famiglia: scrittura ancora consentita",
      assertSucceeds(db.doc(`families/${FAM}/notes/n1`).set({titolo: "Spesa"})));
  await check("famiglia: può rinominare",
      assertSucceeds(db.doc(`families/${FAM}`).update({name: "Rossi-Bianchi"})));
  await check("utente: può aggiornare il proprio profilo",
      assertSucceeds(db.doc(`users/${UID}`).update({nome: "Mario Rossi"})));
  await check("utente: può leggere il proprio contatore famiglie",
      assertSucceeds(db.doc(`user_quotas/${UID}`).get()));
  await check("famiglia: può leggere la propria",
      assertSucceeds(db.doc(`families/${FAM}`).get()));

  console.log("\n── FAMIGLIA ATTIVA SULL'ACCOUNT ───────────────────");
  await check("utente: può salvare activeFamilyId su users/{uid}",
      assertSucceeds(db.doc(`users/${UID}`).set({activeFamilyId: FAM}, {merge: true})));
  await check("utente: NON può infilare plan insieme ad activeFamilyId",
      assertFails(db.doc(`users/${UID}`).set({activeFamilyId: FAM, plan: "max"}, {merge: true})));
  await check("altri: NON possono leggere la famiglia attiva di un utente",
      assertFails(env.authenticatedContext("estraneo").firestore().doc(`users/${UID}`).get()));

  console.log("\n── LISTINO PIANI (config/plans) ───────────────────");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc("config/plans").set({version: 1, plans: {}});
    await ctx.firestore().doc("config/nudges").set({enabled: true});
  });
  const anonimo = env.unauthenticatedContext().firestore();
  await check("listino: leggibile SENZA login (lo legge la landing)",
      assertSucceeds(anonimo.doc("config/plans").get()));
  await check("listino: NON scrivibile da un client loggato",
      assertFails(db.doc("config/plans").update({version: 2})));
  await check("listino: NON scrivibile da un anonimo",
      assertFails(anonimo.doc("config/plans").set({version: 2})));
  await check("altri config: restano chiusi agli anonimi",
      assertFails(anonimo.doc("config/nudges").get()));

  console.log("\n── LIMITE 2 FAMIGLIE ──────────────────────────────");
  await check("2ª famiglia: consentita (ne possiede 1)",
      assertSucceeds(db.doc("families/seconda").set({name: "Due", ownerUid: UID})));

  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`user_quotas/${UID}`).set({ownedFamilies: 2});
  });
  await check("3ª famiglia: BLOCCATA (ne possiede già 2)",
      assertFails(db.doc("families/terza").set({name: "Tre", ownerUid: UID})));

  console.log(`\n══ Risultato: ${pass} superati, ${fail} falliti ══\n`);
  await env.cleanup();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("ERRORE:", e);
  process.exit(1);
});
