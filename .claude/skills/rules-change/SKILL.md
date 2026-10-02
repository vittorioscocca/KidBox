---
name: rules-change
description: Modificare le regole Firestore di KidBox — il file (e quando serve un .next), la suite di test, la verifica differenziale contro le regole in produzione, il deploy e cosa guardare dopo. Usare ogni volta che si tocca firestore.rules o firestore.rules.next, quando l'utente dice «le rules», «i permessi Firestore», o quando qualcuno «non vede più» dei dati.
---

> Il deploy meccanico (comando, commit per path) sta in `/deploy-functions`.
> **Questa skill è quello che viene prima**: una regola sbagliata non dà errore
> di compilazione, non compare in Cloud Logging, e si manifesta come dati che
> spariscono a utenti veri. Su iOS anche peggio (vedi trappola 1).

## Un file solo, e quando serve un secondo

`firestore.rules` è quello che si deploya, ed è sempre deployabile.

Una **restrizione che dipende da un client** (la regola pretende un campo che
solo le app nuove scrivono) non va in `firestore.rules` finché quelle app non
sono diffuse: va in un `firestore.rules.next` identico tranne quella regola, con
un avviso in testa, e `rules.test.js` gira su entrambi (secondo ambiente con un
`projectId` diverso) così la regola in attesa non marcisce. **Ogni altra
modifica va scritta in tutti e due.** Un allargamento invece è retrocompatibile
e si deploya subito: le rules vanno live **prima** del client che ne dipende.

**`.next` in attesa dal 02/10/2026:** `users/{uid}/aiConversations` e
`families/{id}/memoryFacts` accettano solo scritture cifrate
(`aiConversationWriteIsEncrypted`, `memoryFactWriteIsEncrypted`; i fatti escono
dalle scritture del wildcard). Ogni differenza col file in produzione sta fra
`// BEGIN next:<nome>` e `// END next:<nome>`, anche dentro un'espressione. Si
promuove insieme all'interruttore Remote Config `ai_conversations_encrypted`,
quando le build iOS e Android che cifrano sono diffuse
(`internal/assistente-unico.md`). La suite ha un test che fallisce se i due file
divergono fuori dai blocchi marcati: promuovendo, togli i marcatori e il test.

L'ultimo `.next` (auto-iscrizione a `members/{uid}` solo con l'invito
consumato, `joinedWithValidInvite`) è stato promosso il **01/10/2026** e il
file tolto. Il criterio usato per promuoverlo, da riusare: (1) in produzione
ogni join reale recente porta il campo (contati i documenti membro non owner
per data e piattaforma: 9 su 9 dal 22/09); (2) GA4 `platform × appVersion` a
7 giorni senza versioni che non lo scrivono; (3) suite verde sul nuovo e
controprova che fallisca sul vecchio; (4) differenziale a zero regressioni.
Prezzo noto: un'app sotto la 2.2.6 non riesce più a entrare in una famiglia.

## Le tre trappole, tutte già pagate

1. **`**` non è legato nelle LIST.** Dentro `match /{subpath=**}` qualunque
   condizione che legga il capture (`subpath[0]`, `string(subpath)`) va in
   «Variable is not bound in path template» **durante una list**, e quindi
   **nega ogni query di collezione** — a membri e proprietario. Le scritture
   passano, perché il path non lo guardano: per questo il guasto sembra colpire
   solo chi non ha cache locale, cioè un membro appena entrato.
   Un capture di **un solo segmento** è invece legato anche in list: per
   filtrare per nome di sottocollezione si usa `match /{coll}/{docId}/{subpath=**}`
   e si guarda `coll` (è così che è scritto oggi).
   **La conseguenza non è un errore a schermo.** Su iOS
   `SyncCenter.handleFamilyAccessLost` legge il PERMISSION_DENIED come «sei
   stato rimosso», chiama `FamilyLeaveService.leaveFamily` e **cancella il
   documento membro su Firestore**: l'8/09/2026 membri storici si sono
   auto-espulsi e hanno dovuto rientrare da QR o link.
   → Se tocchi il wildcard sotto `families/`, **la verifica sono le `list`, non
   i `get`**: sezione «QUERY DI COLLEZIONE (LIST)» della suite.
2. **Il wildcard combacia anche col documento famiglia stesso** (subpath vuoto),
   e le regole sono in **OR**: senza il guard `string(subpath).size() > 0` la sua
   `allow write` scavalca `keepsPlanFields()` e **il piano torna scrivibile a
   mano** — cioè chiunque si regala Pro/Max con una scrittura. C'è un test
   apposta: se tocchi quel punto, rieseguilo.
3. **Mai `.campo` su un campo che può mancare.** L'accesso diretto a un campo
   assente è un **errore di valutazione, e l'errore nega**. Si usa
   `data.get('campo', false)`. È il bug del passaggio di proprietà: l'owner
   creato da iOS e dal web non ha `isDeleted`, finché è owner passa da `isOwner`
   (valutato prima), ma da membro semplice restava chiuso fuori.
   Attenzione al rovescio: `isMember` **pretende** `role`, e non per caso — un
   membro revocato il cui documento venisse ricreato da un `setData(merge)` del
   client (iOS e web riscrivono il nome così) rientrerebbe dalla finestra.

4. **Le query di collection group non passano dalle `match` annidate.**
   `collectionGroup("members")` ignora `match /families/{familyId}/members/{uid}`:
   serve una regola sua, `match /{path=**}/members/{memberId}` (oggi ammette
   solo `list` con `resource.data.get('uid', '') == request.auth.uid`), **e**
   un'esenzione in `firestore.indexes.json`, altrimenti la query non parte.
   Mancavano entrambe fino al 24/09/2026, e il fallback di Android per
   ritrovare le famiglie falliva in silenzio dentro un try/catch. Tre cose da
   non rompere: la regola vale per **ogni** collezione chiamata `members`,
   anche future (una `members` fuori da `families/` sarebbe listabile col
   proprio uid); il client deve filtrare **esattamente** su `uid ==` il
   proprio, o la query è negata tutta; `.get('uid', '')` e non `.uid`
   (trappola 3). Nella suite ci sono i tre casi: non toglierli.

   E il rovescio della trappola 3: il criterio «membro = non cancellato **e**
   con `role`» vale anche fuori dalle rules. La function `syncMembershipIndex`
   lo aveva dimenticato (vedi `/deploy-functions`); se lo cambi qui, cambialo
   in `isActiveMember` in `functions/index.js` e in
   `scripts/membership-index-audit.js`.

## Prima di scrivere la regola: guarda i dati veri

Una regola che legge un campo vale quanto la presenza di quel campo in
produzione. Prima di appoggiarti a un campo, **contalo**: è così che si è potuto
dire «tutti i 557 inviti hanno `expiresAt` timestamp» e «il campo manca solo sui
76 owner e su 2 membri di famiglie orfane». Un `n/d` qui diventa un utente
chiuso fuori domani.

## La suite

    cd firestore-tests && npm test

(serve `JAVA_HOME` sul JBR di Android Studio: il JDK di sistema è Java 8 e
l'emulatore non parte). Gira su **entrambi** i file. Aggiungi il caso nuovo
**prima** di scrivere la regola, e controlla che fallisca sulle regole di oggi:
un test che passa anche senza la modifica non prova niente.

## La verifica differenziale (per i cambi che toccano l'accesso esistente)

La suite dice che la regola nuova fa quello che vuoi. Non dice **cosa smette di
funzionare**. Per quello si scrive un harness usa-e-getta (nello scratchpad, non
nel repo) che esegue le **scritture esatte dei client** — iOS, Android, web, e
le versioni vecchie ancora installate — contro:

- le regole **oggi in produzione**, scaricate dall'API Rules (non da HEAD: vanno
  confrontate, e devono coincidere);
- le regole nuove.

Poi si confrontano i due esiti passo per passo e si classifica **ogni**
differenza come voluta o come regressione. Il giro del 14/09/2026: 103 passi
(ciclo invito per piattaforma, revoca, scadenze, revoca membro e rientro,
uscita, passaggio di proprietà, eliminazione famiglia, estranei, console admin,
doppio consumo) → 11 cambi, tutti voluti, 0 regressioni. È il controllo che ha
trovato il bug del passaggio di proprietà.

## Deploy e dopo

Il comando è in `/deploy-functions` (`npx firebase deploy --only firestore:rules`
dalla root; gli indici sono un deploy separato). Prima, **di' all'utente cosa
cambia**: additivo (una `match` nuova) è routine, modificare o togliere una
regola esistente può togliere accesso a dati in produzione e va detto chiaro.

Dopo:

1. Verifica che il **ruleset attivo coincida col commit** appena fatto.
   Gli indici hanno un deploy loro: controlla che siano `READY`
   (`GET …/collectionGroups/{coll}/fields/{campo}` sull'API Firestore Admin).
   Se hai toccato membri o appartenenza, `node scripts/membership-index-audit.js`.
2. Guarda `firestore.googleapis.com/rules/evaluation_count` con label
   `result=DENY` su Cloud Monitoring: **i negati delle rules non finiscono in
   Cloud Logging**, si vedono solo lì. Riferimento storico: 0-6 DENY/ora.
3. Un `PERMISSION_DENIED` può essere transitorio (propagazione dopo un join):
   resta aperto rendere non distruttiva la reazione del client — oggi su iOS è
   ancora quella della trappola 1.

## Le collezioni escluse dal wildcard

Il wildcard `{coll}/{docId}/{subpath=**}` dà lettura e scrittura ai membri su
**ogni** sottocollezione, anche future. Le eccezioni sono elencate lì:
`memberKeyBackups` (né lettura né scrittura: ha una regola sua), `geofences`,
`geofenceEvents`, `geofenceState` e `calendarFeeds` (solo lettura: hanno una
regola loro o le scrive una function), `requests` (dal 01/10/2026: il client
crea e ritira, il resto lo scrive il server; vedi `/richieste`). E `locations/{uid}/**` si scrive solo
se `docId == request.auth.uid` (dal 30/09/2026: prima un membro poteva spostare
la posizione di un altro o spegnergli la condivisione).
Una collezione nuova che deve scrivere solo il server va **aggiunta a
quell'elenco**: una `match` sua con `allow write: if false` non basta, le rules
sono in OR e il wildcard la scavalca. Test prima, e che fallisca sulle regole
di oggi (vedi `calendarFeeds` nella suite).

## Resta aperto (non è una svista, è una scelta)

I membri già dentro possono scrivere gli inviti tramite il wildcard
`{coll}/{docId}`: `members` non è escluso, e la nota nel file lo dice.
