const fs = require("fs");
const {deleteField} = require("firebase/firestore");
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

  // ── ESCROW DELLA CHIAVE DI FAMIGLIA ────────────────
  //
  // `families/{familyId}/memberKeyBackups/{uid}` contiene la master key della
  // famiglia wrappata con una chiave derivata da (uid, familyId) e da costanti
  // che stanno nei binari e nel bundle JS — cioè pubbliche. Chi legge l'escrow
  // di un ALTRO utente ricostruisce la chiave e apre note, documenti, wallet,
  // chat e password di tutta la famiglia.
  //
  // Prima il ramo ricadeva nel wildcard `{subpath=**}`, leggibile da ogni
  // membro. E siccome `members/{uid}` lascia a chiunque sia autenticato la
  // creazione del proprio documento di membro, bastava conoscere il `familyId`
  // — che viaggia in chiaro nel QR d'invito — per iscriversi da soli e
  // arrivare alla chiave. L'ultimo test qui sotto è quello che conta: mette in
  // scena esattamente quell'attacco.
  console.log("\n── ESCROW CHIAVE DI FAMIGLIA ──────────────────────");

  const MEMBRO = "membro2";
  await env.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    // `isDeleted` esplicito: `isMember()` legge quel campo, e su un documento
    // che non ce l'ha la rule va in errore di valutazione, non in `false`.
    await adm.doc(`families/${FAM}/members/${MEMBRO}`)
        .set({uid: MEMBRO, role: "parent", isDeleted: false});
    await adm.doc(`families/${FAM}/memberKeyBackups/${UID}`)
        .set({cipher: "A", nonce: "B", tag: "C", version: 1});
    await adm.doc(`families/${FAM}/memberKeyBackups/${MEMBRO}`)
        .set({cipher: "A", nonce: "B", tag: "C", version: 1});
  });
  const dbMembro = env.authenticatedContext(MEMBRO).firestore();

  await check("escrow: NON si legge quello di un altro membro",
      assertFails(dbMembro.doc(`families/${FAM}/memberKeyBackups/${UID}`).get()));
  await check("escrow: nemmeno l'owner legge quello di un membro",
      assertFails(db.doc(`families/${FAM}/memberKeyBackups/${MEMBRO}`).get()));
  await check("escrow: NON si sovrascrive quello di un altro",
      assertFails(dbMembro.doc(`families/${FAM}/memberKeyBackups/${UID}`).set({cipher: "H"})));
  await check("escrow: NON si cancella quello di un altro",
      assertFails(dbMembro.doc(`families/${FAM}/memberKeyBackups/${UID}`).delete()));

  // L'attacco per intero: un estraneo che conosce solo il familyId si iscrive
  // da sé (passo ancora consentito, è un buco a parte) e prova ad arrivare
  // alla chiave. Se un giorno il primo passo verrà chiuso, il secondo test
  // resta valido lo stesso.
  const ESTRANEO = "estraneo99";
  const dbEstraneo = env.authenticatedContext(ESTRANEO).firestore();
  // In PRODUZIONE questo passo riesce ancora: la stretta vive in
  // `firestore.rules.next` ed è verificata in fondo a questo file.
  await check("attacco: l'auto-iscrizione a members/{uid} riesce ancora",
      assertSucceeds(dbEstraneo.doc(`families/${FAM}/members/${ESTRANEO}`)
          .set({uid: ESTRANEO, role: "parent", isDeleted: false})));
  await check("attacco: ma da membro NON si arriva alla chiave di famiglia",
      assertFails(dbEstraneo.doc(`families/${FAM}/memberKeyBackups/${UID}`).get()));

  console.log("\n── ESCROW: l'uso legittimo dei client ─────────────");
  await check("escrow: si legge il PROPRIO (recovery dopo reinstallazione)",
      assertSucceeds(dbMembro.doc(`families/${FAM}/memberKeyBackups/${MEMBRO}`).get()));
  await check("escrow: si riscrive il PROPRIO (backup)",
      assertSucceeds(dbMembro.doc(`families/${FAM}/memberKeyBackups/${MEMBRO}`)
          .set({cipher: "Z", nonce: "Z", tag: "Z", version: 1})));
  await check("escrow: l'owner legge il PROPRIO",
      assertSucceeds(db.doc(`families/${FAM}/memberKeyBackups/${UID}`).get()));
  // Device nuovo, backup non ancora scritto: il client deve ricevere un
  // documento vuoto (→ MissingFamilyKeyError) e non un permission-denied.
  await check("escrow: assente, il get passa comunque e torna vuoto",
      assertSucceeds(dbEstraneo.doc(`families/${FAM}/memberKeyBackups/${ESTRANEO}`).get()));

  // ── QUERY DI COLLEZIONE (LIST) ─────────────────────
  //
  // Regressione vera, in produzione: escludendo `memberKeyBackups` dentro un
  // `match /{subpath=**}` si leggeva il capture `**`, che in una LIST NON è
  // legato ("Variable is not bound in path template"). Ogni query di
  // collezione sotto `families/` veniva negata — a membri E proprietario —
  // mentre le scritture, che il path non lo guardano, continuavano a passare:
  // per questo il guasto si è visto solo su un dispositivo senza cache, cioè
  // su un membro appena entrato. I `get` di un singolo documento non bastano
  // a coprirlo: servono le `list`.
  console.log("\n── QUERY DI COLLEZIONE (LIST) ─────────────────────");
  await env.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    await adm.doc(`families/${FAM}/groceryItems/g1`).set({nome: "latte"});
    await adm.doc(`families/${FAM}/chat/c1/messages/m1`).set({testo: "ciao"});
  });
  await check("membro: LIST di una sottocollezione",
      assertSucceeds(dbMembro.collection(`families/${FAM}/groceryItems`).get()));
  await check("owner: LIST di una sottocollezione",
      assertSucceeds(db.collection(`families/${FAM}/groceryItems`).get()));
  await check("membro: LIST di members",
      assertSucceeds(dbMembro.collection(`families/${FAM}/members`).get()));
  await check("membro: LIST di una sottocollezione annidata",
      assertSucceeds(dbMembro.collection(`families/${FAM}/chat/c1/messages`).get()));
  await check("escrow: NON si LISTA la collezione",
      assertFails(dbMembro.collection(`families/${FAM}/memberKeyBackups`).get()));

  // ── LA VERSIONE FUTURA: firestore.rules.next ───────
  //
  // Ambiente separato perché è un ruleset diverso: `firestore.rules.next`
  // chiude l'auto-iscrizione a `members/{uid}`, ma non è deployabile finché le
  // app che scrivono `inviteId` non sono diffuse. Qui si verifica che il giorno
  // del passaggio funzioni — e che nel frattempo non marcisca.
  const envNext = await initializeTestEnvironment({
    projectId: PROJECT_ID + "-next",
    firestore: {
      rules: fs.readFileSync("/Users/vscocca/KidBox/firestore.rules.next", "utf8"),
      host: "127.0.0.1", port: 8080,
    },
  });
  await envNext.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    await adm.doc(`families/${FAM}`).set({name: "Rossi", ownerUid: UID, plan: "free"});
    await adm.doc(`families/${FAM}/members/${UID}`).set({uid: UID, role: "owner", isDeleted: false});
  });

  // ── AUTO-ISCRIZIONE A members/{uid} ────────────────
  //
  // Il `familyId` viaggia in chiaro nel QR e nel link d'invito, quindi non è un
  // segreto: da solo non deve bastare a entrare. La prova richiesta è l'invito
  // consumato — `JoinWrapService` lo marca `usedBy` in transazione dopo aver
  // verificato l'hash del segreto, e il client ne riporta l'id sul documento
  // membro.
  console.log("\n── AUTO-ISCRIZIONE A members/{uid} ────────────────");
  const NUOVO = "nuovo7";
  const nxNuovo = envNext.authenticatedContext(NUOVO).firestore();
  await envNext.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    // Invito consumato dal nuovo membro (usedBy = lui).
    await adm.doc(`families/${FAM}/invites/inv-ok`)
        .set({usedAt: new Date(), usedBy: NUOVO, secretHash: "x"});
    // Invito mai consumato.
    await adm.doc(`families/${FAM}/invites/inv-vergine`)
        .set({usedAt: null, usedBy: null, secretHash: "x"});
    // Invito consumato da qualcun altro.
    await adm.doc(`families/${FAM}/invites/inv-altrui`)
        .set({usedAt: new Date(), usedBy: "qualcunaltro", secretHash: "x"});
  });

  await check("join: con l'invito che ha consumato, entra",
      assertSucceeds(nxNuovo.doc(`families/${FAM}/members/${NUOVO}`)
          .set({uid: NUOVO, role: "member", isDeleted: false, inviteId: "inv-ok"})));
  const INTRUSO = "intruso2";
  {
    const db0 = envNext.authenticatedContext(INTRUSO).firestore();
    await check("attacco: senza inviteId NON entra",
        assertFails(db0.doc(`families/${FAM}/members/${INTRUSO}`)
            .set({uid: INTRUSO, role: "member", isDeleted: false})));
  }

  const nxIntruso = envNext.authenticatedContext(INTRUSO).firestore();
  await check("attacco: con un inviteId inventato NON entra",
      assertFails(nxIntruso.doc(`families/${FAM}/members/${INTRUSO}`)
          .set({uid: INTRUSO, role: "member", isDeleted: false, inviteId: "inventato"})));
  await check("attacco: con un invito mai consumato NON entra",
      assertFails(nxIntruso.doc(`families/${FAM}/members/${INTRUSO}`)
          .set({uid: INTRUSO, role: "member", isDeleted: false, inviteId: "inv-vergine"})));
  await check("attacco: con l'invito consumato da un ALTRO NON entra",
      assertFails(nxIntruso.doc(`families/${FAM}/members/${INTRUSO}`)
          .set({uid: INTRUSO, role: "member", isDeleted: false, inviteId: "inv-altrui"})));

  // Consumare l'invito significa anche svuotarlo del materiale crittografico:
  // l'invito ora sopravvive all'uso, e un documento che resta non deve
  // continuare a contenere la chiave di famiglia wrappata.
  await envNext.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`families/${FAM}/invites/inv-da-consumare`).set({
      usedAt: null, usedBy: null, secretHash: "h", kdfSalt: "s",
      wrappedKeyCipher: "c", wrappedKeyNonce: "n", wrappedKeyTag: "t",
    });
  });
  const CONSUMA = "consuma1";
  const nxConsuma = envNext.authenticatedContext(CONSUMA).firestore();
  await check("invito: consumarlo azzera anche il materiale cifrato",
      assertSucceeds(nxConsuma.doc(`families/${FAM}/invites/inv-da-consumare`).update({
        usedAt: new Date(), usedBy: CONSUMA,
        secretHash: deleteField(), kdfSalt: deleteField(),
        wrappedKeyCipher: deleteField(), wrappedKeyNonce: deleteField(),
        wrappedKeyTag: deleteField(),
      })));
  await check("invito: consumato, NON si può riscrivere usedBy a proprio nome",
      assertFails(nxIntruso.doc(`families/${FAM}/invites/inv-da-consumare`)
          .update({usedBy: INTRUSO})));
  await check("invito: NON si possono cambiare altri campi passando di qui",
      assertFails(nxConsuma.doc(`families/${FAM}/invites/inv-vergine`)
          .update({usedAt: new Date(), usedBy: CONSUMA, familyName: "Altro"})));

  // Creazione famiglia: documento famiglia e membro proprietario nascono nello
  // stesso batch, quando la famiglia ancora non esiste per le rules.
  const CREATORE = "creatore1";
  const nxCreatore = envNext.authenticatedContext(CREATORE).firestore();
  await check("creazione famiglia: il batch famiglia + membro owner passa",
      assertSucceeds((() => {
        const b = nxCreatore.batch();
        b.set(nxCreatore.doc("families/famiglia-nuova"), {name: "Nuova", ownerUid: CREATORE});
        b.set(nxCreatore.doc(`families/famiglia-nuova/members/${CREATORE}`),
            {uid: CREATORE, role: "owner", isDeleted: false});
        return b.commit();
      })()));

  // Il membro già iscritto resta padrone del proprio documento.
  await check("membro: può ancora aggiornare il proprio documento",
      assertSucceeds(nxNuovo.doc(`families/${FAM}/members/${NUOVO}`)
          .update({displayName: "Nuovo"})));

  await envNext.cleanup();

  console.log(`\n══ Risultato: ${pass} superati, ${fail} falliti ══\n`);
  await env.cleanup();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("ERRORE:", e);
  process.exit(1);
});
