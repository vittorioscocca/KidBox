---
name: deploy-functions
description: Deploy delle Cloud Functions di KidBox (functions/) con i controlli prima e la verifica dopo. Usare ogni volta che si modifica functions/ e va portato in produzione, o quando l'utente dice «deploya», «metti online» le functions, la skill Alexa o il backend. Copre anche rules/indexes e il commit per path.
---

Progetto Firebase `kidbox-42cd7`, CLI già autenticata. Il deploy e il commit
delle superfici server sono compito di Claude, senza chiedere ogni volta; il
`git push` resta all'utente (da questa macchina non funziona).

## 1. Prima del deploy

Dalla root del repo:

    node --check functions/index.js
    (cd functions && npx eslint . --quiet)
    (cd functions && node -e "require('./index.js')" | tail -3)

Il terzo comando carica il modulo ed esegue tutte le definizioni
`onCall`/`onRequest`/`onSchedule`/trigger: una firma incompatibile esplode
qui invece che in produzione. Deve risolvere senza errori (87 export al
24/09/2026: se il numero cambia, dillo).

Poi:

- `git diff --stat functions/` e leggi cosa stai per spedire: il working tree
  contiene spesso codice dell'utente non ancora pronto.
- Se hai toccato quote, prezzi o feature dei piani: **non** si fa da codice,
  si fa da console admin (`config/plans`). `functions/plans.json` è solo il
  fallback: `node scripts/sync-plans-from-remote.js --check` dice se il repo
  è indietro (vedi `internal/plans-source-of-truth.md`).
- Se hai toccato `firestore.rules`: leggi `git diff firestore.rules` e di'
  all'utente cosa cambia **prima** del deploy. Additivo (nuova `match`) è
  routine; modificare o togliere una regola esistente può togliere accesso a
  dati in produzione e va detto chiaramente. Esegui i test:
  `(cd firestore-tests && npm test)`.
  Due tranelli documentati: `**` nelle LIST non è legato (leggere il capture
  nega ogni query di collezione, e iOS si auto-espelle dalla famiglia);
  `isMember` tollera `isDeleted` assente ma pretende `role`.

### Trigger che copiano i documenti membro

`syncMembershipIndex` tiene `users/{uid}/memberships/{familyId}` allineato a
`families/{familyId}/members/{memberId}`. Ogni function che decide «è un
membro?» da un documento membro deve usare **`isActiveMember`** (non
cancellato **e** con `role`), cioè lo stesso criterio di `isMember` nelle
rules. Senza il `role` si ricasca nella regressione del 24/09/2026: iOS e web
si rinominano con `setData({displayName, updatedAt}, merge)`, dopo una revoca
quella scrittura ricrea il documento con solo nome e data, e la function lo
contava come membro attivo: riscriveva l'indice a chi era stato tolto, e il
client si ritrovava in lista una famiglia che non può leggere. Stessa regola
per il backfill: niente ruolo di ripiego («member» inventato).

Verifica dal vivo di un trigger sui membri (con REST e token Owner, su id
`ZZZ-TEST-…`): documento senza `role` → **nessun** indice; aggiunto `role` →
indice. I documenti di prova vanno poi nel comando di cancellazione per
l'utente.

## 2. Deploy

**Sempre scopato al nome della funzione**: il codebase ha ~70 funzioni e un
deploy non scopato spedisce anche ciò che non era previsto.

    npx firebase deploy --only functions:nomeFunzione,functions:altraFunzione

Rules e indici, dalla root:

    npx firebase deploy --only firestore:rules
    npx firebase deploy --only firestore:indexes

Le tre config Firebase sono separate e la root non ha `hosting`: console,
landing e web app si deployano dalle rispettive cartelle
(`KidboxConsole/` → `--only hosting`; `KidboxLanding/` → `--only hosting:landing`;
`KidboxWebApp/` → `npm run build` poi `firebase deploy --only hosting:webapp --project kidbox-42cd7`).

Redeploy completo (`--only functions`, senza nome) solo per un bump dell'SDK
`firebase-functions`: dopo, verifica che i job Cloud Scheduler siano ancora
`ENABLED` con le schedule intatte — è la cosa che è già andata storta in
passato.

## 3. Dopo il deploy

- Il comando deve chiudere con `Deploy complete!` e la funzione in stato
  `ACTIVE`; un «skipped» o un timeout di build non è un successo.
- Log dei primi minuti: `npx firebase functions:log --only nomeFunzione | head -40`
  (o `gcloud logging read` filtrato sulla funzione). Cerca `Error`,
  `TypeError`, `permission`.
- Per una callable, se possibile una chiamata reale (curl con token
  utente, o dalla console admin) e lettura della risposta.
- Se hai toccato membri, indice delle famiglie, join, revoca o
  `deleteFamily`: `node scripts/membership-index-audit.js` (sola lettura)
  prima e dopo. Deve restare 0 «attivi senza indice»; gli orfani si
  cancellano solo col comando all'utente. Una backfill parte **sempre** prima
  con `dryRun: true`.
- Se la feature richiede anche una build client, dillo esplicitamente: gli
  utenti con la build vecchia vedono il fallback, non la feature.

## 4. Commit

Committare **per path** (`git add functions/index.js functions/x.js`), mai
`git add -A`: l'albero contiene lavoro dell'utente su iOS/Android. Si resta
su `main`. Messaggio in italiano, imperativo, che dice cosa cambia per
l'utente finale; **mai** righe `Co-Authored-By`. Poi ricordare all'utente
che il push tocca a lui.

## Cose da non fare

- Non deployare per «vedere se funziona»: prima i tre controlli del punto 1.
- Non toccare `functions/plans.json` a mano per cambiare un piano.
- Non aggiornare `firebase-admin` di major insieme ad altro: sessione dedicata.
- Non lanciare `firebase deploy` senza `--only`.
