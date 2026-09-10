# Skill Alexa — lista della spesa e promemoria

Detta la spesa agli Echo di casa e gli articoli finiscono in
`families/{familyId}/groceries`, la stessa collezione di iOS, Android e webapp.
La skill è solo un client in più: non c'è un modello dati parallelo, e la push
di `notifyNewGroceryItem` scatta come per un articolo aggiunto a mano.

## Perché serve dire «mio box»

Il 1° luglio 2024 Amazon ha chiuso la **List Management REST API** e le **List
Skills**, cioè l'unico modo che un'app terza aveva di leggere e scrivere la
lista della spesa integrata di Alexa. Da allora *«Alexa, aggiungi il latte alla
lista della spesa»* scrive solo nella lista interna di Amazon, che nessuno può
più leggere. L'unica via rimasta — la stessa presa da AnyList e Bring — è una
skill con nome di invocazione proprio:

> «Alexa, chiedi a mio box di aggiungere il latte»

Non è aggirabile. Chi ci prova fa scraping non ufficiale dell'endpoint web di
Alexa, che si rompe a ogni cambio lato Amazon.

## Perché il codice e non l'account linking

L'account linking di Alexa è OAuth2: vuole un authorization server con la sua
pagina di login. I nostri account nascono in buona parte da **Google** e
**Sign in with Apple**, quindi quella pagina dovrebbe rifare il giro completo di
entrambi i provider dentro la webview di Amazon — con i redirect URI di Amazon
registrati su Firebase Auth, e il consenso Apple da riottenere lì dentro.

Il codice di accoppiamento salta tutto: l'utente **è già autenticato nell'app**,
e il codice trasporta quell'identità verso Alexa senza chiedere di nuovo le
credenziali. Il provider di login smette di essere un problema.

Conseguenze da conoscere:

- **Chi parla all'Echo non viene identificato.** Chiunque abbia voce in casa può
  aggiungere alla lista. Per una lista della spesa condivisa è il comportamento
  giusto, ma vale la pena saperlo prima di estendere la skill ad altro.
- **L'attribuzione è di chi ha collegato.** Gli articoli dettati risultano
  creati dall'`uid` che ha dettato il codice. Se ogni membro collega dal proprio
  telefono e dal proprio account Amazon, l'attribuzione resta corretta per
  persona; se collega uno solo, tutto risulta suo.

  Da quando la lista mostra «Aggiunto da … · oggi» sotto ogni articolo, questo
  smette di essere un dettaglio interno e diventa visibile: in una famiglia con
  un solo account Amazon collegato, tutto quello che viene dettato porta il nome
  di chi ha fatto l'accoppiamento, chiunque abbia parlato. È il prezzo di non
  identificare la voce, e va detto prima che qualcuno lo scopra e pensi a un
  bug.
- **Nulla è precluso in futuro.** Se un giorno serve l'account linking vero, si
  aggiunge sopra: `alexaLinks` non cambia forma.

## Cosa c'è nel repo

| File | Cosa fa |
| --- | --- |
| `functions/alexa.js` | Endpoint della skill + le tre callable per l'app |
| `internal/alexa/interaction-model-it-IT.json` | Modello di interazione italiano |
| `internal/alexa/interaction-model-en-GB.json` | Modello inglese |
| `KidBox/KidBox/Features/Settings/Alexa/` | Schermata di accoppiamento iOS |
| `KidBoxAndroid/.../ui/screens/settings/AlexaSettings*` | Stessa schermata su Android |

Lo stato che le due schermate leggono è **di famiglia**, non del singolo:
`getAlexaLinkStatus` vuole un `familyId`, verifica che il chiamante ne sia
membro e restituisce tutti i collegamenti di quella famiglia. Serve perché il
collegamento è per account Amazon: se in casa c'è un solo account Amazon, il
primo che collega copre tutti gli Echo e gli altri membri non devono rifare
nulla — ma senza vederlo scritto rifarebbero l'accoppiamento a vuoto.

Collezioni Firestore, tutte top-level e **non nominate nelle rules**: ricadono
nel default-deny, quindi ci arriva solo l'Admin SDK.

- `alexaPairings/{code}` — codice usa-e-getta, 10 minuti
- `alexaLinks/{sha256(alexaUserId)}` — collegamento permanente
- `alexaLinkAttempts/{sha256(alexaUserId)}` — antibruteforce sul codice

## Sicurezza dell'endpoint

`alexaSkill` è l'**unica function HTTP** del progetto e non passa da App Check:
la chiama Amazon, non un nostro client. Al suo posto valgono tre controlli, in
`alexa.js`, tutti obbligatori:

1. firma RSA del corpo, verificata col certificato pubblicato da Amazon (URL
   vincolato a `https://s3.amazonaws.com/echo.api/`, con i `..` normalizzati);
2. timestamp entro 150 secondi, contro il replay;
3. `applicationId` uguale a `ALEXA_SKILL_ID`, contro una skill altrui che punti
   allo stesso URL.

## Passi in console Amazon (da fare a mano)

1. **developer.amazon.com/alexa/console/ask** → *Create Skill*.
   Modello **Custom**, hosting **Provision your own**.
2. **Invocation name**: `mio box`.

   Cambiato da `kid box` il 10/09/2026. Il motivo: in `it-IT` veniva
   riconosciuto circa una volta su cinque. `kid` è inglese e finisce in /d/, un
   suono che in italiano non chiude nessuna parola, e due monosillabi danno
   pochissimo materiale acustico su cui decidere.

   ⚠️ **Il nome contiene un possessivo, e ha un costo noto**: davanti a «mio
   box» viene naturale dire «chiedi **al** mio box», e quell'articolo rompe lo
   schema `chiedi a ‹nome›` che Alexa si aspetta. Se il riconoscimento dovesse
   risultare fragile, è la prima cosa da guardare — non il backend.

   **Save Model e Build Model sono due cose distinte**: il primo persiste, il
   secondo compila per il riconoscimento vocale. Finché non fai il build, Alexa
   risponde al nome vecchio anche se la console mostra già quello nuovo. È la
   causa più comune di «l'ho cambiato ma non funziona».

   Il **Build skill passa comunque** anche con un nome non valido, perché
   compila il modello di interazione e non il manifest: sembra tutto a posto e
   non lo è. Stessa cosa per il simulatore col testo digitato, che in stage
   development instrada per contesto e risponde correttamente anche quando a
   voce non funziona niente.

   **Sintomo da riconoscere, che vale mezza giornata: testo sì, voce no
   significa nome di invocazione, mai backend.** Il testo bypassa il
   riconoscimento vocale.

   La sezione TRADEMARK / BRAND nelle Testing Instructions era **obbligatoria**
   finché l'invocazione era il marchio. Con `mio box` non lo è più, ma va
   tenuta lo stesso: «KidBox» resta il Public Name e compare nelle descrizioni.

   ### Cosa NON abbiamo dimostrato

   `kid box` è sembrato fallire a voce durante il lavoro, e da lì avevamo
   dedotto che l'ASR italiano non riconoscesse le parole straniere, passando
   per `casa kidbox`, `spesa famiglia` e `famiglia mia` prima di tornare al
   punto di partenza. **La deduzione era sbagliata.**

   L'errore di metodo: dedurre una regola da un test fatto mentre più cose
   erano in movimento — nome cambiato, modello ricompilato, endpoint appena
   salvato — invece di isolare una variabile per volta. È costato tre rinomine
   inutili, ognuna con la propagazione delle frasi su iOS, Android e quattro
   lingue.

   E ha prodotto un danno silenzioso: la sostituzione cieca di `spesa famiglia`
   ha travolto la stringa Android `settings_notif_expenses_sub` («Quando viene
   registrata una spesa famiglia»), che è finita committata. Se si rinomina di
   nuovo, **sostituire i token isolati con un confine di parola**, non con un
   replace testuale, e rileggere il diff delle righe modificate — non solo di
   quelle aggiunte.

3. **JSON Editor** → incolla `interaction-model-it-IT.json` sulla locale
   `Italiano (IT)`. Per l'inglese aggiungi la locale `English (UK)` e incolla
   l'altro file. *Build Model*.

   Il modello italiano porta ogni comando in **due forme**, imperativa e
   infinitiva: `aggiungi {item}` e `aggiungere {item}`. Non è ridondanza.
   L'invocazione in un colpo solo passa dall'infinito — «chiedi a spesa
   famiglia **di aggiungere** il latte» consegna al modello `aggiungere il
   latte` — mentre il dialogo in due tempi («apri mio box», poi
   «aggiungi il latte») usa l'imperativo. Con una sola forma metà delle frasi
   naturali non aggancia nulla. In inglese il problema non si pone: «ask X *to
   add* milk» coincide già con l'imperativo.
4. **Endpoint** → *HTTPS*. L'URL è quello stampato dal deploy al punto 5; con
   le impostazioni attuali è
   `https://europe-west1-kidbox-42cd7.cloudfunctions.net/alexaSkill`, ma vale
   quello che dice `firebase deploy` — le v2 espongono anche un `.run.app`.
   Certificato: **obbligatoriamente** *«My development endpoint is a sub-domain
   of a domain that has a wildcard certificate from a certificate authority»*.

   Non è una formalità e sbagliarla costa ore. Il certificato servito da
   `europe-west1-kidbox-42cd7.cloudfunctions.net` è `CN=misc.google.com` con
   SAN `misc.google.com, cloudfunctions.net, *.cloudfunctions.net`: il nostro
   host combacia **solo** attraverso la wildcard. Se dichiari «has a certificate
   from a trusted certificate authority», Amazon valida la dichiarazione prima
   di aprire la connessione, la trova incoerente e fallisce in ~27 ms — e nei
   log della function non arriva NIENTE, nemmeno un 4xx, perché la richiesta non
   parte proprio. Il simulatore dice solo «Non posso raggiungere la Skill
   richiesta», che manda fuori strada. Il dettaglio vero sta nel Device Log,
   dentro il primo `SkillDebugger.CaptureError`.

   L'ordine comodo è: fai prima il deploy (punto 5) con uno Skill ID
   provvisorio, incolla l'URL qui, poi rifai `secrets:set` con lo Skill ID vero.
5. Copia lo **Skill ID** (`amzn1.ask.skill.…`) dalla pagina *Endpoint* e
   impostalo come secret, poi fai il deploy:

```bash
firebase functions:secrets:set ALEXA_SKILL_ID
```

```bash
firebase deploy --only functions:alexaSkill,functions:createAlexaPairingCode,functions:getAlexaLinkStatus,functions:unlinkAlexa
```

6. **Pubblicazione: DECISA il 08/09/2026.** La skill va sullo Skill Store.
   Fino a quel momento resta in stage *Development*, dove è già abilitata su
   tutti gli Echo registrati all'account del developer; per i membri con un
   account Amazon proprio si può aprire un **beta test** (*Distribution* →
   *Availability* → *Beta Test*, fino a 500 email, 90 giorni rinnovabili).

   ⚠️ **L'app dipende da questa pubblicazione.** In Impostazioni → Alexa, prima
   del collegamento, iOS e Android ora mostrano il passo *«1. Attiva la skill —
   apri l'app Alexa, cerca "KidBox" fra le skill e attivala»*. Con la skill in
   stage *Development* quel testo manda l'utente a cercare qualcosa che non
   troverà (vedi la sezione qui sotto). Se la pubblicazione dovesse saltare, va
   riscritto quel passo nelle due app.

## Come si "installa" sui dispositivi

Non si installa: una skill in stage *Development* **non** si cerca nell'app
Alexa e non si attiva da lì. Amazon la abilita d'ufficio su tutti gli Echo
registrati all'account del developer, appena metti *Test → Development*. Da quel
momento basta parlare: «Alexa, apri mio box».

Se la si vuole vedere elencata: app Alexa → Altro → Skill e giochi → Le mie
skill → scheda **Dev**.

Due precondizioni, e sono la causa più comune di un "non funziona" senza errori:

- **stesso account Amazon** fra developer console ed Echo di casa;
- **lingua del dispositivo `it-IT`**, altrimenti il modello non riconosce nulla.

Per un membro con un account Amazon proprio serve il beta test: *Distribution →
Availability → Beta Test*, la sua email Amazon, lui accetta l'invito. Chi invece
condivide l'account Amazon di casa non deve fare niente — ed è il motivo per cui
la schermata mostra i collegamenti già presenti in famiglia invece di proporre a
tutti un accoppiamento.

## Attribuzione per voce (Personalization)

Serve il permesso **Skills Personalization**, in *Build → Permissions*, in
fondo alla lista. Non basta il link «Enable Personalization» del banner nel tab
Test: quello abilita solo la prova nel simulatore, il permesso è un'altra cosa
e senza di esso `context.System.person` **non compare affatto** nella richiesta
— non vuoto, proprio assente. Dopo averlo attivato: Save, Build skill, e
riabilitare la skill (tab Test da *Development* a *Off* e ritorno), perché i
permessi si applicano al momento dell'abilitazione.

Gli altri permessi della pagina restano spenti. In particolare *Full Name* e
*Given Name* sembrano pertinenti ma non lo sono: darebbero il nome anagrafico
previo consenso, mentre a noi serve solo un identificativo stabile — il nome
del membro ce l'abbiamo già in KidBox. E *Lists Read* / *Lists Write* sono i
permessi sulla lista nativa di Alexa, la cui API Amazon ha chiuso nel 2024.

Con quel permesso attivo, ogni richiesta porta
`context.System.person.personId`: identifica **la persona che ha parlato**, non
l'account. In una casa con un solo account Amazon e più profili vocali, lo
`userId` è sempre lo stesso e il `personId` cambia a ogni voce.

Due legami separati, perché rispondono a domande diverse:

| Collezione | Risponde a |
| --- | --- |
| `alexaLinks/{sha256(alexaUserId)}` | quale **famiglia** — dà accesso alla lista |
| `alexaPersonLinks/{sha256(personId)}` | quale **persona** — dà solo l'attribuzione |

L'accesso resta dell'account. La voce serve solo a decidere `createdBy`: se è
riconosciuta e associata si usa quella, altrimenti si ricade su chi ha
collegato l'account. Quindi **chi non ha un profilo vocale non perde niente**,
si comporta come prima.

Lo stesso codice a sei cifre lega entrambe le cose: se al momento in cui viene
dettato Alexa riconosce la voce, si registra anche quella. È così che un
secondo membro si fa attribuire i propri articoli senza collegare un account
Amazon suo.

Una cosa che è stato necessario cambiare: prima, con l'account già collegato,
`handleLink` rispondeva «già collegato» e si fermava — il che avrebbe bloccato
sul nascere proprio il secondo membro. Ora quel ramo scatta solo quando non
resta niente da legare.

`unlinkAlexa` cancella anche i legami di voce: lasciarli sarebbe peggio che
inutile, continuerebbero ad attribuire articoli a un account scollegato.

## Promemoria a voce (to-do)

Oltre alla spesa, la skill crea **to-do** in `families/{familyId}/todos`, nella
lista chiamata **`Alexa`** (creata al primo uso, cercata per nome così che non
se ne formi una seconda se qualcuno l'ha già fatta a mano dall'app).

> «Alexa, chiedi a mio box di ricordarmi di chiamare la scuola»
> — «A chi lo assegno?» — «a Giulia»
> — «Per quando?» — «domani alle otto»
> — «Fatto: lo ricordo a Giulia domani alle 08:00. Chiamare la scuola.»

Data e ora sono **facoltative**: senza, resta un to-do e basta. Con, si scrive
`remindAt` e a suonare ci pensa `notifyDueTodoReminders` (index.js, ogni 5
minuti), che notifica l'assegnatario o tutta la famiglia se non c'è.

### Perché il dialogo è in più turni

`AMAZON.SearchQuery` è l'unico slot che accetta testo libero — il titolo è una
frase qualsiasi — ma Amazon lo ammette **solo come ultimo elemento del sample e
da solo**: nessun altro slot può stare nella stessa frase. Quindi «ricordami di
{task} e assegnalo a {member}» **non è esprimibile**, e non per una scelta
nostra. Restano due strade: due sample separati, o il multiturno. Qui si fa il
multiturno — due domande costano due turni ma non obbligano l'utente a imparare
due frasi diverse.

Non si usa il **Dialog model** di Amazon (elicitation + `Dialog.Delegate`)
perché non può elicitare uno `AMAZON.SearchQuery` — proprio lo slot che serve —
e perché sposterebbe in console una logica che dipende dai membri della
famiglia, che la console non conosce. Lo stato del dialogo vive in
`sessionAttributes`, quindi tutto in `alexa.js`.

`AMAZON.DATE` e `AMAZON.TIME` invece **possono** convivere nello stesso sample:
il divieto riguarda solo `SearchQuery`.

### I due campi del motore, e i due modi opposti di sbagliarli

`notifyDueTodoReminders` interroga `remindSentAt == null` **e**
`remindAt <= now`. Da lì discendono due regole speculari, e servono entrambe:

- **Con promemoria**: `remindSentAt: null` va scritto **esplicito**. In
  Firestore un campo assente non è `null`, il documento non entra nell'indice
  composto e resta invisibile alla query per sempre — senza errori e senza log.
  Il promemoria semplicemente non suona mai.
- **Senza promemoria**: i due campi **non vanno scritti affatto**, nemmeno a
  `null`. Le query di intervallo di Firestore attraversano i tipi, e `null`
  precede qualunque Timestamp: un documento con `remindAt: null` soddisfa
  `remindAt <= now` ed entra nella query. Un to-do per cui nessuno ha chiesto
  niente farebbe partire una notifica al primo giro dello scheduler.

Oggi vale solo per questa skill — nessun client scrive `remindAt` — ma è la
prima cosa da rileggere il giorno in cui iOS o Android cominceranno a farlo.

### Fuso orario

Alexa consegna data e ora già risolte ma **senza fuso** (`2026-09-11`,
`18:30`): sono ore locali di chi parla e vanno ancorate a un fuso per diventare
un istante. Si usa `Europe/Rome`, come tutto il resto del backend. Chiedere il
fuso vero del dispositivo alle Settings API di Alexa vorrebbe dire una chiamata
HTTP in più dentro gli 8 secondi concessi.

Il conto passa da `Intl` e non da `getHours()`: le Functions girano in **UTC**,
e `new Date().getHours()` a Roma d'estate sbaglia di due ore senza che nessuno
se ne accorga finché un promemoria non suona a colazione invece che a pranzo.
Le due notti del cambio d'ora sono coperte da una seconda passata sull'offset.

Regole sui pezzi mancanti: giorno senza ora → **09:00**; ora senza giorno →
oggi se non è ancora passata, altrimenti domani; un momento già passato viene
rifiutato e richiesto. `AMAZON.DATE` risolve anche cose che un giorno preciso
non sono («questa settimana» → `2026-W38`): si accetta solo `YYYY-MM-DD`, e per
il resto si richiede invece di indovinare.

### Il momento detto dentro il titolo

«ricordami di pagare la mensa **domani alle otto**» consegna a `task` tutta la
frase, data compresa: `AMAZON.SearchQuery` prende quello che trova e non esiste
modo di dirgli dove fermarsi. Il titolo nasceva quindi «Pagare la mensa domani
alle otto».

`extractWhenFromTitle` riconosce la coda temporale, la toglie dal titolo e la
usa come `remindAt`. Il turno «per quando?» sparisce: due domande diventano una.

**La regola che rende sicuro tagliare: si toglie solo ciò che si è riusciti a
trasformare in una data.** Elimina i due modi di sbagliare insieme — non si
taglia mai un pezzo di titolo legittimo, perché quello che non si capisce non si
tocca; e non si perde mai un momento detto, perché ciò che si taglia diventa il
promemoria. Se il momento risulta già passato si torna a chiedere, col titolo
comunque ripulito.

L'uscita ha la forma degli slot `AMAZON.DATE` e `AMAZON.TIME` di proposito: il
momento estratto dal titolo e quello detto rispondendo a «per quando?» passano
dalla **stessa** `resolveRemindAt`. Una regola sola sui pezzi mancanti, una sola
sul passato, un solo insieme di test.

Riconosce: `oggi` `domani` `dopodomani` `stasera` `stamattina` `stanotte`, i
giorni della settimana (sempre risolti **in avanti**: «giovedì» detto giovedì
sera è quello prossimo), `il 15 settembre` (e l'anno dopo se è già passato),
`alle otto` / `alle 8` / `alle 8:30` / `alle sette e mezza` / `a mezzogiorno`,
`di mattina` `di sera`, e `fra venti minuti` / `fra un'ora` / `fra tre giorni`.
Consuma da destra e a giri, così «domani alle otto» e «alle otto di domani»
funzionano entrambi senza due grammatiche da tenere allineate.

Due falsi positivi trovati provandolo, e come sono chiusi:

- **«prenotare il tavolo per otto»** — `per otto` sono persone. L'orario vuole
  `alle`/`per le`, non `per` da solo.
- **«comprare il giornale di oggi»** — dopo un `di` il giorno qualifica il
  titolo invece di datarlo. Ma in «alle otto **di** domani» quello stesso `di` è
  il legame fra ora e giorno: a distinguerli è cosa sta **prima** della
  preposizione, un orario o una parola qualunque. Non basta chiedersi se un'ora
  è già stata consumata — lì l'ora sta a monte del `di`, e il giro che consuma
  da destra non l'ha ancora vista.

Se non resta niente dopo il taglio, si annulla tutto: «ricordami domani» vuol
dire che il titolo **è** «domani», e un to-do senza titolo non lo vuole nessuno.

Solo italiano. Una grammatica inglese scritta a occhi chiusi taglierebbe titoli
veri per riconoscere frasi che, senza gli intent in `en-GB`, nessuno può
pronunciare.

### Come si risolve l'assegnatario

Il nome detto si confronta con `families/{familyId}/members`, campo
`displayName` (ripiego su `name`, poi su `users/{uid}.displayName` — i documenti
in `members` possono non averlo, che è la stessa ragione per cui `memberName`
in `alexa.js` e `resolveMemberName` in `index.js` hanno lo stesso ripiego).
I membri con `isDeleted: true` sono esclusi.

Tre passate, dalla più stretta alla più larga, e a ogni passata si accetta
**solo se il candidato è uno**:

1. nome completo uguale — distingue «Marco» da «Marco Rossi» quando esistono
   entrambi;
2. primo nome uguale — in famiglia il cognome quasi non si dice;
3. primo nome che comincia per quello detto — recupera i troncamenti dell'ASR
   («Ale» per «Alessandra»).

Cosa succede nei casi storti:

| Caso | Risposta |
| --- | --- |
| Nome non trovato | Elenca i membri e richiede. Il to-do **non** si perde: il flusso resta aperto |
| Due membri omonimi | Lo dice e propone di assegnare dall'app, oppure «a nessuno» |
| «a me» | L'uid di chi ha parlato (voce riconosciuta) o dell'account collegato: la stessa regola dell'attribuzione della spesa |
| «a nessuno» | Nessun assegnatario: il promemoria va a tutta la famiglia |
| Nessun membro leggibile | Tira dritto senza assegnatario invece di insistere con una domanda senza risposta |

Al primo dubbio si chiede, non si sceglie: un promemoria assegnato alla persona
sbagliata non suona a chi deve, e nessuno se ne accorge finché non è tardi.

### Intent nuovi da buildare in console

Sono tutti in `interaction-model-it-IT.json` — basta reincollare il file nel
JSON Editor della locale **Italiano (IT)** e fare *Build Model*.

| Intent | Slot | A cosa serve |
| --- | --- | --- |
| `AddReminderIntent` | `task` (`AMAZON.SearchQuery`) | Apre il flusso; il titolo può mancare |
| `ReminderAssigneeIntent` | `member` (`MemberName`) | «assegna a Giulia» |
| `ReminderAssignSelfIntent` | — | «a me» |
| `ReminderWhenIntent` | `date` (`AMAZON.DATE`), `time` (`AMAZON.TIME`) | «domani alle otto» |
| `ReminderSkipIntent` | — | «a nessuno», «senza promemoria» |
| `AMAZON.NoIntent` | — | Stesso trattamento di `ReminderSkipIntent` |

Il tipo custom **`MemberName`** porta i ruoli di famiglia («mamma», «nonna») che
`AMAZON.FirstName` non conosce, più una sessantina di nomi italiani frequenti.
Sono **suggerimenti, non un elenco chiuso**: un custom slot type restituisce
anche parole che non ci sono, e chi si chiama in un modo fuori elenco viene
riconosciuto lo stesso — il nome vero lo decide `matchMember` confrontando coi
membri reali.

Nessun sample del promemoria comincia per «aggiungi» o «aggiungere»: quelli
sono di `AddItemIntent`, che porta a sua volta uno `AMAZON.SearchQuery`. Due
`SearchQuery` dietro lo stesso verbo sono indistinguibili, e «aggiungi un
promemoria per comprare il pane» finirebbe **in lista della spesa** come un
articolo con quel nome.

Vale anche qui la regola delle **due forme, imperativa e infinitiva**:
`ricordami di {task}` e `ricordarmi di {task}`.

⚠️ **Solo italiano.** I testi vocali esistono in `SPEECH` anche in inglese, per
non lasciare mezza tabella vuota, ma `interaction-model-en-GB.json` **non** ha
questi intent: sulla locale inglese la skill continua a fare solo la spesa. Se
un giorno serve, i sample inglesi sono l'unica cosa da scrivere — il backend è
già in parità.

## Categoria degli articoli

Gli articoli dettati non nascono più senza categoria: `guessCategory` in
`alexa.js` riconosce la parola dell'alimento e assegna una delle dieci
categorie di `KBGroceryCategory` (iOS) / `SUGGESTED` (Spesa.jsx). Le stringhe
sono l'italiano salvato su Firestore, che i client traducono per la UI: vanno
scritte identiche o l'articolo finisce in una categoria che nessuna schermata
mostra.

Il confronto passa da una radice grezza — via la vocale finale, che è quella
che cambia al plurale — così «pomodoro» e «pomodori» cadono insieme senza
portarsi dietro uno stemmer. «Surgelati» ha la precedenza sulle altre: è una
qualifica, non una categoria alla pari, e «piselli surgelati» sta nel banco del
surgelato, non con la verdura fresca.

Quando non riconosce lascia `null`, che i client mostrano come «Altro». È
deliberato: una categoria sbagliata è peggio di nessuna categoria, perché
l'articolo finisce dove non lo si cerca.

Perché una tabella e non l'AI: la risposta deve stare negli 8 secondi che Alexa
concede, e una chiamata al modello aggiungerebbe latenza, costo e il gating per
piano — l'AI è una feature a pagamento, mentre la spesa a voce non lo è. Per
allargare la copertura basta aggiungere parole a `CATEGORY_KEYWORDS`.

## Manutenzione

La TTL policy su `alexaPairings.expiresAt` è **attiva** (stato `ACTIVE`), come
quella di `analyticsEvents`: i codici scaduti spariscono da soli, senza
scheduler e senza codice da mantenere. Si verifica con

```bash
gcloud firestore fields ttls list --project=kidbox-42cd7 --database='(default)'
```

Vive in GCP, non nel repo: se un giorno si ricrea il progetto va rimessa a
mano.

## Cosa NON è stato verificato

Il codice è lintato e le funzioni pure di testo hanno i loro test, ma il giro
completo — Echo → Amazon → `alexaSkill` → Firestore → app — si può provare solo
dopo che la skill esiste in console. La verifica della firma in particolare non
si può esercitare in locale: Amazon firma con la sua chiave.

## Vetrina della skill (Distribution → Skill Preview)

Puramente cosmetica finché la skill resta in *Development*: Amazon non la
verifica e non cambia nulla del funzionamento. Ma è quello che si legge nella
scheda dentro l'app Alexa, e coi valori del template si legge «Alexa apri ciao
mondo» sotto il nome KidBox, che confonde.

Locale **Italiano (IT)**:

| Campo | Valore |
| --- | --- |
| Public Name | KidBox |
| One Sentence Description | La spesa e i promemoria di famiglia a voce: quello che detti ad Alexa compare subito nell'app KidBox su tutti i dispositivi. |
| Example Phrase 1 | Alexa, apri mio box |
| Example Phrase 2 | Alexa, chiedi a mio box di aggiungere il latte |
| Example Phrase 3 | Alexa, chiedi a mio box di ricordarmi di chiamare la scuola |
| Small Skill Icon | `internal/alexa/icons/kidbox-108.png` |
| Large Skill Icon | `internal/alexa/icons/kidbox-512.png` |
| Category | Shopping |
| Keywords | spesa, lista della spesa, promemoria, cose da fare, famiglia, supermercato, casa, organizzazione, kidbox |
| Privacy Policy URL | https://kidboxapp.com/privacy.html |
| Terms of Use URL | https://kidboxapp.com/terms.html |

Detailed Description (2886/4000; rispetta i requisiti della console —
prerequisiti, dispositivi, passi numerati, nomi dei pulsanti come li vede
l'utente, e la parola «skill» **non** tradotta):

```
KidBox è l'app per organizzare la famiglia: spesa, calendario, documenti, salute e altro ancora. Questa skill porta su Alexa la lista della spesa e i promemoria di KidBox.

Quello che detti compare subito nell'app KidBox su iPhone, Android e web, e gli altri membri della famiglia ricevono la notifica come se l'avessi scritto a mano. Non è una lista separata da tenere allineata: è la stessa lista.

COSA PUOI FARE CON LA LISTA DELLA SPESA
- Aggiungere un articolo: "Alexa, chiedi a mio box di aggiungere il latte"
- Sapere cosa manca: "Alexa, chiedi a mio box cosa manca"
- Togliere un articolo: "Alexa, chiedi a mio box di togliere il pane"
- Segnare un articolo come comprato: "Alexa, chiedi a mio box di segnare le uova come comprate"

COSA PUOI FARE CON I PROMEMORIA
- Creare un promemoria: "Alexa, chiedi a mio box di ricordarmi di chiamare la scuola"
- Alexa poi chiede a chi assegnarlo, e tu rispondi con il nome di un membro della famiglia, oppure "a me", oppure "a nessuno".
- Poi chiede per quando, e tu rispondi "domani alle otto", "giovedì", "fra due ore", oppure "senza promemoria" se non vuoi che suoni.
- Puoi anche dire tutto in una frase sola: "Alexa, chiedi a mio box di ricordarmi di pagare la mensa domani alle otto"
- Il promemoria diventa una voce nell'elenco delle cose da fare dell'app KidBox, e la notifica arriva sul telefono all'ora che hai indicato.

E IN QUALSIASI MOMENTO
- Aprire la skill e poi parlare: "Alexa, apri mio box"

REQUISITI
- Un account KidBox gratuito. L'app è disponibile per iPhone e Android, e da browser su https://kidboxapp.com
- Una connessione a internet.
- Qualsiasi dispositivo con Alexa. Non serve hardware particolare e non serve uno schermo: la skill risponde solo a voce.

COME INIZIARE
1. Installa KidBox e crea un account, oppure entra nella famiglia di chi ti ha invitato.
2. Nell'app apri Impostazioni e poi Alexa.
3. Tocca "Genera codice di collegamento": compare un codice di sei cifre, valido dieci minuti.
4. Di' "Alexa, chiedi a mio box di collegarsi con" seguito dalle sei cifre.
5. Da quel momento puoi dettare la lista della spesa e i promemoria. Non devi inserire password da nessuna parte.

Il collegamento si fa una volta sola e resta valido. Se in casa i dispositivi Alexa sono registrati sullo stesso account Amazon, basta che lo faccia una persona sola: gli altri membri della famiglia possono parlare senza ripetere il collegamento. Puoi annullarlo quando vuoi da Impostazioni, Alexa, Scollega Alexa.

NOTE
- Questa skill non compra nulla e non aggiunge articoli al carrello Amazon. Scrive soltanto nella lista della spesa e nell'elenco delle cose da fare dell'app KidBox.
- Questa skill non legge e non modifica la lista della spesa integrata di Alexa, né i promemoria, le sveglie e i timer di Alexa: restano tutti separati e continuano a funzionare come prima.
- La funzionalità è disponibile in italiano.
```

Le due righe finali sulle NOTE non sono richieste dalle regole: servono a
evitare che un revisore scambi una «lista della spesa» per una skill con
**Shopping Actions** — quelle che comprano su Amazon — che richiederebbero un
disclaimer obbligatorio che a noi non si applica.

Le frasi d'esempio **devono contenere il nome di invocazione**: se un domani
cambia, vanno riallineate anche qui, oltre che nel catalogo iOS e in
`strings_settings.xml` per le quattro lingue Android.

Le icone sono generate dall'icona dell'app iOS
(`Assets.xcassets/AppIcon.appiconset/1024.png`) e appiattite su bianco: Amazon
rifiuta i PNG con canale alpha.

### Privacy & Compliance

Pagina separata, obbligatoria per salvare:

| Domanda | Risposta |
| --- | --- |
| Acquisti o pagamenti reali | No |
| Raccoglie informazioni personali | **Sì** |
| Rivolta a bambini sotto i 13 anni | No |
| Contiene pubblicità | No |
| Export compliance | spuntata |

Il «Sì» sui dati personali è deliberato: la skill memorizza l'associazione fra
identificativo Alexa e account KidBox (`alexaLinks`) e scrive articoli
riconducibili a una persona. Rispondere No sarebbe difendibile solo negando che
quei dati siano personali. Il «Sì» rende obbligatoria la privacy policy, che
esiste già ed è online.

Testing instructions — servono solo in certificazione, ma il campo è
obbligatorio per salvare. In inglese perché i revisori sono internazionali, con
le frasi vocali in italiano fra virgolette:

```
ACCOUNT LINKING
This skill does not use OAuth account linking. Username/password fields are
intentionally left empty. Linking is done with a one-time 6-digit code shown
inside the KidBox app (Settings > Alexa > "Genera codice di collegamento"),
which the user reads out to Alexa. No credentials are ever entered by voice.

HOW TO TEST
1. Install KidBox (iOS or Android) or open https://kidboxapp.com and create a
   free account. No payment is required.
2. In the app go to Impostazioni > Alexa and tap "Genera codice di
   collegamento". A 6-digit code appears, valid for 10 minutes.
3. Say: "Alexa, chiedi a mio box di collegarsi con <the six digits>".
   Alexa confirms the link.
4. Then test the core functionality:
   - "Alexa, chiedi a mio box di aggiungere il latte"
   - "Alexa, chiedi a mio box cosa manca"
   - "Alexa, chiedi a mio box di togliere il latte"
   - "Alexa, apri mio box"
5. Then test the reminder, which is a multi-turn dialogue:
   - Say "Alexa, chiedi a mio box di ricordarmi di chiamare la scuola".
   - Alexa asks who it is for: answer "a me".
   - Alexa asks when: answer "domani alle otto".
   - Alexa confirms. The reminder appears immediately in the KidBox app under
     To-Do, in the list named "Alexa".
   - The date can also be said in one go: "Alexa, chiedi a mio box di
     ricordarmi di pagare la mensa domani alle otto".
   - The push notification is sent at the time you said, not straight away.
     If you want to see it during the review, pick a time a few minutes ahead
     instead of "domani alle otto": due reminders are checked every 5 minutes,
     so the notification arrives within 5 minutes of that time.
6. Items dictated appear in the shopping list inside the KidBox app in real
   time. The link can be removed from Impostazioni > Alexa > "Scollega Alexa".

TRADEMARK / BRAND
"KidBox" is our own product. Proof of rights:
- iOS App Store: https://apps.apple.com/app/id6761055375
- Google Play: https://play.google.com/store/apps/details?id=it.vittorioscocca.kidbox
- Website: https://kidboxapp.com
No third-party trademark or brand is used in this skill.

NOTES
- The skill is available in Italian (it-IT) only.
- No hardware other than an Alexa-enabled device is required.
- The skill does not purchase anything and does not use Alexa Shopping. It
  writes only to the shopping list and the to-do list inside the KidBox app.
- The skill does not read or modify Alexa's own reminders, alarms or timers,
  nor Alexa's built-in shopping list. They all stay separate.
- The skill uses Alexa Personalization only to attribute a dictated item or
  reminder to the recognised speaker, and to let the user say "a me" ("for me")
  when assigning a reminder. It is optional: when the voice is not recognised,
  or the speaker has no voice profile, everything is attributed to the account
  that linked the skill and the rest works the same.
```

Username e Password nella pagina vanno lasciati **vuoti**: servono alle skill
con account linking OAuth, dove il revisore deve poter fare login nel servizio.
Qui non c'è nessuna credenziale da consegnare — è tutto il senso del codice di
accoppiamento.

Sul marchio, la regola dice che i brand name sono ammessi solo provando i
diritti nelle testing instructions. KidBox è nostro, quindi si soddisfa con i
link qui sopra. La clausola sull'uso referenziale (*unofficial*, *fan*, *for*,
*about*) riguarda i marchi altrui e non ci tocca.

Attenzione a non confondere due piani: la **policy** permetterebbe `kid box`
come nome di invocazione, anche di una parola sola, provando i diritti. Il
**riconoscimento vocale** no — e il permesso di Amazon non mette la parola nel
vocabolario dell'ASR italiano. Sono limiti indipendenti, e il secondo non si
aggira con un documento.
