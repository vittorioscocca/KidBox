# Notizie per la famiglia — disegno

> Richiesta dell'utente del 03/10/2026: una barra in basso (Home · assistente AI
> più grande al centro · Notizie) che sostituisce i pulsanti AI di Home e Salute,
> e una scheda Notizie con, ogni giorno, fino a 10 notizie utili alla famiglia —
> bonus e agevolazioni, economia, scuola, salute, crescita, tempo libero,
> società — dal paese alla regione al comune, eventi entro 50-60 km, e ricerche
> su misura dai dati della famiglia (bollette, spesa). Solo Pro e Max. Il costo
> in dollari delle ricerche si converte in messaggi AI KidBox.

## La barra

| | iOS | Android |
|---|---|---|
| Componente | `UIComponent/KBLiquidTabBar.swift` | `ui/components/KidBoxBottomBar.kt` |
| Aspetto | capsula in vetro liquido (`glassEffect`), cerchio dell'assistente in vetro «prominente» arancione, rialzato | fondo = `kidBoxColors.background`, lo stesso che la radice dipinge sotto la barra di sistema; cerchio dentro la barra |
| Dove sta | `safeAreaBar` su ogni pagina che la mostra, dentro la pila (`RootHostView.withTabBar`) | sotto il `NavHost` in `AppNavGraph` |
| Compatta scorrendo | `KBTabBarScrollObserver` (pan sulla finestra + KVO della scroll view sotto il dito), `KBTabBarScrollState` | `BottomBarScrollState` (`NestedScrollConnection` sul Box del NavHost) |
| Quando c'è | radici (pila vuota) e Salute (`Route.showsRootTabBar`) | `BottomBarRoutes.showsBar` |
| Radici | `AppCoordinator.rootTab` (`.home` / `.news`), cambiate da `selectRootTab` | rotte `home` e `news` (back di sistema da Notizie torna in Home) |

Il cerchio al centro **non è una scheda**: apre l'assistente. Da Salute lo apre
già centrato su persona, visite, visita, esami, esame (`AgentFocus.forRoute` /
`BottomBarViewModel.focusFor`), come facevano i pulsanti che ha sostituito; con
gli stessi controlli (quota del Free, proprietario, consenso). Sparisce con la
tastiera. Piano alimentare e Piano fitness non hanno la barra: hanno il loro AI
(il copilota) e un'azione in basso. Sul Mac la barra non c'è: restano i
pulsanti di prima e le Notizie sono una voce della barra laterale.

`safeAreaBar` e non `safeAreaInset`: con l'inset il testo che scorre dietro si
leggeva attraverso il vetro (visto nell'app-banco). Il cerchio dentro il
`GlassEffectContainer` si fondeva con la capsula in una macchia sfrangiata:
sta fuori, con `.buttonStyle(.glassProminent)`.

**Sulla pagina, non sulla `NavigationStack`.** Messa sulla pila (com'era nel
primo commit, 27d8c734) la barra non arriva al contenuto: la scroll view
tiene solo i 34 punti dell'indicatore home e in fondo alla pagina l'ultimo
pulsante finisce sotto la barra. Uguale con `safeAreaInset`. Misurato
nell'app-banco il 03/10/2026 (`adjustedContentInset.bottom` 34 sulla pila,
114 sulla pagina). Effetto collaterale accettato: passando da Home a Salute
la barra scorre via con la pagina e rientra con la nuova, come le barre di
sistema.

**Compatta scorrendo** (richiesta del 03/10/2026, come le barre di iOS 26):
scorrendo per leggere oltre la barra si riduce (solo icone, cerchio più
piccolo), torna grande scorrendo indietro, arrivando in cima o cambiando
schermata. Soglia di 28 punti nella stessa direzione contro il tremolio; conta
solo un contenuto che scorre in verticale. Su iOS lo spazio riservato resta
quello della barra grande (`KBLiquidTabBar.reservedHeight`), così il contenuto
non salta; su Android la barra è in colonna col NavHost, quindi compatta lascia
20 dp in più alla schermata e nessun contenuto può finirle sotto. Trappola
dell'osservatore iOS: mentre il titolo grande si richiude iOS toglie margine
in alto alla stessa velocità con cui cresce l'offset, e la pagina sembra «in
cima» per i primi ~100 punti; il ritorno in cima si controlla solo a dito
sollevato e salendo. Fino al 03/10/2026 su Android il cerchio sporgeva di
12 dp sopra la barra e copriva l'ultima riga: ora sta dentro.

## Le edizioni

Le notizie le trova **Claude Sonnet 5.5 con la ricerca web** (`web_search_20260318`,
filtro dinamico), in `functions/news/`. Tre tipi di generazione:

| | Chiave | Contenuto | Rinnovo | Sforzo / ricerche |
|---|---|---|---|---|
| Nazionale | `c-{CC}-{lingua}` | due ricerche parallele: bonus+economia+società, scuola+salute+crescita+tempo libero | ogni giorno | medium, 7 + 7 |
| Locale | `l-{CC}-{regione}-{città}-{lingua}` | notizie di regione e comune + eventi entro ~60 km nei 14 giorni | ogni 2 giorni | medium, 10 |
| Offerte su misura | per utente | luce/gas (verdetto anche «restare conviene»), acqua, internet, spesa | solo su richiesta, max ogni 6 ore | medium, 6 |

Nazionale e locale sono **condivise**: tutte le famiglie della stessa zona e
lingua leggono la stessa. Si generano **in coda** (`news_jobs` → trigger
`buildNewsEdition`, 540 s), non dentro la callable: una generazione dura 40-100 s.
`getFamilyNews` mette in coda ciò che manca, serve ciò che c'è e risponde
`status: "preparing"`; il client richiama ogni 6 s. Alle 05:30
`prepareNewsEditions` prepara le zone lette negli ultimi 3 giorni.

Ogni voce passa dal setaccio di `prompts.js`: categoria valida, **URL presente
fra i risultati delle ricerche di quella chiamata** (il modello inventa link),
notizia uscita da ≤ 14 giorni o con una data chiave (scadenza, inizio,
pagamento) ancora davanti e uscita da ≤ 45, eventi non finiti e nel raggio, niente
URL già usciti nei 10 giorni prima (i loro titoli vanno anche nel prompt). Se non
ci sono notizie l'edizione è più corta: niente riempitivi.

L'edizione dell'utente (`compose`) filtra le sue categorie e mette prima il
paese, poi la regione, poi la città: al massimo 10 notizie (metà spazio al locale
quando c'è), 6 eventi (con «Tempo libero»).

**Eventi nel calendario** (03/10/2026): ogni scheda evento ha un «+» in alto a
destra che apre «Nuovo evento» del calendario KidBox già compilato — tutto il
giorno dal primo all'ultimo giorno (le edizioni danno solo le date), Tempo
libero, luogo, riassunto e link nelle note; visibilità e promemoria restano da
scegliere. Su iOS è un foglio sopra le Notizie (`CalendarEventPrefill(newsEvent:)`
in `NewsView.swift`, la scheda è la stessa di «Copia in KidBox»); su Android il
modulo è legato al calendario, quindi il «+» apre il calendario col modulo già
aperto (`CalendarPrefillHandoff`, il prefill non sta in una rotta) e, chiuso il
modulo, torna alle Notizie. Il «+» diventa una spunta quando nel calendario c'è
un evento con lo stesso titolo (senza maiuscole e accenti) e lo stesso giorno
d'inizio: la vede anche l'altro genitore. Non c'è un collegamento fra evento
delle Notizie e evento salvato: cambiato il titolo salvando, la spunta non
compare.

## Notizie salvate

Richiesta dell'utente del 04/10/2026: salvare una notizia mentre la si legge e
ritrovarla in una vista dove gestirle, eliminandole. **Di chi le salva, non
della famiglia** (detto esplicitamente: se A salva tre notizie, B non se le
ritrova), al contrario di accensione, città e offerte.

- Dove: `users/{uid}/savedNews/{id}`, id = SHA-256 dell'URL in esadecimale
  (uguale su iOS e Android: la stessa notizia è un documento solo). Una
  **copia** della notizia (titolo, riassunto, azione, data chiave, fonte, URL,
  categoria, livello, `placeName` del gruppo, `savedAtMs`): le edizioni
  cambiano ogni giorno e hanno un TTL, un riferimento si perderebbe.
- Rules: `match /savedNews/{newsId}` sotto `users/{uid}`, solo il proprietario,
  in `firestore.rules` e `.next` (5 casi nella suite). `deleteAccount` le
  cancella. Il wildcard di `users/{uid}` non esiste: ogni sottocollezione nuova
  vuole la sua `match`.
- Salvare: segnalibro in basso a destra della scheda (iOS e Android); su iOS
  anche «Salva notizia» nel menu Condividi del browser in app
  (`NewsSaveActivity`: un pulsante sopra `SFSafariViewController` non si mette,
  Safari non va coperto). Su Android la notizia si legge nel browser esterno,
  quindi resta il segnalibro.
- Vista: icona del segnalibro in alto nella scheda Notizie, visibile anche a
  chi è tornato Free se ha salvate (l'elenco non costa niente). iOS
  `NewsSavedView` (scorri per eliminare, menu della notizia, «Seleziona»,
  «Elimina tutte» con conferma); Android `NewsSavedScreen` (scorri a sinistra
  con «Annulla», pressione lunga o «Seleziona» per i gruppi, «Elimina tutte»).
  Una scadenza passata diventa «Scaduto il …» in grigio.
- Store: `NewsSavedStore` su entrambe, un ascolto per sessione (iOS lo apre
  la scheda e lo chiude `resetOnSignOut`; Android segue l'`AuthStateListener`).
- Su iOS, dentro una `List` le etichette delle schede prendono la colonna
  larga delle icone di sistema: le righe delle salvate usano
  `NewsCardLabelStyle` (`labelReservedIconWidth(0)` faceva uscire l'icona dal
  margine). Visto nell'app-banco il 04/10/2026.

## Il costo in messaggi

Richiesta esplicita: le spese in dollari diventano messaggi AI KidBox.

- **Cambio**: `usdPerMessage` = 0,02 $ (un messaggio pieno: 50.000 caratteri ad
  Haiku più la risposta). Il costo medio vero di un messaggio scalato, da
  `ai_costs` / `ai_usage`, era 0,006 $ ad agosto e 0,010 $ a settembre 2026.
- **Edizione condivisa**: prezzo per famiglia = costo ÷ famiglie che hanno letto
  le edizioni di quella zona negli ultimi giorni (almeno 1), fissato quando
  l'edizione nasce. Ogni famiglia paga un'edizione **una volta**
  (`news_charges/{familyId}_{editionId}`), anche se la leggono più membri o se
  l'edizione locale vale due giorni. Prenotazione con `create()` prima dello
  scatto del contatore: due dispositivi della stessa famiglia non pagano due volte.
- **Tetto**: `maxUnitsPerEdition` = 6. Misurato il 03/10: nazionale 0,27-0,36 $,
  locale 0,23 $ → 13-18 messaggi a un lettore solo; senza tetto il primo giorno
  si mangiava la quota di un Pro (30). Sopra il tetto il costo resta a KidBox.
- **Offerte**: costo pieno (tetto 8), prenotata la stima prima di generare e
  conguagliata sul costo vero (rimborso con `refundAIUsage`).
- Tutto passa da `checkAndIncrementAIUsage`: stesso contatore dell'assistente
  (Pro 30/giorno, Max 100/giorno, **prova Pro 50 in tutto** — le Notizie la
  consumano). Quota insufficiente → `resource-exhausted` con unità e rimanenti,
  la scheda lo dice e non mostra l'edizione.
- Tetto globale `dailyBudgetUsd` = 5 $: oltre, niente generazioni nuove e si
  serve l'ultima edizione pronta. Spese del giorno in `news_usage/{data}`, del
  mese anche in `ai_costs/{mese}` (`newsCostUsd`, `newsSearches`).
- Tutto regolabile senza deploy in `config/news` (cambio, tetti, sforzi, numero
  di ricerche, rinnovo locale, `enabled` per spegnere).

## Della famiglia, non della persona

Richiesta dell'utente del 03/10/2026: le notizie accese da un membro le vedono
tutti i membri della famiglia. Fino a quel giorno solo le edizioni erano
comuni (per zona e lingua): accensione e città stavano su
`users/{uid}.newsPrefs`, quindi un secondo membro vedeva la presentazione con
«Attiva le notizie», con un'altra città riceveva un'altra edizione locale
(pagata di nuovo), e le offerte su misura le vedeva solo chi le aveva cercate.

| | Dove | Chi la cambia |
|---|---|---|
| Accese o no, luogo, lingua delle edizioni | `families/{familyId}/news/settings` (`enabled`, `place`, `lang`, `updatedAtMs`, `updatedBy`) | qualunque membro, per tutti |
| Offerte su misura trovate | `news_offers/{familyId}` (solo server) | chi tocca «Cerca offerte», per tutti |
| Argomenti, offerte in vista | `users/{uid}.newsPrefs` | ciascuno per sé: filtrano le stesse edizioni, non costano |

- Le rules non hanno una regola per `news/settings`: lo apre ai membri il
  wildcard delle sottocollezioni (6 casi in `firestore-tests`, compreso
  l'estraneo che non legge né spegne).
- Il server legge il documento e, quando c'è, **preferisce luogo e lingua della
  famiglia** a quelli che manda il telefono: due membri con città o lingua
  diverse sul telefono leggono le stesse edizioni, pagate una volta. Spente
  dalla famiglia → `failed-precondition` `news-off`, niente edizione né
  addebito. Senza documento (app vecchie) usa quello che manda il telefono.
- La lingua la fissa chi le accende per primo: un'edizione in un'altra lingua
  sarebbe un'altra ricerca, pagata di nuovo. Chi ha l'app in un'altra lingua
  legge le notizie in quella della famiglia.
- Client: `NewsFamilyStore` (iOS e Android) ascolta il documento con i cambi
  di metadati e, finché non sa com'è la famiglia, la scheda aspetta invece di
  mostrare la presentazione. Le chiamate aspettano l'ultima scrittura
  (`settled()`): un «Attiva» appena toccato arriva prima della richiesta
  dell'edizione, altrimenti il server leggerebbe ancora «spente».
- Le offerte se ne vanno con la famiglia (`deleteFamilyCompletely`, insieme a
  `families/{id}/news`); quelle vecchie per utente (`news_personal/{uid}`, solo
  prove del 03/10) le cancella ancora `deleteAccount`.

## Privacy

- In chiaro sul server: paese, regione, provincia, città e lingua della
  famiglia (`families/{familyId}/news/settings`, letto e scritto dai membri),
  argomenti di ciascuno (`users/{uid}.newsPrefs`). Mai coordinate:
  la posizione si legge una volta, sul telefono, e diventa un nome di città.
- Le query di ricerca contengono luoghi e argomenti, mai dati personali (regola
  nel prompt).
- Offerte su misura: il telefono costruisce un riassunto (tipo di bolletta,
  fornitore, importo, fine contratto, righe con consumi e prezzi, nomi dei
  prodotti della spesa) **senza** nomi, indirizzi, codici cliente, POD/PDR,
  IBAN, email (righe scartate, cifre lunghe mascherate); parte solo al tocco di
  «Cerca offerte» e **dopo il consenso AI**; il server non lo salva. Si salvano
  solo le offerte trovate (`news_offers/{familyId}`), visibili a tutti i membri
  e cancellate con la famiglia.
- Informativa: paragrafo «Notizie» nella sezione Assistente AI di
  `privacy*.html`, confermato dall'utente e pubblicato in 4 lingue il 03/10/2026;
  lo stesso giorno, sempre su suo ok, attivazione, città e offerte della famiglia.
  Il 04/10/2026, su suo ok, la frase sulle notizie salvate: solo nell'account,
  gli altri membri non le vedono, si cancellano con l'account.
- Pulizia: policy TTL su `expireAt` di `news_charges` (40 giorni), `news_jobs`
  (7) e `news_editions` (120), attivate il 03/10/2026.

## Client

| | iOS | Android |
|---|---|---|
| Scheda | `Features/News/NewsView.swift` (+ `NewsCards.swift`) | `ui/screens/news/NewsScreen.kt` |
| Logica | `NewsViewModel`, `NewsService` (presidio di piano) | `NewsViewModel`, `NewsRepository` (presidio di piano) |
| Scelte della famiglia | `NewsFamilyStore` → `families/{familyId}/news/settings` | `NewsFamilyStore`, stesso documento |
| Scelte di ciascuno | `NewsPrefsStore` → `users/{uid}.newsPrefs` | `NewsPrefsStore`, stesso formato |
| Riassunto | `NewsBriefBuilder.swift` | `NewsBriefBuilder.kt` |
| Città | `NewsLocationResolver` (MapKit) | `NewsLocationResolver` (Fused + Geocoder) |
| Impostazioni | Impostazioni → Notizie, e l'icona in alto | uguale |

Stati della scheda: Free → invito a Pro; scelte della famiglia non ancora
arrivate → attesa; famiglia che non le ha mai accese → presentazione con il
costo («al massimo 6 messaggi per edizione») e «Attiva le notizie»: prima non
parte nessuna ricerca né si scala nulla; accese da un qualunque membro →
edizione del giorno.

## Gating (i tre presidi)

Server `gate()` in `functions/news/index.js` (`quota.period === "lifetime"` →
`permission-denied`, reason `plan`); servizio `NewsService.ensurePaidPlan` /
`NewsRepository.ensurePaidPlan` (`currentPlan`, non `isAIAccessible`); vista
`currentPlan == .free` / `state.isPaid`. Il web non ha le Notizie.

## Numeri da guardare

`news_opened` (units, preparing), `news_item_opened` (kind, category, level; kind `saved` dalle salvate),
`news_item_saved` (category, level, from `card`/`browser`),
`news_offers_searched`, `news_activated`, `news_event_add` (il «+»; il
salvataggio vero è `content_created` calendar) in GA4; `news_usage/{data}` e i log
`news: edizione pronta` (costUsd, searches, dropped) per costo e qualità; la
media dei lettori per zona (`readers` sulle edizioni) per capire se il prezzo
per famiglia scende davvero.
