---
name: piani
description: Riallineare il repo al listino Free/Pro/Max dopo una modifica fatta dalla console admin — sync di functions/plans.json e delle card della landing, validazione, deploy. Usare quando l'utente dice «ecco il plans.json», «l'ho scaricato dalla console», «riallinea i piani», o cambia quote, prezzi o feature dei piani.
---

## Chi comanda

**`config/plans` su Firestore è la fonte di verità**, e si modifica dalla console
admin (*Piani → Listino piani*) **senza deploy e senza release delle app**: il
backend applica le quote (`functions/plansConfig.js`, cache 60 s), iOS e Android
le leggono (`KBPlanCatalog`), la landing le legge a runtime via REST
(`assets/plans.js`). `functions/plans.json` è la **rete di sicurezza** deployata,
usata solo se il documento manca o non passa la validazione.

Quindi: quando l'utente cambia il listino, **il cambio è già attivo ovunque**.
Il giro nel repo serve a riportare il fallback e l'HTML statico (quello che vede
Google) sui valori nuovi. Il procedimento lo eseguo io, senza chiedere cosa
farne del file.

## La procedura

1. `node scripts/sync-plans-from-remote.js` — dalla root, **senza credenziali e
   senza il file**: legge `config/plans` (pubblico), lo valida col validatore del
   backend, riscrive `functions/plans.json`, rigenera le card della landing e
   stampa cosa cambia. `--check` dice solo se il repo è indietro.
   Se l'utente ha passato un `plans.json` (di solito `~/Downloads/plans.json`),
   **usalo solo per confronto**: la verità è il documento remoto, il pulsante ⬇️
   della console è un ripiego.
2. Mostra le differenze stampate e `git diff --stat functions/plans.json KidboxLanding/public`.
3. Deploy: `npx firebase-tools deploy --only functions --project kidbox-42cd7`
   dalla root, poi `npx firebase-tools deploy --only hosting:landing --project kidbox-42cd7`
   da `KidboxLanding/`.
4. Commit per path di functions e landing (mai `git add -A`), messaggio in
   italiano; il push lo fa l'utente.

**Lo script esce con 1 senza toccare il repo se il listino remoto non passa la
validazione: in quel caso NON deployare**, riporta l'errore.

## I guardrail (valgono in scrittura e in lettura)

`plansConfig.LIMITS`, applicati anche a un documento scritto a mano con l'Admin
SDK, che le rules non le attraversa:

- `aiLimit` ≤ 500, e ≤ **20 sul Free** — lì il bonus è una tantum, un errore è
  spesa API regalata a chiunque si registri;
- `storageBytes` ≤ 100 GB, ≤ 2 GB sul Free;
- `aiPeriod`: `lifetime` **solo** sul Free, `daily` **solo** sui piani a
  pagamento (un abbonamento con quota a vita smetterebbe di funzionare);
- `priceMonthly` ≤ 99,99;
- `id`, `order`, `displayName`, `productId`, `currency` **non** sono modificabili
  da console: vengono dal JSON deployato. Un `productId` cambiato da un browser
  romperebbe gli acquisti.

**Alzare un tetto è una modifica di codice, non di listino.** Se serve, si
cambia `plansConfig.LIMITS` con un deploy, dicendolo.

## Quello che resta fuori dal listino

| Cosa | Chi decide |
|---|---|
| Quanto paga davvero l'utente | App Store Connect / Play Console. `priceMonthly` e `priceLabel` sono solo l'etichetta di ripiego quando lo store non risponde |
| Che piano ha una famiglia | `families/{id}.plan` + `planOverride` (+ `planExpiresAt`) |
| Aggiungere un quarto piano | prodotti sugli store + `KBPlan` (3 casi compilati) + release di **entrambe** le app |

`plansHistory` conserva autore, nota e listino completo a ogni salvataggio: è il
`git log` che qui non c'è. «Ripristina dal deploy» riporta il documento al JSON.

## Il testo dei piani

Nei testi feature si usano i segnaposto `{storage}` e `{aiLimit}`, risolti da chi
mostra la card dagli stessi `storageBytes`/`aiLimit` del piano: **il numero nella
frase non può divergere dalla quota applicata**. Unità binarie (5 GB = 5 × 1024³).

Se cambia **cosa** è incluso in un piano (non solo quanto), il listino da solo non
basta: servono i tre presidi server/service/view → `/gating-pro`.
