# Richieste — disegno dell'oggetto

> Stato al 01/10/2026: **fase 1 in produzione** (server, rules, pagina `/r`),
> provata end-to-end su `ZZZ-TEST-REQ`. **Nessun client crea ancora
> richieste**: iOS, Android e web app sono le fasi 2-4. Decisioni prese
> dall'utente il 01/10: invito incluso di default, richieste visibili a tutti i
> membri, Free, testo in chiaro come i to-do.

## Cosa risolve

«Chi prende Marco giovedì?» oggi si chiede su WhatsApp. La risposta resta in
chat, nessuno la ritrova, e il to-do (se nasce) va scritto a mano. La
**richiesta** è una domanda con destinatari e scadenza; la prima risposta *Io*
la chiude e fa nascere da sé il to-do assegnato, visibile a tutta la famiglia.

Il destinatario può essere **fuori dall'app**: riceve un link (su WhatsApp,
come oggi), risponde dal browser senza installare nulla, e trova sotto un
invito alla famiglia. È un invito con un motivo: i dati del 15/09 dicono che
l'invito in astratto converte al 17% e la push generica allo 0%, e che il buco
è invito→tentativo (44→15).

**Cosa non è:** non è una chat, non è un sondaggio, non sostituisce il to-do.
È una domanda che finisce in un to-do. Nella prima versione non c'è AI.

## Lo schema

`families/{familyId}/requests/{requestId}`

| Campo | Tipo | Note |
|---|---|---|
| `kind` | `"todo"` | Unico tipo nella prima versione. Poi `"grocery"` («chi passa al supermercato?») ed `"event"`. |
| `title` | string | In chiaro, come `todos.title` oggi (lo legge già il server per la push). |
| `notes`, `priority` | string \| null, 0\|1 | Dall'editor; il server li copia nel to-do. La pagina del link **non** mostra le note. |
| `dueAt` | Timestamp \| null | Copiato nel to-do. |
| `dueHasTime` | bool | Come sul to-do. |
| `listId` | string | **Obbligatorio.** La lista dell'editor da cui parte la richiesta. Vedi «Trappole». |
| `childId` | string \| null | Si copia come fanno oggi i client; non filtra più nulla. |
| `createdBy` | uid | Chi chiede. |
| `createdVia` | `"app"` \| `"assistant"` \| `"connector"` | Oggi solo `app`; gli altri preparano assistente e connettore MCP. |
| `createdAt`, `updatedAt` | Timestamp | Server. |
| `recipients` | [uid] | Membri da avvisare. Può essere vuoto se si chiede solo fuori. La richiesta la **vedono** comunque tutti i membri. |
| `expiresAt` | Timestamp | Vedi «Scadenza». |
| `status` | `"open"` \| `"claimed"` \| `"expired"` \| `"cancelled"` | Unico campo di stato. |
| `responses` | map | Chiave `uid` per i membri, `ext_<id>` per chi risponde dal link. Valore `{answer: "yes"\|"no", at, name?}`. |
| `claimedBy` | map \| null | `{type: "member", uid}` oppure `{type: "external", name}`. |
| `claimedAt` | Timestamp \| null | |
| `todoId` | string \| null | Il to-do nato dal *Io*. |
| `external` | map \| null | Solo se c'è il link: `{label, tokenHash, inviteId, openedAt, answeredAt}`. |

`external.label` è come chi chiede chiama il destinatario («Nonna»): serve a
lui nell'elenco, al destinatario non si mostra. `openedAt` e `answeredAt` si
scrivono la prima volta che succedono: l'oggetto è anche la sua misura (vedi
«Cosa si misura»).

## Gli stati

```
            ┌─── Io (membro o link) ──► claimed  → nasce il to-do
  open ─────┼─── scade expiresAt ─────► expired  → push a chi ha chiesto
            └─── la ritira chi chiede ► cancelled
```

- Solo `open` accetta risposte. Una volta `claimed` è definitiva: per
  cambiare chi lo fa si modifica il to-do, come oggi.
- *Non posso* non cambia lo stato: si registra in `responses`, e chi ha chiesto
  vede «Luca: non posso». Quando **tutti** i `recipients` hanno detto no e non
  c'è un link esterno, parte una sola push a chi ha chiesto: «Nessuno può.
  Chiedi a qualcuno fuori?».

## Scadenza

`expiresAt` = `dueAt` se c'è (una richiesta per giovedì 16:30 non ha senso
dopo), altrimenti 48 ore. Tetto 7 giorni, come gli inviti. Lo scheduler chiude
le richieste scadute.

## Le tre strade

### 1. Creare (client)

Dall'editor del to-do: bottone **«Chiedi a…»** al posto di «Assegna a». Si
scelgono i membri e/o «Qualcuno fuori dall'app». Il client scrive la
richiesta direttamente su Firestore (le rules vincolano la forma, sotto). Se
c'è il link esterno, il client prima crea un invito normale (stesso codice di
oggi) e ne mette l'id in `external.inviteId`.

Così la richiesta non è una funzione nuova da andare a cercare: costa un tocco
dentro un gesto che l'utente sta già facendo.

### 2. Rispondere da membro (callable `respondToRequest`)

Dalla push (azioni *Io* / *Non posso*) o dalla card in app. **Non** è una
scrittura del client: passa da una callable, per tre ragioni:

1. «Il primo *Io* vince» va deciso in una transazione, in un posto solo;
2. il to-do nasce con l'Admin SDK nella stessa transazione, uguale su tutti i
   client;
3. la stessa logica serve alla risposta dal link, che un client non ha.

### 3. Rispondere dal link (HTTP `requestPublic`, dietro `/api/request`)

Link: `https://kidboxapp.com/r?f={familyId}&r={requestId}#t={token}&k={segretoInvito}`

`k=` è lo stesso nome del frammento del link d'invito
(`/join?familyId=…&inviteId=…#k=<segreto>`, letto da `PendingFamilyInvite`
su iOS): la pagina lo passa tale e quale al `/join`.

- `token`: 32 byte casuali, base64url. Sul documento c'è solo `tokenHash`
  (SHA-256), come `secretHash` degli inviti.
- Tutto ciò che sta dopo `#` **non arriva mai al server** né finisce nei log o
  nel referrer. La pagina manda il token nel **corpo** della POST, non
  nell'URL.
- Due azioni: `preview` (titolo, scadenza, nome di battesimo di chi chiede,
  stato) e `respond` (`yes`/`no` + nome).
- Chi risponde da fuori scrive il proprio nome («Come ti chiami?»), che resta
  nel browser per la volta dopo. Senza nome il *Io* non parte.
- Il browser ha un id suo (`localStorage`), mandato come `clientId`: è la
  chiave `ext_<id>` della risposta e fa dire «l'hai presa tu» anche dopo un
  ricaricamento (`claimedByYou`, `claimedBy.key` sul documento).
- `/r` non è rivendicato dagli Universal Link: si apre sempre nel browser,
  anche a chi ha l'app. Il bottone «Entra nella famiglia» porta a `/join` sullo
  **stesso dominio**, e iOS non apre l'app per un link interno allo stesso
  sito: chi ha già KidBox vede la pagina di download. Raro (chi risponde dal
  link di solito non ha l'app); se diventa un problema, un secondo bottone
  con `kidbox://join?…&secret=` lo risolve.
- Nessuna statistica di terze parti sulla pagina, quindi nessun banner.
- Dopo la risposta, la pagina mostra **«Entra nella famiglia»**: punta al
  `/join?familyId=…&inviteId=…#segreto` di sempre, costruito con
  `external.inviteId` e il segreto dal frammento. Tutto il percorso d'invito
  esistente (appunti, referrer di Play, contatore `inviteLandingPing`) resta
  identico e non si tocca.

Un link solo, anche in un gruppo WhatsApp dei nonni: il primo *Io* vince, gli
altri vedono «Già preso da Anna».

## Il cuore comune: `applyResponse`

Usato da entrambe le strade, in una transazione:

1. legge la richiesta; se non è `open` restituisce lo stato e `claimedBy`
   (la UI mostra «già preso da…» o «scaduta»);
2. se `now >= expiresAt`: la porta a `expired`, risponde «scaduta»;
3. `no`: scrive in `responses`, controlla «tutti no», fine;
4. `yes`: `status: claimed`, `claimedBy`, `claimedAt`, crea il to-do, scrive
   `todoId`.

## Il to-do che nasce

`families/{familyId}/todos/{nuovoId}`, gli stessi campi che scrive
`TodoRemoteStore` più un campo nuovo:

| Campo | Valore |
|---|---|
| `title`, `dueAt`, `dueHasTime`, `childId` | dalla richiesta |
| `listId` | dalla richiesta, **verificata** (vedi «Trappole») |
| `assignedTo` | uid di chi ha detto *Io*; `null` se esterno |
| `assignedExternalName` | nuovo: il nome di chi ha detto *Io* da fuori |
| `createdBy` | chi ha chiesto |
| `updatedBy` | **chi ha detto *Io*** (vedi sotto) |
| `isDone: false`, `isDeleted: false`, `priority: 0`, `doneAt/doneBy: null` | |
| `visibilityScope: "family"`, `visibilityMemberIds: []` | |
| `requestId` | nuovo: il legame inverso, ignorato dai client vecchi |

`updatedBy` = chi ha risposto **non è un dettaglio**: `notifyTodoAssigned`
esce se `assignedTo === updatedBy`. Così chi ha appena detto *Io* non riceve
anche «Nuovo To-Do» per la cosa che si è appena preso. La notifica giusta (a
chi ha chiesto) la manda la richiesta.

Esterno: `assignedTo: null` + `assignedExternalName`. I client aggiornati
mostrano «Anna (fuori dall'app)». Gli altri membri, su client vecchi, vedono
un to-do non assegnato: accettabile, perché chi ha chiesto ha per forza il
client nuovo.

Fatto il 01/10/2026 su tutti e tre i client: il nome si mostra solo se
`assignedTo` è vuoto, così una riassegnazione successiva a un membro vince
senza dover cancellare il campo. Android: colonna Room `assignedExternalName`
(versione 50).

## Notifiche

Tre trigger nuovi, testi in `notificationsI18n.js` (4 lingue, lingua del
destinatario):

| Quando | A chi | Testo (IT) |
|---|---|---|
| richiesta creata | `recipients` (non chi chiede) | «Vittorio chiede una mano» / «Prendere Marco · gio 8 ott, 16:30» + azioni *Io* / *Non posso* su iOS |
| `claimed` | chi ha chiesto (la push silenziosa che toglie la notifica agli altri destinatari non c'è ancora: serve un client che la gestisca) | «Ci pensa Luca» / «Ci pensa Anna» |
| `expired` o «tutti no» | chi ha chiesto | «Nessuno ha risposto a: …» / «Nessuno può: …» |

Le azioni sulla notifica sono il pezzo più delicato sui client:

- **iOS**: il server manda già `aps.category = "FAMILY_REQUEST"`. Il client
  registra la `UNNotificationCategory` con le azioni *Io* / *Non posso* e
  l'handler chiama `respondToRequest` in background. Senza categoria
  registrata (build vecchie) la notifica si vede normale, senza bottoni.
- **Android**: con il payload ibrido obbligatorio (vedi `/notifiche`), ad app
  chiusa la notifica la disegna il sistema e **non può avere bottoni**: il tap
  apre la card della richiesta. I bottoni ci sono solo ad app aperta
  (`onMessageReceived`). Non si passa al data-only per averli: su HyperOS/MIUI
  la push non arriverebbe proprio.
- **Build vecchie** che ricevono `family_request`: vedono titolo e testo, il
  tap apre l'app senza deep link. Per questo iOS e Android vanno pubblicati
  insieme.

Se l'azione fallisce, il tap apre la card in app: la risposta non va mai
persa in silenzio.

Preferenza: `notificationPrefs.notifyOnFamilyRequest` se c'è, altrimenti
`notifyOnTodoAssigned` (chi ha spento i to-do assegnati non riceve le
richieste). Nessun badge.

## Rules (entrambi i file, `/rules-change`)

- `requests` **escluso** dalla scrittura del wildcard `{coll}/{docId}`, con una
  regola sua (le rules sono in OR: senza l'esclusione la regola stretta non
  restringe nulla, come per `memberKeyBackups`).
- `read`: membri.
- `create`: membro, `createdBy == auth.uid`, `status == "open"`, e assenti
  `responses`, `claimedBy`, `claimedAt`, `todoId`; `expiresAt` entro 7 giorni.
- `update`: solo chi ha chiesto, solo `open → cancelled`, con `affectedKeys`
  limitati a `status`, `updatedAt`.
- Risposte, `claimed`, `expired`, `openedAt/answeredAt`: solo dall'Admin SDK.
- `delete`: nessuno dal client (la storia serve alla misura). La pulizia
  dopo 90 giorni **non è ancora fatta**; le richieste se ne vanno comunque
  con la famiglia (`requests` è in `FAMILY_SUBCOLLECTIONS`).

## Backend, l'elenco

| Pezzo | Tipo |
|---|---|
| `respondToRequest` | callable (membri): `{familyId, requestId, answer}` → `{outcome, status, todoId, claimedBy, mine}`; errori `not_found`, `own_request` in `details.reason` |
| `requestPublic` | HTTP, rewrite `/api/request` sulla landing, `maxInstances` 3. POST `{action: preview|respond, familyId, requestId, token, clientId, answer?, name?}`; 404 identico per «non esiste», «niente link», «token sbagliato» |
| `onFamilyRequestCreated` | trigger: push ai destinatari che sono membri attivi (`isActiveMember`) |
| `onFamilyRequestUpdated` | trigger: push a chi ha chiesto su `claimed`, `expired` e `allDeclinedAt` |
| `expireFamilyRequests` | scheduler ogni 15 minuti: collection group `requests`, `status == "open"`, `expiresAt <= now`, riverifica in transazione. Indice composito in `firestore.indexes.json`. Le risposte controllano comunque la scadenza da sé. |
| pagina `/r` | landing statica, 4 lingue dal browser, stesso banner di consenso di `/join` |

Abuso del link: indovinare un token da 256 bit non è praticabile; un curl in
loop su `preview` costa invocazioni ma non apre nulla. Niente App Check sulla
pagina pubblica, come `inviteLandingPing`.

## Trappole già pagate che qui ritornano

- **Liste e foreign key di Room.** Un to-do con `listId` vuoto o di una lista
  inesistente su Android non si vede (FK e orfani). Il server, al *Io*,
  verifica che la lista esista e non sia cancellata; se nel frattempo è
  sparita, usa la lista aggiornata più di recente della famiglia. Mai
  `listId: ""`.
- **`remindSentAt: null` esplicito.** Se un giorno la richiesta imposta
  `remindAt` sul to-do, deve scrivere anche `remindSentAt: null`, o il
  promemoria non parte mai, in silenzio.
- **Membro = non cancellato e con `role`.** `recipients` e la callable
  controllano la membership con la stessa definizione di rules e function.
- **Delta Firestore vuoto su Android** (documentChanges vs snap.documents):
  la card delle richieste aperte va letta dagli snapshot interi.
- **Stringhe iOS che nascono non tradotte**: le chiavi sono i letterali
  italiani, quindi `/localizzazione` prima di chiudere.

## Cosa si misura

Tutto dallo stesso oggetto, senza eventi GA4 nuovi da rincorrere:

```
richieste create ─► con link esterno ─► link aperto (external.openedAt)
   ─► risposta (external.answeredAt) ─► invito consumato (invites.usedAt)
   ─► famiglia passata a 2+ membri
```

Più, per i membri: quota di richieste chiuse da un *Io*, tempo mediano alla
risposta, quota scadute. Lo legge `scripts/console-daily-report.js` dal
collection group `requests`, con il filtro del traffico interno.

**Previsione da mettere nel registro** (numeri da tarare sul report prima di
partire): nelle 4 settimane dopo la release, almeno 10 richieste con link
esterno e almeno 2 famiglie passate a 2+ membri entrando da una richiesta.
**Falsificata** se le richieste con link esterno sono meno di 5.

## In che ordine

1. ✅ **Server, rules, pagina `/r`** — live dal 01/10/2026. File:
   `functions/familyRequests.js` (5 function), `firestore.rules` e `.next`
   (+22 casi in `firestore-tests`), `KidboxLanding/public/r.html` con il
   rewrite `/api/request`. Prova end-to-end: richiesta presa dal link, to-do
   nato nella lista giusta con `assignedExternalName`, token sbagliato → 404,
   anteprima di una scaduta → `expired`.
2. ✅ **iOS** — scritto e compilato il 01/10/2026 (iPhone e Mac Catalyst),
   **non provato su device** (il simulatore non supera il login). Cartella
   `Features/FamilyRequests/`:
   - `FamilyRequestService`: modello, creazione (token + invito +
     `setData`), risposta via callable, ritiro, listener legati a `.task`
     (niente start/stop da onAppear), link salvati sul telefono di chi chiede
     per «Invia di nuovo il link»;
   - `FamilyRequestNotifications`: categoria `FAMILY_REQUEST` registrata in
     `KBNotificationCategoryRegistry`; «Ci penso io» apre l'app e il foglio con
     l'esito, «Non posso» resta in background e, se fallisce, lascia una
     notifica locale per riprovare;
   - `FamilyRequestViews`: foglio «Chiedi a…», foglio del link, card in Home
     (esito nel banner globale: dopo un «Io» la card sparisce), dettaglio.
   Editor: riga «Chiedi a qualcuno…» sotto «Assegnato a», solo per un to-do
   nuovo visibile a tutta la famiglia; note e «urgente» passano al to-do (il
   server li copia), il promemoria locale no. Un to-do «tutto il giorno» resta
   chiedibile fino a fine giornata. Deep link `.familyRequest` →
   `coordinator.presentedFamilyRequest` → foglio in `RootHostView`.
   58 stringhe nuove nel catalogo con en/fr/es.
3. ✅ **Android** — commit `a036dbd` in `KidBoxAndroid`, 01/10/2026. Provato
   sul telefono vero (Xiaomi, HyperOS): creazione con link, card in Home che si
   aggiorna dal vivo, risposta dal link, push ricevuta, tap → schermata,
   risposta da membro via callable, ritiro. Non provati: «Ci penso io» fino al
   to-do (avrebbe scritto nella famiglia vera) e i bottoni sulla notifica
   (`dumpsys` li mostra, HyperOS non si lascia espandere via adb).
   Differenze da iOS: niente scadenza «tutto il giorno» (l'editor Android ha
   sempre l'orario); i bottoni sulla notifica solo ad app aperta.
4. ✅ **Web app** — live il 01/10/2026: «Chiedi a qualcuno…» nella modale del
   to-do, richieste aperte in Home sopra la dashboard, modale di dettaglio
   (rispondi, ritira, rimanda il link, apri il to-do → `/todo?lista=<id>`).
   La push web apre `/?richiesta=<id>&famiglia=<id>` (sia `webpushOptions`
   sul server sia il service worker, che calcola la rotta da sé). Componenti
   provati in un banco Vite con dati finti; la Home da utente loggato no
   (serve un accesso).
5. ✅ **Sollecito** (01/10/2026, scelta dell'utente: «parti dal sollecito»):
   chi non ha ancora risposto riceve UNA push alle 19:00 del giorno della
   richiesta, o 3 ore dopo se è nata dalle 16 in poi; mai fra le 21:30 e le
   8:00 (slitta alle 8), e per le richieste che scadono prima a metà del
   tempo (o niente, se resta meno di mezz'ora o cade di notte). `nudgeAt` lo
   scrive `onFamilyRequestCreated` (vale anche per le build già pubblicate),
   `nudgeFamilyRequests` ogni 15 minuti lo consuma in transazione e lo
   CANCELLA (non null: nelle query di intervallo null viene prima di ogni
   Timestamp). Push con lo stesso `type` e bottoni della richiesta: nessuna
   modifica ai client. Le rules vietano `nudgeAt`/`nudgedAt` alla creazione.
6. ✅ **«Chi è libero a quell'ora»** (01/10/2026). Gli eventi del calendario
   NON dicono chi partecipa (solo `childId` e `createdBy`, e chi li crea
   spesso inserisce gli impegni di tutti): scelta dell'utente, si mostrano
   come contesto non attribuito («In calendario, intorno alle 16:30»), e
   accanto a ogni membro solo i suoi to-do assegnati, non fatti e con orario
   («Ha già «Portare Sveva» alle 17:00»). Finestra ±1 ora, ripetizioni
   espanse, visibilità rispettata. Solo se il to-do ha una scadenza con
   orario. `FamilyRequestAvailability` (iOS e Android), `requestAvailability`
   (web). Per renderlo davvero «chi è libero» servirebbero i partecipanti
   negli eventi: scartato per ora.
7. ✅ **Azione AI `request_add`** (01/10/2026), nel blocco `KIDBOX_ACTIONS`
   dei tre client (`PlanningAIActionBlock` iOS/Android, `aiActions.js` web):
   `{"type":"request_add","title","dueAt","notes","askMembers":["Luca"],
   "askOutside","outsideLabel"}`. Il client traduce i nomi in account (nome
   intero o di battesimo), riporta quelli che non trova, e senza destinatari
   non crea niente; con `askOutside` il riepilogo in chat porta il link.
   Provato su Haiku: «serve qualcuno per…» → richiesta a tutti, «chiedi a
   Luca…» → solo Luca, «sabato mattina» → chiede l'ora (3 su 3), to-do
   semplice → resta `todo_add`. **Trovato e corretto per tutte le azioni**:
   il prompt chiedeva date «ISO8601 UTC» senza dire il fuso, e il modello
   scriveva l'ora italiana con la Z (eventi e to-do dell'assistente 2 ore
   avanti) e sbagliava il giorno della settimana. Ora la sezione azioni apre
   con fuso, offset attuale e i prossimi 7 giorni (`dateHeader` /
   `actionsDateHeader`); Android legge anche gli offset (`OffsetDateTime`).
8. Dopo, solo se la previsione regge: `grocery` ed `event`, l'assistente che
   propone a chi chiedere, il connettore MCP come mittente (`createdVia`).

## Decisioni aperte

| Domanda | Raccomandazione |
|---|---|
| Il link esterno include sempre l'invito alla famiglia? | **Sì, di default**, con un interruttore «Includi invito» nell'editor. È il motivo per cui esiste la funzione; l'invito resta monouso come oggi. |
| Chi vede le richieste? | **Tutti i membri**, anche quelli non avvisati. Niente visibilità per membro finché le famiglie 2+ sono poche (scelta del backlog). |
| *Non posso* va mostrato a chi chiede? | **Sì**, con il nome: è informazione utile («allora chiedo alla nonna»). |
| Piano | **Free.** È crescita, non una funzione da vendere. |
| Testo in chiaro sul server | **Sì**, come i to-do oggi. La cifratura con la chiave nel frammento si può aggiungere dopo, ma costerebbe le push con il testo. |
