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

## Limiti noti (dalla tappa 1, 09/11/2026)

- **Un campo svuotato in chiaro può ricomparire.** Se un documento è già
  cifrato e una build vecchia (o un client a interruttore spento) svuota un
  campo, in lettura torna il valore di `secure`. Raro: succede solo dopo
  l'accensione e solo da build vecchie.
- **Vaccini su Android**: scrive anche `name`, `doctorName` e `location`, che
  iOS e web non hanno; restano in chiaro (`name` di solito ripete
  `commercialName`). Da decidere se aggiungerli alla tabella su tutti e tre.
- Il web sigilla solo le scritture che portano **tutti** i campi della tabella
  (una parziale resta in chiaro, e il chiaro vince).
- Scritture parziali, tre comportamenti: il web non sigilla (resta in chiaro),
  iOS rilegge il documento e fonde i campi mancanti prima di sigillare,
  Android sigilla quello che ha (a interruttore acceso un campo nullo diventa
  `""`: una cura con `activeIngredient` nullo lo svuota davvero).
- Restano in chiaro in `medicalVisits` i campi `travelDetailsData`,
  `asNeededDrugsData`, `prescribedExamsData` (Data in base64) e
  `asNeededDrugsJson`, che possono contenere nomi di farmaci: candidati per un
  secondo giro.
- La ricifratura tocca anche i documenti cancellati che il client legge
  (spese, contesto dell'assistente sul web): qualche scrittura in più, nessun
  danno.

Commit della tappa 1: web 996b84e3 (pubblicato), Android 2b141b7, iOS 32c2c8da.

Il prezzo noto della tappa 3: chi resta su una build vecchia vede vuoti nome,
titolo e note dei documenti cifrati (date, importi e struttura restano).

---

# Secondo giro (09/11/2026, stessa build): buchi, figli, to-do, calendario

Stesso formato, stessa regola di lettura, stesso interruttore
`sections_encryption_enabled`. Cambia o si aggiunge solo quanto segue.

## 1. Regola nuova per le scritture parziali (tutti e tre i client)

Quando si sigilla una scrittura che **non** porta tutti i campi della tabella,
i campi mancanti si prendono dal documento esistente (letto e risolto con la
regola di lettura) prima di cifrare. Se la lettura fallisce, si scrive in
chiaro. Così un campo che un client non conosce (es. `name` dei vaccini, che
scrive solo Android) non si perde quando un altro client riscrive `secure`.
Sostituisce i tre comportamenti diversi della tappa 1.

## 2. Campi «da cancellare» invece che `""`

I campi segnati con `*` nella tabella, quando sigillati, si scrivono
**cancellati** (`FieldValue.delete()` / `deleteField()`) invece che `""`: sono
opzionali e contengono JSON o base64, che un parser vecchio potrebbe non
reggere vuoti. Nella regola di lettura un campo assente equivale a vuoto.

## 3. Tabella estesa

| Collezione | Campi in `secure` (aggiunti in **grassetto**) |
|---|---|
| `vaccines` | `commercialName`, `lotNumber`, `administeredBy`, `notes`, **`name`**, **`doctorName`**, **`location`** |
| `medicalVisits` | `doctorName`, `reason`, `diagnosis`, `recommendations`, `notes`, `nextVisitReason`, **`travelDetailsData*`**, **`travelDetailsJson*`**, **`asNeededDrugsData*`**, **`asNeededDrugsJson*`**, **`prescribedExamsData*`**, **`prescribedExamsJson*`** |
| **`children`** | **`name`** |
| **`todos`** | **`title`**, **`notes`** |
| **`todoLists`** | **`name`** |
| **`calendarEvents`** | **`title`**, **`notes`**, **`location`** |

Restano in chiaro: `birthDate` dei figli, date e ricorrenze degli eventi,
assegnatari, visibilità, `remindAt`/`remindSentAt` (li usa il motore dei
promemoria). L'array `prescribedExams` di Android resta in chiaro (non è una
stringa): limite noto.

**Figli**: il nome si legge in molti punti. Ogni lettura da Firestore della
collezione `children` (sync, lettura della famiglia all'ingresso, inviti,
widget, assistente, web) passa dalla regola di lettura. Il server non legge i
nomi dei figli.

**To-do creati dal server** (richieste di famiglia, Alexa no: è la spesa):
nascono in chiaro e li ricifra il primo client che li legge.

## 4. Calendario e link iCal (scelta dell'utente: «in chiaro se esportati»)

- Il server scrive sul documento famiglia `calendarExported: true` quando
  qualcuno crea o rigenera un link iCal, e anche quando il feed viene letto
  (così le famiglie che lo usano già si segnano da sole entro un giorno);
  `false` quando non resta nessun link della famiglia.
- Client, per `calendarEvents`: se la famiglia ha `calendarExported == true`
  **non** si sigilla e i documenti con `secure` si **riaprono** (scrittura in
  merge dei campi in chiaro risolti + `secure` e `secureV` cancellati, senza
  toccare `updatedAt`). Altrimenti regola normale.
- Feed: un evento con `secure` e titolo vuoto esce come «Impegno» (localizzato
  come il resto del feed) finché un client non lo riapre.

## 5. Push con il testo cifrato (iOS e Android)

Push coinvolte: `notifyNewCalendarEvent`, `notifyTodoAssigned`,
`notifyDueTodoReminders`, le push di `familyRequests` che citano un to-do,
`notifyNewExpense`.

Server: se il documento ha `secure` e il titolo in chiaro è vuoto, la push
porta in `data`:

- `secure`: il blob del documento (solo se ≤ 2500 caratteri, altrimenti niente);
- `secureColl`: nome della collezione;
- `secureFamilyId`: familyId;
- `titleTpl`, `bodyTpl`: titolo e testo **già tradotti** nella lingua del
  destinatario, con segnaposto `{campo}` (es. `{title}`) da riempire coi
  valori decifrati;
- `title`/`body` visibili e `fallbackBody`: la versione generica senza testo
  dell'utente (es. «Nuovo evento in calendario»).

Su Android la push è **solo dati** con la stessa regola della chat
(`config/chatPush.dataOnlyAll`, oggi `true` per tutti), così gira
`onMessageReceived`. Su iOS `mutable-content: 1` e la Notification Service
Extension.

Client (NSE iOS, `KidBoxFirebaseMessagingService` Android): se c'è `secure`,
decifra con la chiave di famiglia, riempie `titleTpl`/`bodyTpl` (un segnaposto
senza valore → si usa la versione generica intera), altrimenti mostra
`title`/`body` generici. Deep link invariati.

## 6. Tappe del secondo giro

Tutto dietro lo stesso interruttore spento: a interruttore spento nessun
documento ha `secure`, il server non aggiunge niente alle push e il feed non
cambia.

## Stato del secondo giro (09/11/2026)

Commit: functions 2a7a948c (deployate le 13 functions toccate), web ec18c758
(pubblicato), iOS 6a2b64de, Android 568108b. Interruttore ancora spento.

Limiti noti emersi:
- **Delega automatica** (`delegateUnassignedTodos`): un to-do cifrato non si
  delega (`kidboxAsk.outcome: "sealed"`), perché la richiesta nascerebbe col
  titolo vuoto anche nel link `/r`.
- **Push sul web**: testo generico, il service worker non decifra.
- **Feed iCal**: «Impegno» solo in italiano (il feed non ha lingua).
- **Membro appena entrato senza chiave**: vede vuoti nomi e titoli finché la
  chiave non arriva e il listener non ripropone il documento (riparo solo per
  il nome dei figli su iOS).
- **iOS**: `calendarExported` in cache 10 minuti; subito dopo la creazione di
  un link iCal un evento può nascere cifrato, poi viene riaperto.
- **Android**: le push solo dati di to-do e richieste ora incrementano il
  badge anche ad app chiusa, e i pulsanti delle richieste compaiono anche lì.
- Le visite da Android sono sempre scritture parziali: una lettura in più per
  salvataggio a interruttore acceso.
- `calendarExported` è scrivibile dai membri (non è fra i campi protetti):
  il server non se ne fida per nulla di sicurezza.
