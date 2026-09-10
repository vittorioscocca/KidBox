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

**Nel codice delle functions, `logger.error` significa guasto nostro,
`logger.warn` significa richiesta respinta al client.**

Non è una questione di stile: l'allarme "errore applicativo" conta i log di
livello ERROR. Un rifiuto legittimo loggato con `logger.error` fa suonare
l'allarme per il funzionamento normale.

## Le policy

| Nome | Cosa guarda | Soglia |
|---|---|---|
| KidBox — scheduler in errore | esecuzioni non-ok dei 7 scheduler | 0 (qualsiasi errore) |
| KidBox — errore applicativo | log severity>=ERROR da qualsiasi function | 0, finestra 10 min |
| KidBox — letture Firestore verso il free tier | letture ultime 24h | 35.000 (70% del free tier) |
| KidBox — scritture Firestore verso il free tier | scritture/ora per 2h | 600 |
| KidBox — invocazioni functions verso il free tier | invocazioni/ora per 1h | 1.500 |

**Scheduler coperti dalla prima policy** — l'elenco è cablato nel filtro, un
nuovo scheduler va aggiunto lì a mano: `analyticsRollupDaily`,
`cleanupResolvedCases`, `expireTemporaryLocations`, `garbageCollectDeleted`,
`notifyDueTodoReminders`, `notifyUpcomingWalletTickets`, `syncPlansConfig`.

## Perché è fatta così (10/09/2026)

Prima esisteva una sola policy sulle functions: `status != ok`, soglia 0, su
tutte le funzioni. Per le callable *ogni* rifiuto legittimo a un client
(`permission-denied`, `failed-precondition`, quota AI esaurita) è
un'esecuzione non-ok, e la metrica non distingue: l'etichetta `status` vale
`error` per tutti, sia per il crash sia per il "no" dato a un utente.

Risultato misurato sui 7 giorni al 10/09: **48 esecuzioni non-ok, di cui una
sola era un guasto** (`notifyDueTodoReminders` fermo mentre si costruiva
l'indice `todos(remindSentAt, remindAt)`). Le altre 47 erano presidi che
funzionavano. Quel giorno il guasto vero è arrivato in mezzo a sei falsi
allarmi. Col filtro attuale, la stessa settimana produce 1 allarme.

Sulle letture, la vecchia soglia era 1.500/ora per due ore e la documentazione
della policy affermava una baseline di ~830/ora. È falso: a riposo il progetto
fa **0-5 letture/ora**, e quando qualcuno usa l'app fa **2.000-5.700/ora**. Un
picco orario è solo qualcuno che ha aperto KidBox. Quello che conta è il totale
del giorno: 39.006 letture il 7/09 con due-tre famiglie attive, cioè il 78% del
free tier. Il consumo scala con gli utenti attivi, non col tempo — se questo
allarme diventa frequente la risposta non è alzare la soglia, è capire perché
una sessione d'app costa migliaia di query.
