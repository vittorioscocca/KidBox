# Spazio Squadra — disegno

> Stato al 02/11/2026: **solo disegno**, niente di costruito. Nasce dal
> riscontro sulla pagina `/squadre`: nelle scuole calcio i genitori si
> aggiornano dal gruppo WhatsApp più che dal calendario. Prima di scrivere
> codice c'è la fase 0 (sentire la scuola).

## Cosa risolve

Nel gruppo WhatsApp della squadra convivono due cose diverse:

1. **Avvisi della società**: campo cambiato, allenamento annullato, ritrovo
   anticipato. Pochi, importanti, e annegati fra foto, auguri e vocali.
2. **Chiacchiere fra genitori**: foto, complimenti, «chi ha visto la borraccia».

E sopra a tutto l'allenatore raccoglie a mano **chi c'è sabato**, contando le
risposte nel gruppo.

Lo spazio Squadra prende **solo la prima cosa e le presenze**. Le chiacchiere
restano su WhatsApp.

**Cosa non è:** non è una chat di gruppo. Nessun genitore scrive agli altri
genitori dentro KidBox. Il perché è nella sezione «Perché non una chat».

## Perché non una chat

- **Effetto rete:** una chat serve solo se ci sono tutti i 20 genitori. Se ne
  mancano tre, l'allenatore scrive anche su WhatsApp, KidBox diventa un
  doppione e la squadra lo abbandona. Avvisi e convocazioni, invece, valgono
  anche con metà squadra dentro: chi non ha l'app li apre dal link.
- **Cifratura:** la chat di famiglia è cifrata con la chiave della famiglia
  (`/cifratura`). Un gruppo fra famiglie diverse vorrebbe una chiave sua con
  ingressi e uscite. Lo spazio Squadra **non è cifrato** e lo dice: contiene
  avvisi pubblicati dalla società, come una bacheca.
- **Store e minori:** contenuti scritti fra sconosciuti obbligano a
  segnalazione, blocco e moderazione (App Store 1.2, Play UGC). Qui scrive solo
  lo staff e i genitori rispondono a una domanda chiusa: niente contenuti
  liberi fra sconosciuti.
- **Concorrenza:** Spond e TeamSnap fanno già chat, eventi e presenze, gratis
  o quasi. Su quel terreno partiamo da dietro. Il nostro vantaggio è a casa:
  la convocazione diventa «Chi porta Marco?» (`/richieste`), e Spond quello non
  lo fa.

## I quattro pezzi

1. **Entrare con un QR.** La società stampa o manda il QR (o il link
   `kidboxapp.com/s/<codice>`). Il genitore lo apre, sceglie quale figlio gioca
   in quella squadra, e la famiglia è dentro.
2. **Calendario automatico.** Entrando, la famiglia riceve il calendario della
   squadra senza il passaggio «copia il link ICS» della pagina di oggi.
3. **Bacheca avvisi con push.** Solo lo staff pubblica. Ogni avviso arriva
   come notifica a tutta la famiglia (non solo al genitore che ha scansionato).
4. **Convocazioni.** Lo staff convoca per un evento; ogni famiglia risponde
   «Ci sarà / Non ci sarà» per il suo bambino; lo staff vede il conteggio. Dalla
   convocazione, in casa, un tocco apre «Chi porta Marco?» già compilata.

## Chi vede cosa

| Chi | Vede | Scrive |
|---|---|---|
| Staff (allenatore, dirigente) | avvisi, convocazioni, **nome del bambino come l'ha scritto la famiglia** e la sua risposta, numero di famiglie dentro | avvisi, convocazioni, calendario |
| Famiglia iscritta (tutti i membri) | avvisi, convocazioni, calendario | solo la risposta alla convocazione del **suo** bambino |
| Chi ha il link e non l'app | avvisi recenti e prossimi eventi, in sola lettura | nulla (fase 1) |
| Altre famiglie della squadra | **niente** delle altre famiglie | — |

Lo staff non vede email, cognomi, membri della famiglia o altri dati: solo il
nome che la famiglia sceglie di mostrare («Marco», «Marco R.»). Così la
promessa della pagina, «nessun dato dei ragazzi da consegnare», resta vera:
la società non consegna niente, le famiglie mostrano un nome.

## Lo schema

La scelta principale: **gli avvisi e le convocazioni si copiano dentro ogni
famiglia** (fan-out dal server). I client li leggono da
`families/{familyId}/…` con le regole, la cache offline e i listener che hanno
già. Una squadra ha circa 20 famiglie: un avviso costa circa 20 scritture,
niente.

L'alternativa (i client leggono `teams/{teamId}/posts`) costringerebbe le
rules a sapere quali uid seguono la squadra. Bisognerebbe tenere un elenco di
follower aggiornato a ogni ingresso e uscita di membri dalla famiglia: è la
stessa classe di trappola dell'indice membership
([[project_indice_membership]]).

### Lato squadra (scritto dallo staff via function, letto dallo staff)

`teams/{teamId}`

| Campo | Note |
|---|---|
| `name` | «Pulcini 2017 — ASD Esempio» |
| `club` | nome della società, per la pagina pubblica |
| `staff` | [uid]. Nella fase 1 lo scriviamo noi dalla console. |
| `icsUrl` | il Google Calendar della squadra, se c'è (fase 1). |
| `joinCodeHash` | hash del codice del QR; il codice si può rigenerare (QR finito nel posto sbagliato). |
| `familyCount` | contatore, scritto dal server. |
| `createdAt`, `updatedAt` | |

`teams/{teamId}/posts/{postId}`: `text`, `createdBy`, `createdAt`,
`pinnedUntil?`. Testo semplice, tetto 1000 caratteri.

`teams/{teamId}/callups/{callupId}`: `eventRef` (id dell'occorrenza del feed,
oppure titolo e data liberi), `title`, `startsAt`, `meetAt?`, `place?`,
`deadlineAt`, `responses: {<familyId>_<childKey>: {name, answer, at}}`
(scritto solo dal server).

`teams/{teamId}/families/{familyId}`: `children: [{childKey, displayName}]`,
`joinedAt`, `joinedBy` (uid). Solo lo staff legge, solo il server scrive.

### Lato famiglia (letto dai membri con le regole di oggi)

`families/{familyId}/teamLinks/{teamId}`: `name`, `club`, `children`,
`feedId` (il `calendarFeeds` creato all'ingresso), `muted`. Scritto dal server.

`families/{familyId}/teamPosts/{postId}`: copia dell'avviso più `teamId`.
Scritto dal server.

`families/{familyId}/teamCallups/{callupId}`: copia della convocazione con le
sole righe dei bambini di questa famiglia: `rows: {<childKey>: {answer, at,
by}}`. Il client scrive **solo** `rows.<childKey>.answer|at|by`, e un trigger
riporta la risposta in `teams/{t}/callups/{c}.responses`.

### Rules

- `teams/**`: lettura solo se `request.auth.uid in staff`; scrittura nessuna
  dal client (tutto via callable).
- Nel blocco generico `families/{familyId}/{coll}/…`: escludere dalla
  scrittura `teamLinks` e `teamPosts`, e dare a `teamCallups` una regola sua
  che permette solo l'update delle chiavi di `rows` (stessa forma di
  `requests`). Vedi `/rules-change`.

## Le strade lato server (`functions/teams.js`)

- `joinTeam` (callable): `{code, familyId, children:[{childKey, displayName}]}`.
  Verifica il codice e la membership, scrive `teams/{t}/families/{f}` e
  `families/{f}/teamLinks/{t}`, crea il `calendarFeeds` della squadra
  riusando la stessa funzione di `saveCalendarFeed` (stessi controlli
  sull'URL), copia gli ultimi 10 avvisi e le convocazioni aperte.
- `leaveTeam` (callable): l'inverso, e cancella anche feed, avvisi e
  convocazioni copiate.
- `publishTeamPost` / `createCallup` (callable, solo staff): scrive lato
  squadra, fa il fan-out in batch a tutte le famiglie e manda le push.
- `onTeamCallupAnswer` (trigger su `families/{f}/teamCallups/{c}`): riporta la
  risposta lato squadra. Un trigger, non una callable, così funziona anche
  offline.
- `teamPublic` (HTTP dietro `/api/team`): per la pagina `/s` restituisce nome,
  società, ultimi 5 avvisi e prossimi 5 eventi. **Nessun** nome di bambino.
- Push: un tipo nuovo in `notificationsI18n.js` (avviso e convocazione), con
  deep link alla scheda Squadra. Vedi `/notifiche`; in casa rispetta `muted`.

## La pagina `/s/<codice>` (landing)

Come `/r`: non rivendicata dagli Universal Link, si apre sempre nel browser.

- Chi ha KidBox: bottone **«Apri in KidBox»** (`kidbox://team?c=<codice>`)
  che porta alla scelta del figlio.
- Chi non ce l'ha: avvisi e prossimi eventi in sola lettura, poi
  «Scarica KidBox per ricevere gli avvisi e rispondere alle convocazioni».
  È l'invito con un motivo, come `/r`.
- Il codice va nel **frammento** (`#c=`) per non finire nei log e nel
  referrer, come il token di `/r`. Il percorso `/s/<x>` resta solo per la
  leggibilità del QR stampato: la pagina lo sposta nel frammento al primo
  caricamento.
- Niente statistiche di terze parti, quindi nessun banner.

## I client

- **iOS** (fase 1), poi Android e web (fase 2): in Impostazioni → «Squadre»
  ci sono «Entra con un QR», l'elenco delle squadre, il silenzioso e l'uscita.
  Scheda della squadra: avvisi in alto, poi le convocazioni aperte con i due
  bottoni, poi i prossimi eventi. In Home, un riquadro solo quando c'è una
  convocazione senza risposta.
- Dalla convocazione: **«Chi porta Marco?»** apre l'editor della richiesta
  con titolo, data e luogo già scritti (`/richieste`).
- **Staff:** nella fase 1 pubblica dalla **web app** (`app.kidboxapp.com/squadra`),
  perché l'allenatore lavora dal telefono ma non deve installare niente di
  nuovo se ha già il browser. In una fase successiva anche dall'app.
- Stringhe nelle quattro lingue (`/localizzazione`), anche se il pilota è
  italiano.

## Piano e prezzo

Tutto **Free**, per la società e per le famiglie: la pagina `/squadre` lo
promette («Gratis per la società») e il valore per noi sono le famiglie che
entrano, non i soldi della squadra. Nessun presidio `/gating-pro`.

## Fasi

0. **Validazione (costo zero).** Due domande alla scuola che ha dato il
   riscontro:
   - l'allenatore pubblicherebbe gli avvisi lì invece che nel gruppo?
   - oggi le presenze come le raccoglie?

   Se la seconda risposta è «a mano, ed è un incubo», le convocazioni vengono
   prima degli avvisi.
1. **Pilota, una squadra.** Squadra creata da noi dalla console, server, rules,
   pagina `/s`, web app staff (avvisi e convocazioni), iOS genitori.
2. **Android e web app genitori**, «Chi porta?» dalla convocazione.
3. **Self-service:** la società crea la squadra da sola e lo staff la gestisce
   dall'app. Solo se il pilota passa la scommessa qui sotto.

## La scommessa (da mettere nel registro di `/auto-miglioramento`)

Pilota con una squadra di circa 20 famiglie, quattro settimane dal QR:

- almeno il **60%** delle famiglie entra dal QR;
- almeno il **50%** delle risposte alle convocazioni arriva da KidBox e non dal
  gruppo;
- almeno **3** famiglie della squadra arrivano a 2+ membri veri (la stella
  polare, [[project_numeri_che_contano]]).

Se la prima regge e la seconda no, l'allenatore non è passato: il pezzo da
rivedere è il lato staff, non quello dei genitori.

## Cosa si misura

Eventi GA4: `team_joined` (sorgente qr/link), `team_post_opened`,
`team_callup_answered` (app/web), `team_request_from_callup`. Lato server, su
`teams/{t}` i contatori che la console può mostrare senza leggere le famiglie.

## Domande aperte per l'utente

- Lo staff ha bisogno di un account KidBox. Oggi l'account nasce con
  l'onboarding di famiglia: va bene che l'allenatore abbia una sua famiglia
  (spesso è anche un genitore), o serve un account «solo staff»?
- Un bambino che cambia squadra a metà stagione: basta uscire e rientrare,
  oppure serve lo storico?
- La pagina `/squadre` va riscritta («Nessuna app per l'allenatore» non è più
  vero se pubblica avvisi): ora o dopo il pilota?
