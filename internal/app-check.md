# App Check — stato, cancello e accensione

Stato al **20/09/2026**: l'enforcement è **spento ovunque**, e `enforceAppCheck`
non compare in nessuna function. Il codice nei client c'è da agosto; quello che
manca è la **condizione** per accenderlo.

**Il 20/09/2026 è caduto l'ostacolo principale**: Android non superava
l'attestazione per un'impronta SHA-256 mancante in Firebase, non per un difetto
dell'app (sezione «Risolto» più sotto). Da quel momento il cancello non dipende
più da una pubblicazione.

Misura del cancello, in qualunque momento:

    node scripts/appcheck-daily-report.js

## Dove siamo

Misurato il **20/09/2026 alle 12:00**, finestra 7 giorni, **prima** del fix:

| Servizio | Richieste | Valide | Non valide |
|---|---|---|---|
| Firestore | 129.296 | **13%** | 87% |
| Storage | 645 | 33% | 67% |
| Auth | 346 | 22% | 78% |

Tra le valide comparivano solo `ios` e `web`; Android in nessun servizio.

Alle **13:12**, un quarto d'ora dopo il fix, finestra di un'ora: Firestore al
**31%** di valide, Storage al 35%, e `android` presente tra le valide con 214
richieste e **zero** non valide. La quota continuerà a salire mano a mano che i
device Android rinnovano il token (TTL circa un'ora), **senza alcuna release**.

La lettura aggiornata si ottiene sempre dallo script; i numeri qui sopra sono un
segnaposto storico, non una fonte.

**Come si legge l'etichetta `security`** (è la sola che conta; `result` dice
solo se la richiesta è stata servita, e a enforcement spento è sempre `ALLOW`):

- `VALID` — token presente e accettato;
- `INVALID` — **token presente e rifiutato**: attestazione fallita. È il caso
  grave, perché con l'enforcement acceso queste richieste verrebbero negate;
- `MISSING_*` — nessun token (client vecchio, origine sconosciuta). Sono 475 su
  130.000: il problema non è che manchi il token, è che venga **respinto**.

Le richieste rifiutate hanno `app_id = UNKNOWN`, quindi la metrica non dice da
quale app arrivino. **L'indizio utile è l'opposto: quali piattaforme compaiono
tra le VALID** — le valide portano l'`app_id`, quindi basta una sola richiesta
valida per provare che una piattaforma attesta. È questa asimmetria che rende la
verifica rapida.

## Il cancello

Si accende **solo** quando, insieme:

1. le richieste valide su **Firestore ≥ 90%** per **7 giorni consecutivi**;
2. **tutte e tre le piattaforme** (ios, android, web) compaiono tra le VALID.

Lo script stampa il verdetto da sé. Non accendere «tanto per provare»: a
enforcement acceso una richiesta `INVALID` non è un avviso, è un'app che non
funziona. Il 13/08/2026 il traffico verificato era 0%.

## Risolto il 20/09/2026: l'impronta SHA-256 mancante

Android presentava un token e se lo vedeva rifiutare (`403 App attestation
failed` dal 30/08/2026). La catena vera, letta in `adb logcat` su una build
release installata da Play:

    requestIntegrityToken(… cloudProjectNumber=52613538008)
    Integrity key attestation record generated successfully
    requestIntegrityToken() finished for it.vittorioscocca.kidbox
    W StorageUtil: Error getting App Check token; using placeholder token
                   instead. Error: 403 body: App attestation failed.

Cioè: **Play Integrity produce il token regolarmente sul device**, ed è
**Firebase** a rifiutarlo. Poi l'SDK allega un **token segnaposto** — ed è da lì
che venivano le ~112.000 richieste `INVALID` al giorno con `app_id = UNKNOWN`.

**Causa:** lo SHA-256 della chiave di **App Signing** di Play non era fra le
impronte registrate nel progetto Firebase. Play Integrity include nel verdetto
il digest del certificato di firma; App Check lo confronta con le impronte
registrate e, non trovandolo, rifiuta.

**Come si è trovata** (ripetibile): estrarre il certificato dell'APK installato
da Play e confrontarlo con le impronte del progetto.

    adb shell pm path it.vittorioscocca.kidbox
    adb pull <base.apk> && apksigner verify --print-certs base.apk
    curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
         -H "x-goog-user-project: kidbox-42cd7" \
         "https://firebase.googleapis.com/v1beta1/projects/kidbox-42cd7/androidApps/<appId>/sha"

**La regola generale, che è il vero lascito di questa diagnosi:** App Check con
Play Integrity vuole lo **SHA-256 della chiave di App Signing** — non lo SHA-1,
e non la chiave di **upload**. È il motivo per cui la verifica «riga per riga»
dell'08/09/2026 non l'aveva visto: guardava lo SHA-1, che era ed è corretto.
Le impronte registrate erano cinque (tre SHA-1, due SHA-256) e nessuna delle due
SHA-256 era quella giusta.

**Conseguenza sulla pianificazione:** era una configurazione di progetto, non un
difetto dell'app. **Non serve pubblicare nulla**: ogni Android già installato
ricomincia ad attestare al rinnovo del token. Il cancello non dipende
dall'adozione di una release.

Verificato lo stesso giorno: log pulito su processo fresco (il nostro
`AppCheckTokenCache` impone 30 minuti di cooldown dopo un fallimento duro,
quindi la riprova va fatta dopo un force-stop, non aspettando), e `android` tra
le VALID nella metrica quindici minuti dopo.

## L'ordine di accensione (non negoziabile)

1. ✅ Codice nei client — fatto su iOS, Android, web app e console.
2. ✅ App registrate in console (Android → Play Integrity, iOS → App Attest).
3. ✅ App pubblicate.
4. **Osservare la quota di valide salire** mentre gli utenti aggiornano.
5. **Solo a cancello superato**: accendere l'enforcement **un prodotto per
   volta** dalla console Firebase, partendo da quello meno critico (Storage),
   guardando il report dopo ognuno; **per ultime** le Functions, con
   `enforceAppCheck: true` nel codice e un deploy.

**Rollback:** per i prodotti Firebase si spegne dalla console e ha effetto
subito. Per le Functions no: `enforceAppCheck` è nel codice, quindi tornare
indietro richiede un **redeploy** — motivo in più per farle per ultime.

## I due presidi che rendono l'accensione sopravvivibile

1. **`SyncCenter.verifyRevocation(familyId:)` su iOS.** Prima esisteva questa
   catena: `PERMISSION_DENIED` → `handleFamilyAccessLost` → `currentUserRevoked`
   → `FamilyLeaveService.leaveFamily` → **`.delete()` del documento membro su
   Firestore**. Con l'enforcement acceso, un utente con attestazione fallita
   sarebbe stato **rimosso davvero dalla famiglia**, con perdita di dati reale.
   Ora la revoca si verifica leggendo **dal server** `members/{uid}` (documento
   con regola propria, leggibile anche quando il resto della famiglia non lo è)
   e solo `.confirmed` autorizza il wipe: **assenza di prove non è prova**.
   ⚠️ E una lezione dentro la lezione: la prima stesura metteva un controllo sul
   token App Check *prima* della domanda vera, e così non arrivava mai a farla —
   una revoca autentica non veniva più riconosciuta. **Una sola domanda, niente
   cancelli davanti.**
2. **`KidBoxShareExtension` coperta** (08/09/2026): `ShareViewController`
   chiamava `FirebaseApp.configure()` senza installare App Check e scrive note
   su Firestore. Con l'enforcement acceso, condividere una nota dentro KidBox da
   un'altra app si sarebbe rotto. Da confermare che la release **in store**
   contenga la correzione prima di accendere.

## Cosa resta fuori da App Check, di proposito

L'endpoint Alexa (lo chiama Amazon, non un nostro client: al suo posto valgono
la firma e altri tre controlli), la landing degli inviti e la chat della landing
(pagine statiche senza login: lì il tetto è il budget e il rate limit). Non sono
buchi da tappare accendendo l'enforcement: non passerebbero comunque da lì.

## 23/09/2026 — la guarigione in corso, e la media che la nasconde

Report a 7 giorni: Firestore **40%**, Storage 52%, Auth (`identitytoolkit`)
**36%**. Letti così sembrano fermi. Letti **giorno per giorno** raccontano il
contrario — è la coda del fix SHA-256 del 20/09, che si propaga al ritmo con cui
i device rinnovano il token:

| | 19/09 | 20/09 | 21/09 | 22/09 | 23/09 |
|---|---|---|---|---|---|
| Firestore | 14% | 29% | 48% | 70% | **82%** |
| Auth | 16% | 30% | 42% | 57% | **100%** (17 req) |

**La regola che ne esce, valida oltre questo episodio:** la percentuale mostrata
in console è una **media della finestra**; dopo un fix resta bassa per giorni
mentre il dato di oggi è già sano. Prima di aprire un'indagine su una riga
bassa, guardare l'andamento giornaliero. E attenzione ai volumi: Auth fa decine
di richieste al giorno contro le decine di migliaia di Firestore, quindi la sua
percentuale è rumorosa e il 100% di oggi è su 17 richieste. **Il cancello resta
Firestore.** Verdetto dello script: ancora ⛔️, 0 giorni su 8 sopra soglia.

Tutte e tre le piattaforme compaiono tra le VALID (ios 23.639, android 23.583,
web 3.191): la seconda condizione del cancello è soddisfatta, manca solo la
prima. Le INVALID restano su `app_id = UNKNOWN`, come da asimmetria nota.

## 23/09/2026 — «Google Identity for iOS» (0%): catena diversa, lasciato fuori

La riga sotto **Other Google APIs** in console è `oauth2.googleapis.com`: le
chiamate dell'SDK **GoogleSignIn-iOS** (9.1.0 in SPM). **13 richieste in 7
giorni, tutte `MISSING_OUTDATED_CLIENT`** — nessun token, non un token
rifiutato. Non è un guasto e non è un errore di configurazione.

GoogleSignIn-iOS ha una catena App Check **sua, indipendente da Firebase**: il
provider installato in `AppCheckInstaller.swift` copre gli SDK Firebase e non lo
tocca. Verificato nel sorgente del checkout SPM: `GIDSignIn.m:822` allega il
token (come `client_assertion`, *limited use*, da `GIDAppCheck
appCheckUsingAppAttestProvider`) **solo se** è stato chiamato
`GIDSignIn.sharedInstance.configure(completion:)` — oppure
`configureDebugProvider(withAPIKey:completion:)` per debug/simulatore. Nel
progetto non viene mai chiamato: in `FirebaseGoogleAuthService.swift:53` si
imposta solo `.configuration`, che è il client ID e un'altra cosa.

**Deciso di NON accenderla**, per tre motivi in ordine di peso:

1. App Check protegge solo **in enforcement**; in monitoraggio quel token
   sposterebbe un numero in dashboard e basta.
2. **L'enforcement lì non potrà mai essere completo**: tutto il blocco è dentro
   `#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST`, quindi la build **Mac Catalyst
   resta scoperta per costruzione** e quella riga non raggiungerà il 90%.
3. `configure` mette una chiamata di rete (con loader a tempo) **dentro il
   login**, cioè nel funnel invito→primo membro. Non rompe nulla — se il token
   fallisce il flusso prosegue — ma è latenza dove non serve.

**Quando rimetterla in agenda:** se compare traffico anomalo sul client OAuth
Google (è quello il rischio che copre: usare il client ID per generare sign-in
da fuori l'app), oppure al momento di accendere l'enforcement, per decidere se
escluderla in modo definitivo.

⚠️ **All'accensione, escludere questa riga.** E se un giorno si facesse: la
chiamata va in `AppDelegate` accanto ad `AppCheckInstaller.install()`, doppio
ramo debug/produzione (in simulatore App Attest non esiste: serve il debug
provider con la web API key, da xcconfig e non nel sorgente), iOS 14+.

## 22/10/2026 — il calo al 34% sono i simulatori iOS, non gli utenti

Firestore giorno per giorno: 70% (20/10) → 55% (21/10) → **34%** (22/10, 32.903
richieste). Scomposto per ora e per piattaforma:

- le VALID **Android** restano dove erano (8–10 mila al giorno): Play Integrity
  sta bene, e il codice Android di App Check non cambia dal 19/09;
- le **INVALID** passano da 3–5 mila a 21.589 al giorno, e salgono **solo nelle
  ore delle sessioni di sviluppo iOS** (21/10 14–18, 22/10 10–18 e 20–22: gli
  orari dei commit su ricerca, demo per gli screenshot, Duo, iPad, chat). Di
  notte restano a 30–140 l'ora, come prima.

**Causa:** su iOS `AppCheckInstaller` usa `AppCheckDebugProviderFactory` in
DEBUG e nel Simulatore, e l'app iOS in Firebase ha **zero debug token
registrati** (Android ne ha due, gli Xiaomi). Ogni simulatore genera e conserva
un token suo (`GACAppCheckDebugToken` nelle preferenze dell'app): il 21–22/10 ne
erano attivi **sei diversi** (iPhone 17 Pro Max, iPhone 18 Pro, iPad Pro 11 e
13, KB Demo Duo, KB Demo iPad 13), tutti rifiutati → INVALID con `app_id =
UNKNOWN`. Lo stesso vale per un iPhone vero con una build lanciata da Xcode.

**Cosa NON è:** né le build in revisione (girano in Release, con App Attest) né
un guasto dei client in store. L'enforcement è `UNENFORCED` su tutti i servizi,
quindi nessun utente ne ha risentito.

**La lezione:** una giornata di lavoro sui simulatori iOS sposta il cancello di
decine di punti. Prima di leggere un calo, guardare se le INVALID seguono le
ore di sviluppo; e con l'enforcement acceso il Simulatore smetterebbe di
funzionare finché il suo token non è registrato (Firebase → App Check → app
iOS → Gestisci token di debug).

Resta aperto, ed è un'altra cosa: un fondo di 3–5 mila INVALID al giorno anche
nei giorni senza sviluppo iOS, che da solo tiene il cancello sotto il 90%.

## 10/11/2026 — il fondo non è il mio Simulatore, e non si sta chiudendo

Misura a 7 giorni: Firestore **71%** (432.840 richieste, 124.451 INVALID),
Storage 58%, Auth 74%, `oauth2` 0% (13 richieste, la riga esclusa per
costruzione). **Giorni sopra soglia: 0 su 8.** Tra le VALID compaiono tutte e
tre le piattaforme — android 212.890, ios 86.918, web 9.676 — quindi la
**seconda** condizione del cancello è soddisfatta e lo è da settembre: manca
solo la prima.

**Smentita la spiegazione comoda.** Il 22/10 il calo era stato attribuito ai
debug token dei simulatori iOS, e restava aperta la voce «un fondo di 3–5 mila
INVALID al giorno anche nei giorni senza sviluppo iOS». Bucketando le INVALID di
Firestore per **ora del giorno** su 7 giorni, quel fondo si vede ed è grande:

| | INVALID | per ora |
|---|---|---|
| 09–23 (ore di lavoro) | 95.156 | ~906 |
| 00–08 (notte) | 29.287 | ~465 |

Le ore di lavoro fanno il **doppio** delle INVALID della notte — i simulatori
esistono e si vedono (10:00 al 56%, 13:00 al 60%) — ma la **percentuale** resta
piatta tutto il giorno: **70–77% anche alle 3 di notte**. Se le INVALID fossero
solo le mie, di notte la quota sarebbe vicina al 100%. Non lo è: circa **4.200
INVALID per notte** arrivano da device di utenti veri. È quello il muro.

**L'attesa non sta funzionando.** Firestore era all'82% nel giorno del 23/09 e
al 70% il 20/10; oggi la mediana giornaliera è ~73%. In sette settimane il fondo
**non si è mosso**, e non si muoverà da sé: non è una coda da smaltire, è una
condizione in corso. Il cancello si apre solo trovando *che cosa* viene
rifiutato — non aspettando ancora.

**Prossimo passo, nell'ordine:** registrare i debug token dei simulatori iOS
(Firebase → App Check → app iOS → Gestisci token di debug). Serve comunque prima
dell'enforcement, altrimenti il Simulatore smette di funzionare; e togliendo il
rumore diurno rende il fondo misurabile pulito. Poi rimisurare: se la notte e il
giorno convergono sullo stesso valore, quel valore è il fondo vero da
diagnosticare.

**La riga «AI Logic» non ci riguarda.** La console annuncia che dal
**21/01/2027** App Check applicherà da sé le richieste di Firebase AI Logic.
KidBox non usa AI Logic: zero occorrenze di `FirebaseVertexAI`, `FirebaseAI`,
`vertexai` e `getAI(` in tutti e quattro i client — l'AI passa dai client alle
Cloud Functions e da lì a `api.anthropic.com`. Quella scadenza non tocca
l'applicazione.

**I due presidi, riverificati oggi.** `SyncCenter.verifyRevocation`
(`SyncCenter.swift:330`, nato il 10/09 in `8200ecb6`, quindi in store da un
pezzo: il repo è a 2.5.1/170) non ha più il pre-controllo sul token App Check —
è stato **tolto di proposito**, perché su Android mascherava le espulsioni vere;
se l'enforcement negasse tutto, è la lettura `source: .server` a fallire e a
tornare `.undetermined`, che non fa wipe. Gli altri due punti che emettono
`currentUserRevoked` (righe ~682 e ~823) partono da uno snapshot che *mostra* il
membro rimosso, e un rifiuto di App Check non produce snapshot ma
`PERMISSION_DENIED`: non sono raggiungibili da un'attestazione fallita.
`KidBox/KidBoxShareExtension/ShareViewController.swift:26` installa App Check
prima di `FirebaseApp.configure()`. Entrambi a posto.

### 10/11/2026 — i 5 token dei simulatori iOS sono registrati

Registrati dall'utente in console e verificati via API (`debugTokens` sull'app
iOS `1:52613538008:ios:932807334c01080b3df7ad`, prima **zero**, ora **cinque**):
`iPhone 17`, `iPhone 18 Pro`, `KB Demo 17 Pro 27.0`, `KB Demo iPad 13`,
`KB Demo Duo`. Estratti da `GACAppCheckDebugToken` nei plist dei container
(`~/Library/Developer/CoreSimulator/Devices/*/…/Preferences/it.vittorioscocca.KidBox.plist`).

⚠️ **Cambiano a ogni reinstallazione dell'app sul simulatore**: non è un lavoro
una volta per sempre. Se un calo diurno ricompare, la prima cosa da rifare è
questa estrazione e confrontarla con la lista registrata.

**Stato degli altri client:** Android ha 2 token (`Xiaomi Debug 2`,
`Xiaomi Debug Vittorio`), registrati a settembre e **mai verificati dopo**: se
il Xiaomi ha reinstallato la debug, sono scaduti e il device genera INVALID.
Da controllare col telefono collegato (`adb shell run-as` sulle SharedPreferences,
oppure il token stampato in logcat all'avvio). Web: 0 token, corretto — lì il
debug token sarebbe un bypass di progetto, vedi la nota sulla console admin.

**Letture API, per non ricercarle:** servono il token utente *e* l'header
`x-goog-user-project: kidbox-42cd7`, altrimenti la chiamata torna 403
`SERVICE_DISABLED` parlando di quota project — non è un permesso mancante.

    curl -sS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
         -H "x-goog-user-project: kidbox-42cd7" \
      "https://firebaseappcheck.googleapis.com/v1/projects/kidbox-42cd7/apps/<APP_ID>/debugTokens"

**Prossima misura: dal 14/11**, per avere 3-4 giorni interi senza il rumore dei
simulatori. Se le ore di lavoro convergono sulla percentuale della notte
(~70-77%), quello è il fondo vero da diagnosticare e i simulatori erano solo
volume. Se invece sale tutto, il fondo era più piccolo di quanto stimato oggi.

### ⚠️ 10/11/2026 — i valori dei token di debug NON si leggono. Errore mio, da non ripetere

`debugTokens.list` restituisce `name`, `displayName`, `updateTime`, `etag` — **mai
il valore del token**: è write-only, si scrive alla creazione e non torna più
indietro.

**La trappola:** l'ultimo segmento di `name` è base64, e decodificandolo esce un
UUID perfettamente plausibile. **Non è il token.** È un identificatore casuale
della risorsa. Prova decisiva: ho creato un token con valore
`5440b28d-a117-4cb9-98e4-9807ed51f8ea` e la risorsa tornata decodifica in
`fbf4ffe2-c277-423a-b1f0-833ee432be10`.

Ci ho costruito sopra due verdetti sbagliati («il token registrato non
corrisponde al telefono», detto due volte) e un terzo non dimostrato («il
dialogo della console rigenera l'UUID quando lo apri»): tutti poggiavano su
quella decodifica, quindi **nessuno dei tre è sostenuto da prove**. Sono anche
stati cancellati due token di aprile/maggio sulla base dello stesso ragionamento
— plausibilmente scaduti davvero (l'app è stata reinstallata il 24/10), ma non
per il motivo che avevo dato.

**Come si verifica davvero**, in ordine di costo:

1. **Registrare il valore via API invece che dalla console**, così è noto per
   costruzione (`POST …/debugTokens` con `{"displayName":…, "token":…}`). È
   l'unico modo di *sapere* cosa c'è registrato.
2. **Leggere il segreto dal device** e confrontarlo con quello che si è scritto:
   su Android esce in logcat a ogni avvio
   (`DebugAppCheckProvider: Enter this debug secret …`), su iOS sta in
   `GACAppCheckDebugToken` nei plist del container del simulatore.
3. **La metrica**, ~25 minuti dopo una richiesta vera dal device: è l'unica
   prova end-to-end che il token sia accettato.

**Mai** dedurre lo stato di un token da un confronto di identificatori.

**Nota su Xiaomi/HyperOS:** `run-as <pkg>` legge ma **non scrive** — la cartella
dati risulta `Read-only file system` anche per l'uid dell'app. Allineare il
device al token della console scrivendo in `shared_prefs` non è praticabile lì;
va fatto il contrario, registrando via API il valore che il device ha già.

### ✅ 10/11/2026, 11:26 — il fondo era il Xiaomi. 98% in un'ora

Finestra di 1 ora dopo la registrazione del token del Xiaomi:

| | valore |
|---|---|
| Firestore | 2.616 richieste, **98% VALID** |
| INVALID | **42** |
| per app | android 1.106 · ios 1.090 · web 380, tutte VALID |

**Baseline della stessa fascia oraria** (media 7 giorni, bucket 11:00): **66%**,
con ~1.000 INVALID l'ora. Le INVALID sono scese del **~96%** togliendo di mezzo
**un solo telefono**.

**Conclusione: l'ipotesi del 10/11 mattina era sbagliata.** Avevo scritto che il
fondo notturno (~4.200 INVALID a notte, 70-77% anche alle 3) veniva da device di
utenti veri, perché i simulatori iOS di notte sono spenti. Il ragionamento
reggeva ma la premessa era incompleta: il Xiaomi è un telefono vero, acceso, con
listener, FCM e sync che girano **anche di notte** — ha la forma piatta sulle 24
ore che avevo attribuito agli utenti. Generava INVALID da ogni reinstallazione
della build debug successiva a maggio (i token registrati erano di aprile e
maggio).

**L'adozione reale tra gli utenti era già alta**: non erano loro a tenere chiuso
il cancello, ero io.

**Il cancello però NON è ancora superato**, e la finestra a 7 giorni dice ancora
**73%** perché contiene la settimana sporca. Servono **7 giorni consecutivi**
≥90%: il 10/11 è parziale (quasi tutto pre-fix), quindi il primo giorno pulito è
l'**11/11** e la serie si completa il **17/11**. Rimisurare il **18/11**.

Residuo da capire, ma non bloccante: **42 INVALID l'ora** (~1.000 al giorno,
~2%) di origine ignota. A quel livello non impedisce il 90%.

⚠️ **Lo script invitava ad accendere l'enforcement su un'ora di dati.** Con
`--hours` stampava «Cancello superato» perché `cancelloSuperato` guardava solo
la media della finestra e **non contava affatto i giorni consecutivi**.
Corretto (`fd94201c`): la modalità a ore è esclusa dal verdetto e la serie
consecutiva è calcolata e mostrata. Era esattamente il modo di accendere
l'enforcement su 2.616 richieste credendo di seguire la procedura.

## 11/11/2026 — la console admin non otteneva il token: mancava l'appId

Dalla console (`kidbox-42cd7.web.app`) lo scambio del token rispondeva **400 a
ogni tentativo**. Non era il dominio (la chiave «KidBox Web App Check» lo
autorizza già, insieme a `app.kidboxapp.com` e `kidbox-webapp.web.app`: si
legge con `gcloud recaptcha keys list --project kidbox-42cd7`). La
configurazione che la console salva nel browser ha solo `apiKey`, `projectId`
e `authDomain`: senza `appId` la richiesta andava a `apps/undefined`.
Corretto in `KidboxConsole/public/app.js` (`APP_CHECK_APP_ID`, l'appId della
web app): ora lo scambio risponde 200 e le richieste della console contano
come valide sotto l'app web. **Senza questo, l'enforcement avrebbe chiuso fuori
la console.** Da ricontrollare prima di accenderlo: Rete → `exchangeRecaptchaEnterpriseToken` = 200.

Stesso giorno, CSP sugli hosting di web app e console: App Check ha bisogno di
`www.google.com/recaptcha/`, `www.gstatic.com/recaptcha/` (script), di
`www.google.com` e `*.googleapis.com` (rete) e dell'iframe di `www.google.com`.
Se la quota di VALID del web scende dopo una modifica agli header, guardare lì.
