---
name: notifiche
description: Notifiche di KidBox — push dal server, notifiche locali iOS e Android, promemoria, lingua, deep link e broadcast. Usare quando si aggiunge o si corregge una notifica, quando l'utente dice «non arriva la notifica», «il promemoria non suona», «la notifica è in italiano», o quando si tocca il motore dei promemoria.
---

## Tre strade diverse, non una

| Strada | Chi la manda | Dove vive il testo |
|---|---|---|
| **Push (FCM)** | le functions | `functions/notificationsI18n.js`, tradotto server-side |
| **Locale iOS** | l'app, schedulata in anticipo | `UNMutableNotificationContent`, **congelato alla schedulazione** |
| **Locale Android** | l'app, `AlarmManager` | armato dal device che crea l'elemento |

Sbagliare strada è l'errore più comune: una notifica che deve arrivare a un
altro membro **non può** essere locale, e un promemoria che deve suonare senza
rete **non può** essere una push.

## Lingua

La preferenza è `users/{uid}.notificationLanguage` — **dell'utente, non del
device** — e si aggancia al selettore già esistente
(`Features/Settings/Language/AppLanguage.swift`, `LanguageManager.apply()`).
Il piano completo è `internal/notifiche-localizzazione-piano.md`: **aprilo prima
di toccare le notifiche**, non è una nota di colore.

Due cose che non si aggirano:

1. **Su iOS non esiste un hook prima di mostrare una notifica locale**: il
   sistema la renderizza senza eseguire codice dell'app. Quindi il testo si
   **congela al momento della schedulazione**, e chi cambia lingua deve vedere
   le notifiche **riprogrammate** dentro `apply()`. Per i template si usa
   `NSString.localizedUserNotificationString`.
2. **`UNMutableNotificationContent.title` è una `String`, non una
   `LocalizedStringKey`**: non passa dal String Catalog e non viene nemmeno
   estratta. È la stessa trappola di `/localizzazione`, e per questo la maggior
   parte delle notifiche locali è rimasta in italiano cablato.

Lato server, `getTokensForUsers` restituisce anche `lang` per uid: le date e gli
importi seguono la lingua del destinatario, il fuso resta Europe/Rome.

## Android: il payload e il tap

- **Il payload FCM deve restare ibrido** (`notification` + `data`) con
  `android.notification.clickAction`. Il data-only «così gira sempre
  `onMessageReceived`» è una strada già percorsa e fallita: ad app killata su
  HyperOS/MIUI la notifica non arriva proprio, e senza il blocco `notification`
  spariscono i banner heads-up.
- **Se il tap non naviga, guarda il manifest, non il payload.** Senza
  `clickAction` FCM usa `getLaunchIntentForPackage()`: con il task già esistente
  Android lo riporta avanti **senza consegnare l'intent**. Serve un intent-filter
  dedicato su `MainActivity` + `launchMode="singleTop"`. **Le modifiche al
  manifest richiedono reinstall**, non basta aggiornare.
- **I timeout dei deep link si contano da quando la sync può consegnare**, non
  dal tap: a freddo il ripristino della sessione Firebase prende ~20 s. Attesa
  in due fasi (prima `auth.currentUser != null`, poi il dato).
- **L'anteprima del messaggio di chat resta «Nuovo messaggio» di proposito**:
  iOS decifra nella Notification Service Extension, Android non ha equivalente.

## Token morti: pulirli, e non farli suonare come guasti

Un token FCM muore quando l'utente disinstalla o reinstalla l'app. È
**funzionamento normale**, non un guasto, e si riconosce da due codici:
`messaging/registration-token-not-registered` e
`messaging/invalid-registration-token`.

Due regole, entrambe pagate:

1. **Si logga `warn`, mai `error`.** Un `logger.error` — o un `console.error`,
   che scrive la stessa severity — fa suonare l'allarme «KidBox — errore
   applicativo» per una disinstallazione. `notifyTodoAssigned` lo faceva ed era
   l'unico punto di tutte le functions (corretto il 23/09/2026). La convenzione
   generale è in `/deploy-functions`: `error` = guasto nostro, `warn` = tutto il
   resto.
2. **Il token va cancellato**, con `pruneInvalidFcmTokens(uid, tokens,
   responses, refsByToken)`. Senza la pulizia quel destinatario **smette di
   ricevere quel tipo di notifica per sempre**, in silenzio: nessun errore,
   `successCount` a zero e nessuno che se ne accorge. Passa `refsByToken` se ce
   l'hai (`getTokensForUsers` lo restituisce); se no il helper rilegge la
   collezione — una query in più, solo quando c'è davvero un fallimento.
   Attenzione: `getUserTokensIfEnabled` restituisce **solo** i token e i ref li
   butta via.

Dal 23/09/2026 **tutte e 15 le funzioni che inviano push puliscono**. Le dieci
che non lo facevano usano `sendMulticastAndPrune(messages, owners, label)`, che
invia, conta e ripulisce in un colpo solo: `owners[i]` è il destinatario di
`messages[i]` e le due liste si riempiono fianco a fianco nello stesso giro di
ciclo. Se non combaciano, invia e **salta** la pulizia. Usalo anche tu per un
invio nuovo, invece di riscrivere `Promise.allSettled` a mano.

Due forme che non ci rientrano, e il motivo:

- `notifyUpcomingWalletTickets` salta i membri senza token, quindi l'indice del
  ciclo non coincide con quello dei membri: va per indice esplicito;
- `notifyCriticalCase` appiattisce i token di **più admin** in un unico invio,
  quindi prima di cancellare raggruppa i falliti per proprietario
  (`ownerOfToken`). Cancellare il token di un altro è peggio che lasciarne uno
  morto.

## Il motore dei promemoria to-do

`notifyDueTodoReminders` (`functions/index.js`, `europe-west1`, **ogni 5
minuti**). Due campi di proprietà del server:

- `remindAt` — l'ordine di suonare, **distinto da `dueAt`** (la scadenza
  mostrata in app: 19 to-do su 80 avevano `dueAt` e nessuno voleva una notifica);
- `remindSentAt` — l'unico presidio contro il doppio invio. Si scrive **sempre**,
  anche quando non si è inviato nulla (zero token, to-do chiuso, nessun
  destinatario), altrimenti quel documento viene riletto a ogni giro per sempre.

⚠️ **Chi scrive `remindAt` deve scrivere anche `remindSentAt: null` esplicito.**
La query è `where("remindSentAt","==",null)`, e in Firestore **un campo assente
non è uguale a `null`**: un documento senza quel campo resta invisibile per
sempre, in silenzio. Verificato sull'emulatore: il caso «campo assente» non
viene pescato.

## I promemoria locali sono del device

Scelta di design confermata: un elemento creato su iOS che arriva su Android via
sync **non deve** armare alcun alarm. Non è un bug.

Conseguenza sul ripristino dopo un reboot: rileggere Room al `BOOT_COMPLETED`
sarebbe la strada ovvia ed è **sbagliata**, perché resusciterebbe anche i
promemoria sincronizzati da altri dispositivi. Il ripristino passa da
`ReminderAlarmRegistry` (SharedPrefs `kb_reminder_alarms`), che persiste la
ricetta di ogni alarm armato **localmente**; `BootReceiver` chiama
`restoreAll()`. Su iOS il filtro è `KBDeviceReminderLedger`.
Eccezioni storiche con semantica famiglia-wide: veicoli, pagamenti casa,
password — quelli sì si ripristinano da Room.

### Eventi ricorrenti del calendario (dal 26/09/2026)

`recurrenceRaw` non lo espandeva nessun client, e il promemoria armava la
**prima** data della serie: su una serie già iniziata non suonava mai. Ora si
arma sempre la **prossima** ripetizione, con due strategie diverse:

- **iOS** (`CalendarEventReminderService`): le prossime 3 ripetizioni come
  notifiche singole (`calendar.reminder.<id>`, `.1`, `.2`; la sveglia AlarmKit
  solo la prossima: ne tiene una per elemento), iscrizione a
  `KBDeviceReminderLedger` con chiave `calendarEvent:<id>`, e
  `rescheduleArmed` nella manutenzione al rientro in app (`KidBoxApp`). Niente
  trigger `repeats: true`: seguono il calendario, non la serie (il mensile del
  31 salterebbe i mesi corti) e resterebbero in coda per sempre.
- **Android** (`CalendarEventReminderScheduler`): una sola ripetizione; quando
  suona, `CalendarEventReminderReceiver`/`UrgentAlarmReceiver` chiamano
  `rearmAfterFire`, che rilegge Room e arma la successiva. La catena si regge
  ad app chiusa e il reboot la riprende dal registro.

In entrambi il riarmo parte solo da ciò che **questo** device aveva armato,
ma legge l'evento locale: per una serie le modifiche fatte altrove (orario,
avviso tolto, evento cancellato) arrivano anche qui. Il resto del calendario
(ricorrenze, calendari del telefono e iscritti) è in `/calendario`.

## Zone di arrivo e uscita (geofence)

Il server **non** decide niente: l'«entrato/uscito» lo decide il telefono di
chi si muove (GeofencingClient su Android, region monitoring su iOS), che
scrive `families/{id}/geofenceEvents`; `onGeofenceEvent` lo inoltra a
`notifyMembers`. Quello che il telefono manda non è una sequenza pulita di
attraversamenti — misurato il 24/09/2026 su «Casa genitore» (Famiglia Scocca,
due Android, giugno-settembre): 484 eventi, **356 che ripetevano il tipo
precedente** (anche tre nello stesso secondo: coda offline che si svuota,
ri-registrazione delle zone), e metà delle uscite di Cosimo rientrate in meno
di 5 minuti (GPS che oscilla sul bordo).

Presidi oggi, da non togliere:
- **Stato per zona e persona** in `families/{id}/geofenceState/{geofenceId}_{uid}`,
  aggiornato in transazione: si avvisa solo se il tipo cambia. I filtri
  `notifyOnArrive`/`notifyOnLeave` vengono **dopo** lo stato, o un'uscita non
  notificata farebbe sembrare doppione il rientro. `geofenceState` è in
  `FAMILY_SUBCOLLECTIONS` (cancellata con la famiglia).
- **Eventi in ritardo**: i client dal 24/09 scrivono `clientAt` (ms); se è più
  vecchio di 15 minuti lo stato si aggiorna ma non si avvisa. `timestamp` è
  l'ora d'arrivo al server, non dell'evento: non usarlo per giudicare.
- **Raggio sempre numerico**: una stringa viene letta come assente e i client
  ripiegano su 200 m. Attenzione nel leggere i dati via REST: gli interi
  tornano come `"integerValue": "400"`, fra virgolette — non è una stringa.

- **Uscite rimandate di 5 minuti** (scelta dell'utente del 24/09/2026, 5 e non
  10): l'uscita scrive `pendingLeaveDueAt` sullo stato invece di avvisare; un
  rientro prima della scadenza annulla **tutti e due** gli avvisi (per chi
  riceve non è successo niente); `sendDueGeofenceLeaves`, ogni minuto, manda
  le uscite scadute riverificando stato e zona in transazione. L'avviso arriva
  quindi 5-6 minuti dopo l'uscita; gli arrivi restano immediati. La query del
  job è una collection group su `geofenceState.pendingLeaveDueAt`: senza
  l'esenzione in `firestore.indexes.json` fallisce. Sui dati di giugno-settembre
  Cosimo passava da 363 avvisi a ~47, Maria Pia da 119 a ~35.
- **Zone solo-arrivo** (dal 30/09/2026). Il principio del primo punto («i
  filtri dopo lo stato») i client **non** lo rispettano: registrano sul
  telefono solo il passaggio da avvisare (iOS `notifyOnExit = notifyOnLeave`,
  Android `setTransitionTypes` dai flag, più un filtro nel receiver). E
  l'uscita nasce spenta negli editor, quindi è il caso di default: dopo il
  primo arrivo `lastType` restava «arrive» e ogni arrivo successivo era un
  doppione, per sempre. Per queste zone ora il doppione è un arrivo entro 30
  minuti dal precedente (`lastEventAt`, finestra che scorre); oltre, è un
  arrivo nuovo. Prezzo misurato simulando «Casa genitore» come solo-arrivo,
  dal 24/09: 10 giusti, 3 persi, 8 in più (GPS che oscilla sul bordo dopo ore
  di permanenza). Vale solo per gli arrivi: un «è arrivato» in più dice una
  cosa vera, un «è uscito» falso no. La cura vera è nei client: dalle build
  del 30/09 sera (iOS `GeofenceMonitorService`, Android `toAndroidGeofence`)
  ogni zona che avvisa qualcosa si registra con entrata E uscita e il
  telefono manda tutti e due i passaggi; iOS porta anche le regioni già
  registrate a entrambe all'avvio. Da lì la finestra dei 30 minuti scatta
  solo per le build vecchie, e `leftAt` sullo stato scarta il rientro entro
  5 minuti anche dove l'uscita non si avvisa.
- **Gli eventi scadono dopo 30 giorni** (scelta dell'utente, 30/09/2026):
  `onGeofenceEvent` scrive `expireAt` e la TTL di Firestore su
  `geofenceEvents.expireAt` li cancella. Gli eventi scritti prima del 30/09
  non hanno il campo e restano, finché non si decide a parte.

Limite noto, accettato il 24/09/2026: se il telefono perde un'uscita (GPS
spento, zona ri-registrata) e poi manda l'arrivo, il server lo legge come
doppione e l'arrivo vero **non** si avvisa. Prima si avvisava, al prezzo di
356 doppioni su 484 eventi. Se arrivano segnalazioni di «non mi ha avvisato
che è arrivato», i log di `onGeofenceEvent` dicono l'esito di ogni evento
(`same`, `silent`, `deferred`, `cancelled`): è da lì che si parte, non dal
togliere il filtro.

Per verificare dal vivo senza avvisare nessuno: famiglia `ZZZ-TEST-GEO`, zona
con `notifyMembers: ["ZZZ-NESSUNO"]` (arrivare a «no per-user notifications
to send» vuol dire che l'invio è partito), eventi scritti via REST con token
Owner e `clientAt` attuale. Casi: doppione → «stesso stato»; uscita + rientro
entro 5 min → «entrambi annullati»; uscita sola → dopo ~5-6 min log di
`sendduegeofenceleaves`; `clientAt` vecchio di 30 min → «stato aggiornato
senza notifica». L'attesa si fa con un Bash in background, non con `sleep` in
primo piano. Poi pulizia con `scripts/firestore-delete-doc.js` (zona, eventi e
stati `geofenceState`). Il 24/09/2026 tutti e cinque i casi sono passati.
Zona solo-arrivo (30/09/2026, famiglia senza membri così non parte nulla):
arrivo con `clientAt` di 50 min fa → «senza notifica»; arrivo di 45 min fa →
«stesso stato»; arrivo attuale → arriva all'invio («members subcollection is
empty»). E ogni evento deve avere `expireAt`.

Per misurare: leggere `geofenceEvents` della famiglia, ordinare per
`timestamp`, contare tipi ripetuti, raffiche < 2 s e coppie uscita→rientro;
i log di `onGeofenceEvent` dicono quali eventi sono stati scartati e perché.

## Notifiche con azioni (richieste di famiglia, dal 01/10/2026)

Una push con bottoni sotto: «Ci penso io» / «Non posso». Il dettaglio sta in
`/richieste`; qui le regole che valgono per ogni notifica con azioni.

- **iOS**: il server mette `aps.category`, il client registra la categoria in
  `KBNotificationCategoryRegistry` (unico punto: `setNotificationCategories`
  sostituisce tutto) e gestisce l'azione in `AppDelegate.didReceive` **prima**
  del deep link. Un'azione che deve mostrare un esito va `.foreground`; una in
  background, se fallisce, lascia una notifica locale di riprova invece di
  perdersi. Le build senza categoria mostrano la notifica normale: innocuo.
- **Android**: i bottoni esistono solo quando la notifica la costruisce
  `onMessageReceived`, cioè con l'app aperta. Ad app chiusa la disegna il
  sistema dal blocco `notification` e i bottoni non ci sono: **non** si passa
  al data-only per averli. Un'azione che apre l'app va `PendingIntent.getActivity`
  diretto (da Android 12 un receiver non può aprire un'Activity partendo da una
  notifica); quella in background è un `BroadcastReceiver` con `goAsync()`.
- Su HyperOS una notifica compressa non si espande via `adb`: per verificare i
  bottoni si legge `adb shell dumpsys notification --noredact` (`actions=2` e
  i titoli).
- **Web**: `webpushOptions` (server) **e** il service worker
  (`firebase-messaging-sw.js`, che calcola la rotta da sé) vanno cambiati
  insieme, o il clic porta in posti diversi.

**Promemoria programmati dal server con un campo-orario** (`nudgeAt` del
sollecito, come `remindAt`): la query è `campo <= now`, e in Firestore `null`
viene prima di ogni Timestamp. Dopo l'uso il campo si **cancella**
(`FieldValue.delete()`), mai a `null`, o il documento viene ripescato a ogni
giro. Consumarlo in transazione **prima** di mandare: al massimo un invio
anche se due giri si sovrappongono.

## Broadcast e nudge

Il **broadcast manuale dalla console** è deployato. Il motore di nudge
automatico non è iniziato, e la decisione architetturale è già presa:

- il **server** sa *chi* è dormiente (i rollup `metrics/{data}` hanno gli `uids`
  con azioni di valore) ma **non** *cosa* un utente non usa: `byFeature` è
  aggregato sulla popolazione, e costruire un profilo feature-per-utente
  contraddirebbe il vincolo privacy dichiarato in `functions/analytics.js`;
- quindi **il client** decide quale feature suggerire, dai propri dati locali;
- il **server** ospita regole, testi e frequenze (`config/nudges`), così la
  cadenza si cambia senza release;
- la consegna è una **notifica locale pre-schedulata**, non una push.

## Prima di dire «fatto»

- Il testo è tradotto in tutte e quattro le lingue? (`/localizzazione`)
- Se è locale: quale device la arma, e sopravvive a un reboot?
- Se è push: il destinatario ha un token? il payload è ibrido? il tap dove porta?
- Se è un invio nuovo: i fallimenti sono `warn` (non `error`) e chiami
  `pruneInvalidFcmTokens`?
- Se scrive `remindAt`: c'è il `remindSentAt: null` esplicito?
