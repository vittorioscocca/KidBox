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
| Aspetto | capsula in vetro liquido (`glassEffect`), cerchio dell'assistente in vetro «prominente» arancione, rialzato | fondo = `kidBoxColors.background`, lo stesso che la radice dipinge sotto la barra di sistema |
| Dove sta | `safeAreaBar` sulla `NavigationStack` di `RootHostView` | sotto il `NavHost` in `AppNavGraph` |
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

## Privacy

- In chiaro sul server: paese, regione, provincia, città, lingua e categorie
  (`users/{uid}.newsPrefs`, letto e scritto solo dall'utente). Mai coordinate:
  la posizione si legge una volta, sul telefono, e diventa un nome di città.
- Le query di ricerca contengono luoghi e argomenti, mai dati personali (regola
  nel prompt).
- Offerte su misura: il telefono costruisce un riassunto (tipo di bolletta,
  fornitore, importo, fine contratto, righe con consumi e prezzi, nomi dei
  prodotti della spesa) **senza** nomi, indirizzi, codici cliente, POD/PDR,
  IBAN, email (righe scartate, cifre lunghe mascherate); parte solo al tocco di
  «Cerca offerte» e **dopo il consenso AI**; il server non lo salva. Si salvano
  solo le offerte trovate (`news_personal/{uid}`), cancellate con l'account.
- Informativa: paragrafo «Notizie» nella sezione Assistente AI di
  `privacy*.html`, confermato dall'utente e pubblicato in 4 lingue il 03/10/2026.
- Pulizia: policy TTL su `expireAt` di `news_charges` (40 giorni), `news_jobs`
  (7) e `news_editions` (120), attivate il 03/10/2026.

## Client

| | iOS | Android |
|---|---|---|
| Scheda | `Features/News/NewsView.swift` (+ `NewsCards.swift`) | `ui/screens/news/NewsScreen.kt` |
| Logica | `NewsViewModel`, `NewsService` (presidio di piano) | `NewsViewModel`, `NewsRepository` (presidio di piano) |
| Scelte | `NewsPrefsStore` → `users/{uid}.newsPrefs` | `NewsPrefsStore`, stesso formato |
| Riassunto | `NewsBriefBuilder.swift` | `NewsBriefBuilder.kt` |
| Città | `NewsLocationResolver` (MapKit) | `NewsLocationResolver` (Fused + Geocoder) |
| Impostazioni | Impostazioni → Notizie, e l'icona in alto | uguale |

Stati della scheda: Free → invito a Pro; mai attivata → presentazione con il
costo («al massimo 6 messaggi per edizione») e «Attiva le notizie»: prima non
parte nessuna ricerca né si scala nulla; attiva → edizione del giorno.

## Gating (i tre presidi)

Server `gate()` in `functions/news/index.js` (`quota.period === "lifetime"` →
`permission-denied`, reason `plan`); servizio `NewsService.ensurePaidPlan` /
`NewsRepository.ensurePaidPlan` (`currentPlan`, non `isAIAccessible`); vista
`currentPlan == .free` / `state.isPaid`. Il web non ha le Notizie.

## Numeri da guardare

`news_opened` (units, preparing), `news_item_opened` (kind, category, level),
`news_offers_searched`, `news_activated` in GA4; `news_usage/{data}` e i log
`news: edizione pronta` (costUsd, searches, dropped) per costo e qualità; la
media dei lettori per zona (`readers` sulle edizioni) per capire se il prezzo
per famiglia scende davvero.
