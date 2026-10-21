# Accessi e deploy: dove sta cosa, come si entra

Punto di ingresso unico per chi lavora sul progetto (Claude compreso): per ogni
superficie, **con quale identità si entra, dove vive la credenziale, come si
usa e cosa Claude NON può fare**. **Nessun segreto in questo file né nel
repo.** Ci sono solo identificativi pubblici, nomi di voci del Portachiavi e
comandi. I segreti stanno nel Portachiavi macOS (account `kidbox`), in Secret
Manager, o si ottengono impersonando un service account.

Verificato il 21/10/2026 su questa macchina. Per le fonti dei report
(GA4, Search Console, Meta, Anthropic, billing) il dettaglio è in
`analytics-accessi.md`: qui c'è il resto e i rimandi.

## Identità di base

| Cosa | Valore |
|---|---|
| Progetto Firebase/GCP | `kidbox-42cd7` (numero 52613538008), regione delle funzioni `europe-west1` |
| Utente `gcloud` e `firebase` | `ing.vittorioscocca@gmail.com` (Owner). Controllo: `gcloud auth list`, `npx firebase-tools login:list` |
| `.firebaserc` della root | progetto di default `kidbox-42cd7` |
| Funzioni | Node 22, un solo codebase `default` in `functions/` |
| Il `firebase` globale non c'è | si usa sempre `npx firebase-tools …` |

Se `gcloud` o `firebase` chiedono di nuovo il login, **lo fa l'utente**
(`gcloud auth login`, `npx firebase-tools login`): Claude non inserisce
password né codici.

## Deploy, superficie per superficie

Il deploy e il commit di queste superfici sono di Claude (vedi `CLAUDE.md`).
Mai `firebase deploy` senza `--only`.

| Superficie | Cartella | Comando (dalla root salvo diversa indicazione) |
|---|---|---|
| Cloud Functions | `functions/` | `npx firebase-tools deploy --only functions:<nome> --project kidbox-42cd7` (anche più nomi, separati da virgola). Prima: `node --check`, `eslint`, `require('./index.js')`: procedura in `/deploy-functions` |
| Regole Firestore e indici | `firestore.rules`, `firestore.indexes.json` | `npx firebase-tools deploy --only firestore:rules` (o `firestore:indexes`). Procedura in `/rules-change` |
| Landing | `KidboxLanding/` | da quella cartella: `npx firebase-tools deploy --only hosting:landing --project kidbox-42cd7`. Target `landing` → sito `kidbox-landing`. Dominio: kidboxapp.com |
| Web app | `KidboxWebApp/` | da quella cartella: `npm run build`, poi `npx firebase-tools deploy --only hosting:webapp --project kidbox-42cd7`. Target `webapp` → sito `kidbox-webapp`. Dominio: app.kidboxapp.com |
| Console admin | `KidboxConsole/` | da quella cartella: deploy hosting (cartella `public`, nessun target nominato; `.firebaserc` con progetto di default) |
| iOS, macOS | `KidBox/` | **Xcode Cloud**: un push su `main` fa partire la build. Il push lo dice l'utente. La pubblicazione sugli store è dell'utente. Team di sviluppo `5WA8KG2G2W`, bundle `it.vittorioscocca.KidBox` (+ 4 estensioni: AutoFill, ControlsExtension, NotificationService, ShareExtension) |
| Android | `KidBoxAndroid/` | **repo git separato** (`vittorioscocca/KidBoxAndroid`). Claude compila (`/porting-android`, JBR di Android Studio via `JAVA_HOME`) e committa; versione e pubblicazione sono dell'utente. Package `it.vittorioscocca.kidbox` |

Dopo un deploy delle funzioni: warning ed errori recenti con
`gcloud logging read … severity>=WARNING`, e job pianificati `ENABLED` (vedi
`/deploy-functions`).

## Cloud Functions: segreti e identità

**Secret Manager** (progetto `kidbox-42cd7`; nomi, mai valori):

| Segreto | Usato da | Note |
|---|---|---|
| `ANTHROPIC_API_KEY` | funzioni AI, chat della landing, Notizie | `defineSecret` in `functions/` |
| `GOOGLE_PLACES_API_KEY` | luoghi e viaggi | `defineSecret` |
| `ALEXA_SKILL_ID` | skill Alexa | `defineSecret` |
| `GEMINI_API_KEY` | elencato in `functions/ARCHITECTURE.md`; non l'ho trovato referenziato nel codice | da verificare prima di toccarlo |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | presente in Secret Manager; nel codice non trovo una `defineSecret` con questo nome | da verificare: la validazione ricevute Play usa il service account `play-purchase-validator` |

- Aggiornare un segreto: `npx firebase-tools functions:secrets:set NOME`
  (chiede il valore in modo interattivo, lo fa l'utente) e poi redeploy
  delle funzioni che lo usano.
- Leggerne i nomi: `gcloud secrets list --project kidbox-42cd7`.
- **Mai** stampare il valore di un segreto in chat o nei log.

**Service account del progetto** (verificati con `gcloud iam service-accounts list`):

| Service account | A cosa serve |
|---|---|
| `kidbox-42cd7@appspot.gserviceaccount.com` | identità di runtime di default delle funzioni |
| `firebase-adminsdk-fbsvc@kidbox-42cd7.iam.gserviceaccount.com` | Admin SDK di Firebase |
| `play-purchase-validator@kidbox-42cd7.iam.gserviceaccount.com` | validazione ricevute Play; lo si **impersona** (scope `androidpublisher`) per leggere e modificare abbonamenti e scheda Play |
| `ga4-reader@kidbox-42cd7.iam.gserviceaccount.com` | sola lettura di GA4 e Search Console (scope `analytics.readonly`, `webmasters.readonly`) |
| `52613538008-compute@developer.gserviceaccount.com`, `ais-gemini-key-…` | di default o legati a una chiave Gemini; non usati dal lavoro quotidiano |

Per impersonare serve `roles/iam.serviceAccountTokenCreator` **sul service
account** (Owner non basta), già concesso all'utente:

    gcloud auth print-access-token --impersonate-service-account=<SA> --scopes=<scope>

Nessun file JSON di service account esiste né deve esistere.

## Firebase (app e configurazione)

- File di configurazione nel repo, **tracciati da git**: iOS
  `KidBox/KidBox/Support/Firebase/GoogleService-Info.plist`, Android
  `KidBoxAndroid/app/google-services.json`. Contengono identificativi
  pubblici delle app, non segreti.
- Chiavi Android locali: `KidBoxAndroid/local.properties` (non tracciato)
  con `MAPS_API_KEY`. Senza, la build Android si ferma con un messaggio chiaro.
- App Check attivo sui quattro client, enforcement spento (cancello in
  `/app-check`).
- Cancellazioni su Firestore: solo `scripts/firestore-delete-doc.js`
  (`CLAUDE.md`).
- Accesso ai dati per i controlli: token utente `gcloud` più header
  `x-goog-user-project: kidbox-42cd7`, REST di Firestore e Identity Toolkit.

## Apple

| Cosa | Dettaglio |
|---|---|
| Account | Apple Developer, team `5WA8KG2G2W` |
| App KidBox | ID App Store Connect `6761055375` (iPhone, iPad, Mac) |
| API App Store Connect | chiave «KidBox Report Admin», Key ID `5XN458397C`, Issuer `2deae1f9-70dc-49b6-b792-083e481811d3`, ruolo **Admin**. Il `.p8` sta nel Portachiavi, voce `asc-api-key` (base64): presente il 21/10/2026. Apple non la rida: se si perde si rigenera dal sito |
| Cosa può fare Claude via API | note «Novità» (`scripts/asc-whatsnew.js`), testo promozionale, abbonamenti e loro localizzazioni, lettura di report e stati. **Non** crea né invia in revisione le versioni, **non** pubblica |
| Gruppo abbonamenti | `kidbox_premium` 21994693 (mensili e annuali, vedi `/abbonamenti-store`) |
| Firma e distribuzione | Xcode Cloud; certificati e profili non sono accessibili a Claude |

## Google Play

| Cosa | Dettaglio |
|---|---|
| App | `it.vittorioscocca.kidbox` |
| Come si entra via API | impersonando `play-purchase-validator` (già collegato in Play Console), scope `androidpublisher`. **Può** leggere e modificare abbonamenti e scheda (anche en-US, testi lunghi e brevi). **Non può** creare release né pubblicare |
| Trappola | il commit di una modifica di scheda richiede `Content-Length: 0` esplicito, altrimenti la risposta è vuota e la modifica si perde senza errore. Salvare la scheda mentre una release è in revisione la aggiunge a quella revisione |
| Statistiche | CSV in un bucket `gs://pubsite_prod_rev_…/stats/` letto col token utente `gcloud`; 5-7 giorni di ritardo e buchi. Crash e ANR dalla Play Developer Reporting API |
| Pubblicazione | l'utente, da Play Console o Android Studio. La chiave di firma/caricamento **non è nel repo né accessibile a Claude** |

## Google Ads (nuovo, 15-21/10/2026)

- Account `868-406-1522` («Vittorio Scocca»), aperto con
  `ing.vittorioscocca@gmail.com`. Collegato a GA4 il 15/10/2026.
- Conversione importata: `family_created` (KidBox Android), categoria
  «Registrazione», principale.
- **Claude non ha accesso diretto**: nessun token sviluppatore dell'API di
  Google Ads. Si lavora con gli screenshot dell'utente e si leggono spesa e
  clic dai dati di GA4. Budget, pause, pagamento e nuove campagne restano
  dell'utente.
- Nello stesso account c'è una campagna in pausa («Morgana Music Club») che
  non è di KidBox: non riattivarla.
- Campagna di KidBox: «KidBox Android Italia ott 2026», scommessa 10 del
  registro.

## Meta

Account pubblicitario `act_26185514281057282`, token di lettura nel
Portachiavi (`meta-ads-token`). Dettagli e come rigenerarlo in
`analytics-accessi.md`. Le campagne sono ferme dal 03/10/2026.

## GitHub e push

- Remoti HTTPS: `github.com/vittorioscocca/KidBox` e
  `github.com/vittorioscocca/KidBoxAndroid`.
- **Il push da qui non funziona**: nel Portachiavi manca la password internet
  di github.com che `git-credential-osxkeychain` cerca. La voce che l'utente
  indica come token è di SourceTree («SourceTree (Access Key) for
  github.com») e contiene un valore che GitHub rifiuta. Non cercare altre
  credenziali.
- Il push lo fa l'utente (SourceTree, Android Studio, o Terminale con un token
  personale la prima volta). Un push su `main` del repo principale avvia
  Xcode Cloud: solo quando l'utente lo dice.

## Strumenti collegati alla sessione

| Strumento | Account | Note |
|---|---|---|
| Gmail (connettore) | `passboxcontact@gmail.com` | leggere, creare bozze, inviare. **Inviare solo con l'ok esplicito dell'utente.** Le mail partono da questo indirizzo, diverso da quello di firma |
| Artifact (cruscotto) | account dell'utente | `https://claude.ai/artifact/UVf8RrK61zVSeu2Cj1GGzJ`: `read`, poi publish con `url`; mai `force` |
| Task pianificati | `~/.claude/scheduled-tasks/` | `kidbox-ga4-daily` (report, solo su richiesta), `kidbox-ticket-triage`, più alcuni una tantum |

## Cosa Claude NON può fare

- Pubblicare su App Store o Google Play, creare release, scrivere la versione
  Android, firmare le app.
- Inserire credenziali, carte, password o codici di verifica.
- Creare account o accettare condizioni.
- Fare il push su GitHub da questa macchina.
- Entrare in Google Ads, nella console Amazon (Alexa), in Meta Business o in
  Play Console da sola: si guida l'utente con gli screenshot.

## Se qualcosa smette di funzionare

1. `gcloud auth list` e `npx firebase-tools login:list`: l'utente è
   ancora quello giusto?
2. Un 403 su un'API di Google con un service account: manca
   `serviceAccountTokenCreator` o l'API non è abilitata sul progetto.
3. Un 401 di App Store Connect è quasi sempre transitorio: riprovare con un
   token fresco prima di rigenerare la chiave (`/release-client`).
4. Il token Meta non risponde: vedi «Rigenerare» in `analytics-accessi.md`.
5. Macchina nuova: `gcloud auth login` e `firebase login` con l'utente Owner,
   rifare le tre voci del Portachiavi (`asc-api-key`, `meta-ads-token`,
   `anthropic-admin-key`), controllare `tokenCreator` sui due service account
   e `local.properties` di Android.
