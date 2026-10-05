---
name: notizie
description: Le Notizie per la famiglia (Pro e Max) e la barra in basso Home · assistente · Notizie — edizioni condivise trovate da Claude con la ricerca web, setaccio delle voci, costo convertito in messaggi AI, offerte su misura da bollette e spesa, focus dell'assistente dalla barra. Usare quando si tocca functions/news, la scheda o le impostazioni Notizie su iOS/Android, la barra in basso, o quando l'utente dice «le notizie sono vecchie / poche / sbagliate», «costano troppi messaggi», «non trovo la mia città», «il pulsante AI non c'è più».
---

Disegno completo in `internal/notizie.md`. Qui le regole e le trappole.

## Dove sta cosa

- Server: `functions/news/` — `prompts.js` (prompt e setaccio, funzioni pure),
  `search.js` (chiamata con ricerca web), `index.js` (callable, trigger,
  scheduler, addebito). `build(deps)` riceve da `index.js` appartenenza, quota,
  contatore e rimborso: una copia sola.
- Scelte: della famiglia (accese, luogo, lingua) in
  `families/{familyId}/news/settings` via `NewsFamilyStore`; di ciascuno
  (argomenti, offerte in vista) in `users/{uid}.newsPrefs` via `NewsPrefsStore`.
  Offerte trovate in `news_offers/{familyId}`. Notizie salvate col
  segnalibro: dell'account, in `users/{uid}/savedNews/{sha256(url)}` via
  `NewsSavedStore` (mai della famiglia: richiesta esplicita del 04/10/2026).
- iOS: `Features/News/`, barra `UIComponent/KBLiquidTabBar.swift`, focus
  `Features/AIAgent/AgentFocus+Route.swift`, aggancio in `RootHostView`.
- Android: `ui/screens/news/`, barra e focus `ui/components/KidBoxBottomBar.kt`,
  aggancio in `AppNavGraph` (Column con NavHost e barra).
- Parametri senza deploy: `config/news` (cambio dollari→messaggi, tetti,
  sforzo e ricerche per tipo, rinnovo locale, `enabled`).

## Le trappole già pagate (03/10/2026)

1. **Un'edizione nazionale con una ricerca sola esce con 2 notizie**: 12
   ricerche finite tutte sui bonus. Per questo si divide in due gruppi di
   categorie in parallelo (`COUNTRY_GROUPS`). Se un'edizione torna corta, prima
   di alzare l'effort guarda come ha distribuito le ricerche (`server_tool_use`).
2. **Il setaccio buttava notizie ancora attuali** («la mensa parte il 6 ottobre»
   uscita il 12/09): esiste la **data chiave** (`keyDate` + `keyDateKind`
   deadline/start/payment). Una notizia vale se è recente **o** se la data chiave
   è davanti. Non stringere l'età senza guardare i `droppedReasons` nei log.
3. **Il modello inventa link**: ogni URL deve stare fra i risultati delle
   ricerche di quella chiamata (`collectSearchUrls`, compresi i blocchi con
   `caller` del filtro dinamico). Si mostra l'URL originale del risultato.
4. **Cache del prompt obbligatoria**: il ciclo delle ricerche rilegge tutto il
   contesto a ogni passo; senza `cache_control` un'edizione costava 140.000
   token in input. Con la cache ~0,2-0,3 $.
5. **`pause_turn`**: si rimanda il turno dell'assistente così com'è, senza un
   «continua»; c'è una scadenza complessiva (`deadline`) perché il trigger ha
   540 s.
6. **Il punto in `set()`**: `byKind.x` con merge crea un campo che si chiama
   «byKind.x». Mappe annidate (vedi `recordSpend`).
7. **Un paese non supportato da `user_location` è un 400 su tutta la
   richiesta**: si riprova senza localizzazione.
8. **Il trigger appena deployato non riceve gli eventi per un paio di minuti**:
   un'edizione messa in coda subito resta `queued`. Si ricrea solo il job
   (`news_jobs/{id}_…`), l'edizione si riprende da sola.
9. **Senza tetto, il primo lettore di una zona paga tutto**: nazionale + locale
   = 30 messaggi, la quota intera di un Pro. Il tetto per edizione
   (`maxUnitsPerEdition`) è una scelta di prodotto: cambiarlo da `config/news`.
   **Dal 05/10/2026 le Notizie scalano anche dal tetto mensile** (Pro 100, Max
   200, prova compresa): `checkAndIncrementAIUsage` ferma con
   `reason: "monthly-limit"`, che news passa ai client così com'è; iOS
   (`NewsService`) e Android (`NewsRepository`) hanno la frase del mese, le
   build vecchie mostrano quella del giorno («riprova domani»).
10. **iOS: la barra con `safeAreaInset` lasciava leggere il testo attraverso il
    vetro**, e il cerchio dentro `GlassEffectContainer` si fondeva con la capsula
    in una macchia. `safeAreaBar` e cerchio fuori dal contenitore con
    `.glassProminent`. Provare il vetro nell'app-banco (memoria «Verifica UI iOS»):
    `KBLiquidTabBar.swift` e `NewsCards.swift` compilano senza Firebase.
11. **iOS: `safeAreaBar` sulla `NavigationStack` non arriva al contenuto** delle
    pagine (34 punti invece di 114: l'ultimo pulsante finiva sotto la barra).
    Va su ogni pagina con la barra (`RootHostView.withTabBar`). Per misurarlo:
    `adjustedContentInset.bottom` della scroll view nell'app-banco.
12. **La barra compatta**: su iOS l'osservatore sulla finestra
    (`KBTabBarScrollObserver`) non deve guardare «in cima» mentre il dito
    trascina, perché col titolo grande che si richiude l'offset resta uguale al
    margine in alto per ~100 punti e la barra rimbalzava subito grande. Su
    Android `BottomBarScrollState` conta solo lo scorrimento consumato
    (test in `BottomBarScrollStateTest`). Il cerchio Android non deve sporgere
    sopra la barra: copriva il contenuto.
13. **Le notizie sono della famiglia** (03/10/2026): accensione e città per
    persona facevano rivedere la presentazione al secondo membro, gli davano
    un'altra edizione locale pagata di nuovo e gli nascondevano le offerte.
    Non rimettere `enabled`/`place` in `newsPrefs`: il server preferisce il
    documento di famiglia a quello che manda il telefono. Le chiamate aspettano
    `NewsFamilyStore.settled()`, o un «Attiva» appena toccato arriva dopo la
    richiesta e il server risponde `news-off`.

## Regole

- **Il piano**: tre presidi (`gate()` server, `ensurePaidPlan` nei servizi,
  `currentPlan`/`isPaid` nelle viste) → `/gating-pro`. Mai `isAIAccessible`.
- **Il costo si paga in messaggi** con `checkAndIncrementAIUsage`: stesso
  contatore dell'assistente. Una famiglia paga un'edizione una volta
  (`news_charges`). Le offerte si prenotano a stima e si conguagliano;
  ogni fallimento dopo la prenotazione si rimborsa.
- **Niente dati personali nelle query** e nel riassunto delle offerte: il
  telefono scarta le righe con nomi/indirizzi/codici e maschera le cifre
  lunghe. Il riassunto parte solo **dopo il consenso AI** e non si salva.
- **Mai coordinate sul server**: solo paese, regione, provincia, città.
- **La barra non è per tutte le schermate**: radici e Salute. Aggiungerla a
  una schermata con un'azione in basso (chat, editor) vuol dire provarla.
- Le prove di prompt si fanno con script nello scratchpad che usano
  `prompts.js` e `search.js` veri e la chiave da Secret Manager (mai stampata),
  come in `/ai` regola 9. Costano 0,1-0,4 $ l'una: pesano nel report dei costi.
- Testi in quattro lingue sulle due app (`/localizzazione`): su iOS le
  `NSLocalizedString` non escono nei `.stringsdata`, vanno aggiunte a mano.
