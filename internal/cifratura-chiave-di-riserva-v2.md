# Chiave di riserva v2: la copia della chiave di famiglia che il server non può aprire

Piano scritto l'08/11/2026. Stato al 09/11/2026: **Fase 1 fatta per regole,
`deleteAccount` e web app** (deployate; web provata sugli emulatori e accesa
solo per gli account interni: `config/keyVault.internal`). Dominio delle
passkey pronto per iOS e Android. iOS e Android scritti e committati (non
pushati, nessuna UI: arriva con la Fase 2), provati sul vettore del web.
Formato e costanti nella sezione 3.3.
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
- **Cassaforte dell'utente** `users/{uid}/keyVault/{slotId}` (un documento per
  slot, sezione 3.3): la RK avvolta da uno o più
  «slot», uno per ogni modo di aprirla (come le serrature con più chiavi):
  - `recoveryCode`: chiave = HKDF-SHA256(codice, salt casuale per slot). Il codice lo
    **genera l'app** (24 caratteri base32 a gruppi, ~120 bit): con tanta entropia non
    serve una derivazione lenta, e nessuno lo indovina.
  - `passkey`: chiave = HKDF(output dell'estensione **WebAuthn PRF** della passkey).
    Funziona su Safari, Chrome, iOS e Android recenti; dove non c'è, solo codice.
    **Più slot passkey per utente**, uno per ogni credenziale: quella creata su
    iPhone vive nel Portachiavi iCloud, quella creata su Android nel Gestore
    password di Google, e sono serrature diverse. Dopo un rientro su un sistema
    nuovo l'app propone di aggiungere la passkey di quel sistema.
  - formato di ogni slot: sezione 3.3.
- **Il codice di recupero c'è sempre, la passkey è un'aggiunta.** Chi crea la
  cassaforte riceve il codice in ogni caso: una passkey sola lascerebbe fuori chi
  entra da un Mac con un altro account Apple, da Windows o da Android.
- **La biometria non c'entra con la chiave.** Face ID, Touch ID e impronta
  sbloccano il dispositivo; la passkey è la stessa e l'uscita PRF è la stessa,
  quindi iPhone con Face ID e Mac con l'impronta aprono la stessa cassaforte.
- **Copia di riserva v2** `families/{familyId}/memberKeyBackups/{uid}`: la chiave di
  famiglia avvolta con la RK, nella mappa `v2` **accanto** ai campi della v1 (che
  resta fino alla Fase 3). Stesso documento di oggi, così revoca, uscita,
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

Casi concreti, stesso account KidBox:

| Da → a | Strada | Note |
|---|---|---|
| iPhone → app Mac, stesso account Apple | Portachiavi iCloud | Da provare: che l'app Mac legga la stessa voce sincronizzata non è scontato |
| iPhone → web in Safari sul Mac, stesso account Apple | Passkey sincronizzata, sblocco con l'impronta | — |
| iPhone → web in Chrome sul Mac | Passkey iCloud **probabilmente**; altrimenti codice | Da provare sul Mac dell'utente prima di contarci |
| iPhone → Mac con un altro account Apple | QR dall'iPhone, altrimenti codice | La passkey lì non c'è |
| iPhone → Android | QR dall'iPhone, poi QR di un familiare, poi codice | La passkey Apple via «inquadra con il telefono» (hybrid) non dà il PRF in modo affidabile: non ci si conta |
| Android → web in Chrome, stesso account Google | Passkey sincronizzata dal Gestore password di Google | — |
| Telefono → web su un PC qualunque (Windows compreso) | **«Entra con il telefono»** (sotto) | Strada principale del web quando la passkey non c'è |

**«Entra con il telefono» (come WhatsApp Web, deciso il 09/11/2026).** Il QR
fra dispositivi qui va al contrario: il PC non ha la fotocamera, quindi è il
browser a mostrare il QR e l'app a inquadrarlo.
1. Il browser, già loggato, genera una coppia di chiavi effimera (ECDH P-256).
   La privata resta in memoria; nel QR vanno la pubblica e l'id di una
   «stanza» Firestore creata dal PC, a scadenza di 10 minuti.
2. L'app KidBox inquadra, **controlla che la stanza sia dello stesso uid**
   (chi ti fa inquadrare il suo QR non riceve niente) e chiede conferma:
   «Mandare la chiave di "Famiglia X" al browser Chrome su Windows?».
3. L'app chiude la chiave di famiglia con la pubblica e la deposita nella stanza.
4. Il browser, in ascolto sulla stanza, apre con la privata e cancella la stanza.
Il server vede solo byte chiusi. Variante da familiare: la stanza è di chi
entra, il telefono del familiare conferma chi è.

**Una cassaforte per utente, valida ovunque.** Se esiste, ogni client la
**apre** (passkey o codice); la **crea** solo se non esiste. Il codice creato
su iOS è lo stesso che si scrive sul web, e viceversa.

**Dominio della passkey.** La passkey è legata al dominio (RP ID): va fissato
una volta a `kidboxapp.com` (non `app.kidboxapp.com`) ed è una costante come
quelle HKDF. Perché la passkey creata dall'app iOS valga sul web servono
`webcredentials:kidboxapp.com` negli Associated Domains dell'app e l'app
elencata in `apple-app-site-association` della landing; su Android il
`assetlinks.json` con il permesso `get_login_creds`. Da verificare prima di
scrivere il codice delle passkey.

Il QR riusa `InviteCrypto` (segreto nel QR, materiale avvolto in un documento a
scadenza breve, 10 minuti, cancellato dopo l'uso): il codice c'è già per gli inviti.

### 3.3 Formato e costanti v2 (scritti il 09/11/2026 col web; iOS e Android li copiano identici)

Un carattere diverso in una di queste stringhe produce una chiave diversa e dati
illeggibili, senza un errore. Riferimento: `KidboxWebApp/src/services/familyKeyVault.js`.

| Cosa | Valore |
|---|---|
| Contesto | `kidbox-vault-v2`, `version: 2` negli slot |
| RK | 32 byte casuali |
| `rkId` (pubblico) | HKDF-SHA256(ikm = RK, salt vuoto, info `kidbox-vault-v2:rk-id`), 16 byte, base64url senza padding |
| Codice di recupero | 15 byte casuali → 24 caratteri base32 di Crockford `0123456789ABCDEFGHJKMNPQRSTVWXYZ`, mostrato `XXXX-XXXX-XXXX-XXXX-XXXX-XXXX` |
| Forma canonica del codice | maiuscole, via spazi e trattini, `O`→`0`, `I` e `L`→`1`; deve restare di 24 caratteri dell'alfabeto |
| Chiave dello slot codice | HKDF-SHA256(ikm = UTF-8 della forma canonica, salt = 16 byte casuali dello slot, info `kidbox-vault-v2:slot:recoveryCode`), 32 byte |
| Input PRF della passkey | `eval.first` = UTF-8 di `kidbox-vault-v2:prf` |
| Chiave dello slot passkey | HKDF-SHA256(ikm = uscita PRF di 32 byte, salt = 16 byte dello slot, info `kidbox-vault-v2:slot:passkey`), 32 byte |
| Cifratura della RK nello slot | AES-256-GCM, nonce 12 byte, AAD = UTF-8 di `kidbox-vault-v2:rk:{uid}` |
| Chiave per le copie di famiglia | HKDF-SHA256(ikm = RK, salt vuoto, info `kidbox-vault-v2:family`), 32 byte |
| Cifratura della copia v2 | AES-256-GCM, nonce 12 byte, AAD = UTF-8 di `kidbox-vault-v2:family:{uid}:{familyId}` |
| Dominio della passkey (RP ID) | `kidboxapp.com` su `*.kidboxapp.com`; in sviluppo l'host stesso |
| Dichiarazioni del dominio (09/11/2026) | `kidboxapp.com/.well-known/apple-app-site-association` con `webcredentials.apps = ["5WA8KG2G2W.it.vittorioscocca.KidBox"]` (già sul CDN di Apple) e entitlement iOS `webcredentials:kidboxapp.com`; `assetlinks.json` con `delegate_permission/common.get_login_creds` per `it.vittorioscocca.kidbox` firmata `ED:B8:…:80:99`, la chiave di firma di Play (letta dagli APK generati della release 86). Verificato con `assetlinks:check` di Google: `linked: true`. L'`assetlinks.json` di `app.kidboxapp.com` è generato da Firebase con altre impronte: non conta, l'RP ID è `kidboxapp.com` |
| Id dello slot passkey | `passkey_` + base64url dei primi 16 byte di SHA-256(rawId della credenziale) |

Ciphertext e tag sempre in **campi separati**, base64 standard (come la v1 e
CryptoKit); `credentialId` e `rkId` in base64url.

**Documenti** (forma imposta dalle rules, suite in `firestore-tests/`):
- `users/{uid}/keyVault/recoveryCode` e `users/{uid}/keyVault/passkey_<id>`:
  `{type: "recoveryCode"|"passkey", version: 2, rkId, salt, nonce, cipher, tag,
  credentialId? (solo passkey), label? (es. «Chrome · Mac»), createdAt, updatedAt?}`.
  Solo il proprietario legge e scrive; un update non cambia `rkId`.
- `families/{fid}/memberKeyBackups/{uid}`: `{cipher, nonce, tag, updatedAt,
  version: 1, v2?: {cipher, nonce, tag, rkId, updatedAt}}` finché c'è la v1;
  dopo la Fase 3 `{version: 2, v2, updatedAt}`. Le app vecchie riscrivono la v1
  con `setData` e la mappa `v2` sparisce: è previsto, i client nuovi la
  riaggiungono con un merge alla lettura successiva. **Nessun client nuovo
  sovrascrive il documento senza rimettere anche la `v2`.**
- Creazione: lo slot del codice si crea in transazione solo se non esiste; se
  un altro dispositivo l'ha appena creata, si apre quella (mai due RK).

**Interruttore** `config/keyVault`: `{enabled, internal, enforce}`. `enabled` =
tutti; `internal` = solo gli uid in `config/internalUsers.uids`; `enforce` = niente
«Più tardi». Documento assente = spento per tutti (stato al 09/11/2026).

**Web** (fatto il 09/11/2026):
- la RK sta in IndexedDB (`kidbox-vault`, store `rk`, chiave = uid) come
  `CryptoKey` HKDF non esportabile; all'**uscita dall'account** il browser la
  dimentica (anche col logout remoto), e al login successivo chiede di nuovo
  passkey o codice una volta;
- lettura: v2 se il browser ha la RK, poi v1; se c'è solo la v2 e manca la RK,
  `MissingFamilyKeyError` con `vaultLocked = true`;
- alla lettura dalla v1 con la cassaforte attiva, la copia v2 si aggiunge in
  background; ogni copia v2 scritta si **rilegge dal server e si apre** prima di
  contarla buona (regola 4); la v1 non si cancella (4 ter, punto 2);
- promemoria in `KeyVaultGate` (dentro l'app) e in fondo all'onboarding, dopo
  creazione o ingresso in famiglia, con «Più tardi»;
- prova: 22 controlli su emulatori Auth e Firestore con Chrome e un autenticatore
  virtuale con PRF (crea, ingresso da invito con passkey, rimando, revoca, login
  di un revocato, rientro con passkey e con codice, codice sbagliato, solo v2,
  logout). Limite: un autenticatore virtuale non esporta il segreto PRF, quindi
  «la stessa passkey sincronizzata su un altro dispositivo» va provata con un
  Mac e un iPhone veri.

## 4. Le fasi

### Fase 0 — Subito, prima del codice
- Landing e schede store **invariate** (decisione dell'utente, sezione 8): resta
  il rischio che «end-to-end» prometta più di quanto regge finché la v1 esiste.
- Testi dentro le app (sezione 7) nelle quattro lingue.
- Decisioni dell'utente (sezione 8): prese.

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
- **Functions**: `deleteAccount` cancella anche `users/{uid}/keyVault` (fatto
  e deployato il 09/11/2026).
- **Interruttore `config/keyVault`** letto dai tre client (sezione 4 ter): si
  rilascia spento, si accende prima per gli account di test.

**Fatto sui nativi (09/11/2026).** iOS: `Support/FamilyKeyVault.swift`, RK nel
Portachiavi sincronizzato (service `KidBox`, account `kidbox.vault.rk.{uid}`).
Android: `data/crypto/FamilyKeyVaultCrypto.kt` (JVM puro) e `FamilyKeyVault.kt`,
RK in EncryptedPrefs (`kidbox_vault`, `rk_{uid}`; mai nel fallback in chiaro).
Su entrambi `FamilyKeyEscrow…`: recupero v2 (con la RK locale) → v1; il backup
scrive la v1 in **merge** (prima `setData`/`set` interi cancellavano la v2) e
aggiunge la v2 se l'interruttore è acceso e c'è la RK; dopo un recupero dalla
v1 la v2 mancante si scrive e si verifica in background. Test sul vettore
scritto dal web: `KidBoxTests/CryptoTests/FamilyKeyVaultTests.swift`,
`FamilyKeyVaultCryptoTest.kt`. Block Store: deciso, si fa nella Fase 2 (vedi lì).

**Regola comune ai tre client:** la RK nasce **solo con la cassaforte**
(codice creato o aperto), mai in silenzio all'avvio, come `createVault` sul web. Due
dispositivi che generassero ognuno la sua RK prima che esista la cassaforte
darebbero due chiavi personali per lo stesso utente, e una delle due copie v2
diventerebbe inapribile (regola 1 della sezione 4 bis). Le funzioni
`createVault` e `openWithRecoveryCode` esistono già, le schermate sono la
Fase 2.

### Fase 2 — Ogni utente crea il suo segreto
- **Dopo l'aggiornamento** (promemoria chiudibile finché c'è la v1; l'obbligo
  arriva dopo con `config/keyVault.enforce`: sezioni 4 ter e 8):
  «Proteggi la chiave della tua famiglia». Si genera sempre il codice di
  recupero; la passkey (Face ID / Touch ID / impronta) si propone in aggiunta. Il
  codice si mostra una volta, con «Stampa», «Salva come file» e «Copia» (per il
  gestore di password del sistema: Password di Apple, Gestore password di Google),
  e si chiede di riscriverne 4 caratteri presi a caso per conferma.
- **Mai proporre di salvarlo nelle Password di KidBox**: sono cifrate con la
  chiave di famiglia, cioè con quello che il codice deve recuperare. La schermata
  lo dice.
- **Rigenera codice** in Impostazioni › Famiglia, da qualunque dispositivo che ha
  la chiave: slot nuovo, slot vecchio eliminato, niente da ricifrare.
- Fatto il passo: si scrive la copia v2 per ogni famiglia. **La v1 resta** fino
  alla Fase 3 (rete di sicurezza 2, sezione 4 ter).
- **Web**: al primo accesso dopo il rilascio si propone, chiudibile come sulle
  app finché c'è la v1. Si legge la v1, si apre la cassaforte se esiste
  (passkey, «Entra con il telefono» o codice) o la si crea, si scrive la v2. Il
  segreto si chiede una volta per browser: poi la RK resta in IndexedDB.
- **QR fra dispositivi** e **QR da un familiare** in Impostazioni › Famiglia, e nella
  schermata «chiave mancante» (`FamilyKeyMissingGate` / `MissingFamilyKeyException`).
  Sul web **«Entra con il telefono»** (sezione 3.2): QR mostrato dal browser,
  inquadrato dall'app.
- **Android, RK dopo reinstallazione o telefono nuovo** (deciso dall'utente il
  09/11/2026): la RK si salva anche su **Google Block Store**, ma **solo se
  l'API conferma la cifratura end-to-end** (`isEndToEndEncryptionAvailable`,
  cioè telefono con blocco schermo). Senza blocco schermo o senza servizi
  Google non si salva lì: si torna al codice di recupero o alla passkey. Al
  rientro si legge Block Store prima di chiedere il segreto; una RK trovata
  vale solo se il suo `rkId` coincide con quello della cassaforte. Motivo: senza
  E2E Google potrebbe aprire la RK, cioè proprio quello che la v2 deve
  impedire. È l'equivalente del Portachiavi iCloud su iOS.
- **Stato al 09/11/2026 (non pushato, non provato su device):** su iOS
  (`KeyVaultPromptView.swift`, agganciata in `RootHostView`) e Android
  (`KeyVaultPrompt.kt`, in `AppNavGraph`) c'è la schermata col **solo codice**:
  crea (codice mostrato una volta, «Copia» locale/sensibile, «Salva o stampa»
  dal foglio di condivisione, conferma di 4 caratteri) o apre la cassaforte, poi
  scrive e verifica la v2 di ogni famiglia di cui il telefono ha la chiave.
  Compare 3 secondi dopo l'avvio solo con l'interruttore acceso e senza RK in
  locale; «Più tardi» vale fino alla prossima apertura dell'app. Android prova
  prima Block Store (solo E2E, `rkId` controllato). Testi uguali al web, nelle 4
  lingue. Da fare: passkey native, QR, «Rigenera codice», misura.
- **Prova su Android vero (Xiaomi, account interno, 09/11/2026):** il promemoria
  compare e riconosce la cassaforte creata dal web; codice sbagliato rifiutato;
  col codice vero la RK arriva e la v2 della famiglia attiva viene scritta e
  verificata (stesso `rkId` della cassaforte, v1 intatta). Block Store ha
  risposto **senza E2E** su quel telefono, quindi la RK non è stata salvata lì:
  la regola regge, ma va capito quanti telefoni veri hanno l'E2E prima di
  contarci per la Fase 3.
- **Prova su iPhone vero (stesso account, 09/11/2026):** codice accettato; alle
  10:54 l'app ha riscritto la v1 in merge (la v2 è rimasta) e 18 secondi dopo
  la v2 della famiglia attiva, con lo stesso `rkId` di web e Android. Web,
  Android e iOS aprono la stessa cassaforte.
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

## 4 bis. Non rompere ingresso, revoca e login

Ogni volta che si è toccata la chiave, si sono rotti l'ingresso in famiglia, la
revoca di un membro o il login su un altro dispositivo. Non per la crittografia:
per il codice attorno, che davanti a una chiave mancante o a un errore prendeva
decisioni distruttive (il cleaner delle famiglie residue che cancellava anche
quando il server rifiutava, le rules che facevano auto-espellere i membri). Regole
fisse per la v2:

1. **L'ingresso in famiglia non aspetta mai il segreto.** La chiave arriva
   dall'invito come oggi; la RK nasce in silenzio sul dispositivo se non c'è; la
   copia v2 si scrive subito; il codice si chiede dopo. Se la scrittura della v2
   fallisce si ritenta più tardi, senza bloccare l'ingresso. **Sul web** il
   segreto si propone dentro il flusso di ingresso, prima di finirlo, perché è
   il momento in cui l'utente c'è di sicuro; finché esiste la v1 c'è anche
   «Più tardi» (la v1 si scrive comunque, come oggi). Diventa obbligatorio solo
   con `config/keyVault.enforce`.
2. **La revoca di un membro tocca solo la sua copia in quella famiglia**, mai la
   sua cassaforte (personale: le rules lo impediscono a chiunque altro).
3. **Login su un altro dispositivo, in ordine fisso**: Portachiavi / Keystore →
   RK sincronizzata → cassaforte (passkey o codice) → v1 finché esiste → QR. Se
   nessuna strada riesce: schermata «chiave mancante». **Mai** cancellare dati,
   uscire dalla famiglia o riscrivere la chiave per un fallimento di lettura.
4. **La v1 si cancella solo dopo aver riletto la v2 dal server e averla aperta
   davvero** con la chiave appena scritta: scriverla non basta.
5. **Fino alla Fase 3 la v1 resta come rete**: un difetto della v2 rallenta il
   rientro, non chiude fuori nessuno.

**Tabella di prova prima di ogni fase** (oltre alla sezione 6): per iOS, Android,
web e Mac, tre azioni — entrare in famiglia da invito, revocare un altro membro,
login su un dispositivo nuovo — anche con build vecchie e nuove nella stessa
famiglia. Una cella rossa ferma la fase.

## 4 ter. Reti di sicurezza (09/11/2026)

Gli utenti attivi sono pochi: perderne anche uno per la chiave costa più di
qualche settimana in più con la v1. Dove può andare storto:

| Fase | Chi può restare fuori | Rischio |
|---|---|---|
| 1 | Nessuno: la v2 si aggiunge accanto alla v1, che non si tocca | Basso (il pericolo è il codice attorno, sezione 4 bis) |
| 2 | Chi davanti alla schermata obbligatoria se ne va | Medio: abbandono più che dati |
| 3 | Chi non ha il segreto, perde il telefono e non ha familiari con l'app | Unica perdita vera di dati |
| 4 | Una ricifratura interrotta a metà | Alto, facoltativa, da progettare a parte |

1. **Interruttore `config/keyVault`** (come `config/chatPush`): spento = i
   client si comportano come oggi; acceso solo per `config/internalUsers` =
   prova sugli account di test; acceso per tutti = rilascio. Letto con cache
   breve, spegnibile senza release né deploy. Con l'interruttore spento la v2
   non si scrive e non si chiede alcun segreto; quella già scritta si può
   ancora leggere, ma la v1 resta la strada sicura.
2. **La v1 non si cancella in Fase 2.** Si cancella solo in Fase 3. Un difetto
   della v2 rallenta il rientro, non chiude fuori nessuno.
3. **Fase 3 solo con i nomi davanti**: prima della chiusura, l'elenco degli
   utenti attivi senza cassaforte (script di sola lettura), da contattare uno
   per uno. Chi è in una famiglia con 2+ membri rientra comunque con il QR di
   un familiare.
4. **All'inizio il promemoria si chiude sempre** (deciso dall'utente il
   09/11/2026, cambia la decisione 1 della sezione 8). È il punto in cui è più
   facile perdere qualcuno: finché i primi utenti reali non sono passati senza
   problemi il promemoria è insistente ma chiudibile anche dopo i 3 giorni.
   L'obbligo è un secondo interruttore (`config/keyVault.enforce`), acceso
   dopo, su decisione dell'utente. **Anche sul web** (deciso il 09/11/2026):
   finché c'è la v1 il browser rilegge la chiave da lì, quindi il segreto non
   deve essere obbligatorio. L'obbligo sul web serve solo prima della Fase 3,
   quando la v1 sparisce.
5. **Tabella della 4 bis sui dispositivi veri** (iPhone, Xiaomi, web, Mac;
   build vecchie e nuove nella stessa famiglia) **prima di ogni allargamento**
   dell'interruttore, non solo prima di ogni fase.

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
- Dove tenerlo: «Stampalo o salvalo nel gestore di password del telefono. Non
  salvarlo nelle Password di KidBox: si aprono con la stessa chiave che questo
  codice serve a ritrovare.»
- Quando serve: «Di solito non ti servirà: se hai ancora un dispositivo o un
  familiare con KidBox, rientri con un QR.»

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
   **Aggiornata il 09/11/2026**: all'inizio il promemoria resta chiudibile
   anche dopo i 3 giorni; l'obbligo si accende dopo con
   `config/keyVault.enforce` (sezione 4 ter, punto 4). Vale anche per il
   web: chiudibile finché c'è la v1.
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
