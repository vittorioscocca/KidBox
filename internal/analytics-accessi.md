# Routine analytics: dove stanno gli accessi

Mappa di ogni fonte letta dalla routine giornaliera (`/report-giornaliero`,
script in `scripts/`): identificativi, dove vive la credenziale, come si
ottiene il token, cosa fare se smette di funzionare. **Nessun segreto in
questo file né nel repo**: i segreti stanno nel Portachiavi macOS (account
`kidbox`) o passano dall'impersonazione di service account con `gcloud`.

Aggiornato al 20/09/2026. Progetto Firebase/GCP: `kidbox-42cd7`. Utente
gcloud: `ing.vittorioscocca@gmail.com` (Owner del progetto).

## Portachiavi macOS

Tutte le voci hanno account `kidbox`. Lettura:
`security find-generic-password -a kidbox -s <voce> -w`.
Scrittura/aggiornamento:
`security add-generic-password -a kidbox -s <voce> -w '<valore>' -U`.

| Voce | Contenuto | Usata da |
|---|---|---|
| `asc-api-key` | file `.p8` di App Store Connect in **base64** (`base64 -i AuthKey.p8`) | `appstore-daily-report.js`, `asc-whatsnew.js` |
| `meta-ads-token` | token Marketing API di Meta (permesso `ads_read`, senza scadenza) | `meta-ads-daily-report.js` |
| `anthropic-admin-key` | chiave Anthropic personale con scope **Organizzazione** | `anthropic-daily-report.js` |

Il resto (Google Analytics, Search Console, Play, Firestore/Auth, BigQuery)
non ha segreti salvati: usa il login `gcloud` dell'utente, da solo o
impersonando un service account.

## Fonte per fonte

### Google Analytics 4 — `scripts/ga4-daily-report.js`

- Property **523225071** (account 383309163), una sola per tutto. Stream:
  Android 14315737465, iOS 13430491487, web 15477284642 (`G-0PG65CW2VF`,
  condiviso da web app e landing → si distinguono per `hostName`).
- L'ID property si riottiene dalla Firebase Management API:
  `GET https://firebase.googleapis.com/v1beta1/projects/kidbox-42cd7/analyticsDetails`
  con header `x-goog-user-project: kidbox-42cd7`.
- **Token**: impersonazione del SA `ga4-reader@kidbox-42cd7.iam.gserviceaccount.com`
  (creato 14/09/2026, nessun ruolo IAM, aggiunto come *Visualizzatore* nella
  property dall'utente):
  `gcloud auth print-access-token --impersonate-service-account=ga4-reader@kidbox-42cd7.iam.gserviceaccount.com --scopes=https://www.googleapis.com/auth/analytics.readonly`.
  Serve `roles/iam.serviceAccountTokenCreator` **sul SA** (Owner non basta):
  concesso a ing.vittorioscocca@gmail.com.
- Non usare il token utente di gcloud (403, manca lo scope Analytics) e non
  provare `gcloud auth application-default login --scopes=…analytics`: Google
  rifiuta il client OAuth di gcloud per Analytics. Strada morta.
- Non mandare `x-goog-user-project` col token del SA.
- Filtro «Internal Traffic» (`traffic_type=internal`) attivo dal 15/09/2026.
- Dimensioni personalizzate registrate il 14/09/2026 (`content_type`,
  `method`, `channel`…): prima di quella data valgono `(not set)`.

### Search Console — `scripts/search-console-daily-report.js`

- Property di dominio `sc-domain:kidboxapp.com` (creata 12/09/2026).
- Stesso SA `ga4-reader`, aggiunto come utente «Limitata» della property;
  scope `https://www.googleapis.com/auth/webmasters.readonly`. API
  `searchconsole.googleapis.com` abilitata sul progetto.
- Dati con 2-3 giorni di ritardo; il campo «indexed» delle sitemap nell'API
  è inaffidabile (0). Per lo stato reale di un URL: URL Inspection API.

### Console admin (Auth + Firestore) — `scripts/console-daily-report.js`

- Token utente: `gcloud auth print-access-token` (Owner del progetto).
- Identity Toolkit `accounts:batchGet` (GET, header `x-goog-user-project`)
  e Firestore REST (`runQuery`, aggregazioni count). Solo aggregati.
- Account di test esclusi via `config/internalUsers` (uid + emailSha256).
- Trappola zsh: `"$B:runQuery"` viene mangiato dal modificatore `:r`, usare `${B}`.

### Google Play — `scripts/play-daily-report.js`

- App `it.vittorioscocca.kidbox`. Statistiche = CSV esportati da Play in
  `gs://pubsite_prod_rev_00873204915190884037/stats/{installs,crashes,ratings}/`
  (UTF-16LE + gzip, **5-7 giorni di ritardo, con buchi**), letti col token
  utente di gcloud (l'utente è proprietario dell'account Play).
- Crash/ANR freschi: Play Developer Reporting API (abilitata 15/09/2026;
  `errorCountMetricSet`, non `crashRateMetricSet`; `timeZone America/Los_Angeles`).
  Recensioni: Android Publisher API. Entrambe impersonando
  `play-purchase-validator@kidbox-42cd7.iam.gserviceaccount.com` (lo stesso SA
  della validazione ricevute, già collegato in Play Console; tokenCreator
  concesso all'utente).

### App Store Connect — `scripts/appstore-daily-report.js`, `scripts/asc-whatsnew.js`

- App KidBox = **6761055375**.
- Chiave API «KidBox Report Admin»: Key ID `5XN458397C`, Issuer
  `2deae1f9-70dc-49b6-b792-083e481811d3`, ruolo **Admin** (con «Vendite e
  report» il POST `analyticsReportRequests` dà 403). Il `.p8` sta nel
  Portachiavi (`asc-api-key`, base64); Apple non lo rida: se si perde, nuova
  chiave da App Store Connect → Utenti e accesso → Chiavi, e aggiornare
  Key ID/Issuer negli script.
- La prima chiave (`298UYJX44D`, ruolo Sales) va revocata dall'utente.
- JWT ES256 firmato in Node senza dipendenze
  (`crypto.sign(..., {dsaEncoding: "ieee-p1363"})`).
- Richiesta report ONGOING `b82f1b10-0332-44ac-909b-8802ea358337` (+ snapshot
  `8c344610-…`) creata il 15/09/2026: Discovery and Engagement, App Downloads,
  Installation and Deletion, App Sessions, App Crashes Standard. Istanze DAILY
  con 1-2 giorni di ritardo; con numeri strani usare `--raw` e correggere le
  colonne nello script.
- Il numero venditore non serve.

### Meta Ads — `scripts/meta-ads-daily-report.js`

- Account pubblicitario `act_26185514281057282` (EUR, portfolio PassBox,
  condiviso con il portfolio kidbox_app).
- Token dell'utente di sistema «Conversions API System User» del portfolio
  kidbox_app (un portfolio non verificato ne ammette uno solo: crearne un
  secondo fallisce con «nome non valido»), generato sull'app **KidBox Ads
  Reader** (creata apposta: l'app KidBox del Login è consumer e non può
  avere la Marketing API). Permesso solo `ads_read`, scadenza mai. Voce
  Portachiavi `meta-ads-token`.
- Rigenerare: Business Settings → Utenti di sistema → Genera token → app
  KidBox Ads Reader → `ads_read`.

### Anthropic — `scripts/anthropic-daily-report.js`

- Usage & Cost Admin API: `/v1/organizations/cost_report` (importi in
  **centesimi**) e `/v1/organizations/usage_report/messages`.
- L'Admin API non esiste per gli account individuali: l'org è stata
  convertita in team il 15/09/2026. Basta una **chiave personale con scope
  Organizzazione** (le chiavi di workspace danno `permission_error`). Voce
  Portachiavi `anthropic-admin-key`.

### Google Cloud billing — `scripts/gcloud-billing-daily-report.js`

- Account di fatturazione `015E5B-092B59-BED0B8` (EUR). Export «Costo di
  utilizzo standard» su BigQuery, dataset `kidbox-42cd7.billing_export` (EU),
  tabella `gcp_billing_export_v1_015E5B_092B59_BED0B8`, attivo dal
  15/09/2026 (niente storico prima). Query con `bq` e credenziali gcloud
  dell'utente. `bq` scrive gli errori su stdout.
- Le righe di un giorno arrivano il giorno dopo, spesso dopo le 08:30.

### Cruscotto — `scripts/build-dashboard.js`

- Rilancia gli script in `--json` e scrive `dashboard/kidbox-dashboard.html`
  (cartella ignorata da git). Pubblicato come artefatto
  https://claude.ai/artifact/UVf8RrK61zVSeu2Cj1GGzJ (stesso link ogni
  giorno: `read` e poi publish con `url`). Anteprima locale: `launch.json`
  → «dashboard», porta 5090.

## Verifica rapida che tutto risponda

    for s in ga4 console meta-ads play appstore anthropic gcloud-billing search-console; do
      node scripts/$s-daily-report.js --json >/dev/null && echo "OK  $s" || echo "KO  $s"
    done

Ogni script, se manca la sua credenziale, stampa da solo cosa serve e come
salvarla.

## Cosa NON è nel repo, per scelta

- I valori delle tre voci del Portachiavi.
- I file `.p8` di Apple e i JSON di service account (nessuno: si impersona).
- I token OAuth di Google: sono di un'ora, sempre rigenerati da `gcloud`.

Chi mette in piedi una macchina nuova deve: fare `gcloud auth login` con
l'utente Owner, ricreare le tre voci del Portachiavi, e verificare di avere
tokenCreator sui due SA (`ga4-reader`, `play-purchase-validator`).
