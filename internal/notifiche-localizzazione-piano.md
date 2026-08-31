# Localizzazione notifiche — piano

Stato al 2026-08-31. Fonte di verità del piano; la memoria di Claude punta qui.

## Il problema

Nessuna notifica è localizzata, e non esiste alcun meccanismo per scegliere la lingua.

- **Remote (FCM da functions)**: `title`/`body` sono letterali italiani in `functions/index.js`
  (`:372`, `:720`, `:6029`, `:6333`). Il server non sa in che lingua sta l'utente: il doc token
  salva solo `token`/`platform`/`updatedAt`, e su `users/{uid}` non c'è nessun campo lingua.
- **Locali iOS**: `UNMutableNotificationContent.title` è una `String`, non una `LocalizedStringKey`,
  quindi **non passa dal String Catalog** (stessa trappola di `project_ios_stringhe_non_tradotte`).
  Solo 3 file usano `String(localized:)`: esami, vaccini, todo. Tutti gli altri sono italiano
  hardcoded: abbonamento, password, wallet documenti, casa, veicoli, briefing/sintesi/pattern AI,
  estensione menzioni.
- **Promemoria**: sono notifiche locali schedulate, stesso trattamento — ma con in più il problema
  del congelamento nel tempo (sotto).

## Fatto di partenza: il selettore lingua esiste già

`KidBox/Features/Settings/Language/AppLanguage.swift` — `LanguageManager.apply()`, 4 lingue
(it/en/fr/es + system), live-swap del bundle senza riavvio. È il punto unico dove agganciare
"quando l'utente cambia lingua". `resolvedLanguageCode(for:)` dà il codice effettivo anche per `.system`.

## 1. Remote — FATTO (2026-08-31), da deployare

Implementato come descritto sotto. In sintesi:

- `functions/notificationsI18n.js` (nuovo): catalogo it/en/fr/es, `t(lang, key, params)` con
  segnaposto `{nome}`, `normalizeLang` (accetta `en` come `en-US`, fallback `it`), più
  `walletKindLabel`, `formatLongDate`, `formatShortDateTime`, `formatCurrency` — date e importi
  seguono la lingua del destinatario, il fuso resta Europe/Rome.
- `getTokensForUsers` restituisce anche `lang` per uid: legge sempre i doc utente (prima li leggeva
  solo con `prefField`), così la lingua c'è anche per le notifiche non disattivabili.
- Tradotti tutti gli 11 handler: documento, chat (+menzioni), posizione, geofence, spesa, nota,
  calendario, spese, biglietto Wallet, carta fedeltà, promemoria biglietto. Le vecchie
  `walletKindLabel`/`formatWalletDate` italiane sono sparite, sostituite da quelle del modulo.
- **Non tradotti di proposito**: il broadcast dalla console (testo scritto dall'admin) e le push
  ticket critical (destinatari admin interni). Restano contenuto dell'utente, e quindi intatti, il
  corpo dei messaggi di chat, i nomi dei documenti, i titoli di spese ed eventi.
- Client iOS: `LanguageManager.currentLanguageCode` espone la lingua risolta;
  `NotificationManager.syncNotificationLanguage()` scrive il campo, chiamata dentro
  `persistFCMToken` (ogni avvio) e da `LanguageSettingsView` al cambio lingua.
- Client Android: `AppLanguage.resolvedTag()`/`resolvedTagFor()`,
  `PushNotificationManager.syncNotificationLanguage(tag)`, chiamata da `persistFcmToken` e dal
  `LanguageViewModel` **prima** di applicare la lingua — `setLanguage` ricrea le activity e porta
  via il `viewModelScope`, mentre la chiamata Firestore già partita l'SDK la completa da sé.
- Le rules non sono state toccate: `users/{uid}` è già aggiornabile dal proprietario tranne `plan`.

Restano da fare: deploy delle functions, e la verifica su device che le push arrivino tradotte.

## 1b. Remote — approccio scelto (razionale)

Preferenza persistita lato utente, testo tradotto lato server.

- **Scrittura**: `users/{uid}.notificationLanguage` da `LanguageManager.apply()`, **e anche al login**
  (per chi non tocca mai il selettore), usando `resolvedLanguageCode`. Sta su `users/{uid}` e non sul
  token doc perché la scelta è dell'utente, non del device — e le functions quel doc lo leggono già.
- **Lettura**: helper `pickLang(uid)` nelle functions + tabella stringhe per lingua (fallback `it`),
  al posto dei letterali hardcoded.
- **Attenzione**: dove il server manda testo *generato* e non a template (chat `fallbackBody`,
  briefing/sintesi AI) tradurre la cornice non basta — la stessa preferenza va passata alla
  generazione AI.
- **Scartato**: `loc-key`/`title_loc_key` risolti dal device. Elegante ma richiede chiavi stabili
  duplicate in catalogo iOS e `strings.xml`, e non copre il testo generato. Da riconsiderare solo
  se le lingue diventassero molte.

## 2. Locali iOS — FATTO (2026-08-31)

`KBNotificationLocalization` (nuovo, in `App/Notification/`) risolve il congelamento senza toccare la
logica di scheduling dei singoli servizi:

- `setText(on:titleKey:titleArgs:bodyKey:bodyArgs:)` scrive il testo tradotto **e** lascia chiave e
  argomenti dentro `userInfo`.
- `relocalizePending()` rilegge la coda al cambio lingua e riscrive i testi, riusando identifier e
  trigger — quindi non sposta di un minuto l'orario di consegna. Chiamata da `LanguageSettingsView`.
- `Arg` (`.text` / `.localized`) serve per i titoli composti da più pezzi tradotti ("Treno tra 2
  ore", "Promemoria: Assicurazione: Panda"): passando il pezzo già tradotto resterebbe nella lingua
  vecchia mentre la cornice cambia — mezzo tradotto è peggio di non tradotto. `ExpressibleByStringLiteral`
  tiene i casi semplici a `["Mario"]`.

Convertiti: esami, visite, vaccini, todo, wallet biglietti, wallet documenti, casa, veicoli, terapie,
password (scadenza + scan sicurezza), abbonamento, nudge, e i titoli dei tre servizi AI.
Aggiunti `displayNameKey` a `KBWalletTicketKind`/`KBWalletDocumentKind` e `schedulePeriodLabelArg`
per le fasce orarie delle terapie — restituiscono la chiave invece del testo tradotto (i letterali
sono ripetuti di proposito: con una chiave calcolata Xcode non li estrarrebbe più).

**Restano non tradotti, di proposito**: i corpi generati dall'AI (briefing, sintesi, pattern) — si
riscrivono rigenerandoli, non traducendoli; i contenuti dell'utente (titolo del todo, del biglietto,
del documento); e i nudge con override remoto, che sono già una frase scelta senza chiave dietro.

Note collegate:
- La NSE (`KidBoxNotificationService`) non ha un proprio catalogo: **non** riscrive più il titolo
  delle menzioni, che il server manda già tradotto, e prende il sottotitolo da `mentionSubtitle`
  (nuova chiave `chat.mentionSubtitle` nelle functions).
- 21 chiavi nuove nel catalogo iOS, con en/fr/es. Il file va scritto con lo stile di Xcode
  (`"key" : value`, oggetti vuoti su tre righe, nessun riordino) o il diff diventa l'intero file.
- `NSString.localizedUserNotificationString` **non** è stato usato: la riscrittura in coda copre gli
  stessi casi senza dipendere da come iOS risolve il bundle fuori dal processo dell'app.

## 2b. Locali iOS — vincolo di partenza (razionale)

**"Controllare la lingua prima di mostrarla" non è un hook che iOS ci dà.** Una notifica locale
schedulata la renderizza il sistema senza eseguire codice dell'app: `willPresent` scatta solo in
foreground, e la Notification Service Extension vale solo per le push remote con `mutable-content`.
Il testo si congela al momento della schedulazione — un promemoria armato oggi e consegnato tra
3 mesi resta nella lingua di oggi.

Due meccanismi, da usare **entrambi** secondo il tipo di testo:

1. **`NSString.localizedUserNotificationString(forKey:arguments:)`** per i testi a template fisso
   (vaccini, esami, todo, wallet, password, casa, veicoli): si salva la chiave, il sistema risolve
   alla consegna. Oggi 0 occorrenze nel progetto.
   *Da verificare su device reale*: risolvendo iOS fuori dal nostro processo, non è scontato che
   rispetti il live-swap del bundle di `LanguageManager` invece della lingua di sistema. Il trucco
   `AppleLanguages` in UserDefaults di solito basta, ma va provato.
2. **Riprogrammazione al cambio lingua** dentro `apply()`. Deterministico e indipendente dal punto 1,
   ed è l'**unico** modo per i testi non-template (briefing, sintesi settimanale, pattern salute),
   dove il corpo è generato dall'AI e va rigenerato, non ritradotto.

Infrastruttura già presente per il punto 2: `rescheduleAllActive` esiste per casa e veicoli
(`KidBoxApp.swift:575`), e `KBDeviceReminderLedger` sa già quali promemoria appartengono a questo
device. Manca l'equivalente per wallet, vaccini, visite, esami, terapie, todo.

## 3. Android — FATTO (2026-08-31)

Approccio **diverso da iOS, e più semplice**: su Android il nostro codice gira quando l'alarm scatta,
quindi non serve riscrivere la coda — basta non congelare il testo. `KBNotificationText` (nuovo, in
`notifications/`) fa viaggiare negli extra il **nome della risorsa** e i suoi argomenti; la frase la
compone il receiver, con le risorse della lingua di quel momento.

- Si passa il **nome** e non l'id numerico: gli id cambiano a ogni build e un alarm armato prima di
  un aggiornamento gli sopravvive, quindi con l'id mostrerebbe la stringa sbagliata. La mappa
  `KEYS` è esplicita (niente `getIdentifier`) così R8 non rimuove le risorse.
- Gli argomenti a loro volta traducibili si marcano con `@nome_risorsa` — stesso problema di `Arg`
  su iOS (il tipo di biglietto dentro la frase).
- **Retrocompatibilità**: i receiver leggono prima la chiave, poi il vecchio `EXTRA_TITLE`/`EXTRA_BODY`.
  I `PendingIntent` armati dalla versione precedente sopravvivono all'aggiornamento e vanno ancora
  mostrati, in italiano, finché non vengono riprogrammati.

Convertiti: esami (con variante urgente come chiave a sé, il suffisso concatenato non era
ricostruibile), visite, vaccini, wallet biglietti e documenti, password, casa, todo, nudge, i tre
servizi AI, `SecurityNotifier`, `LocationSharingService`. Vaccini e veicoli componevano già nel
receiver e sono rimasti così. 25 stringhe nuove x 4 lingue in `strings_health.xml`.

Limite accettato: la data di scadenza password resta formattata alla programmazione — per rifarla
alla consegna dovrebbe viaggiare l'epoch, e cambierebbe solo il nome del mese.

## 3b. Android — situazione di partenza

Situazione mista, in parte già corretta: i receiver che fanno `context.getString(R.string...)`
(`TodoReminderReceiver.kt:48`, vaccini in `HealthReminderReceiver.kt:217`) risolvono davvero alla
consegna, perché il nostro codice gira quando l'alarm scatta — lì il modello funziona nativamente.
Gli altri ricevono il `title` come extra dell'intent, quindi congelato alla schedulazione come su
iOS, e vanno spostati su `getString`. I servizi AI (`DailyBriefingService.kt`,
`HealthPatternAnalyzerService.kt`, `WeeklySummaryService.kt`) e `SecurityNotifier.kt` hanno gli
stessi letterali italiani di iOS.

## Ordine di esecuzione

Le tre parti sono indipendenti. Deciso: **prima il remoto**, poi il giro iOS sulle locali, poi Android.

## Landing (2026-08-31)

Portata da cinque a sette agenti, in IT e EN: aggiunte le card **Piano Alimentare** (esiste: usa dati
clinici, allergie e HealthKit) e **Piano di Movimento**, quest'ultima con badge "Presto disponibile"
perché la feature **non esiste ancora nel codice** — nessun `ActivityPlan`/`WorkoutPlan`, e `askAI`
ha solo il purpose `mealPlan`. Quando la feature arriva, togliere il `<div class="soon">` da
entrambe le pagine.

Tolto anche "Sempre in italiano" dall'eyebrow (l'app è multilingua: it/en/fr/es) e il "in italiano"
dal sottotitolo della sezione AI e dall'og:description.
