# Snapshot dei report su Firestore

Costruito il 07/11/2026. Questo file basta a rifare, spiegare o riparare tutto
da zero, anche da un altro account Claude o da una macchina nuova. **Nessun
segreto qui**: solo identificativi pubblici, nomi di ruoli e comandi.

## Cosa fa

Due funzioni pianificate leggono le fonti esterne e scrivono il risultato su
Firestore, in `reportSnapshots/{fonte}_{YYYY-MM-DD}`. Gli script di report
(`scripts/*-daily-report.js`) leggono quello snapshot invece di richiamare le
API, e ripiegano sul vivo se manca. Si ottiene anche uno storico che le API non
conservano.

| Funzione | Quando (Roma) | Fonti scritte | Identità di runtime |
|---|---|---|---|
| `reportSnapshotDaily` | 07:30 | `ga4`, `searchConsole` | `ga4-reader` |
| `reportSnapshotStoreDaily` | 11:00 | `play` (solo crash, ANR, recensioni), `billing` | `report-snapshotter` |

Codice: `functions/reportSnapshots.js` (le due funzioni e gli helper).
**Raccolta dati: una sola copia** in `functions/reportCollectors/`
(`ga4.js`, `searchConsole.js`, `play.js`, `billing.js`), usata sia dalla
funzione sia dallo script in modalità `--live`. Una modifica alle query si fa
lì, mai negli script. I collector hanno `/* eslint-disable */` (stile
prettier degli script) e nessuna dipendenza: solo `fetch`.

## Formato del documento

Campi: `source`, `day` (data di scrittura, fuso di Roma), `ok`, `error` (se
fallito), `dataThrough` (ultimo giorno che la fonte ha davvero), `computedAt`
(timestamp server), `payloadJson` (**stringa JSON**: lo stesso oggetto che lo
script stampa con `--json`, senza `origin` e senza gli obiettivi di Search
Console). Stringa e non mappa perché Firestore non accetta `undefined` né punti
nei nomi dei campi e il limite è 1 MB (la funzione scarta oltre 900 000
caratteri). Una fonte che fallisce scrive comunque il documento con `ok:false`.

Rules: `reportSnapshots/{docId}` lettura solo `isAdmin()`, scrittura `false`
(le funzioni scrivono con IAM, non con le rules). Test in `firestore-tests/rules.test.js`.

## Come li leggono gli script

`scripts/lib/snapshot.js` → `readSnapshot(fonte)`: REST di Firestore col token
utente `gcloud` (Owner), documento di oggi (fuso di Roma). Restituisce il
payload oppure `{reason}` se manca, è `ok:false`, ha più di 30 ore o non si
legge. Ogni script stampa in testa `Fonte: snapshot Firestore delle HH:MM` o
`Fonte: dal vivo (motivo)`.

- `ga4-daily-report.js`, `search-console-daily-report.js`,
  `gcloud-billing-daily-report.js`: tutto da snapshot.
- `play-daily-report.js`: **solo** crash/ANR e recensioni da snapshot. Le
  installazioni vengono dall'export manuale in `internal/play-export/` e dal
  bucket (che Google non scrive più dal 13/09/2026): non sono nello snapshot.
- `--live` forza il vivo. Per GA4 anche `--day` e `--insights-from` vanno
  sempre dal vivo (lo snapshot è «ieri» con finestra standard).
- Prima delle 07:30 (GA4, Search Console) o delle 11:00 (Play, billing) il
  report ripiega sul vivo: normale.

**Non passano da Firestore** (servono segreti del Portachiavi o il token utente
a ogni giro): console Auth+Firestore, App Store Connect, Meta, Anthropic,
App Check. Portarli nello snapshot richiede i segreti in Secret Manager
(`functions:secrets:set`, lo fa l'utente).

## Permessi IAM (tutti concessi il 07/11/2026, progetto `kidbox-42cd7`)

Nessuno li concede di iniziativa: **vanno approvati dall'utente in chat**
(il sistema di permessi blocca le modifiche IAM non approvate; non aggirarlo).

| A chi | Cosa | Perché |
|---|---|---|
| `ga4-reader` | `roles/datastore.user` (progetto) | la funzione gira come lui e scrive su Firestore |
| service agent di Scheduler `service-52613538008@gcp-sa-cloudscheduler.iam.gserviceaccount.com` | `roles/iam.serviceAccountTokenCreator` su `ga4-reader` | il job Scheduler usa `ga4-reader` come identità OIDC |
| `report-snapshotter` (SA creato apposta) | `roles/datastore.user`, `roles/bigquery.jobUser` (progetto) | scrive gli snapshot, lancia le query |
| `report-snapshotter` | lettore del solo dataset `billing_export` | legge l'export della fatturazione |
| `report-snapshotter` | `roles/iam.serviceAccountTokenCreator` su `play-purchase-validator` | impersona il SA che ha accesso a Play Console |
| service agent di Scheduler | `roles/iam.serviceAccountTokenCreator` su `report-snapshotter` | come sopra |

Comandi per rifarli (dal progetto, utente Owner):

    P=kidbox-42cd7
    gcloud iam service-accounts create report-snapshotter --project=$P
    SA=report-snapshotter@$P.iam.gserviceaccount.com
    SCHED=service-52613538008@gcp-sa-cloudscheduler.iam.gserviceaccount.com
    gcloud projects add-iam-policy-binding $P --member=serviceAccount:ga4-reader@$P.iam.gserviceaccount.com --role=roles/datastore.user --condition=None
    gcloud projects add-iam-policy-binding $P --member=serviceAccount:$SA --role=roles/datastore.user --condition=None
    gcloud projects add-iam-policy-binding $P --member=serviceAccount:$SA --role=roles/bigquery.jobUser --condition=None
    gcloud iam service-accounts add-iam-policy-binding play-purchase-validator@$P.iam.gserviceaccount.com --member=serviceAccount:$SA --role=roles/iam.serviceAccountTokenCreator
    gcloud iam service-accounts add-iam-policy-binding ga4-reader@$P.iam.gserviceaccount.com --member=serviceAccount:$SCHED --role=roles/iam.serviceAccountTokenCreator
    gcloud iam service-accounts add-iam-policy-binding $SA --member=serviceAccount:$SCHED --role=roles/iam.serviceAccountTokenCreator

Il lettore del dataset **non** si dà con `bq add-iam-policy-binding` (risponde
«This feature requires allowlisting»): si aggiunge una voce `READER` con
`userByEmail` alla ACL del dataset: `bq show --format=prettyjson
$P:billing_export > ds.json`, aggiungere `{"role":"READER","userByEmail":"<SA>"}`
a `access`, salvare `{"access": [...]}` e `bq update --source file.json
$P:billing_export`.

## Deploy e verifica

    npx firebase-tools deploy --only functions:reportSnapshotDaily,functions:reportSnapshotStoreDaily --project kidbox-42cd7
    npx firebase-tools deploy --only firestore:rules --project kidbox-42cd7

Prima: `(cd functions && npx eslint . --quiet)` e `node -e "require('./index.js')"`
(procedura completa in `/deploy-functions`). Rules: la suite
`(cd firestore-tests && npm test)` **richiede Java 21**: su questo Mac si usa
`JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`.

Lanciare un job a mano e leggere il risultato:

    gcloud scheduler jobs run firebase-schedule-reportSnapshotDaily-europe-west1 --location=europe-west1 --project=kidbox-42cd7
    gcloud scheduler jobs run firebase-schedule-reportSnapshotStoreDaily-europe-west1 --location=europe-west1 --project=kidbox-42cd7
    gcloud scheduler jobs describe <job> --location=europe-west1 --project=kidbox-42cd7 --format="value(status.code,lastAttemptTime)"
    node scripts/ga4-daily-report.js | head -3        # deve dire «Fonte: snapshot Firestore»

`status.code` vuoto = riuscito; `7` = permesso negato. Dopo una funzione nuova
il **primo lancio può dare 7** per la propagazione dei permessi appena creati
(è successo due volte): aspettare 1-2 minuti e rilanciare prima di cercare altre
cause. Se resta 7: manca `tokenCreator` di Scheduler sul SA del job, oppure
l'identità del job non ha `run.invoker` sul servizio (`gcloud run services
get-iam-policy <nome-minuscolo> --region=europe-west1`). I log:
`gcloud logging read 'resource.labels.service_name="reportsnapshotdaily" severity>=WARNING' --project kidbox-42cd7 --freshness 1h`.

Leggere un documento a mano:

    T=$(gcloud auth print-access-token)
    curl -s -H "Authorization: Bearer $T" -H "x-goog-user-project: kidbox-42cd7" "https://firestore.googleapis.com/v1/projects/kidbox-42cd7/databases/(default)/documents/reportSnapshots/ga4_$(date +%F)"

## Trappole già pagate

- **Su questo Mac `timeout` non esiste**: non anteporlo ai comandi.
- Il **service account di runtime di default** (`…-compute@developer…`) NON è
  Editor: non legge BigQuery né Play. Per questo esiste `report-snapshotter`.
- `getLandingStats` e `reportSnapshots.js` condividono gli helper
  (`exports._helpers` di `landingStats.js`): non spostarli senza aggiornare
  entrambi.
- Il billing: le righe di ieri arrivano in mattinata (ultima volta alle
  06:57); `payload.totals.yesterday.present` dice se ci sono. Un `dataThrough`
  `null` sul billing = ieri non ancora esportato, non un guasto.
- Search Console ha 2-3 giorni di ritardo: `dataThrough` è l'ultimo giorno vero.
- Il lint di `functions/` è stretto (google style, 80 colonne); i collector
  sono esentati, il resto no.
- Questo account Claude non può dare permessi IAM da solo: chiedere all'utente,
  citando ruolo e service account, e attendere il sì.

## Dove sta il resto

`functions/ARCHITECTURE.md` (tabella degli schedulati), `internal/accessi.md`
(service account e identità), `internal/analytics-accessi.md` (fonte per fonte e
tabella «fonte → script → identità → ritardo»), skill `/report-giornaliero`
(come si leggono i numeri), skill `/deploy-functions` e `/rules-change`.
