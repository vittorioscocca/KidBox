# Utenti attivi — definizione e schema eventi

Stato: implementato e in produzione (server, console, client iOS e Android).
Manca solo il rilascio delle app sugli store. Vedi §9 per le fasi.

Documento **interno**: non sta in `docs/`, che è pubblicata da GitHub Pages come
sito legale (privacy, termini, eliminazione dati, supporto).

Oggi KidBox non ha nessuna instrumentazione analytics: nessun `logEvent`, nessun SDK
Analytics linkato, `IS_ANALYTICS_ENABLED = false` nel progetto Firebase.
Questo documento definisce cosa registrare e come misurarlo, senza SDK di terze parti.

---

## 1. Definizione di utente attivo

> Un utente è **attivo** in un giorno se compie almeno una **azione di valore**:
> crea / modifica / completa un contenuto familiare, **oppure recupera
> deliberatamente un contenuto** (documento, password, posizione), oppure
> interagisce con l'AI.

Non contano come attività: apertura app, apertura Home, visualizzazione widget,
ricezione notifica.

Due precisazioni che guidano tutto il resto dello schema.

**La lettura è valore, non contorno.** Una volta caricato un documento, il valore di
KidBox è che sia a disposizione della famiglia a portata di click, senza doverlo
cercare o chiedere. Una definizione basata sulle sole scritture misurerebbe
l'onboarding, non il prodotto.

**Il soggetto è anche la famiglia, non solo l'utente.** Una famiglia con un solo
membro attivo è a rischio churn anche se il suo DAU è stabile. Ogni evento deve
portare `familyId`, altrimenti le metriche di famiglia non sono calcolabili a
posteriori.

---

## 2. Perché non Firebase Analytics

L'SDK sarebbe quasi gratis da attivare (`firebase-ios-sdk` 12.10.0 e
`GoogleAppMeasurement` sono già in `Package.resolved`, manca solo il product linkato).
Si è scelto di non usarlo:

- Ciò che dà gratis (`session_start`, `screen_view`) è esattamente la definizione di
  attivo che abbiamo scartato. Gli eventi di valore andrebbero scritti a mano comunque.
- Le metriche di famiglia richiederebbero export BigQuery e query custom: Firebase
  darebbe solo l'ingestion.
- KidBox tratta documenti d'identità, password, dati sanitari e posizione di minori.
  Un SDK di terze parti aggiunge consenso, ATT, privacy manifest e un responsabile
  esterno del trattamento. Restando su Firestore i dati non escono dal perimetro
  attuale.

Il costo di questa scelta: una scrittura Firestore per evento (Firebase ingerisce
gratis). Alla scala attuale è dentro il free tier; è il numero da monitorare se cresce.

---

## 3. Dove finiscono gli eventi

Collection **top-level `analyticsEvents`**. Due vincoli obbligatori:

- **Non** `families/{familyId}/events`: il nome è già usato per gli eventi famiglia.
- **Non** sotto `families/{familyId}` in generale: `firestore.rules:62` concede
  `read` su tutto il ramo a ogni membro. Il log delle letture diventerebbe un
  registro di chi-ha-guardato-cosa consultabile dal partner.

```
/analyticsEvents/{autoId}     ← append-only, TTL 90gg, client: create-only
/metrics/{YYYY-MM-DD}         ← rollup notturni, letti dalla console
```

### TTL — la policy va su `expiresAt`, mai su `ts`

Firestore cancella i documenti il cui campo TTL è **nel passato**. Il campo è la
data di *morte*, non di nascita: una policy puntata su `ts` (istante di creazione,
quindi già passato alla scrittura) cancellerebbe **ogni evento entro poche ore
dalla scrittura, in silenzio**.

`logEvent()` scrive quindi `expiresAt = now + 90gg` (`RETENTION_DAYS`). La policy va
creata dalla console Firebase — Firestore → TTL → collection `analyticsEvents`,
campo **`expiresAt`** — perché non è codice e non è deployabile.

90 giorni bastano: gli eventi grezzi servono solo a calcolare i rollup, che sono
l'artefatto durevole e non scadono. La finestra serve a ricalcolare all'indietro se
la definizione cambia o si trova un bug.

Rules da aggiungere:

```
match /analyticsEvents/{id} {
  allow create: if isSignedIn()
    && request.resource.data.uid == request.auth.uid
    && request.resource.data.keys().hasOnly(
         ['name','uid','familyId','feature','ts','expiresAt','props']);
  allow read, update, delete: if false;   // solo Admin SDK
}
```

Il client scrive e non rilegge mai. Console e rollup passano dall'Admin SDK.

---

## 4. Regole di privacy (vincolanti)

### Cancellazione account — `purgeAnalyticsForUid()`

`deleteAccount` (`functions/index.js`) rimuove **tutte** le tracce analytics di un
utente. Non basta cancellare `analyticsEvents`: i rollup in `metrics/` contengono
l'array `uids` (serve per le finestre WAU/MAU) e **non hanno TTL**, quindi l'uid vi
resterebbe per sempre. `purgeAnalyticsForUid()` fa entrambe le cose: elimina gli
eventi (query per `uid`) e toglie l'uid dai rollup (`array-contains` + `arrayRemove`).

I conteggi aggregati (`dau`, `byFeature`, …) **non** vengono ricalcolati: sono già
storicizzati e non identificano nessuno. Si rimuove solo l'identificatore.

Questo è ciò che rende vera la frase già presente nella privacy policy — *"alla
cancellazione dell'account tutti i dati associati vengono eliminati in modo
permanente"*. Senza, sarebbe falsa.


**Registra la forma dell'azione, mai l'oggetto.** `feature: "wallet"` sì;
`documentId`, titolo, nome file, o qualunque cosa permetta di ricostruire *quale*
documento ha aperto chi, no. Le domande che abbiamo sono aggregate: non si perde
nulla di analitico e si evita di costruire un registro di sorveglianza interno alla
famiglia dentro il proprio Firestore.

Vale a maggior ragione per `passwords` (E2E, cfr. `memberKeyBackups`) e `health`.

Nessun free text, nessun contenuto utente, nessuna coordinata GPS in `props`.
`daysSinceUpload` va a bucket (`0`, `1-7`, `8-30`, `31-180`, `180+`), non esatto:
il valore esatto è quasi un identificatore del documento.

---

## 5. Schema eventi

Pochi eventi generici con proprietà, **non** un evento per feature: con 25 feature un
evento ciascuna diventa ingestibile in tre mesi.

`feature` ∈ `todo | grocery | shoppingList | wallet | documents | passwords | health |
travel | vehicles | pets | note | expenses | calendar | photoVideo | wiki | homeItems |
chat | familyLocation`

### Campi comuni (ogni evento)

| Campo | Tipo | Note |
|---|---|---|
| `name` | string | nome evento |
| `uid` | string | utente |
| `familyId` | string | **obbligatorio** — senza, niente metriche famiglia |
| `feature` | string | vedi sopra |
| `ts` | timestamp | server time |
| `props` | map | specifiche dell'evento |

### Eventi

| Evento | Origine | `props` |
|---|---|---|
| `content_created` | trigger | `source`: manual \| ai \| import \| shareExt |
| `content_updated` | trigger | — |
| `content_completed` | trigger | — |
| `content_retrieved` | **client** | `uploaderIsSelf`, `entryPoint`, `daysSinceUpload`, `count` |
| `ai_interaction` | callable | `surface`, `actionType`, `accepted` |
| `family_member_joined` | trigger ✅ | `role` — **persistente** (senza `expiresAt`, non scade a 90gg) |
| `session_start` | client | `entryPoint`: icon \| widget \| notification \| dynamicIsland \| shareExt |

`session_start` si registra ma **non** conta per il DAU: serve come denominatore per
sapere quanti aprono senza fare nulla.

### `content_retrieved` — l'evento centrale

Il conteggio grezzo delle letture non prova la tesi del prodotto: sei documenti aperti
per trovarne uno sono sei letture, ma sono il "doverlo cercare" che il prodotto doveva
eliminare. Le proprietà servono a distinguere il recupero riuscito dal brancolare:

- **`uploaderIsSelf: false` → cross-member read.** È la metrica più importante che
  abbiamo: leggo ciò che ha caricato un altro membro, senza averglielo chiesto. È la
  dimostrazione diretta del valore di condivisione. Una lettura del proprio contenuto
  è solo un archivio personale.
- **`entryPoint`** (`search | widget | home | list`) → dice se è "a portata di click".
- **`daysSinceUpload`** → un contenuto caricato mesi fa e ancora letto prova che
  l'archivio ha valore duraturo. Miglior predittore di retention.

**Batching obbligatorio.** Le letture sono l'evento più frequente dell'app: una
scrittura Firestore ciascuna costa più del valore. Accumulare in memoria durante la
sessione, un solo flush alla chiusura con `count` aggregato per combinazione di props.

---

## 6. Da dove arrivano — copertura

### Trigger analytics dedicati — `functions/analytics.js` ✅ implementato

Scelta rivista in fase di implementazione. L'ipotesi iniziale era agganciare un
`logEvent()` dentro gli 11 trigger di notifica già esistenti. Si è preferito un
**modulo separato con trigger propri**, per tre motivi:

- I trigger di notifica sono pieni di **early return** (uid mancante, nessun
  destinatario, solo il creatore in famiglia). Un `logEvent` agganciato lì dentro
  verrebbe saltato proprio nei casi limite — es. famiglia di una persona sola.
- Un bug nell'analytics non deve poter impedire una notifica. Moduli separati =
  nessun rischio sul codice esistente.
- Un **factory su tabella** copre 15 collection in ~190 righe, contro 11 patch a
  mano. Aggiungere una feature = aggiungere una riga a `TRACKED`.

Costo: un'invocazione in più per scrittura (Firestore ammette più trigger sullo
stesso path). Trascurabile a questa scala — 2M invocazioni/mese nel free tier.

Copertura (tutte `families/{familyId}/…`, region `europe-west1`):

| Collection | Feature | Completamento |
|---|---|---|
| `documents` | documents | |
| `chatMessages` | chat | |
| `photos` | photoVideo | |
| `medicalVisits` | health | |
| `todos` | todo | `isDone` |
| `groceries` | grocery | `isPurchased` (attore: `purchasedBy`) |
| `notes` | note | |
| `calendarEvents` | calendar | |
| `expenses` | expenses | |
| `walletTickets` | wallet | |
| `passwords` | passwords | |
| `vehicles` | vehicles | |
| `pets` | pets | |
| `homeItems` | homeItems | |
| `trips` | travel | |

Le ultime cinque erano la fase 6: il factory le assorbe subito.

**Convenzione uid**: `createdBy` / `updatedBy` è uniforme nel data model;
`expenses` usa `createdByUid`. `resolveUid()` gestisce la catena di fallback.

**Fuori copertura**: hard e soft delete non sono azioni di valore (`classify()`
ritorna null). `geofenceEvents` è escluso: è generato dal sistema, non dall'utente.

### `family_member_joined` — crescita, non attività

`analyticsFamilyMemberJoined` (`onDocumentCreated` su `families/{f}/members/{uid}`)
scrive l'evento per ogni membro che **non** è l'`ownerUid` della famiglia. È il
segnale di intento di condivisione: chi invita ha già deciso che l'app vale per la
famiglia — non serve misurare se poi l'invitato la usa.

- **Confronto con `ownerUid`, non conteggio membri**: un conteggio con due join
  quasi simultanei ha una race; il campo owner è stabile e atomico.
- **Persistente**: `logEvent({persistent: true})` omette `expiresAt`, la TTL policy
  ignora i doc senza quel campo. Evento di stato: interessa anche fra un anno.
- **Fuori da `VALUE_EVENTS`**: non conta per il DAU. Nel rollup finisce in
  `membersJoined` / `familiesGrown`; la console somma gli ultimi 28 giorni
  (card "Famiglie attive").
- **Rientri**: uscire dalla famiglia è hard delete del doc membro, quindi un
  rientro riconta. Voluto; dedup a posteriori su `familyId`+`uid` se mai servirà.

### Callable ✅ `askAI`

`askAI` (`functions/index.js`) → `ai_interaction`, **solo sul percorso di successo**:
una chiamata fallita o bloccata dal rate limit non è un uso del prodotto.
`props.surface` = `clinicalRecord` | `chat`, `props.actionType` = `message`.

Limite noto: `feature` è sempre `chat`. `askAI` serve anche le chat Salute, visite ed
esami, ma `request.data` non porta la feature d'origine — solo `purpose`. Per
distinguerle servirebbe un campo nuovo dal client.

`generateTravelPlan` / `suggestTravelDestinations` → non ancora agganciate.

### Client — `KBAnalytics.swift` ✅ implementato

Il server **non può vedere le letture**: un trigger scatta su una scrittura. Aprire il
wallet, copiare una password, guardare dov'è un figlio non producono scritture. Un
approccio solo server-side darebbe un *"DAU dei creatori"*, cieco proprio sulle
feature a maggior valore passivo.

`KidBox/KidBox/Support/Analytics/KBAnalytics.swift` — actor, nessun SDK. Prende `uid`
da `Auth` e `familyId` dall'App Group (stessa fonte di `AIService`).

**Batching**: le letture sono l'evento più frequente dell'app, una scrittura Firestore
ciascuna costerebbe più del valore. Si aggregano in memoria per chiave
(`feature` + `uploaderIsSelf` + `entryPoint` + bucket) con un contatore, e partono in
un unico `WriteBatch` su `scenePhase == .background`. Soglia di sicurezza a 25 chiavi
distinte, se l'app viene terminata senza passare da background.

**Sessioni**: `session_start` su `.active`, con finestra di inattività di 30 minuti —
senza, ogni cambio di app conterebbe come apertura.

Call site agganciati:

| Punto | Feature | Evento |
|---|---|---|
| `KidBoxApp.swift` `.active` | app | `session_start` |
| `KidBoxApp.swift` `.background` | — | flush del buffer |
| `DocumentDetailView.onAppear` | documents | `content_retrieved` |
| `WalletTicketDetailView.onAppear` | wallet | `content_retrieved` |
| `PasswordDetailView.copyPassword` | passwords | `content_retrieved` |
| `FamilyLocationView.onAppear` | familyLocation | `content_retrieved` |
| `NoteDetailView.onAppear` | note | `content_retrieved` |
| `PediatricVisitDetailView.onAppear` | health | `content_retrieved` |
| `PhotoFullscreenView.onAppear` | photoVideo | `content_retrieved` |

`familyLocation` usa la variante `uploaderIsSelf:` esplicita: non ha un `createdBy` da
confrontare, e guardare dov'è un altro membro è cross-member per definizione.

### `entryPoint` — cosa è ottenibile e cosa no

`AppCoordinator.setRetrievalOrigin(_:)` / `consumeRetrievalOrigin()`: chi naviga
dichiara l'origine, il dettaglio la consuma e la azzera. Azzerare è il punto — senza,
una notifica colorerebbe tutte le aperture successive fatte sfogliando.

| Origine | Stato |
|---|---|
| `.notification` | ✅ `openDocumentFromPush`, `openWalletTicketFromPush`, `openNoteFromPush` |
| `.search` | ✅ solo Passwords |
| `.list` | ✅ default |
| `.widget` | ❌ **non ottenibile**: il widget non ha `widgetURL` né `Link`, non naviga dentro un contenuto |
| `.deepLink` | ❌ gli unici schemi sono `kidbox://share`, `join`, `control` — nessuno apre un contenuto |

**Documents e Wallet non hanno ricerca.** L'unica `searchable` tra le feature ad alta
lettura è quella di Passwords. Per i documenti, quindi, la risposta a "è a portata di
click?" oggi è strutturalmente *no*: l'unico modo di arrivare a un documento è sfogliare
le cartelle o ricevere una notifica. Non è un limite dell'instrumentazione — è una
constatazione sul prodotto, ed è la prima cosa che i dati confermeranno.

---

## 6-bis. Android — `KBAnalytics.kt` ✅ implementato

**Il server è comune**: i 15 trigger scattano sulle scritture Firestore da qualunque
piattaforma. Metà del lavoro Android era già attiva senza toccare nulla. Qui serve solo
la metà che il server non vede.

`app/.../util/analytics/KBAnalytics.kt` — `object` + `Mutex`, gemello dell'`actor` iOS.
Stesse costanti (90gg, gap sessione 30min, soglia 25) e **stessi valori `raw`** nelle
enum: finiscono nello stesso rollup, quindi devono coincidere carattere per carattere.

`KBAnalyticsLifecycleObserver` registrato in `KidBoxApplication`: conta le Activity
avviate (0→1 foreground, →0 background) invece di usare `ProcessLifecycleOwner`, perché
`androidx.lifecycle:lifecycle-process` non è tra le dipendenze e aggiungerla solo per
questo non vale il costo. Il contatore è immune alle rotazioni, che distruggono e
ricreano l'Activity senza portare il conteggio a zero.

| Punto | Feature |
|---|---|
| `KidBoxApplication` + observer | `session_start` / flush |
| `DocumentBrowserScreen.openDocument()` | documents |
| `WalletTicketDetailScreen` | wallet |
| `PasswordDetailScreen` (copia) | passwords |
| `NoteDetailScreen` (solo note esistenti) | note |
| `MedicalVisitDetailScreen` | health |
| `FamilyLocationScreen` | familyLocation |
| `FamilyPhotosScreen` (viewer aperto) | photoVideo |

`familyId` letto da `SharedPreferences` (`kidbox_prefs` / `active_family_id`) — le
costanti sono duplicate da `FamilySessionPreferences`, che richiede Hilt e non è
disponibile nei Composable e nei callback di lifecycle.

### `entryPoint` su Android

`KBAnalyticsOrigin.set()` / `.consume()` — equivalente di
`AppCoordinator.setRetrievalOrigin` su iOS, stessa semantica: consumare azzera.

`.notification` è impostato in `NotificationDeepLinkRouter` **solo sui tre casi che
aprono un contenuto** (`new_document`, `new_note`, `new_wallet_ticket` /
`wallet_ticket_reminder`). Non in cima a `handleLaunchIntent`: quello gestisce anche
`daily_briefing` & co., che portano in Home — marcarli colorerebbe di `.notification`
il primo dettaglio aperto poi sfogliando.

`.search` da `PasswordsHomeScreen`, avvolgendo `onOpenPassword` dove `state.searchQuery`
è in scope, senza cambiare la firma dei composable annidati.

### Parità con iOS

Raggiunta. Le uniche differenze residue sono strutturali, non di instrumentazione:

- `daysSinceUpload` per `familyLocation` è `unknown` su entrambe: non c'è una data di
  caricamento da usare.
- `.widget` / `.deepLink` non esistono su nessuna delle due — vedi sopra.

---

## 7. Rollup

**Mai un documento unico**: limite 1 MB, ~1 scrittura/secondo. Con un doc solo si
satura in giorni e si va in contesa da subito.

`functions/analyticsRollup.js` — `analyticsRollupDaily`, `onSchedule` alle 03:15
Europe/Rome, chiude il giorno precedente → `metrics/{YYYY-MM-DD}` (doc id = data):

```jsonc
{
  "date": "2026-07-16", "tz": "Europe/Rome",
  "dau": 0, "daf": 0,              // utenti / famiglie attive
  "activeMembersPerActiveFamily": 0.0,
  "sessionsNoAction": 0,           // aperture senza azione di valore
  "sessionsTotal": 0,              // 0 = NON MISURATO (manca il logger client)
  "byFeature": { "wallet": {"created":0,"updated":0,"completed":0,"retrieved":0,"ai":0} },
  "retrievedTotal": 0,             // 0 = NON MISURATO, idem
  "crossMemberReadRate": 0.0,      // quota content_retrieved con uploaderIsSelf=false
  "wau": 0, "mau": 0, "waf": 0, "maf": 0,
  "stickinessDauMau": 0.0, "stickinessWauMau": 0.0,
  "uids": [], "familyIds": [],     // per unire le finestre rolling
  "eventsScanned": 0
}
```

`uids` / `familyIds` sono la ragione per cui WAU/MAU restano calcolabili senza
riscansionare i grezzi — che a 90gg scadono. `buildWindows()` unisce gli insiemi
degli ultimi 7 / 28 rollup. Limite noto: array in un doc da 1 MB, ~30k uid. Oltre,
va spostato su una sottocollection o BigQuery.

**Zero ≠ non misurato.** Finché manca il logger client non esistono
`content_retrieved` né `session_start`: `crossMemberReadRate` e `sessionsNoAction`
sarebbero 0 e leggerebbero come un fallimento del prodotto. `retrievedTotal` e
`sessionsTotal` esistono apposta perché la console mostri `n/d` invece di `0%`.

**Esecuzione manuale**: `runAnalyticsRollup` (onCall, solo `ADMIN_UIDS`) ricalcola
`days` giorni a partire da `date`. Idempotente. Serve per il primo giorno, per i
backfill dopo un cambio di definizione, e per il bottone ↻ della console.

La console legge i rollup, non scansiona mai `analyticsEvents`: costo di lettura
costante mentre gli eventi crescono. TTL 90gg sui grezzi.

**Niente query ordinate su `metrics`.** La console ricostruisce gli id (`YYYY-MM-DD`)
degli ultimi 28 giorni e fa 28 point read. `orderBy(documentId(), 'desc')`
richiederebbe un indice dedicato — Firestore indicizza `__name__` solo in ascendente —
e un indice su `metrics` sarebbe un costo permanente per aggirare un ordinamento che
si ottiene gratis da id già ordinabili. Le date si costruiscono in `Europe/Rome`, lo
stesso fuso del rollup: usarne un altro disallineerebbe i confini di giornata.

---

## 8. Come si misura

**Giorno solare nel fuso dell'utente**, non UTC: con un'app familiare le sere contano,
e UTC spezza la serata italiana a mezzanotte spostando eventi al giorno dopo.

*Scostamento in implementazione*: gli eventi non portano il fuso e il server non lo
conosce, quindi il rollup usa **Europe/Rome per tutti** — buona approssimazione per
una base italiana, e comunque meglio di UTC. Se la base diventa multi-fuso serve un
campo `tz` sull'evento.

- **DAU** — utenti unici con ≥1 azione di valore nel giorno.
- **WAU / MAU** — **rolling window** di 7 e **28** giorni, ricalcolate ogni giorno.
  Non settimana/mese di calendario: 28 giorni contengono sempre 4 weekend, quindi le
  finestre sono confrontabili tra loro.
- **DAF / WAF / MAF** — stesse finestre, famiglie con ≥1 membro attivo.

**Rapporti:**

- **WAU/MAU** è il benchmark utile, target > 50%. Un **DAU/MAU basso non è un
  fallimento**: KidBox ha cadenza settimanale su spesa e calendario, mensile o annuale
  su documenti e veicoli.
- **Membri attivi per famiglia attiva** — predice il churn meglio del DAU.
- **Cross-member read rate** — la validazione della tesi di prodotto.

---

## 9. Fasi

1. ✅ Rules `analyticsEvents` (create-only) + `metrics` (read admin).
2. ✅ `functions/analytics.js` — 15 trigger di scrittura. **Non ancora deployato.**
3. ⬜ TTL 90gg su `analyticsEvents`, campo **`expiresAt`** (console Firebase, non è
   codice). Mai su `ts`: cancellerebbe tutto subito.
4. ✅ Rollup `analyticsRollupDaily` + `runAnalyticsRollup` → `metrics/{date}`.
5. ✅ Sezione "Utenti attivi" in `KidboxConsole/public/index.html` — l'unica console
   (`firebase.json` serve `public/`). Legge `metrics/`, mai `analyticsEvents`.
6. ✅ Logger client `KBAnalytics` + 7 call site di lettura + `entryPoint` reali
   (`.notification`, `.search`, `.list`). **Richiede rilascio app.**
7. ✅ `ai_interaction` da `askAI`. Deployata.
8. ✅ Android — `KBAnalytics.kt` + `KBAnalyticsOrigin` + observer + 7 call site +
   `entryPoint` reali. **Parità con iOS raggiunta** (§6-bis).
9. ⬜ **Rilascio app (iOS + Android)** — l'unica cosa che manca per accendere le letture.
10. ⬜ Ricerca in Documents e Wallet — prerequisito di prodotto, non di analytics:
    senza, `.search` lì non esisterà mai e la tesi resta non verificabile.

I passi 1–5 danno le scritture, i numeri e la dashboard senza toccare l'app. Dal 6 in
poi serve un rilascio, e fino a quel momento la console mostra `n/d` su cross-member
read e aperture a vuoto — non `0%`, che leggerebbe come un fallimento inesistente.

**Nessun dato è retroattivo**, per Firestore come per qualsiasi alternativa: ciò che
non si registra oggi è perso. È l'argomento più forte per fare presto i passi 1–2.
