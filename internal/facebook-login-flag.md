# Pulsante «Continua con Facebook» — nascosto dietro un interruttore remoto

Stato: implementato su iOS e Android. Il pulsante **non compare** in nessuna delle
due app finché il flag remoto resta spento.

Documento **interno**: non sta in `docs/`, che GitHub Pages pubblica come sito
legale (privacy, termini, eliminazione dati, supporto).

---

## 1. Perché il pulsante è sparito

L'app Meta di KidBox è in **modalità sviluppo**. Chi non ha un ruolo assegnato su
quell'app, toccando «Continua con Facebook», riceve da Meta:

> «Questa app non funziona e lo sviluppatore ne è a conoscenza»

Un utente non legge quella frase come «questo provider è spento»: la legge come
**«KidBox è rotta»**, e la legge sulla schermata di login, cioè nel momento in cui
sta decidendo se fidarsi dell'app.

Il dato che ha chiuso la discussione: **su 256 registrazioni un solo login
Facebook è andato a buon fine, ed era quello dello sviluppatore.**

Il pulsante quindi va tolto. Ma il giorno in cui Meta approva la pubblicazione
deve poter **tornare senza una nuova release** e senza riattraversare la review
di App Store e Play Store — da qui l'interruttore remoto invece della semplice
cancellazione del codice.

Il codice di autenticazione Facebook **resta al suo posto**, intatto: SDK,
`FacebookAuthService`, gestione del callback. Si nasconde solo il pulsante.

---

## 2. Dove vive il valore

Il flag sta su **Firebase Remote Config**, parametro `facebook_login_enabled`,
**uno solo per entrambe le piattaforme**.

**Perché Remote Config e non Firestore.** La schermata di login sta *prima*
dell'autenticazione, e ogni documento sotto `config/` richiede `isSignedIn()`
(`firestore.rules`): un flag lì sarebbe illeggibile proprio dove serve. Remote
Config si legge senza account.

Il valore vive in tre posti, dal più pronto al più autorevole:

1. il **default compilato** — usato al primissimo avvio e offline;
2. la **cache locale** (`UserDefaults` su iOS, `SharedPreferences` su Android) —
   l'ultimo valore visto, serve a disegnare la schermata subito senza far
   comparire un pulsante che un istante dopo sparisce;
3. **Remote Config** — la verità, recuperata a ogni avvio.

**Il default compilato è `false`.** Se la fetch non arriva mai — rete assente,
primo avvio, console non ancora configurata — resta lo stato che vogliamo oggi.
Un default acceso rimetterebbe il pulsante rotto davanti a chi è offline, cioè
esattamente il caso peggiore.

---

## 3. Le due implementazioni

| | iOS | Android |
|---|---|---|
| Flag | `KBFeatureFlags` (`Support/KBFeatureFlags.swift`) | `KBFeatureFlags` (`data/local/KBFeatureFlags.kt`) |
| Chiave remota | `facebook_login_enabled` | `facebook_login_enabled` |
| Cache | `UserDefaults` → `kb_facebookLoginEnabled` | `SharedPreferences` (`kidbox_prefs`) → `kb_facebookLoginEnabled` |
| Default | `false` | `false` |
| Aggiornamento a video | `@AppStorage` in `LoginView` | `StateFlow` raccolto in `LoginScreen` |
| Avvio | `AppDelegate`, subito dopo `FirebaseApp.configure()` | `KidBoxApplication.onCreate()` (`init` + `refresh`) |

In entrambe la `refresh` **non si attende**: la schermata parte con la cache e si
ridisegna da sola se il valore remoto è diverso. Su iOS lo fa `@AppStorage`, su
Android lo `StateFlow` — in tutti e due i casi senza che la vista debba sapere da
dove arriva il valore.

**Intervallo di fetch**: 0 in debug (una modifica in console si verifica subito),
3600 secondi in release. Il flag cambia una volta all'anno, non vale una chiamata
di rete a ogni apertura.

**In caso di fetch fallita non si scrive nulla**: resta l'ultimo valore noto, che
è già la scelta giusta dell'ultima volta.

---

## 4. Come si riaccende

Quando Meta approva la pubblicazione dell'app:

1. Firebase Console → Remote Config → `facebook_login_enabled` → `true` →
   pubblica.
2. Nient'altro. Nessuna release, nessuna review.

Le app lo prendono al primo avvio utile (entro un'ora in release), e la schermata
di login si ridisegna anche se è già aperta.

Per riaccenderlo **solo a sé stessi** durante le prove: condizione su Remote
Config per utente/versione, oppure build di debug, dove l'intervallo di fetch è
zero.

---

## 5. Cosa NON è stato fatto, di proposito

- **Il codice Facebook non è stato rimosso.** Toglierlo avrebbe reso il ritorno
  una modifica vera, con release e review; il costo di tenerlo è nullo finché il
  pulsante non si disegna.
- **Nessun flag generico multi-feature.** `KBFeatureFlags` oggi governa una cosa
  sola. Quando ne servirà una seconda si aggiunge una chiave accanto, con lo
  stesso schema a tre livelli.
- **Nessun avviso all'utente.** Non c'è niente da spiegare: chi non ha mai visto
  quel pulsante non ne sente la mancanza, e chi lo usava era una persona sola.
