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
    // Un membro vero come lo scrivono i client al join. (Senza `isDeleted`
    // `isMember()` lo tratta come attivo: vedi «PASSAGGIO DI PROPRIETÀ».)
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

  // Il fallback di Android quando l'indice `users/{uid}/memberships` è
  // incompleto: ritrovare le proprie famiglie dai documenti membro con una
  // query di collection group. Senza una regola a livello di collection group
  // — le `match /families/{familyId}/members/{uid}` NON valgono lì — la query
  // è negata, e nel client sta dentro un try/catch: fallisce in silenzio, e la
  // rete di sicurezza sembra esserci senza esserci.
  await check("membro: collection group LIST dei PROPRI documenti membro",
      assertSucceeds(dbMembro.collectionGroup("members")
          .where("uid", "==", MEMBRO).get()));
  await check("estraneo: collection group LIST sull'uid di un ALTRO è negata",
      assertFails(env.authenticatedContext("curioso1").firestore()
          .collectionGroup("members").where("uid", "==", MEMBRO).get()));
  await check("membro: collection group LIST di TUTTI i membri è negata",
      assertFails(dbMembro.collectionGroup("members").get()));

  // ── PASSAGGIO DI PROPRIETÀ ─────────────────────────
  //
  // Regressione vera, trovata il 14/09/2026: iOS e web creano il membro owner
  // SENZA `isDeleted`. Dopo aver ceduto la proprietà l'ex owner è un membro
  // semplice, e `isMember()` leggeva `.isDeleted` con accesso diretto: errore
  // di valutazione, quindi accesso negato. L'uscita falliva a proprietà già
  // ceduta — su Android rileggendo la famiglia, sul web elencando i membri.
  console.log("\n── PASSAGGIO DI PROPRIETÀ ─────────────────────────");
  const EX_OWNER = "exowner4";
  const EREDE = "erede4";
  const FAM_PASS = "famiglia-passaggio";
  await env.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    await adm.doc(`families/${FAM_PASS}`).set({name: "P", ownerUid: EX_OWNER});
    // Forma esatta di iOS `createFamilyWithChild` e web `createFamily`.
    await adm.doc(`families/${FAM_PASS}/members/${EX_OWNER}`).set({uid: EX_OWNER, role: "owner"});
    await adm.doc(`families/${FAM_PASS}/members/${EREDE}`)
        .set({uid: EREDE, role: "member", isDeleted: false});
    await adm.doc(`users/${EX_OWNER}/memberships/${FAM_PASS}`).set({familyId: FAM_PASS, role: "owner"});
  });
  const dbEx = env.authenticatedContext(EX_OWNER).firestore();
  await check("passaggio: l'owner cede la proprietà (batch dei client)",
      assertSucceeds((() => {
        const b = dbEx.batch();
        b.update(dbEx.doc(`families/${FAM_PASS}`), {ownerUid: EREDE});
        b.update(dbEx.doc(`families/${FAM_PASS}/members/${EREDE}`), {role: "owner"});
        b.update(dbEx.doc(`families/${FAM_PASS}/members/${EX_OWNER}`), {role: "member"});
        return b.commit();
      })()));
  await check("passaggio: l'ex owner senza isDeleted rilegge la famiglia (Android)",
      assertSucceeds(dbEx.doc(`families/${FAM_PASS}`).get()));
  await check("passaggio: l'ex owner senza isDeleted elenca i membri (web)",
      assertSucceeds(dbEx.collection(`families/${FAM_PASS}/members`).get()));
  await check("passaggio: l'ex owner esce cancellando il proprio membro",
      assertSucceeds(dbEx.doc(`families/${FAM_PASS}/members/${EX_OWNER}`).delete()));
  await check("passaggio: e la propria membership",
      assertSucceeds(dbEx.doc(`users/${EX_OWNER}/memberships/${FAM_PASS}`).delete()));
  await check("passaggio: uscito, NON legge più la famiglia",
      assertFails(dbEx.doc(`families/${FAM_PASS}`).get()));
  await check("passaggio: il nuovo owner legge e invita",
      assertSucceeds(env.authenticatedContext(EREDE).firestore()
          .doc(`families/${FAM_PASS}/invites/dopo-passaggio`).set({
            createdBy: EREDE, usedAt: null, usedBy: null,
            expiresAt: new Date(Date.now() + 24 * 3600 * 1000)})));

  // Il default vale solo per il campo ASSENTE: un membro marcato cancellato
  // (revoca da Android) resta fuori.
  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`families/${FAM_PASS}/members/revocato4`)
        .set({uid: "revocato4", role: "member", isDeleted: true});
  });
  await check("membro con isDeleted true: NON legge la famiglia",
      assertFails(env.authenticatedContext("revocato4").firestore().doc(`families/${FAM_PASS}`).get()));
  await check("membro con isDeleted true: NON elenca i membri",
      assertFails(env.authenticatedContext("revocato4").firestore()
          .collection(`families/${FAM_PASS}/members`).get()));

  // ── MEMBRO «RESUSCITATO» DAL NOME ──────────────────
  //
  // iOS e web aggiornano il nome con `setData({displayName, updatedAt}, merge)`
  // sul documento membro. Se il membro è stato revocato cancellando il
  // documento, quella scrittura lo ricrea con solo nome e data: non deve
  // valere come iscrizione.
  console.log("\n── MEMBRO «RESUSCITATO» DAL NOME ──────────────────");
  const RESUSCITATO = "resuscitato5";
  const dbRes = env.authenticatedContext(RESUSCITATO).firestore();
  await check("resuscitato: la scrittura del nome ricrea il documento (auto-creazione ancora libera)",
      assertSucceeds(dbRes.doc(`families/${FAM_PASS}/members/${RESUSCITATO}`)
          .set({displayName: "Nome", updatedAt: new Date()}, {merge: true})));
  await check("resuscitato: senza role NON legge la famiglia",
      assertFails(dbRes.doc(`families/${FAM_PASS}`).get()));
  await check("resuscitato: senza role NON elenca i membri",
      assertFails(dbRes.collection(`families/${FAM_PASS}/members`).get()));
  // In PRODUZIONE la riattivazione da sé riesce ancora: la stretta vive in
  // `firestore.rules.next` ed è verificata in fondo a questo file.
  await check("revocato da Android: rimettere isDeleted false da sé riesce ancora",
      assertSucceeds(env.authenticatedContext("revocato4").firestore()
          .doc(`families/${FAM_PASS}/members/revocato4`).update({isDeleted: false})));

  // ── INVITI ─────────────────────────────────────────
  //
  // Senza queste strette la regola anti-auto-iscrizione di `firestore.rules.next`
  // non chiuderebbe nulla: un estraneo che conosce il `familyId` poteva elencare
  // gli inviti pendenti (o fabbricarsene uno), marcarlo a proprio nome e
  // presentarlo come prova. Qui si verifica che l'attacco fallisca e che ogni
  // uso reale dei client — versioni già installate comprese — passi ancora.
  console.log("\n── INVITI ─────────────────────────────────────────");
  const DOMANI = new Date(Date.now() + 24 * 3600 * 1000);
  const IERI = new Date(Date.now() - 24 * 3600 * 1000);
  const invitoPendente = () => ({
    createdAt: new Date(), createdBy: UID, expiresAt: DOMANI,
    familyName: "Rossi", createdByDisplayName: "Mario",
    secretHash: "h", kdfSalt: "s",
    wrappedKeyCipher: "c", wrappedKeyNonce: "n", wrappedKeyTag: "t",
    usedAt: null, usedBy: null,
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    await adm.doc(`families/${FAM}/invites/inv-anteprima`).set(invitoPendente());
    await adm.doc(`families/${FAM}/invites/inv-nuovo-client`).set(invitoPendente());
    await adm.doc(`families/${FAM}/invites/inv-vecchio-client`).set(invitoPendente());
    await adm.doc(`families/${FAM}/invites/inv-scaduto`)
        .set({...invitoPendente(), expiresAt: IERI});
    await adm.doc(`families/${FAM}/invites/inv-senza-scadenza`)
        .set({...invitoPendente(), expiresAt: null});
    await adm.doc(`families/${FAM}/invites/inv-per-altri`).set(invitoPendente());
  });

  // Chi riceve il link: non è ancora membro.
  const INVITATO = "invitato5";
  const dbInvitato = env.authenticatedContext(INVITATO).firestore();
  await check("invito: chi ha il link LEGGE l'anteprima per id",
      assertSucceeds(dbInvitato.doc(`families/${FAM}/invites/inv-anteprima`).get()));

  // Consumo come lo fanno oggi iOS, Android e web: transazione get + update che
  // svuota il materiale cifrato.
  await check("invito: consumo del client attuale (transazione) passa",
      assertSucceeds(dbInvitato.runTransaction(async (txn) => {
        const ref = dbInvitato.doc(`families/${FAM}/invites/inv-nuovo-client`);
        await txn.get(ref);
        txn.update(ref, {
          usedAt: new Date(), usedBy: INVITATO,
          secretHash: deleteField(), kdfSalt: deleteField(),
          wrappedKeyCipher: deleteField(), wrappedKeyNonce: deleteField(),
          wrappedKeyTag: deleteField(),
        });
      })));

  // Consumo come lo fanno le app già installate (iOS e Android fino ad agosto
  // 2026): solo usedAt/usedBy, poi join e cancellazione dell'invito da membro.
  const VECCHIO = "vecchioclient3";
  const dbVecchio = env.authenticatedContext(VECCHIO).firestore();
  await check("invito: consumo della versione vecchia (solo usedAt/usedBy) passa",
      assertSucceeds(dbVecchio.runTransaction(async (txn) => {
        const ref = dbVecchio.doc(`families/${FAM}/invites/inv-vecchio-client`);
        await txn.get(ref);
        txn.update(ref, {usedAt: new Date(), usedBy: VECCHIO});
      })));
  await check("invito: la versione vecchia entra e poi cancella l'invito",
      assertSucceeds((async () => {
        await dbVecchio.doc(`families/${FAM}/members/${VECCHIO}`)
            .set({uid: VECCHIO, role: "member", isDeleted: false});
        await dbVecchio.doc(`families/${FAM}/invites/inv-vecchio-client`).delete();
      })()));

  await check("invito: il PROPRIETARIO (membro senza isDeleted) ne crea uno",
      assertSucceeds(db.doc(`families/${FAM}/invites/inv-da-owner`).set(invitoPendente())));
  await check("invito: un MEMBRO non proprietario ne crea uno",
      assertSucceeds(dbMembro.doc(`families/${FAM}/invites/inv-da-membro`)
          .set({...invitoPendente(), createdBy: MEMBRO})));
  await check("invito: chi l'ha creato lo revoca",
      assertSucceeds(dbMembro.doc(`families/${FAM}/invites/inv-da-membro`).delete()));
  await check("invito: un membro elenca gli inviti della famiglia",
      assertSucceeds(dbMembro.collection(`families/${FAM}/invites`).get()));

  // L'attacco.
  const PREDONE = "predone8";
  const dbPredone = env.authenticatedContext(PREDONE).firestore();
  await check("attacco: un estraneo NON elenca gli inviti pendenti",
      assertFails(dbPredone.collection(`families/${FAM}/invites`).get()));
  await check("attacco: un estraneo NON si fabbrica un invito",
      assertFails(dbPredone.doc(`families/${FAM}/invites/inv-falso`).set(invitoPendente())));
  await check("attacco: NON consuma un invito a nome di un altro",
      assertFails(dbPredone.doc(`families/${FAM}/invites/inv-per-altri`)
          .update({usedAt: new Date(), usedBy: "qualcunaltro"})));
  await check("attacco: NON consuma un invito scaduto",
      assertFails(dbPredone.doc(`families/${FAM}/invites/inv-scaduto`)
          .update({usedAt: new Date(), usedBy: PREDONE})));
  await check("invito: senza expiresAt NON si consuma",
      assertFails(dbPredone.doc(`families/${FAM}/invites/inv-senza-scadenza`)
          .update({usedAt: new Date(), usedBy: PREDONE})));

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
    // Invito mai consumato, ancora valido.
    await adm.doc(`families/${FAM}/invites/inv-vergine`)
        .set({usedAt: null, usedBy: null, secretHash: "x",
          expiresAt: new Date(Date.now() + 24 * 3600 * 1000)});
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

  // L'attacco per intero, con solo il familyId in mano: ogni strada per
  // procurarsi un invito marcato a proprio nome deve essere chiusa.
  await check("attacco completo: NON elenca gli inviti per trovarne uno pendente",
      assertFails(nxIntruso.collection(`families/${FAM}/invites`).get()));
  await check("attacco completo: NON si fabbrica un invito da consumare",
      assertFails(nxIntruso.doc(`families/${FAM}/invites/inv-fabbricato`).set({
        usedAt: null, usedBy: null, secretHash: "mio",
        expiresAt: new Date(Date.now() + 24 * 3600 * 1000),
      })));
  await check("attacco completo: e quindi NON entra",
      assertFails((async () => {
        // Se la creazione fosse passata, proverebbe a consumarlo e a entrare.
        await nxIntruso.doc(`families/${FAM}/invites/inv-fabbricato`)
            .update({usedAt: new Date(), usedBy: INTRUSO}).catch(() => {});
        await nxIntruso.doc(`families/${FAM}/members/${INTRUSO}`)
            .set({uid: INTRUSO, role: "member", isDeleted: false, inviteId: "inv-fabbricato"});
      })()));

  // Consumare l'invito significa anche svuotarlo del materiale crittografico:
  // l'invito ora sopravvive all'uso, e un documento che resta non deve
  // continuare a contenere la chiave di famiglia wrappata.
  await envNext.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`families/${FAM}/invites/inv-da-consumare`).set({
      expiresAt: new Date(Date.now() + 24 * 3600 * 1000),
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

  // ── RIATTIVAZIONE DOPO UNA REVOCA ──────────────────
  //
  // Android revoca con `isDeleted: true` e il documento resta. Rimettere
  // `isDeleted: false` da sé deve richiedere un invito NUOVO consumato a
  // proprio nome: quello del primo ingresso è ancora sul documento.
  console.log("\n── RIATTIVAZIONE DOPO UNA REVOCA ──────────────────");
  const RIATT = "riattiva6";
  const nxRiatt = envNext.authenticatedContext(RIATT).firestore();
  const DOMANI_NX = new Date(Date.now() + 24 * 3600 * 1000);
  await envNext.withSecurityRulesDisabled(async (ctx) => {
    const adm = ctx.firestore();
    await adm.doc(`families/${FAM}/invites/inv-primo`).set({usedAt: new Date(), usedBy: RIATT, expiresAt: DOMANI_NX});
    await adm.doc(`families/${FAM}/invites/inv-rientro`).set({usedAt: new Date(), usedBy: RIATT, expiresAt: DOMANI_NX});
    await adm.doc(`families/${FAM}/invites/inv-rientro-altrui`).set({usedAt: new Date(), usedBy: "altro6", expiresAt: DOMANI_NX});
    await adm.doc(`families/${FAM}/invites/inv-rientro-vergine`).set({usedAt: null, usedBy: null, expiresAt: DOMANI_NX});
    await adm.doc(`families/${FAM}/members/${RIATT}`)
        .set({uid: RIATT, role: "member", isDeleted: true, inviteId: "inv-primo"});
  });
  const riattiva = (extra) => nxRiatt.doc(`families/${FAM}/members/${RIATT}`)
      .set({uid: RIATT, role: "member", isDeleted: false, updatedBy: RIATT, ...extra}, {merge: true});
  await check("revocato: aggiornare il nome restando revocato è permesso",
      assertSucceeds(nxRiatt.doc(`families/${FAM}/members/${RIATT}`)
          .set({displayName: "Nome", updatedAt: new Date()}, {merge: true})));
  await check("attacco: si riattiva senza invito NON passa",
      assertFails(riattiva({})));
  await check("attacco: si riattiva riusando l'invito del primo ingresso NON passa",
      assertFails(riattiva({inviteId: "inv-primo"})));
  await check("attacco: si riattiva con un invito mai consumato NON passa",
      assertFails(riattiva({inviteId: "inv-rientro-vergine"})));
  await check("attacco: si riattiva con un invito consumato da un altro NON passa",
      assertFails(riattiva({inviteId: "inv-rientro-altrui"})));
  await check("attacco: cancellare il campo isDeleted NON riattiva",
      assertFails(nxRiatt.doc(`families/${FAM}/members/${RIATT}`).update({isDeleted: deleteField()})));
  await check("rientro legittimo: nuovo invito consumato a proprio nome (addMember) passa",
      assertSucceeds(riattiva({inviteId: "inv-rientro"})));
  await check("rientrato: legge la famiglia",
      assertSucceeds(nxRiatt.doc(`families/${FAM}`).get()));
  await envNext.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`families/${FAM}/members/${RIATT}`).update({isDeleted: true});
  });
  await check("owner: riattiva un membro revocato senza invito",
      assertSucceeds(envNext.authenticatedContext(UID).firestore()
          .doc(`families/${FAM}/members/${RIATT}`).update({isDeleted: false})));
  await check("membro: esce cancellando il proprio documento",
      assertSucceeds(nxRiatt.doc(`families/${FAM}/members/${RIATT}`).delete()));
  await check("uscito: la scrittura del nome NON ricrea il documento senza invito",
      assertFails(nxRiatt.doc(`families/${FAM}/members/${RIATT}`)
          .set({displayName: "Nome", updatedAt: new Date()}, {merge: true})));

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
