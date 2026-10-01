---
name: calendario
description: Calendario di KidBox — eventi e ricorrenze, promemoria degli eventi, calendari del telefono (EventKit / CalendarContract), calendari iscritti da link (feed ICS) e «Collega Google / Outlook». Usare quando si tocca il calendario su iOS, Android o web, quando l'utente dice «un evento compare tutti i giorni», «non vedo il mio Google Calendar», «il calendario della scuola non si aggiorna», «il promemoria dell'evento non suona», o prima di proporre un'integrazione con Google o Outlook.
---

## Quattro fonti di eventi, due regole diverse

| Fonte | Dove sta | Chi la vede | Si modifica? |
|---|---|---|---|
| Eventi KidBox | `families/{id}/calendarEvents` | la famiglia (visibilità per evento) | sì |
| Promemoria | to-do con `dueAt` in `families/{id}/todos` | la famiglia | sì, è un to-do |
| Calendari del telefono | EventKit (iOS) / CalendarContract (Android), mai su Firestore | solo chi ha quel telefono | no |
| Calendari iscritti | `families/{id}/calendarFeeds/{feedId}`, eventi **dentro** il documento | tutta la famiglia, anche web | no |

Le ultime due arrivano a schermo con lo stesso tipo (`DeviceCalendarEvent` su
iOS e Android, oggetti con `_feed` sul web): `feedId` valorizzato vuol dire
«iscritto». Da entrambe si esce solo con **«Copia in KidBox»**, che crea un
evento normale e indipendente. Un evento esterno già copiato non si disegna due
volte: il confronto è **per contenuto** (titolo normalizzato, minuto d'inizio,
tutto-il-giorno), così sparisce anche all'altro genitore che ha lo stesso evento
sul suo Google senza aver copiato niente.

File: iOS `Features/Calendar/` (`DeviceCalendarStore`, `CalendarFeedStore`,
`DeviceCalendarViews`, `KBEventOccurrence`); Android `data/devicecalendar`,
`data/calendarfeed`, `domain/calendar/EventRecurrence.kt`,
`ui/screens/calendar/DeviceCalendarUi.kt`; web `hooks/useCalendarFeeds.js`,
`calendarUtils.js`; server `functions/calendarFeeds.js`.

## Ricorrenze

- **Nessun client le espandeva fino al 26/09/2026.** Ora sì, con la stessa
  funzione sui tre client e gli stessi casi limite (test Android
  `EventRecurrenceTest`): ogni occorrenza è `inizio + n × passo` dall'inizio
  originale, mai dalla precedente (il 31 cade l'ultimo giorno dei mesi corti e
  torna al 31); orario da orologio attraverso l'ora legale; 29 febbraio → 28.
- **Le ripetizioni sono copie con lo stesso id della serie.** Servono a
  disegnare. Si modifica e si cancella **la serie** (`seriesOf` su Android,
  `occurrence.event` su iOS, `_series` sul web), mai la copia: si scriverebbero
  sulla serie le date di una ripetizione. Non esistono eccezioni per singola
  data: eliminare da una ripetizione chiede conferma e cancella tutto.
- **Si espande una finestra**, non la serie intera (non ha fine): l'anno del
  giorno guardato più qualche mese. La vista Anno calcola ogni anno quando la
  sua riga compare.
- **«Giornaliera» veniva letta come «dura tutta la giornata».** Quando le
  ricorrenze sono diventate visibili, 9 eventi su 189 (Pasqua, pranzi, un esame)
  sono comparsi ogni giorno. Corretti su Firestore con `updatedBy`
  «kidbox-maintenance» (`analytics.js` conta ogni update come attività di
  `updatedBy`); etichette ora «Non si ripete / Ogni giorno…». Se cambi le
  etichette, controlla con un audit che i valori salvati siano plausibili.

## Promemoria degli eventi

Sono del dispositivo che salva l'evento (vedi `/notifiche`). Su una serie si
arma la **prossima** ripetizione, non la prima (su una serie già iniziata non
suonava mai). iOS: le prossime 3 come notifiche singole, registro
`KBDeviceReminderLedger` (`calendarEvent:<id>`) e riarmo al rientro in app;
niente trigger `repeats`, seguono il calendario e non la serie. Android: una
sola, e il ricevitore arma la successiva quando suona (`rearmAfterFire`).

## Calendari del telefono

- **Sola lettura, niente server.** La sincronizzazione con Google, iCloud o
  Outlook la fa il sistema; KidBox rilegge su `EKEventStoreChanged` /
  `ContentObserver`. Le preferenze (interruttore, calendari nascosti — si
  salvano i nascosti, così un account nuovo compare da solo) sono del
  dispositivo.
- **Android, due trappole di `CalendarContract`:** gli eventi tutto-il-giorno
  sono a mezzanotte **UTC** (vanno riportati alla mezzanotte locale della stessa
  data) e la fine è **esclusa** (nelle mappe per giorno togliere un
  millisecondo). E su Xiaomi/MIUI i calendari locali hanno per nome una chiave
  (`calendar_displayname_local`, `account_name_local`): `readableName`.
- **Google e Outlook ci arrivano aggiungendo l'account al telefono.**
  «Collega un account»: Android apre `Settings.ACTION_ADD_ACCOUNT` per Google;
  Outlook non passa dagli account di sistema, lo sincronizza l'app Outlook
  (package dichiarato in `<queries>`, Play Store esplicito perché su Xiaomi
  `market://` apre la scelta con GetApps). iOS non può aprire la schermata
  degli account: si danno i passi e «Apri Impostazioni».

## Calendari iscritti (feed ICS)

- **Lo scrive solo il server.** Le rules escludono `calendarFeeds` dal write del
  wildcard: un client potrebbe iniettare eventi o puntare il refresh verso un
  indirizzo interno. `saveCalendarFeed` scarica subito il link (difese SSRF:
  DNS verso IP privati e metadata, redirect ricontrollati, 5 MB, 15 s),
  `refreshCalendarFeeds` ogni 6 ore con ETag, `deleteCalendarFeed`.
- **Le occorrenze le espande il server** con `ical.js` (RRULE, EXDATE,
  RECURRENCE-ID, fusi) e le salva nel documento: una lettura per feed.
  Tutto-il-giorno come `"YYYY-MM-DD"` (fine esclusa), orari in ms. Un `TZID`
  senza `VTIMEZONE` nel file va risolto con `Intl`, o una riunione delle 9 a New
  York finisce alle 9 italiane.
- **Google Calendar risponde 429 alle Cloud Functions** (non a Cloud Shell, non
  ai telefoni, con qualunque User-Agent). Ripiego: l'app scarica il `.ics` dal
  telefono e lo manda (`icsText` a `saveCalendarFeed`,
  `uploadCalendarFeedContent` per i refresh); all'apertura del calendario le app
  rinfrescano i feed con errore o più vecchi di 12 ore. Il web non può (CORS):
  per i link Google rimanda all'app. 429 e 5xx sono «riprova più tardi», non
  «link privato».
- **L'URL è leggibile da tutti i membri.** Per l'«indirizzo segreto» di Google
  vuol dire dare a tutta la famiglia la lettura di quel calendario: il dialogo
  lo dice.

## Gli eventi non hanno partecipanti

`calendarEvents` ha `childId` e `createdBy`, **non** chi partecipa. Quindi «chi è
libero alle 16?» non si calcola dagli eventi: attribuirli a chi li ha creati è
sbagliato (spesso un genitore inserisce gli impegni di tutti). Nel «Chiedi a…»
delle richieste (`/richieste`) gli eventi della fascia oraria si mostrano come
contesto non attribuito, e accanto ai membri solo i to-do **assegnati** a loro.
Aggiungere i partecipanti agli eventi è stato scartato il 01/10/2026: lavoro
sui tre client e valore zero finché nessuno li compila.

## Cosa non fare

- **OAuth con Google Calendar API o Microsoft Graph**: scartato due volte
  (17/09 e 26/09). Verifica Google dello scope calendari, token per utente,
  sync lato server — per un valore quasi uguale a «account sul telefono» +
  «link iCal». Riaprire solo se i dati mostrano che la gente si ferma lì.
- **Salvare le ripetizioni come eventi**: moltiplica i documenti e rompe la
  modifica della serie.

## Prima di dire «fatto»

- Le tre superfici: iOS, Android, web (il web non ha i calendari del telefono).
- Stringhe in quattro lingue (`/localizzazione`); le etichette della ricorrenza
  sono in `KBCalendarEvent.swift`, `calendar_recurrence_*`, `t.calendar.recurrences`.
- Sul telefono vero l'app gira (il simulatore iOS si ferma al login): installare
  la build di debug con `adb install -r -t` sopra quella di Studio tiene dati e
  login; mai sopra una build dello Store senza chiedere.
