---
name: cifratura
description: La chiave di famiglia di KidBox — dove vive, come arriva a un nuovo membro, cosa si rompe se si sbaglia, e cosa il server NON può fare per via sua. Usare quando si tocca un campo cifrato (documenti, note, password, wallet, chat, foto), il join o la revoca di un membro, l'escrow della chiave, o quando l'utente dice «non vedo più le note», «si vede cifrato», «non riesco a leggere».
---

> È la skill più trasversale del progetto: **una sola chiave** copre documenti,
> note, password, wallet, chat e foto/video. Un errore commesso lavorando su
> *una* sezione rende illeggibili *tutte* le altre, e non c'è modo di rimediare
> lato server — il backend vede byte.

## Cosa è cifrato e come si riconosce

Convenzione: il campo cifrato finisce in **`Enc`** — `textEnc`, `titleEnc`,
`bodyEnc`, `notesEnc`, `fileNameEnc`, `holderNameEnc`, `seatEnc`,
`bookingCodeEnc`, `barcodeTextEnc`, `locationEnc`, `arrivalLocationEnc`.
Se aggiungi un campo con contenuto scritto dall'utente, si chiama così anche lui.

Su un campo `*Enc` **non** si fanno query, **non** si costruiscono indici, **non**
si scrivono log, e **nessuna Cloud Function può migrarlo**: un cambio di schema
su un campo cifrato non è backfillabile dal server, va fatto dai client.

## Dove vive la chiave (tre posti, non uno)

| Client | Dove |
|---|---|
| iOS | Keychain (`FamilyKeychainStore`) + **mirror** in access group condiviso con l'estensione AutoFill (`SharedFamilyKey`, account `family.key`) |
| Android | Keystore / `EncryptedPrefs` (`FamilyKeyStore`) |
| Web | **da nessuna parte**: non c'è Keychain, la chiave passa sempre dall'escrow |

L'**escrow** è `families/{familyId}/memberKeyBackups/{uid}`: la chiave AES-256
della famiglia, wrappata con una chiave derivata in modo **deterministico** da
`(userId, familyId)`. È il percorso previsto dai client nativi dopo una
reinstallazione o un cambio di device, ed è l'**unico** percorso del web.

⚠️ **Sul web, se `backupFamilyKey` fallisce, la famiglia è cieca per sempre.**
Non c'è una seconda copia da cui ripartire.

⚠️ **Le costanti di derivazione devono restare identiche su tutti i client**
(`ESCROW_SALT`, `ESCROW_CONTEXT`, e le costanti di `InviteCrypto` ↔
`onboarding.js` sul web). **Un carattere diverso produce una chiave diversa**, e
il risultato non è un errore: è testo illeggibile, scoperto dopo.

## Come la chiave arriva a un nuovo membro

Viaggia nel **frammento** del link d'invito (`…/join?familyId&inviteId#k=…`). Il
frammento non viene trasmesso al server: la chiave non passa mai da Firestore in
chiaro. Sul web va **catturata prima del render** (`pendingInvite.js`,
sessionStorage) perché il login social ricarica la pagina e perderebbe il
frammento.

L'hash del segreto dell'invito lo verifica **il client**, non le rules: è per
questo che le regole sugli inviti devono reggere da sole → `/rules-change`.

## Revoca, uscita, cancellazione

- Revocare un membro **cancella il suo** `memberKeyBackups/{uid}`: perde
  l'accesso al rientro dall'escrow, ma **la chiave che ha già in Keychain
  sopravvive**. Non è un buco: è il motivo per cui l'8/09/2026, quando i membri
  si sono auto-espulsi per un errore nelle rules, sono potuti rientrare da
  QR/link senza perdere i dati.
- Cancellare la famiglia **deve** includere `memberKeyBackups` nell'elenco delle
  sottocollezioni: mancava, e restavano orfani documenti con dentro la chiave
  wrappata di ogni membro.
- Se la chiave manca, l'app non deve fingere: c'è un percorso dedicato
  (`FamilyKeyMissing` / `FamilyKeyMissingGate` su iOS,
  `MissingFamilyKeyException` su Android).

## Cosa la cifratura rende impossibile (e non è un bug da risolvere)

- **Anteprime nelle notifiche**: su Android la notifica di chat resta «Nuovo
  messaggio» perché il sistema la mostra senza eseguire codice dell'app. Su iOS
  il testo si vede solo grazie alla Notification Service Extension, che decifra
  prima del banner. → `/notifiche`
- **Ricerca, AI o analytics lato server sui contenuti**: il server vede byte.
  Tutto ciò che legge contenuti gira **sul client**.
- **QA**: gli script con il client SDK possono verificare che i blob esistano e
  che le regole reggano, **non** i contenuti. La prova vera è cross-client: A
  scrive su iOS, B legge su Android e web. → `/qa-device`
- **Supporto**: davanti a «non vedo più le note», la prima domanda non è sui
  dati ma sulla **chiave**: quel device ce l'ha? l'escrow c'è? è lo stesso
  `familyId` (la famiglia attiva vive su `users/{uid}.activeFamilyId`)?

## Prima di dire «fatto»

- Il campo nuovo si chiama `*Enc` e nessuno ci fa query sopra.
- Cifratura e decifratura esistono su **tutti e tre** i client, con le stesse
  costanti.
- Un membro nuovo, su un device nuovo, legge quel campo (prova cross-client).
- Niente valori decifrati nei log, nelle notifiche, negli eventi analytics.
