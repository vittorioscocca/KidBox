# Piani Free / Pro / Max — fonte di verità

## Il problema che risolve

Quote, prezzi e feature dei piani erano scritti a mano in quattro posti
indipendenti: `KBSubscriptionManager.swift` (iOS), `KBPlan.kt` (Android),
`functions/index.js` (backend) e le due landing HTML. Combaciavano per
disciplina, non per costruzione. Un esempio già presente prima di questo lavoro:
la landing dichiarava "Assistente AI" non incluso sul piano Free, mentre le app
davano (e danno) 5 messaggi bonus una tantum.

## Chi comanda

**`config/plans` su Firestore è la fonte di verità.** Si modifica dalla console
admin (sezione *Piani* → *Listino piani*), **senza deploy e senza release delle
app**. Da lì:

- il **backend** applica le quote (`functions/plansConfig.js`, cache 60 s);
- **iOS e Android** leggono lo stesso documento per mostrarle;
- la **landing** lo legge anche lei, via REST, senza login (`assets/plans.js`).

`functions/plans.json`, impacchettato col deploy, è la **rete di sicurezza**: si
usa quando il documento manca, non è leggibile o non supera la validazione.

Restano fuori dal listino, per forza di cose:

| cosa | chi decide |
|---|---|
| **Quanto paga davvero l'utente** | App Store Connect / Play Console. `priceMonthly` e `priceLabel` sono solo l'etichetta mostrata quando lo store non risponde. |
| Che piano ha una famiglia | `families/{id}.plan` + `planOverride` |
| **Aggiungere un quarto piano** | prodotto sugli store + `KBPlan` (3 casi compilati) + release di entrambe le app |

## I guardrail

Un documento modificabile da browser governa spesa vera. La validazione sta in
`plansConfig.validatePlans` e vale **sia in scrittura sia in lettura**: un
listino fuori scala non viene applicato nemmeno se scritto a mano dalla console
Firebase con l'Admin SDK (che le rules non le attraversa).

- `aiLimit` ≤ 500, e ≤ **20 sul Free** — lì il bonus è una tantum, un errore è
  spesa API regalata a chiunque si registri;
- `storageBytes` ≤ 100 GB, e ≤ 2 GB sul Free;
- `aiPeriod`: `lifetime` **solo** sul Free, `daily` **solo** sui piani a pagamento
  (un abbonamento con quota a vita smetterebbe di funzionare);
- `priceMonthly` ≤ 99,99;
- `id`, `order`, `displayName`, `productId`, `currency` **non sono modificabili
  da console**: vengono sempre dal JSON deployato. Cambiare un `productId` da un
  browser romperebbe gli acquisti.

Ogni salvataggio finisce in `plansHistory` con autore, nota e listino completo:
è il sostituto del `git log` che qui non c'è. "Ripristina dal deploy" riporta il
documento al JSON dell'ultimo deploy.

## Segnaposto

Nei testi feature si usano `{storage}` e `{aiLimit}`, risolti da chi mostra la
card a partire da `storageBytes` / `aiLimit` dello stesso piano: il numero nella
frase non può divergere dalla quota applicata.

Le unità sono binarie (5 GB = 5 × 1024³), come le quote: per questo il client
non usa `ByteCountFormatter` / `Formatter.formatFileSize`, che contano in unità
da 1000 e mostrerebbero "5,37 GB".

## Come si cambia un piano

**Caso normale — quote, prezzi mostrati, testi:**

Console admin → Piani → Listino piani → modifica → **Salva e pubblica**. Basta
questo: il backend applica entro un minuto (cache), le app al prossimo avvio, il
sito al primo caricamento senza cache di sessione.

**Poi, con calma, allinea il repo** — un comando, nessun download e nessuna
credenziale (il documento è leggibile senza login):

```bash
node scripts/sync-plans-from-remote.js
```

Riscrive `functions/plans.json` dal documento vivo, rigenera le card della
landing e stampa cosa è cambiato. `--check` non scrive e esce con 1 se il repo è
indietro: è la forma da mettere in CI. Poi deploy di functions e landing. Non serve a far vedere i valori nuovi — quelli si
vedono già — ma a due cose che contano lo stesso: riportare la **rete di
sicurezza** sui valori nuovi, e aggiornare l'**HTML statico** della landing, che
è ciò che vedono Google e chi ha JS disabilitato.

**Cambio di prezzo vero:** prima App Store Connect e Play Console, poi il
listino. Il JSON non fa pagare niente a nessuno.

## Come fa la landing a leggere il listino

È HTML statico, quindi fa entrambe le cose:

1. le card sono **generate al deploy** dentro i marcatori `PLANS:START/END` —
   primo paint immediato, contenuto nel sorgente per i motori di ricerca;
2. `assets/plans.js` le **riallinea a runtime** leggendo `config/plans` con una
   `fetch` alla REST di Firestore (nessun SDK: ~4 KB in tutto), con cache di
   sessione di 6 ore. Se la rete non risponde o JS è spento, restano le card
   generate al deploy.

Lo stesso file è il renderer usato da `scripts/render-landing-plans.js`: HTML
generato e HTML vivo escono dalla **stessa funzione**, non da due copie che
divergono.

Perché questo funzioni, `config/plans` è **leggibile senza login** (rule
dedicata in `firestore.rules`, testata in `firestore-tests/rules.test.js`).
Contiene solo prezzi, quote e testi già stampati sul sito: **non aggiungere
altro a quel documento**.

## Lato client

- iOS: `KBPlanCatalog.swift` — `KBPlan` non contiene più numeri, li chiede al
  catalogo. Ultimo listino valido in `UserDefaults` dell'app group, così a
  freddo non si riparte dai valori compilati. `KBPlanCatalog` scrive anche
  `proStorageLabel` nell'app group, perché `KBStorageGateLite` (Share Extension,
  senza Firebase) possa dire "passa a Pro per 5 GB" senza avere il numero
  scritto dentro.
- Android: `KBPlanCatalog.kt` — stessa cosa con `SharedPreferences`,
  inizializzato da `KidBoxApplication.onCreate()`.
- Su entrambi i valori compilati restano come rete di sicurezza (stesso pattern
  di `config/nudges` / `NudgeCatalog`): volutamente scarni sulle feature, perché
  l'elenco di listino vive nel catalogo, non nell'app.
