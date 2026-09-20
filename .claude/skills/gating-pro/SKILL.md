---
name: gating-pro
description: Checklist per una feature inclusa nei soli piani Pro/Max di KidBox (o per verificarne una esistente) — i tre presidi server/service/view su iOS, Android e web, il contatore Free una tantum, dove vive il testo dei piani. Usare quando nasce una feature a pagamento, quando si cambia il piano richiesto da una feature, o quando l'utente chiede «i Free ci arrivano?».
---

## La trappola da cui nasce questa skill

`isAIAccessible` (iOS, `KBSubscriptionManager`) e `aiAccessBlocked` (Android,
`CurrentPlanStore`) **non dicono il piano**: sono false solo quando un Free ha
esaurito i 5 messaggi bonus una tantum. Un Free col bonus intatto risulta
«accessibile». Il Pianificatore Viaggi è rimasto aperto ai Free fino al
31/08/2026 per questo, con un messaggio d'errore che descriveva un controllo
inesistente. Non si vede in test: un account di prova Free col bonus intatto
funziona «correttamente». Mai usare quei flag come gate di piano.

## I tre presidi (tutti, non uno)

1. **Server, sulla callable** — l'unico che regge contro un client aggirato
   o già pubblicato. Discriminante: `quota.period === "lifetime"`, vero solo
   per i Free (`resolveAIQuota` in `functions/index.js`: pro/max → `daily`,
   free → `lifetime`). Modello: il blocco `mealPlan` / `fitnessPlan` in
   `askAI` (`HttpsError("permission-denied", "… incluso nei piani Pro e Max …")`)
   e `generateTravelPlan`. Va **prima** di `checkAndIncrementAIUsage`, così
   il tentativo non consuma il bonus.
2. **Service, prima della callable** — il collo di bottiglia attraversato da
   ogni percorso, rigenerazioni comprese; è il presidio più facile da
   dimenticare perché sta sotto le view.
   - iOS: `KidBox/KidBox/App/AI Core/AIService.swift`, set `paidOnlyPurposes`
     (+ `loadPlan()` prima del check, poi `currentPlan != .free`). Aggiungere
     il nuovo `purpose` al set basta per i flussi che passano da `sendMessages`;
     una callable dedicata (come i Viaggi) vuole il suo guard.
   - Android: `KidBoxAndroid/app/src/main/java/it/vittorioscocca/kidbox/data/remote/ai/AIService.kt`,
     `CurrentPlanStore.plan.value == KBPlan.FREE` → `error(...)`.
   - Web: `KidboxWebApp/src/services/<feature>.js`, `isPaidPlan(plan)` da
     `services/profile.js` (che ricalca `resolveFamilyPlanForQuotas`:
     `planOverride` e `planExpiresAt` compresi — mai leggere il solo campo `plan`).
3. **View, solo per la UX di upsell** — `subscriptionManager.currentPlan != .free`
   (iOS), `CurrentPlanStore.plan != KBPlan.FREE` (Android), `isPaidPlan`
   (web): banner «Passa a Pro», bottone disabilitato, paywall. Non è
   sicurezza.

## Regole collaterali

- **Il piano è della famiglia**, non dell'utente: si legge dal documento
  famiglia (con `planOverride` della console e scadenza `planExpiresAt`).
- **Il bonus Free è una tantum**: 5 messaggi che non si resettano mai,
  doppio contatore `ai_usage/family_{id}/lifetime/free` e
  `ai_usage/user_{uid}/lifetime/free`, blocca sul più alto. Una feature
  Pro-only **non** deve consumarlo né sbloccarsi finché resta.
- **Il modello dipende dal `purpose`, mai dal piano** (Haiku di default,
  Sonnet per cartella clinica e fitness).
- Se la feature è nuova e ha un `purpose` nuovo: aggiungerlo anche al
  metering/`ai_costs` e al report console se ha una voce per feature.
- Test da fare a mano, con un account Free **col bonus intatto**: la
  callable deve rispondere `permission-denied` e il contatore non deve
  scendere. Poi con un override Pro dalla console admin.

## Dove vive il testo

- Quote, prezzi e liste feature dei piani: Firestore `config/plans`, si
  cambiano dalla **console admin** (Piani → Listino piani), non da codice.
  `functions/plans.json` è il fallback: dopo un cambio da console,
  `node scripts/sync-plans-from-remote.js` e deploy di functions e landing
  (`internal/plans-source-of-truth.md`).
- Una feature Pro-only nuova va scritta nel listino (riga «✓ … » su Pro/Max,
  assente o «—» su Free) in IT/EN/FR/ES, altrimenti la landing e le
  schermate Piani continuano a raccontare il listino vecchio.
- Il messaggio d'errore client deve descrivere il controllo che **esiste**:
  «inclusa nei piani Pro e Max» solo se il gate server c'è davvero.
- Nessun limite di membri per famiglia sul Free: non inventarne.

## Chiusura

Prima di dire «fatto», elencare i tre presidi con file:riga per ciascuna
piattaforma toccata (iOS, Android, web) e il punto del server. Un presidio
mancante è un buco, anche se gli altri due ci sono.
