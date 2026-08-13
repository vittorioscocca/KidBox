# Test delle regole Firestore

Verificano che il piano di abbonamento **non** sia scrivibile dai client e che il
limite di 2 famiglie per account regga. Nascono da una falla reale: prima chiunque
poteva assegnarsi Pro/Max con una singola scrittura su Firestore.

## Eseguirli

Serve un JDK 11+ (quello di sistema è Java 8, usa il JBR di Android Studio):

```bash
cd firestore-tests
npm install
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
firebase emulators:exec --only firestore --project kidbox-rules-test "node rules.test.js"
```

## Attenzione a `match /{subpath=**}` sotto `families`

Quel wildcard combacia **anche con il documento famiglia stesso** (subpath vuoto).
Le regole Firestore sono in OR: senza il guard `string(subpath).size() > 0`, la sua
`allow write` scavalca `keepsPlanFields()` e il piano torna scrivibile a mano.
C'è un test apposta — se lo tocchi, rieseguilo.
