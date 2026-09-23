---
name: app-check
description: App Check di KidBox — misurare la quota di richieste attestate, leggere le righe della console Firebase senza farsi ingannare, e decidere se accendere l'enforcement. Usare quando l'utente chiede perché una riga di App Check è bassa o a zero, se accendere l'enforcement, quando compare «App attestation failed», o prima di toccare `enforceAppCheck`.
---

## Prima regola: non si guarda la console, si misura

    node scripts/appcheck-daily-report.js            # finestra 7 giorni
    node scripts/appcheck-daily-report.js --hours 2  # prova mirata su un device

Legge `firebaseappcheck.googleapis.com/services/verification_count` da Cloud
Monitoring con `gcloud auth print-access-token`. Solo lettura. La metrica arriva
con **~25 minuti di ritardo**: guardare prima è tempo perso.

La storia completa — diagnosi, presidi, ordine di accensione — sta in
**`internal/app-check.md`**. Leggerlo prima di agire.

## ⚠️ La media a 7 giorni nasconde la guarigione

**La trappola principale, e quella che fa sprecare più tempo.** La percentuale
che la console mostra su una riga è una **media della finestra**: dopo un fix,
resta bassa per giorni mentre il dato di *oggi* è già sano. Prima di aprire
un'indagine su una riga bassa, **guardare l'andamento giorno per giorno** — è
quello che dice se il problema è in corso o già chiuso.

Caso reale (23/09/2026): Authentication al **36%** in console sembrava un
problema nuovo. Giorno per giorno: 16% (19/09) → 30 → 42 → 57 → **100%** il
23/09. Era la coda del fix SHA-256 del 20/09, non un guasto. Stessa curva su
Firestore: 40% di media, **82% oggi**. Nessun intervento dovuto.

Corollario sui **volumi**: Auth fa decine di richieste al giorno, Firestore
decine di migliaia. Su numeri piccoli la percentuale ballerina non significa
niente e **un solo device di sviluppo domina il campione**. Il cancello si legge
su Firestore.

## Come si legge l'etichetta `security`

Conta solo quella; `result` (ALLOW/DENY) a enforcement spento è sempre ALLOW.

- **`VALID`** — token presente e accettato.
- **`INVALID`** — token presente e **rifiutato**: attestazione fallita. È il caso
  grave: con l'enforcement acceso queste richieste verrebbero **negate**.
- **`MISSING_*`** — nessun token (client vecchio, origine sconosciuta). Meno
  grave: significa che il token non parte, non che venga respinto.

Le richieste rifiutate hanno `app_id = UNKNOWN`: la metrica **non** dice da quale
app arrivino. L'indizio utile è l'opposto — **quali piattaforme compaiono tra le
VALID**, perché le valide portano l'`app_id`. Basta una richiesta valida per
provare che una piattaforma attesta.

## Il cancello per l'enforcement

Si accende **solo** quando, insieme: Firestore **≥ 90% di VALID per 7 giorni
consecutivi**, e **ios, android e web** tutte presenti tra le VALID. Lo script
stampa il verdetto da sé.

Poi **un prodotto per volta** dalla console, dal meno critico (Storage), con il
report dopo ognuno; **per ultime le Functions** (`enforceAppCheck: true` nel
codice) perché lì il rollback richiede un redeploy, mentre sui prodotti Firebase
si spegne dalla console con effetto immediato.

Non accendere «tanto per provare»: una richiesta `INVALID` a enforcement acceso
non è un avviso, è un'app che non funziona.

## Le due trappole già pagate

**Play Integrity vuole lo SHA-256 della chiave di App Signing di Play** — non lo
SHA-1, e non la chiave di upload. Un'impronta mancante ha prodotto ~112.000
richieste INVALID al giorno per tre settimane, con il device che generava il
token regolarmente ed era **Firebase** a rifiutarlo. La verifica «riga per riga»
dell'08/09 non l'aveva vista perché guardava lo SHA-1, che era corretto.

**Una riga a 0% può essere una catena diversa, non un guasto.** «Google Identity
for iOS» (`oauth2.googleapis.com`) sono le chiamate di **GoogleSignIn-iOS**, che
ha un App Check **suo**, indipendente da Firebase: si attiva solo chiamando
`GIDSignIn.sharedInstance.configure(completion:)`, mai chiamato nel progetto.
**Deciso il 23/09/2026 di lasciarlo così** — è escluso su Mac Catalyst per
costruzione, quindi non potrà mai superare il cancello, e `configure` mette una
chiamata di rete dentro il login. Volume reale: 13 richieste in 7 giorni, tutte
`MISSING_OUTDATED_CLIENT`. Quando si accenderà l'enforcement, **quella riga va
esclusa**. Vedi `internal/app-check.md`.

## Prima di accendere, ricontrollare i due presidi

`SyncCenter.verifyRevocation` su iOS (un `PERMISSION_DENIED` da App Check non
deve far uscire l'utente dalla famiglia) e `KidBoxShareExtension` (installa App
Check prima di `FirebaseApp.configure()`, e la correzione deve essere nella
release **in store**). Sono descritti in `internal/app-check.md`: senza quelli,
accendere l'enforcement causa perdita di dati, non un errore di rete.
