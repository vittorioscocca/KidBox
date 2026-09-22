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
