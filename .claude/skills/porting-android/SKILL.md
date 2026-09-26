---
name: porting-android
description: Portare su Android una funzione già fatta su iOS (o correggere un bug Android) evitando le trappole già pagate — foreign key di Room, delta Firestore vuoto, contentColor in dark mode, dialog tagliato, deep link, JDK. Usare quando si scrive codice in KidBoxAndroid/, quando una cosa «su iOS funziona e su Android no», o quando dati corretti non compaiono a schermo.
---

Le tre app condividono **lo stesso schema Firestore** (`families/{familyId}/…`):
nessun client ha un modello dati suo. Un porting è quindi sempre UI + Room +
listener, mai un nuovo schema. Prima di iniziare apri la view iOS equivalente e
copiane campi, logica e testi.

## Ambiente

Il JDK di sistema è **Java 8**, Gradle ne vuole ≥ 11: `./gradlew` fallisce in
*configurazione* con un errore che sembra delle dipendenze ed è solo l'ambiente.
Da `KidBoxAndroid/`:

    JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:compileDebugKotlin

`KidBoxAndroid/` è un **repo git separato e annidato**: i commit e la
pubblicazione li fa l'utente, e qui si vedono solo con `git -C KidBoxAndroid`.
Un `org.gradle.java.home` in `gradle.properties` risolverebbe stabilmente il
JDK: **proporlo, non applicarlo di iniziativa**.

## Le trappole dei dati (sintomo identico: «i dati ci sono ma non si vedono»)

1. **`documentChanges` invece di `snap.documents`.** Con la persistenza locale
   Firestore può riusare una snapshot in cache e confermarla invariata con un
   existence filter: il target arriva a `CURRENT` **con zero
   `document_change`**, quindi il delta è vuoto pur avendo la query risultati
   reali. Deriva gli upsert da `snap.documents` (risultato completo); usa
   `documentChanges` **solo** filtrato su `REMOVED`, che sul delta è affidabile.
   Già corretto in `TodoRemoteStore`; gli altri RemoteStore non sono auditati.
   Stesso spirito per l'elenco delle famiglie: `users/{uid}/memberships` è una
   **copia** (la tiene il server da `syncMembershipIndex`), la verità sono i
   documenti membro. Il fallback `collectionGroup("members")` funziona solo
   con `whereEqualTo("uid", uid)` esatto (è l'unica forma che le rules
   ammettono) e scarta i documenti senza `role` o con `isDeleted == true`.
2. **Le foreign key di Room scartano in silenzio.** `kb_family_members` →
   `kb_families`, `kb_todo_lists.childId`, `kb_todo_items.listId`: se il padre
   non è ancora in Room, il figlio viene scartato (o salvato con `listId = null`
   **per sempre**, perché all'arrivo della lista nessuno torna a rilegarlo), e
   l'eccezione viene inghiottita riga per riga. Dipende solo dall'ordine di
   arrivo degli snapshot: da qui l'intermittenza. Rimedio già in uso: inserire
   una **riga segnaposto** (`ensureFamilyRowExists`, `ensureChildExists`, con
   `updatedAt = 0` così il dato remoto vince il last-write-wins) e risolvere il
   riferimento mancante leggendolo da Firestore (`resolveReferencedListId`).
3. **`@Insert(onConflict = REPLACE)` sui DAO padre.** In SQLite REPLACE è
   DELETE + INSERT: riscrivere una riga **identica a se stessa** fa scattare le
   azioni FK e cancella i figli (CASCADE) o li scollega (SET NULL). È il «a
   volte le liste non si caricano» dopo un force refresh.
4. **`clearPersistence()` a ogni avvio** (corretto l'11/09/2026): cancellava
   cache e resume token, 179 `document_change` e ~300 letture per avvio contro
   ~58 dopo il fix. Deve scattare **solo al cambio di uid**. Né iOS né la web app
   lo chiamano: se ricompare su un client, è questo il costo.

Per misurare davvero: il debug dell'SDK è già attivo, `adb logcat` mostra
`document_change`, `target_change` e gli existence filter (`filter { count: N }`
= set invariato, non ritrasmetto). È una misura **per dispositivo**.

4b. **Le ripetizioni sono copie con lo stesso id.** `occurrencesIn`
   (`domain/calendar/EventRecurrence.kt`) restituisce copie dell'evento con le
   date spostate: vanno bene per disegnare, **mai** per salvare o cancellare
   (si scriverebbero le date di una ripetizione sulla serie). Da un tocco in
   griglia si torna all'originale con `state.events.seriesOf(it)`.
   `uiState.events` sono le serie, `uiState.displayEvents` le ripetizioni.

4c. **`CalendarContract` (calendari del telefono, `DeviceCalendarRepository`).**
   Gli eventi tutto-il-giorno sono salvati a mezzanotte **UTC**: letti così
   come sono cadono all'una di notte in Italia e il giorno prima in America,
   vanno riportati alla mezzanotte locale della stessa data. La fine è
   **esclusa** (mezzanotte dopo): nelle mappe per giorno, che la includono,
   va tolto un millisecondo. E i calendari locali di Xiaomi/MIUI hanno come
   nome una **chiave** (`calendar_displayname_local`, `..._birthday`,
   `account_name_local`) che solo l'app Calendario di sistema traduce:
   mostrata così sembra un errore (`readableName`).

## Le trappole della UI

5. **Dark mode: `contentColor`.** Material3 deriva il contentColor solo dai
   propri colori: dentro una `Surface`/`ModalBottomSheet` tinta con
   `MaterialTheme.kidBoxColors.*`, ogni `Text`/`Icon` senza `color`/`tint`
   esplicito resta nero e sparisce in tema scuro. Serve `color = kb.title`.
   **Non** serve dentro `AlertDialog`, `TextField`, `TopAppBar`, `Tab`,
   `Button` (componenti Material veri: forzarli peggiora). `Color.White` su
   pillole/FAB/badge di colore fisso è corretto e va lasciato.
   Trovato almeno cinque volte in schermate diverse.
6. **Dialog a schermo intero tagliato sotto la barra.** Con
   `usePlatformDefaultWidth=false` Compose misura sull'intero display ma la
   finestra resta **dentro** le barre di sistema: gli ultimi ~245 px sono fuori
   finestra, visibili a metà e non toccabili. Non c'entrano gli inset. Fix nel
   `Dialog`: `(LocalView.current.parent as? DialogWindowProvider)?.window` →
   `WindowCompat.setDecorFitsSystemWindows(w, false)` +
   `addFlags(FLAG_LAYOUT_IN_SCREEN or FLAG_LAYOUT_INSET_DECOR)` in un
   `SideEffect`. Niente `navigationBarsPadding()` in più, o si raddoppia.
   Stesso pattern in PetDetail, Chat, VisibilityPicker.

## Le trappole delle liste di chat (trovate il 24/09/2026)

11. **Coil: prefetch e bolla devono fare la stessa richiesta.** Stessa
    `memoryCacheKey` ma taglia diversa (prefetch 400×400, bolla alla misura
    del layout) e Coil scarta la bitmap prefetchata perché più piccola:
    ridecodifica proprio durante lo scroll. Le richieste della chat stanno in
    `ChatMediaRequests` (taglia esplicita, stessa per tutti e due). La taglia
    esplicita va presa dal **contenitore più grande** in cui l'immagine può
    finire (bolla con citazione, 80%/360dp), non da quello tipico: Coil non
    misura più il layout, e un riquadro più grande della bitmap la mostra
    ingrandita e sfocata. **Mai un
    URL video a Coil**, nemmeno come ripiego: non lo decodifica, ma prima lo
    scarica per intero nella cache immagini. Le miniature video passano da
    `VideoThumbnailLoader` (max 640 px; la galleria a schermo intero chiede
    `maxSide` pieno).
12. **Stato iniziale dalla cache, non `null`.** `produceState(initialValue =
    null)` per anteprime link e miniature: ogni bolla che rientra nel
    viewport nasce senza card e cresce un frame dopo, e la lista scatta. Si
    parte da `peek()` sincrono (`LinkPreviewFetcher`, `VideoThumbnailLoader`,
    `SenderAvatarCache`). Nelle `LazyColumn` eterogenee serve `contentType`.
13. **Lo stato di scroll non si legge nel corpo della schermata.**
    `listState.firstVisibleItemIndex` o `layoutInfo` letti nudi (per la FAB
    «vai in fondo») ricompongono tutta la schermata a ogni frame: si usa
    `derivedStateOf`. Idem per contatori ad alta frequenza come il tick del
    typewriter AI: si osservano con `snapshotFlow` dentro l'effetto, non
    nella composizione. E si ricordano le derivazioni (`messages.reversed()`,
    `SimpleDateFormat`, parse del markdown), che altrimenti rigirano a ogni
    tasto premuto nel composer.
14. **Chat AI: si segue il fondo solo se l'utente ci sta.**
    `AIChatListScrollEffect` riportava giù in modo incondizionato a ogni tick
    del typewriter (ogni 120 ms) e a ogni messaggio: chi risaliva a rileggere
    veniva strappato giù. Ora `followBottom` si spegne quando lo scroll si
    ferma lontano dal fondo e si riaccende al ritorno o all'invio. Non
    reintrodurre `scrollToItem` incondizionati in quell'effetto.
    **Mai `scrollToItem(i, Int.MAX_VALUE)`** per «fino in fondo all'ultimo
    item»: `LazyListMeasure` calcola `maxOffset - (-offset)` e l'intero
    trabocca (verificato sul sorgente di foundation 1.7.6). Si scorre
    sull'item e poi `scrollBy` di quanto sporge oltre `viewportEndOffset`.

15. **Mai consumare i tocchi nel passaggio `Initial` per «lasciarli al genitore».**
    `Initial` scende dal genitore al figlio, ma `clickable`/`combinedClickable`
    decidono nel passaggio `Main` e scartano un tocco già consumato: il
    genitore non riceve più niente. Era l'overlay sulla mappa delle posizioni
    in chat, e da aprile toccarle non apriva mai le mappe. Per rendere
    inerte una vista sotto (mappa, video, WebView) si mette il `clickable`
    **sull'overlay in cima**: vince l'hit test fra fratelli, e sotto non
    arriva niente. E ogni `startActivity` verso un'altra app (`geo:`, `tel:`,
    link) ha un ripiego o un `runCatching`: senza l'app che lo gestisce è un
    `ActivityNotFoundException` e l'app si chiude.

## Notifiche e deep link

7. **Payload FCM ibrido obbligatorio** (`notification` + `data`) con
   `android.notification.clickAction`. Il data-only «per far girare sempre
   `onMessageReceived`» è una strada già percorsa e fallita: ad app killata su
   HyperOS/MIUI la notifica non arriva, e senza il blocco `notification`
   spariscono i banner heads-up. Il tap non navigava per il **manifest**, non
   per il payload: serve un intent-filter dedicato su `MainActivity` +
   `launchMode="singleTop"`. **Le modifiche al manifest richiedono reinstall.**
8. **I timeout dei deep link si contano da quando la sync può consegnare**, non
   dal tap: a freddo il solo ripristino della sessione Firebase prende ~20 s.
   Attesa in due fasi (prima `auth.currentUser != null`, poi il dato).
9. **Anteprima chat**: resta «Nuovo messaggio» di proposito. iOS decifra nella
   Notification Service Extension, Android non ha equivalente.

## Salute

10. **Health Connect: mai nascondere una metrica quando il dato manca.** La v47
    è stata respinta perché ogni UI delle calorie era condizionata alla presenza
    del dato e il resoconto che le giustifica stava dietro `isPaidPlan`: per un
    revisore su emulatore senza indossabile il permesso era **indimostrabile**.
    Stato vuoto esplicito («—»), riga visibile anche in Free, e dichiarazione
    per-tipo in Play Console e nella privacy. Vale per ogni nuovo tipo di dato.

## Prima di dire «fatto»

- La stessa funzione esiste su iOS: confronta campi e testi, non a memoria.
- Compila col JBR; l'utente committa e pubblica (`git -C KidBoxAndroid`).
- Test unitari: `./gradlew :app:testDebugUnitTest` col JBR, conteggio dagli XML
  in `app/build/test-results/testDebugUnitTest/` (30 al 26/09/2026, 7 sono `EventRecurrenceTest`).
- Se hai toccato il manifest: reinstall, non aggiornamento.
- Aggiorna `FEATURES.md` se la parità cambia.
