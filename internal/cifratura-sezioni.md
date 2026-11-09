# Cifratura delle sezioni (Garage, Animali, Spese, Salute)

Deciso con l'utente il 09/11/2026: estendere la cifratura con la chiave di
famiglia alle sezioni che il server **non legge** (gruppo «costo basso»).
Il server su queste collezioni conta documenti, somma dimensioni e cancella:
nessuna di queste cose guarda i campi cifrati qui sotto.

Unica perdita lato server: la push «nuova spesa» (`notifyNewExpense`) usa il
titolo; con la spesa cifrata il titolo è vuoto e la push usa il testo generico
(`expense.fallback`). Rimedio possibile in seguito: `titleEnc` nella push e
decifratura sul telefono, come per la chat.

Fuori da questo giro, di proposito: **profili dei figli** (`children.name` è
letto in troppi punti, anche fuori dal sync: va mappato a parte) e gli
allegati (sono già file cifrati).

## Formato

Un solo campo in più per documento:

- `secure`: stringa, `base64(AES-GCM combined)` di un JSON UTF-8
  `{"campo": "valore", …}` con i campi della tabella. Stesso formato e stessa
  chiave delle note (`NoteCryptoService.encryptString` su iOS,
  `ChatCryptoService.encryptStringToBase64` su Android,
  `noteCrypto.encryptString` sul web). Solo campi stringa; un campo nullo o
  vuoto si omette dal JSON.
- `secureV`: numero, `1`.

Solo stringhe scritte dall'utente o che identificano. Restano in chiaro id,
riferimenti (`childId`, `vehicleId`, `petId`, `linked…Id`), date, numeri
(km, costi, importi, dosi), booleani, valori enum `…Raw`, `photoURL(s)`,
`isDeleted`, `createdAt/By`, `updatedAt/By`, impostazioni dei promemoria.

## Campi cifrati per collezione (identici sui tre client)

Tutte sotto `families/{familyId}/`.

| Collezione | Campi in `secure` |
|---|---|
| `vehicles` | `name`, `licensePlate`, `brand`, `model`, `color`, `vin`, `notes` |
| `vehicleEvents` | `title`, `garageName`, `notes` |
| `pets` | `name`, `breed`, `color`, `chipCode`, `notes` |
| `petEvents` | `title`, `vetName`, `notes` |
| `expenses` | `title`, `notes` |
| `medicalVisits` | `doctorName`, `reason`, `diagnosis`, `recommendations`, `notes`, `nextVisitReason` |
| `medicalExams` | `name`, `preparation`, `location`, `resultText`, `notes` |
| `treatments` | `drugName`, `activeIngredient`, `notes` |
| `vaccines` | `commercialName`, `lotNumber`, `administeredBy`, `notes` |
| `pediatricProfiles` | `bloodGroup`, `allergies`, `medicalNotes`, `doctorName`, `doctorPhone`, `doctorEmail`, `doctorAddress`, `doctorWebsite`, `doctorOfficeHoursJSON`, `emergencyContactsJSON` |

## Lettura (sempre, a interruttore spento o acceso)

Per ogni campo della tabella: **il valore in chiaro vince se è una stringa non
vuota**; altrimenti si prende quello in `secure` (se c'è e si decifra).
Motivo: una build vecchia che modifica il documento riscrive il campo in
chiaro, e quella modifica è la più recente.

Se `secure` non si decifra (chiave mancante): si usano i valori in chiaro, che
saranno vuoti. Niente crash, niente documento scartato, niente scrittura.

La regola va applicata **ovunque** si leggano queste collezioni da Firestore,
non solo nel sync: contesto dell'assistente AI, quaderno della memoria, link
dell'agente, schermate web che leggono direttamente.

## Scrittura

Interruttore Remote Config **`sections_encryption_enabled`** (booleano,
default compilato `false`), letto come `text_encryption_enabled`.

- **Spento**: si scrive come oggi, in chiaro. `secure` non si tocca.
- **Acceso** e chiave di famiglia disponibile: i campi della tabella si
  scrivono `""` (stringa vuota, non cancellati: le build vecchie hanno campi
  obbligatori come `name` o `title` e scarterebbero il documento se
  mancassero) e il loro valore va in `secure` + `secureV: 1`.
- **Acceso ma chiave mancante**: si scrive in chiaro come da spento.

## Ricifratura dei documenti vecchi

A interruttore acceso, quando un client legge un documento con almeno un campo
della tabella in chiaro non vuoto e ha la chiave: scrive in merge **solo**
`secure` (valori uniti con la regola di lettura), `secureV: 1` e i campi della
tabella a `""`. **Non tocca** `updatedAt` né `updatedBy`. Una volta per
documento per sessione. Due client che lo fanno insieme scrivono la stessa
cosa.

## Rules

Nessuna regola che rifiuti il chiaro, come per `extractedTextEnc`: le build
vecchie devono poter continuare a modificare i propri dati. Il chiaro che
riscrivono viene ricifrato dal primo client nuovo che legge.

## Tappe

| Tappa | Cosa | Stato |
|---|---|---|
| 1 | iOS, Android e web leggono entrambi i formati e scrivono in chiaro (interruttore spento) | in corso dal 09/11/2026 |
| 2 | Build iOS e Android con la tappa 1 diffuse (GA4 `platform × appVersion` a 7 giorni) | da fare |
| 3 | Accendere `sections_encryption_enabled` | da fare |

Il prezzo noto della tappa 3: chi resta su una build vecchia vede vuoti nome,
titolo e note dei documenti cifrati (date, importi e struttura restano).
