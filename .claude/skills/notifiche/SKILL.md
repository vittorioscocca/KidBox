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

Aperto: le uscite lampo (fuori e dentro in pochi minuti) passano ancora. Il
rimedio è ritardare l'avviso di uscita e annullarlo se il rientro arriva
prima; sui dati toglie altre ~50 notifiche su 87 per Cosimo, ma ritarda ogni
uscita vera: è una scelta di prodotto dell'utente.

Per misurare: leggere `geofenceEvents` della famiglia, ordinare per
`timestamp`, contare tipi ripetuti, raffiche < 2 s e coppie uscita→rientro;
i log di `onGeofenceEvent` dicono quali eventi sono stati scartati e perché.

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
