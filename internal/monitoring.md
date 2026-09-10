# Allarmi Cloud Monitoring

Le policy vivono in GCP (progetto `kidbox-42cd7`), non nel repo: questo file è
l'unico posto in cui sono scritte. Si leggono e si modificano via API:

```
TOKEN=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOKEN" \
  https://monitoring.googleapis.com/v3/projects/kidbox-42cd7/alertPolicies
```

Canale di notifica unico: email a ing.vittorioscocca@gmail.com
(`notificationChannels/14215284348497766316`).

## La convenzione che regge tutto

**Su una callable, a decidere se scatta l'allarme è il codice dell'`HttpsError`,
non il livello di log.**

Questa è la regola completa, ed è più larga di come era scritta qui prima. La
metrica `kidbox_function_errors` conta `resource.type="cloud_run_revision" AND
severity>=ERROR`, e a livello ERROR ci finiscono **due** cose diverse:

1. i log che scrive il nostro codice — lì contano `logger.error` (guasto) vs
   `logger.warn` (rifiuto al client);
2. i **request log di Cloud Run**, la cui severity la decide lo status HTTP e
   non il nostro codice.

La seconda voce è quella che si dimentica. Mappa misurata sui 48 non-ok della
settimana 4-10/09:

| HTTP | severity | allarme |
|---|---|---|
| 400 `invalid-argument`, `failed-precondition` | `WARNING` | no |
| 403 `permission-denied` | `WARNING` | no |
| 405 | `WARNING` | no |
| 429 `resource-exhausted` (quota AI) | `WARNING` | no |
| **500 `internal`**, 503 `unavailable`, 504 `deadline-exceeded` | **`ERROR`** | **sì** |

Le due conseguenze pratiche:

- **Un rifiuto legittimo tirato come `internal` suona comunque**, per quanto lo
  si logghi con `warn`. Era il caso di `searchTravelPlaces`, corretto in
  `failed-precondition` il 10/09 per allinearlo a `searchTravelDestinations` e
  `getTravelPlaceDetails`, che già trattavano così un errore di Google Places.
- **Ogni `throw new HttpsError("internal", ...)` deve essere preceduto da un
  `logger.error`**, altrimenti l'allarme arriva su un 500 nudo e non resta
  traccia del perché. Vedi sotto: è successo davvero.

## Le policy

| Nome | Cosa guarda | Soglia |
|---|---|---|
| KidBox — scheduler in errore | esecuzioni non-ok dei 7 scheduler | 0 (qualsiasi errore) |
| KidBox — scheduler muto | scheduler che smette di essere invocato | assenza di esecuzioni |
| KidBox — errore applicativo | log severity>=ERROR da qualsiasi function | 0, finestra 10 min |
| KidBox — letture Firestore verso il free tier | letture ultime 24h | 35.000 (70% del free tier) |
| KidBox — scritture Firestore verso il free tier | scritture/ora per 2h | 600 |
| KidBox — invocazioni functions verso il free tier | invocazioni/ora per 1h | 1.500 |

**Scheduler coperti dalla policy "in errore"** — l'elenco è cablato nel filtro,
un nuovo scheduler va aggiunto lì a mano: `analyticsRollupDaily`,
`cleanupResolvedCases`, `expireTemporaryLocations`, `garbageCollectDeleted`,
`notifyDueTodoReminders`, `notifyUpcomingWalletTickets`, `syncPlansConfig`.

### "Scheduler muto": il buco che le altre due non vedono

Entrambe le policy sulle functions hanno bisogno di **un'esecuzione** per
accorgersi di qualcosa. Uno scheduler che smette di essere invocato — job Cloud
Scheduler in pausa, deploy che perde il trigger — non produce né esecuzioni
non-ok né log ERROR: produce silenzio. È lo scenario per cui questi allarmi
sono nati (tre scheduler fermi da settimane, agosto 2026), ed è rimasto scoperto
fino al 10/09.

Finestre calibrate sui gap veri misurati dal 20/08 al 10/09, non a occhio:

| Scheduler | Cadenza | Gap peggiore misurato | Finestra |
|---|---|---|---|
| `expireTemporaryLocations`, `notifyDueTodoReminders` | 5 min | 5 min | 30 min |
| `notifyUpcomingWalletTickets` | 60 min | 2h25m | 4h |
| `analyticsRollupDaily`, `cleanupResolvedCases`, `syncPlansConfig` | cron 02:00 / 03:15 / 03:30 | 23h45m | 26h |

**`cleanupResolvedCases` è passato a cron il 10/09**, ed è il motivo per cui è
in tabella. Usava `every 24 hours`, che è un **intervallo** e riparte a ogni
deploy: fra il 20/08 e il 10/09 l'orario è derivato (13:00 → 09:00 → 14:00 →
11:00 → 18:00 → 00:00) con gap fino a 45h, sempre in corrispondenza di un
rilascio. Nessuna finestra sotto le 45h poteva sorvegliarlo senza suonare a ogni
deploy. Ora è `0 2 * * *` Europe/Rome — le 02:00 e non le 03:45 col resto del
gruppo notturno perché è l'ora in cui già girava, e spostarlo in avanti avrebbe
creato un buco di transizione sopra la soglia dell'allarme.

Da qui una regola generale: **uno scheduler che deve essere sorvegliabile va
scritto con un cron, non con `every N hours`.** L'intervallo è ancorato
all'ultimo run, quindi il deploy lo sposta; il cron no.

**`garbageCollectDeleted` è passato a giornaliero il 10/09** (`0 3 * * *`
Europe/Rome, prima `0 3 */5 * *`), per la stessa ragione: a 5 giorni di distanza
fra un giro e l'altro non era sorvegliabile, perché Cloud Monitoring **non
accetta finestre di assenza oltre 23h30m né allineamenti oltre 25h** (lo dice
l'API, verificato) e nessuna condizione può quindi esprimere «non gira da 5
giorni». Costo del cambio, misurato: a vuoto un giro sono 4 query che non
tornano nulla, quindi farlo 5 volte più spesso vale ~4 letture al giorno. In
cambio un documento cancellato aspetta al massimo un giorno la rimozione
definitiva invece di cinque.

> **In sospeso al 10/09:** non è ancora dentro la condizione dei cron notturni.
> L'ultimo giro a cadenza vecchia è del 06/09, quindi la finestra di 25h è
> vuota e aggiungerlo adesso aprirebbe un incidente immediato. Va aggiunto
> all'elenco `one_of(...)` della condizione «cron notturno fermo da 26h» dopo
> il primo giro giornaliero, previsto l'11/09 alle 01:00 UTC.

Sui cron notturni l'assenza non è utilizzabile per lo stesso cap: la serie di
uno scheduler giornaliero ha buchi di 24h per costruzione, quindi una condizione
di assenza suonerebbe ogni giorno. Si usa invece la somma su finestra scorrevole
di 25h, con `evaluationMissingData: EVALUATION_MISSING_DATA_ACTIVE` — senza il
quale una serie **senza punti** non verrebbe valutata affatto, che è esattamente
il guasto da vedere.

## Perché è fatta così (10/09/2026)

Prima esisteva una sola policy sulle functions: `status != ok`, soglia 0, su
tutte le funzioni. Per le callable *ogni* rifiuto legittimo a un client
(`permission-denied`, `failed-precondition`, quota AI esaurita) è
un'esecuzione non-ok, e la metrica non distingue: l'etichetta `status` vale
`error` per tutti, sia per il crash sia per il "no" dato a un utente. Verificato
sull'API: nei 48 non-ok della settimana il label ha **un solo valore distinto**,
`error`. Filtrare per status non era praticabile.

Risultato misurato sui 7 giorni al 10/09: **48 esecuzioni non-ok, di cui due
erano guasti veri.**

1. `notifyDueTodoReminders` fermo mentre si costruiva l'indice
   `todos(remindSentAt, remindAt)`, il 10/09 alle 10:06. Un solo tick saltato.
2. `askAI` il 04/09 alle 09:37:25, **HTTP 500 in 0,88s**. Questo non era stato
   visto: stava dentro i "6 di askAI" ed era indistinguibile dai 5 rifiuti 403
   che gli stavano intorno. Non aveva **nessun log applicativo** — solo un 500
   nudo nel request log — perché l'unico percorso 500 non loggato di `askAI` era
   `if (!reply)`. Da qui la regola sopra, e i log aggiunti il 10/09 su tutti i
   `throw internal` che ne erano sprovvisti (`askAI`, `generateTravelPlan`,
   `suggestTravelDestinations` ×2, `publishPlansConfig`).

Le altre 46 erano presidi che funzionavano. Riapplicando il filtro attuale a
quella stessa settimana restano **3 entry di log per 2 incidenti**, entrambi
veri: da 48 allarmi a 2.

Il caso 2 è anche l'argomento migliore a favore del cambio: un guasto vero era
già lì, e nessuno l'aveva visto perché stava in mezzo al rumore.

Sulle letture, la vecchia soglia era 1.500/ora per due ore e la documentazione
della policy affermava una baseline di ~830/ora. È falso: a riposo il progetto
fa **0-5 letture/ora**, e quando qualcuno usa l'app fa **2.000-5.700/ora**. Un
picco orario è solo qualcuno che ha aperto KidBox. Quello che conta è il totale
del giorno: 39.006 letture il 7/09 con due-tre famiglie attive, cioè il 78% del
free tier. Il consumo scala con gli utenti attivi, non col tempo — se questo
allarme diventa frequente la risposta non è alzare la soglia, è capire perché
una sessione d'app costa migliaia di query.
