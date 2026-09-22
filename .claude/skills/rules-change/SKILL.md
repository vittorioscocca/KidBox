---
name: rules-change
description: Modificare le regole Firestore di KidBox — i due file, la suite di test, la verifica differenziale contro le regole in produzione, il deploy e cosa guardare dopo. Usare ogni volta che si tocca firestore.rules o firestore.rules.next, quando l'utente dice «le rules», «i permessi Firestore», o quando qualcuno «non vede più» dei dati.
---

> Il deploy meccanico (comando, commit per path) sta in `/deploy-functions`.
> **Questa skill è quello che viene prima**: una regola sbagliata non dà errore
> di compilazione, non compare in Cloud Logging, e si manifesta come dati che
> spariscono a utenti veri. Su iOS anche peggio (vedi trappola 1).

## I due file

| File | Cos'è |
|---|---|
| `firestore.rules` | quello che si deploya |
| `firestore.rules.next` | **versione futura, non deployabile**: chiude l'auto-iscrizione e l'auto-riattivazione dopo revoca pretendendo `joinedWithValidInvite`, cioè l'`inviteId` sul documento membro |

I due file devono differire **solo** nell'`allow create` / `allow update` di
`families/{familyId}/members/{uid}` (più il blocco di avviso in testa al
`.next`). `rules.test.js` gira su entrambi e fallisce se divergono oltre quel
blocco: **ogni altra modifica va scritta in tutti e due**.

**Il `.next` si deploya solo quando** iOS e Android con il join aggiornato sono
pubblicati **e** l'adozione è alta — stessa disciplina dell'enforcement App
Check. Le app pubblicate prima di settembre 2026 non scrivono `inviteId`: con
quella regola attiva **ogni join da un'app non aggiornata viene negato**. Se
serve deployare per altro prima di allora, si rimette l'`allow create` di
`members` alla forma permissiva commentata lì accanto e si deploya il resto.

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
2. Guarda `firestore.googleapis.com/rules/evaluation_count` con label
   `result=DENY` su Cloud Monitoring: **i negati delle rules non finiscono in
   Cloud Logging**, si vedono solo lì. Riferimento storico: 0-6 DENY/ora.
3. Un `PERMISSION_DENIED` può essere transitorio (propagazione dopo un join):
   resta aperto rendere non distruttiva la reazione del client — oggi su iOS è
   ancora quella della trappola 1.

## Resta aperto (non è una svista, è una scelta)

I membri già dentro possono scrivere gli inviti tramite il wildcard
`{coll}/{docId}`: `members` non è escluso, e la nota nel file lo dice.
