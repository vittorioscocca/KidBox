---
name: abbonamenti-store
description: Abbonamenti Pro e Max su App Store Connect e Google Play — product id, gruppo e livelli, prezzi con l'IVA, traduzioni, screenshot e invio in revisione, verifica via API. Usare quando si crea o si modifica un abbonamento (mensile o annuale), si cambia un prezzo, si traducono nomi e vantaggi, si manda un abbonamento in revisione, o l'utente chiede «controlla i piani sugli store» o «perché non vedo l'annuale».
---

## Cosa esiste (al 29/09/2026)

**Testi (05/10/2026):** descrizioni e vantaggi con il tetto mensile. Play:
aggiornati e salvati su tutti e quattro, in 5 lingue (la descrizione del Pro
annuale era il segnaposto tecnico «Versione annuale di
it.vittorioscocca.kidbox.pro.monthly…» in tutte le lingue, ora vera; mancavano
le descrizioni italiane dei mensili). Apple: solo i mensili citano i numeri, in
bozza da inviare; gli annuali non hanno numeri e restano come sono.

| Product id | Durata | Italia (IVA inclusa) | Livello Apple |
|---|---|---|---|
| `it.vittorioscocca.kidbox.max.monthly` | 1 mese | 9,99 € | 1 |
| `it.vittorioscocca.kidbox.max.yearly` | 1 anno | 79,99 € | 1 |
| `it.vittorioscocca.kidbox.pro.monthly` | 1 mese | 4,99 € | 2 |
| `it.vittorioscocca.kidbox.pro.yearly` | 1 anno | 39,99 € | 2 |

- **App Store:** gruppo `kidbox_premium` (id 21994693), 175 paesi. Ids Apple: pro.yearly 6817055817, max.yearly 6817056377, pro.monthly 6761060381, max.monthly 6761060916. Gli abbonamenti valgono per iPhone e Mac: la scheda è una sola.
- **Play:** un prodotto per id, ciascuno con un solo piano base (`pro-monthly`, `max-monthly`, `pro-yearly`, `max-yearly`), rinnovo automatico, 174 paesi, nessuna offerta.
- **Server:** `functions/purchases.js` → `PRODUCT_TO_PLAN`. Un product id che non sta lì non concede niente, anche se l'acquisto va a buon fine. Aggiungerlo lì PRIMA di crearlo sugli store.
- **Client:** l'id annuale si ricava dal mensile (`.monthly` → `.yearly`) in `KBPlan.productIdYearly` (iOS e Android). Un annuale non creato sullo store non è un errore: l'app nasconde la scelta Mensile/Annuale.
- **Listino:** `priceYearly` in `config/plans` serve solo alla landing e alla chat. Nelle app il prezzo lo mostra sempre lo store.

## Le trappole già pagate

1. **Livelli Apple: 1 è il PIÙ ALTO.** Max deve stare al livello 1 e Pro al 2; mensile e annuale dello stesso piano allo stesso livello. Erano invertiti fino al 29/09, e un Pro→Max contava come downgrade. Via API, spostare un prodotto al livello 1 **rinumera tutto il gruppo** (erano finiti tutti a 1), e un `PATCH` può rispondere 500 pur essendo applicato: rileggere sempre i livelli dopo ogni modifica.
2. **Play: nella console si inserisce il prezzo IVA ESCLUSA.** Play aggiunge l'aliquota di ogni paese e arrotonda a ,99. Per 39,99 € al cliente italiano si scrive 32,78; per 79,99 si scrive 65,57; per 4,99 → 4,09; per 9,99 → 8,19. Invece `regionalConfigs.price` dell'API restituisce il prezzo IVA INCLUSA. Apple (`customerPrice`) è sempre IVA inclusa.
3. **Periodo di fatturazione Play:** il form del piano base parte da «Ogni mese». Per un annuale va cambiato in «Ogni anno», altrimenti nasce un secondo mensile al prezzo dell'annuale. Tipo sempre «Rinnovo automatico»: prepagato e rate non li riconosce né l'app né `verifyGooglePurchase`.
4. **Play, inglese:** il form propone en-GB. Serve anche **en-US** con gli stessi testi, altrimenti chi ha il telefono in inglese americano rischia di vedere l'italiano. Lo si aggiunge via API (sotto).
5. **Nuovi abbonamenti Apple NON si scelgono dalla pagina della versione** (solo il primo abbonamento dell'app si allegava lì). Si preme «Aggiungi alla verifica» sulle pagine di ciascun abbonamento e del gruppo, e sulla versione. Tutto finisce in una bozza in «Revisione app», e parte solo con «Invia per la revisione». L'ordine dei «Aggiungi» non conta; conta non inviare la versione prima che gli abbonamenti siano nella bozza.
6. **Un invio senza build porta come etichetta la versione in vendita** (es. «iOS 2.3.5» per i testi dei mensili mentre si rilascia la 2.3.6). È normale.
7. **Screenshot di revisione, circolo vizioso:** senza screenshot l'abbonamento resta in «Metadati mancanti» e non si carica nemmeno in sandbox, quindi l'annuale non compare e non si può fotografare. Si sblocca caricando un segnaposto (lo screenshot di un altro abbonamento), poi si sostituisce con quello vero, preso dalla build da TestFlight o da Xcode sul telefono, PRIMA di inviare.
8. **Localizzazioni Apple approvate non si modificano.** Ogni testo ha una versione APPROVED e una bozza PREPARE_FOR_SUBMISSION: si patcha la bozza, che va in vendita solo con la revisione successiva. Il campo `state` delle localizzazioni resta PREPARE_FOR_SUBMISSION anche dopo l'invio: non è la prova che non sono state inviate.
   **Se la bozza non c'è** (solo APPROVED in elenco), il `PATCH` sull'approvata risponde **409 «Cannot edit SubscriptionLocalization when it is in ACTIVE state»**. Si crea con un `POST /v1/subscriptionLocalizations` per **una** lingua, con lo stesso `name` dell'approvata: Apple risponde 201 e **clona in bozza tutte le altre lingue** col testo vecchio (un secondo `POST` per un'altra lingua dà 409 «locale already exists»). Poi si patchano quelle bozze. Fatto così il 05/10/2026 per i due mensili (tetto mensile nella descrizione); vanno in vendita con «Aggiungi alla verifica» sulle pagine dei due abbonamenti e «Invia per la revisione».
9. **Salvare la scheda Play via API la manda in revisione insieme alla release in corso** (la «Panoramica della pubblicazione» mostra release e scheda nello stesso gruppo). Avvisare l'utente PRIMA di salvare se c'è una release in revisione.
10. **Account di revisione Apple:** deve essere FREE (famiglia senza `plan`, senza `planOverride`, senza `users/{uid}.plan`) e proprietario della famiglia, altrimenti il revisore non vede «Upgrade» e respinge l'abbonamento. Verificarlo con REST prima dell'invio. La nota ai revisori (in inglese) deve dire dove si trova il paywall: Profilo → Abbonamento → Upgrade, oppure Impostazioni → Utilizzo spazio.
11. **Da NON attivare:** «In famiglia» (Family Sharing, irreversibile: il piano copre già la famiglia dentro l'app), «Fatturazione mensile con impegno di 12 mesi», e offerte di prova gratuita dello store (c'è già la prova Pro nostra, vedi `/prova-pro`).

## API

**App Store Connect** — chiave nel Portachiavi (`asc-api-key`, account `kidbox`), Key ID `5XN458397C`, Issuer `2deae1f9-70dc-49b6-b792-083e481811d3`, JWT ES256 come in `scripts/asc-whatsnew.js`. Endpoint utili:
- `GET /v1/apps/6761055375/subscriptionGroups?include=subscriptions`
- `POST /v1/subscriptions`, poi `subscriptionLocalizations` (descrizione ≤ 45 caratteri, nome ≤ 30), `subscriptionAvailabilities` (copiare i territori del mensile), `subscriptionPrices`: il punto prezzo ITA più tutti gli `equalizations` del punto, uno per paese.
- `subscriptionAppStoreReviewScreenshots`: reservation, poi PUT delle `uploadOperations`, poi PATCH `uploaded: true` con l'md5.
- `GET /v1/reviewSubmissions?filter[app]=6761055375` per vedere gli invii. Gli elementi di un invio non si risolvono bene via API: per sapere cosa c'è dentro, farlo guardare all'utente nella pagina.

**Play** — service account `play-purchase-validator` impersonato con scope `androidpublisher`. PUÒ leggere e modificare gli abbonamenti e la scheda; NON può creare release.
- Abbonamenti: `GET/PATCH …/subscriptions/{id}?updateMask=listings&regionsVersion.version=2022/02`. Per en-US: copia della scheda en-GB con `languageCode` cambiato.
- Offerte: `GET …/subscriptions/{id}/basePlans/{basePlanId}/offers` (con `-` al posto dell'id non funziona).
- Scheda: `POST …/edits`, `PATCH …/edits/{e}/listings/{lang}`, poi `POST …/edits/{e}:commit` **con `Content-Length: 0` esplicito**: senza, la risposta arriva vuota, l'edit viene cancellato e la modifica si perde senza errore. Rileggere sempre con un edit nuovo.
- Letture senza modifiche: aprire un edit e poi `DELETE` dell'edit.

## Controllo completo («i piani sono a posto?»)

Rileggere dai due store, non dalla memoria:
1. **Apple:** stato di ogni abbonamento, livello, prezzo ITA, numero di paesi con prezzo, screenshot presente (e se è ancora il segnaposto: md5 uguale a quello del mensile), stato delle localizzazioni del gruppo.
2. **Play:** stato del piano base, periodo (`P1M`/`P1Y`), numero di paesi, prezzo IT, lingue della scheda (le 4 più en-US), numero di vantaggi per lingua, offerte assenti.
3. **Server:** i quattro id in `PRODUCT_TO_PLAN`; `config/plans` con `priceYearly` e `productIdYearly`.
4. Dire cosa NON si è potuto verificare (es. il contenuto dei singoli invii Apple).
