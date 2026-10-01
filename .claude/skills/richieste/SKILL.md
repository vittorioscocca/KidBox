---
name: richieste
description: Richieste di famiglia di KidBox («Chi prende Marco giovedì?») — «Chiedi a qualcuno…» nei to-do, il primo «Ci penso io» che fa nascere il to-do, il link per chi non ha l'app (kidboxapp.com/r), il sollecito, «chi è libero», l'azione AI request_add. Usare quando si tocca una di queste parti su server, iOS, Android, web o landing, quando l'utente dice «la richiesta non arriva», «il link non funziona», «il to-do non è nato», «il sollecito non è partito», o prima di aggiungere un tipo di richiesta nuovo (spesa, evento).
---

Disegno, schema completo e storia delle scelte: `internal/richieste-disegno.md`.
**Leggerlo prima di cambiare qualcosa**: qui ci sono la mappa e le trappole.

## Cosa fa, in una riga per pezzo

| Pezzo | Dove |
|---|---|
| Documento | `families/{id}/requests/{requestId}`: `title`, `dueAt`, `dueHasTime`, `listId`, `recipients`, `expiresAt`, `status` (open → claimed / expired / cancelled), `responses`, `claimedBy`, `todoId`, `external` (`label`, `tokenHash`, `inviteId`, `openedAt`, `answeredAt`), `nudgeAt`/`nudgedAt` |
| Server | `functions/familyRequests.js` (factory `build(deps)`: gli helper delle push arrivano da `index.js`, una sola copia): `respondToRequest` (callable), `requestPublic` (HTTP, `/api/request` sulla landing), `onFamilyRequestCreated`, `onFamilyRequestUpdated`, `expireFamilyRequests` e `nudgeFamilyRequests` (ogni 15 minuti) |
| Pagina pubblica | `KidboxLanding/public/r.html`, link `kidboxapp.com/r?f=…&r=…#t=<token>&k=<segreto invito>` |
| iOS | `Features/FamilyRequests/` (servizio, notifiche, view, `FamilyRequestAvailability`), riga nell'editor `TodoEditView`, card in `HomeView`, foglio in `RootHostView`, azione AI in `PlanningAIActionBlock` |
| Android | `data/remote/requests/FamilyRequestRemoteStore.kt`, `ui/screens/requests/`, rotta `family_request/{familyId}/{requestId}?answer=`, `FamilyRequestActionReceiver`, azione AI in `PlanningActionExecutor` |
| Web | `services/requests.js`, `components/FamilyRequests.jsx`, modale del to-do, Home (`/?richiesta=&famiglia=` dalla push), `aiActions.js` |
| Landing | `strumenti/to-do` (passo «Assegna o chiedi» + FAQ), cella in home, `strumenti/assistente-ai`, articolo `chiedere-aiuto-in-famiglia` |

Piano: **Free** (è crescita, non una funzione da vendere). Testo **in chiaro**
come i to-do: niente chiave di famiglia, così la push può mostrarlo.

## Le regole del server (non spostarle nei client)

- **Il client crea e ritira, nient'altro.** Le rules (in `firestore.rules`,
  `requests` escluso dal wildcard) vietano alla creazione `responses`,
  `claimedBy`, `todoId`, `nudgeAt`… e permettono solo `open → cancelled` a chi ha
  chiesto. Risposte, to-do, scadenza e sollecito li scrive il server.
- **«Il primo Io vince» è una transazione** (`applyResponse`), condivisa da
  membri (callable) e link (HTTP). Due «Io» simultanei → un solo to-do,
  stesso vincitore per entrambi (provato in emulatore).
- **Il to-do nato ha `updatedBy` = chi ha risposto**: così `notifyTodoAssigned`
  (che esce se `assignedTo === updatedBy`) non gli manda «Nuovo To-Do» per la
  cosa che si è appena preso.
- **`listId` sempre valido.** Il server verifica la lista in transazione: se è
  sparita usa la più recente, se non ce n'è nessuna ne crea una «To-do». Un
  to-do senza lista su Android non si vede (foreign key di Room).
- **Preso da fuori**: `assignedTo: ""` + `assignedExternalName`. I tre client
  mostrano «Anna (fuori dall'app)» **solo se `assignedTo` è vuoto**, così una
  riassegnazione a un membro vince senza dover cancellare il campo. Android lo
  tiene in Room (versione 50).

## Il link per chi non ha l'app

- Il **token sta nel frammento** (`#t=`), che non arriva mai al server né alle
  anteprime di WhatsApp; la pagina lo manda nel **corpo** della POST. Sul
  documento c'è solo `tokenHash` (SHA-256). 404 identico per «non esiste»,
  «niente link», «token sbagliato».
- L'invito alla famiglia viaggia nello stesso frammento (`&k=`, stesso nome di
  `/join`): «Entra nella famiglia» costruisce il `/join` di sempre.
- `/r` **non** è negli Universal Link, e da lì `/join` è sullo stesso dominio:
  iOS non apre l'app, chi ha KidBox vede la pagina di download. Accettato.
- Il link si può rimandare solo dal telefono di chi l'ha creato (salvato in
  `UserDefaults` / `SharedPreferences` / `localStorage`): il server ha solo
  l'impronta.

## Notifiche

- `type` `family_request` (nuova e sollecito) e `family_request_resolved`
  (esito a chi ha chiesto). iOS: `aps.category = "FAMILY_REQUEST"` con «Ci penso
  io» (`.foreground`, apre il foglio con l'esito) e «Non posso» (background, se
  fallisce una notifica locale di riprova). Android: i bottoni **solo con l'app
  aperta** (ad app chiusa la disegna il sistema dal payload ibrido); il tap apre
  la richiesta.
- **Sollecito**: una volta sola a chi non ha risposto, alle 19:00 o 3 ore dopo
  se la richiesta è nata dalle 16; mai fra le 21:30 e le 8:00; per le richieste
  che scadono presto a metà del tempo. `nudgeAt` lo scrive il trigger di
  creazione (vale anche per le build già pubblicate) e lo scheduler **lo
  cancella** dopo l'uso: messo a `null` verrebbe ripescato da `nudgeAt <= now`.
  Indice `requests (status, nudgeAt)`.

## «Chi è libero» e l'AI

- Gli **eventi del calendario non dicono chi partecipa**: si mostrano come
  contesto non attribuito; accanto ai membri solo i loro to-do assegnati, non
  fatti, con orario, ±1 ora. Scelta dell'utente: non attribuire per `createdBy`.
- Azione AI `request_add` (`askMembers`, `askOutside`, `outsideLabel`): il client
  traduce i nomi in account e dice quelli che non trova. Se manca l'ora,
  l'assistente la chiede. Provato su Haiku; vedi `/ai` per il fuso nel prompt.

## Provare senza disturbare nessuno

- Famiglia `ZZZ-TEST-REQ` con membri senza dispositivi: si arriva fino all'invio
  («nessun destinatario con notifiche attive») senza notificare nessuno. Il
  documento si crea via REST con il token Owner.
- Sul telefono vero (vedi `/porting-android`): richieste con **solo** il link e
  invito spento non avvisano nessuno; ritirarle subito. Una richiesta a un
  membro che dice «Non posso» fa partire «Nessuno può» a **chi ha chiesto**.
- La pagina `/r` si prova con `curl` su `/api/request` (`preview` / `respond`)
  e nel browser; la web app logged-in con un banco Vite e dati finti (alias su
  `AuthContext`, `useFamilyMembers`, `services/requests`).
- Pulizia: `scripts/firestore-delete-doc.js` per le richieste; famiglia e
  membri di test li cancella l'utente.

## Resta aperto

- Pulizia delle richieste dopo 90 giorni (oggi restano; spariscono con la
  famiglia, `requests` è in `FAMILY_SUBCOLLECTIONS`).
- Push silenziosa che toglie la notifica agli altri quando qualcuno la prende.
- Tipi `grocery` ed `event` (oggi solo `kind: "todo"`).
- Previsione da registrare in `/auto-miglioramento`: 4 settimane dopo la
  release, ≥10 richieste con link e ≥2 famiglie passate a 2+ membri da lì;
  falsificata sotto 5 richieste con link.
