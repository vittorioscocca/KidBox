# Chiave di riserva v2: la copia della chiave di famiglia che il server non può aprire

Piano scritto l'08/11/2026. Stato: **da approvare, niente ancora nel codice.**
Contesto e regole generali sulla chiave: skill `/cifratura`.

## 1. Il problema, in una frase

La chiave di famiglia cifra documenti, note, password, Wallet, chat e foto. La sua
copia di riserva su Firestore (`families/{familyId}/memberKeyBackups/{uid}`) è
avvolta con una chiave ricavata **solo** da `uid`, `familyId` e due costanti scritte
nell'app (`kidbox-escrow-salt-2026`, `kidbox-key-escrow-v1`): nessuna è segreta.
Chi può leggere quel documento ricostruisce la chiave. Oggi la protezione è
**solo** la regola Firestore `request.auth.uid == memberUid`.

Dove sta il codice:

| Client | File |
|---|---|
| iOS / Mac | `KidBox/KidBox/Support/FamilyKeyEscrowService.swift` |
| Android | `KidBoxAndroid/.../data/crypto/FamilyKeyEscrow.kt` |
| Web | `KidboxWebApp/src/services/familyKey.js` (chiave solo in memoria: a ogni sessione la rilegge dall'escrow) |
| Rules | `firestore.rules`, `match /memberKeyBackups/{memberUid}` |
| Functions | `functions/index.js`: `memberKeyBackups` nella cancellazione di famiglia e di account |

### Chi oggi può ricavare la chiave

| Chi | Può? | Perché |
|---|---|---|
| Un estraneo senza accessi | No | file e campi cifrati, regole che bloccano la copia |
| Chi ruba l'account di un membro | Sì | entra come lui (vale per qualunque app; resta vero anche dopo) |
| Chi ha un accesso amministrativo al progetto Firebase (service account trapelato, account Google del proprietario, function manomessa) | **Sì, per tutte le famiglie** | legge tutte le copie e conosce le costanti |
| Chi legge un backup o un export di Firestore | **Sì** | stesso motivo |
| Un errore futuro nelle regole su `memberKeyBackups` | **Sì** | la regola è l'unica barriera |

### Cosa è già a posto (non si tocca)

- **Inviti**: la chiave viaggia avvolta con un segreto che sta nel **frammento** del
  link (`#k=`) e non arriva mai al server; su Firestore c'è solo l'hash.
- **Apple**: la chiave è nel Portachiavi con `kSecAttrSynchronizable` (Portachiavi
  iCloud, cifrato end-to-end da Apple): un iPad o un Mac nuovo con lo stesso account
  Apple la trova senza passare da noi. Lì la copia sul server serve solo se
  il Portachiavi iCloud è spento.
- **Android**: `allowBackup="false"`, quindi dopo una reinstallazione oggi c'è solo
  l'escrow.

## 2. L'obiettivo

1. La copia sul server resta (serve al web e a chi perde il telefono), ma è avvolta
   con un segreto che **solo l'utente** ha. Il server conserva byte che non sa aprire.
2. Nella maggior parte dei casi non serve nemmeno quella: la chiave arriva da un
   altro dispositivo o da un familiare.
3. Chi dimentica tutto e non ha altri dispositivi né familiari perde i dati cifrati.
   È il prezzo della cifratura vera, e va detto chiaro all'utente.

Non è un obiettivo (qui): proteggere da chi ruba l'account **e** ha già un
dispositivo sbloccato; cambiare cosa è cifrato e cosa no (to-do e richieste restano
in chiaro, di proposito).

## 3. Il modello nuovo

### 3.1 Una «chiave personale» per utente

Oggi ogni famiglia ha la sua copia avvolta in modo debole. Nella v2 c'è un livello
in più:

```
segreto dell'utente (codice di recupero / passkey)
        └─ apre ─▶ chiave personale (32 byte casuali, una per utente)
                          └─ apre ─▶ chiave di famiglia A, chiave di famiglia B, …
```

- **Chiave personale (RK)**: 32 byte casuali generati sul dispositivo. Vive nel
  Portachiavi (sincronizzato) su Apple, nel Keystore su Android, in IndexedDB come
  `CryptoKey` non esportabile sul web.
- **Cassaforte dell'utente** `users/{uid}/keyVault/main`: la RK avvolta da uno o più
  «slot», uno per ogni modo di aprirla (come le serrature con più chiavi):
  - `recoveryCode`: chiave = HKDF-SHA256(codice, salt casuale per slot). Il codice lo
    **genera l'app** (24 caratteri base32 a gruppi, ~120 bit): con tanta entropia non
    serve una derivazione lenta, e nessuno lo indovina.
  - `passkey`: chiave = HKDF(output dell'estensione **WebAuthn PRF** della passkey).
    Funziona su Safari, Chrome, iOS e Android recenti; dove non c'è, solo codice.
  - formato di ogni slot: `{type, salt, nonce, cipher, tag, credentialId?, createdAt}`.
- **Copia di riserva v2** `families/{familyId}/memberKeyBackups/{uid}`: la chiave di
  famiglia avvolta con la RK, `version: 2`. Stesso percorso di oggi, così
  cancellazione di famiglia e di account funzionano già.

Un solo codice per utente, anche con più famiglie. Aggiungere una famiglia = una
copia v2 in più, nessun codice nuovo.

### 3.2 Come si riavrà la chiave, in ordine

| Situazione | Strada | Server coinvolto? |
|---|---|---|
| Stesso telefono | Portachiavi / Keystore | No |
| iPad o Mac con lo stesso account Apple | Portachiavi iCloud | No (Apple, end-to-end) |
| Dispositivo nuovo, ne ho un altro in mano | **QR dal vecchio dispositivo** | Solo byte cifrati con un segreto che sta nel QR |
| Dispositivo nuovo, un familiare ha l'app | **QR del familiare**, come un invito | Come sopra |
| Browser nuovo | **Passkey**, altrimenti codice di recupero | Sì, ma vede solo byte chiusi |
| Ho perso tutto, sono l'unico membro | Codice di recupero | Sì, byte chiusi |
| Ho perso tutto, anche il codice, e sono solo | **Dati cifrati persi** | — |

Il QR riusa `InviteCrypto` (segreto nel QR, materiale avvolto in un documento a
scadenza breve, 10 minuti, cancellato dopo l'uso): il codice c'è già per gli inviti.

## 4. Le fasi

### Fase 0 — Subito, prima del codice
- Landing e schede store: «cifrato con una chiave della famiglia» al posto di
  «cifrato end-to-end» finché non si chiude la Fase 3. Quattro lingue, landing e
  descrizioni App Store/Play.
- Decisioni dell'utente (sezione 8).

### Fase 1 — Cassaforte v2 nei tre client (lettura e scrittura)
- **iOS/Mac**: `FamilyKeyVault.swift` nuovo (RK, slot, copia v2). In
  `FamilyKeyEscrowService.ensureFamilyKeyAvailable`: Portachiavi → copia v2 con la
  RK → (solo durante la transizione) copia v1.
- **Android**: `FamilyKeyVault.kt`; la RK nel Keystore. Valutare **Google Block
  Store** per far sopravvivere la RK a una reinstallazione (end-to-end se il telefono
  ha il blocco schermo).
- **Web**: `familyKeyVault.js`; RK in IndexedDB non esportabile; passkey con PRF.
- **Costanti nuove** (`kidbox-vault-v2`, info HKDF degli slot) identiche sui tre
  client: un carattere diverso = chiave diversa = dati illeggibili.
- **Rules**: `users/{uid}/keyVault/{doc}` solo il proprietario, forma validata;
  `memberKeyBackups` accetta `version` 1 o 2, solo il proprio `uid`. Suite in
  `firestore-tests/` con la verifica differenziale (`/rules-change`).
- **Functions**: `deleteAccount` cancella anche `users/{uid}/keyVault`.

### Fase 2 — Ogni utente crea il suo segreto
- **Dopo l'aggiornamento** (una volta, rimandabile): «Proteggi la chiave della tua
  famiglia», con passkey (Face ID / Touch ID / impronta) o codice di recupero. Il
  codice si mostra una volta, con «Salva nelle Password» / condividi / stampa, e si
  chiede di riscriverne 4 caratteri per conferma.
- Fatto il passo: si scrive la copia v2 per ogni famiglia e si **cancella la propria
  v1** (il client può cancellare il proprio documento).
- **Web**: al primo accesso dopo il rilascio è obbligatorio. Si legge la v1 un'ultima
  volta, si crea passkey o codice, si scrive la v2, si cancella la v1.
- **QR fra dispositivi** e **QR da un familiare** in Impostazioni › Famiglia, e nella
  schermata «chiave mancante» (`FamilyKeyMissingGate` / `MissingFamilyKeyException`).
- **Misura**: quota di utenti attivi con `keyVault` e senza v1 (script di sola
  lettura sul conteggio dei documenti, non sui contenuti).

### Fase 3 — Chiusura della v1
Quando la quota della Fase 2 è alta (soglia da decidere, es. 90% degli attivi a 30
giorni):
- **Rules**: `memberKeyBackups` accetta solo `version == 2`. Le app vecchie che
  provano a riscrivere la v1 vengono rifiutate: la loro scrittura è «best-effort», la
  chiave resta nel loro Portachiavi, nessuna rottura visibile.
- **Cancellazione delle v1 rimaste** con `scripts/firestore-delete-doc.js`, un
  documento alla volta, prima senza `--yes` e mostrando l'elenco. Chi non ha
  aggiornato perde solo il recupero dal server: gli resta il telefono e il QR di un
  familiare.
- Solo da qui la landing può tornare a dire «end-to-end».

### Fase 4 — Rotazione della chiave di famiglia (dopo, facoltativa)
La chiave attuale va considerata **già esposta** a chi ha avuto accesso al server
finora (e i backup di Firestore la conservano). Per chiudere davvero:
- chiave di famiglia nuova con un `keyId`; ogni campo `*Enc` e ogni file `.kbenc`
  ricifrato **dal telefono** di un membro (il server non può farlo);
- i client leggono entrambe le chiavi durante la migrazione, scrivono solo con la
  nuova;
- è anche la cura per i **membri revocati**, che oggi tengono la vecchia chiave nel
  loro Portachiavi.

È il lavoro più pesante (documenti e foto da riscaricare e ricaricare) e va
progettato a parte.

## 5. Casi limite

- **Più famiglie**: un codice solo (la RK è dell'utente).
- **Estensioni iOS** (Notification Service, AutoFill) leggono `SharedFamilyKey`:
  invariate, la chiave di famiglia in locale non cambia.
- **Membro che esce o viene revocato**: si cancella la sua copia v2 (come oggi la
  v1); la sua cassaforte resta sua.
- **Portachiavi iCloud spento** su Apple: si comporta come Android.
- **Account cancellato**: `keyVault` e copie v2 spariscono con l'account.
- **Codice compromesso**: «Rigenera codice» = slot nuovo, slot vecchio eliminato; la
  RK resta la stessa, quindi niente da ricifrare.

## 6. Prove (prima di ogni fase)

- Cross-client: A crea il codice su iOS, B entra dal web con la passkey, C reinstalla
  Android e recupera col codice; tutti leggono una nota, una password e una foto del
  Wallet.
- Recupero via QR fra due dispositivi dello stesso utente e da un familiare.
- App vecchia (build in vendita) dopo la Fase 3: nessun crash, nessun dato perso.
- Suite delle regole con i casi nuovi (`keyVault` di un altro utente, `version: 1`
  dopo la chiusura).
- Mai un valore decifrato o un codice nei log, nelle notifiche, negli eventi GA4.

## 7. Cosa diciamo agli utenti (testi da tradurre in 4 lingue)

- Titolo: «Proteggi la chiave della tua famiglia».
- Corpo: «Documenti, password e foto di KidBox sono cifrati con una chiave che ha solo
  la tua famiglia. Per ritrovarla su un nuovo telefono o sul computer, attiva Face ID
  o salva un codice di recupero. Nemmeno KidBox può aprirla.»
- Avviso sul codice: «Se perdi questo codice e tutti i tuoi dispositivi, e nessun
  familiare ha l'app, i dati cifrati non si possono recuperare.»

## 8. Decisioni che spettano all'utente

1. Sulle app (iOS/Android) il passo è **obbligatorio** o **rimandabile**? (Proposta:
   rimandabile, ricordato una volta a settimana; sul web obbligatorio.)
2. Soglia per la Fase 3 (proposta: 90% degli attivi a 30 giorni, poi chiusura).
3. Fase 4 sì o no, e quando.
4. Testo della landing da cambiare subito (Fase 0)?

### Decise dall'utente l'08/11/2026

1. **App: rimandabile per 3 giorni, poi obbligatorio.** Chi ha il telefono
   attivo non viene bloccato all'aggiornamento; dal terzo giorno dopo il primo
   avvio della versione v2 il promemoria non si chiude più finché il segreto non
   esiste. Il conteggio parte dal primo avvio della versione nuova su quel
   device, salvato in locale. Sul web resta obbligatorio da subito.
2. **Chiusura v1: 90% dei membri attivi passati alla v2, e comunque dopo 30
   giorni** dall'uscita delle versioni con la Fase 1. Chi resta fuori rientra
   da telefono attivo o QR.
3. **Fase 4 dopo, a parte**: si decide a Fase 3 chiusa.
4. **Landing invariata**: «end-to-end» resta com'è. La Fase 0 si riduce ai
   testi dentro le app (schermata del segreto e promemoria).

## 9. Stima a grandi linee

| Fase | Lavoro |
|---|---|
| 0 | mezza giornata (testi in 4 lingue) |
| 1 | 3-4 giorni (tre client, regole, test) |
| 2 | 2-3 giorni (UX, QR, testi) + attesa dell'adozione |
| 3 | 1 giorno + cancellazioni |
| 4 | da progettare; settimane, non giorni |
