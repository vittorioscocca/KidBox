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
- Se hai toccato il manifest: reinstall, non aggiornamento.
- Aggiorna `FEATURES.md` se la parità cambia.
