# ARCHITECTURE — KidBox Cloud Functions

> Backend serverless di KidBox. Tutto in un singolo file `index.js` (~4700 righe, JavaScript, niente TypeScript). Condiviso da app **iOS** e **Android**. Per il contesto Firestore/Storage completo vedi anche `KidBox/ARCHITECTURE.md` §5.

---

## 1. Setup

- **Progetto Firebase**: `kidbox-42cd7` (`../.firebaserc`). Codebase `default`, config in `../firebase.json`.
- **Runtime**: Node `22` (`package.json` → `engines.node`). Tutte funzioni **v2** (`firebase-functions/v2/...`).
- **Regione**: `europe-west1` (hardcoded). **Bucket Storage**: `kidbox-42cd7-eu` (UE, hardcoded `index.js:7`).
- **Admin UID**: `efw85HN41nb1rmslevC3wkFpVUo1` (coerente con `isAdmin()` nelle `../firestore.rules`).
- **Secrets** (`defineSecret`): `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_PLACES_API_KEY`.
- **Dipendenze**: `firebase-admin` ^13, `firebase-functions` ^7, `@google/generative-ai` ^0.24, `node-fetch` ^3.

### Comandi
```bash
npm run serve     # emulatori locali (solo functions)
npm run deploy    # firebase deploy --only functions
npm run logs      # firebase functions:log
npm run lint      # eslint
```

---

## 2. Funzioni esportate

### 2.1 Callable HTTPS (`onCall`)

| Funzione | Scopo |
|---|---|
| `askAI` | Chat AI Anthropic (Haiku/Sonnet) con vision blocks. Auth + plan check + contatore `ai_usage/{family_*}/daily/{YYYY-MM-DD}`. Aggiorna anche `ai_costs`. Usa **prompt caching** (vedi §4). |
| `getAIUsage` | `{usageToday, dailyLimit}` per l'utente/famiglia. |
| `generateTravelPlan` | Itinerario di viaggio AI (Sonnet). |
| `suggestTravelDestinations` / `searchTravelDestinations` | Suggerimento/ricerca destinazioni. |
| `getTravelPlaceDetails` | Dettagli + foto via Google Places API. |
| `getStorageUsage` | `{usedBytes, quotaBytes, breakdown}` (auth + membership). |
| `initStorageUsage` / `initStorageUsageAdmin` | Ricalcola da zero `families/{fid}/stats/storage`. |
| `deleteAccount` | Wipe completo account: membership, famiglie senza altri membri, FCM token, `users/{uid}`, blob Storage `users/{uid}/`, contatori AI, `Auth.deleteUser`. |
| `deleteFamily` | Pulisce famiglia completa (tutte le sottocollezioni `FAMILY_SUBCOLLECTIONS`). Solo ultimo membro. |
| `setFamilyPlanOverride` | Imposta `planOverride` su `families/{fid}` (admin/billing). |
| `analyzeLogs` | Analisi AI dei log di un crash report. |
| `takeCase` / `resolveCase` / `deleteCase` | Gestione triage `cases/{caseId}` (admin console). |
| `registerAdminNotifications` / `checkAdminNotifStatus` / `unregisterAdminNotifications` | Push admin per crash critici. |

### 2.2 Trigger Firestore (`onDocumentCreated` / `onDocumentWritten`)

- **Documenti**: `notifyNewDocument`, `onDocumentSoftDeleted`, `onDocumentHardDeleted`.
- **Chat**: `notifyNewChatMessage` (payload cifrato `textEnc` + mention, `mutable-content` per la NSE iOS), `onChatMessageSoftDeleted`.
- **Foto**: `onPhotoCreated`, `onPhotoSoftDeleted`, `onPhotoHardDeleted` (→ `stats/storage.sections.photos`).
- **Salute**: `onMedicalVisitWritten` (→ `sections.salute` da `photoURLs.length * 200 KB`).
- **Posizione**: `notifyLocationSharingChanged` (cooldown 15 s), `onGeofenceEvent` (→ push membri).
- **Altre sezioni**: `notifyTodoAssigned`, `notifyNewGroceryItem`, `notifyNewNote`, `notifyNewCalendarEvent` (Europe/Rome), `notifyNewExpense` (€), `notifyNewWalletTicket`, `onWalletTicketStorageChanged`.
- **Crash triage**: `onNewCrashReport` (dedup su `cases/{caseId}`), `onCaseStatusChange`, `notifyCriticalCase` (push admin).

### 2.3 Schedulati (`onSchedule`)

| Funzione | Cadenza | Scopo |
|---|---|---|
| `expireTemporaryLocations` | ogni 5 min | `collectionGroup("locations")`, scade `mode == "temporary"` con `expiresAt <= now`. |
| `garbageCollectDeleted` | `0 3 */5 * *` (540 s, 512 MiB) | Hard-delete `isDeleted == true` in `documents`, `chatMessages`, `photos`, `walletTickets` + blob Storage. |
| `notifyUpcomingWalletTickets` | ogni 60 min | Promemoria wallet T-24h / T-2h (flag idempotenti). |
| `cleanupResolvedCases` | ogni 24 h | Pulizia `cases` risolti. |

---

## 3. Convenzioni & vincoli

- **`FAMILY_SUBCOLLECTIONS`** (`index.js` ~3679-3723): whitelist delle sottocollezioni cancellate da `deleteFamilyCompletely`. ⚠️ **Se aggiungi una nuova sottocollezione di famiglia con dati, DEVI estendere questo array** o lascerai orphan data dopo `deleteFamily`/`deleteAccount`.
- **`deleteStoragePrefix`** (~3746): cancellazione massiva blob, usata da `deleteAccount` / `deleteFamily`.
- **Contatori & storage stats** (`families/{fid}/counters/{uid}`, `families/{fid}/stats/storage`) sono **server-only**: il client non ha rule di write (vedi `firestore.rules`). Solo le functions li scrivono.
- **`ai_usage/{userId-or-family_*}/daily/{YYYY-MM-DD}`**: contatore quota AI giornaliera (key giornata in Europe/Rome). **`ai_costs/{monthKey}/families/{fid}`**: tracking costi AI mensili (letto dalla console admin).
- **Push**: i token FCM stanno in `users/{uid}/fcmTokens/{tokenId}`; le notifiche rispettano `users/{uid}.notificationPrefs`.

---

## 4. Prompt caching (`askAI`)

Implementato in `index.js` tramite due helper (`cacheableSystem`, `messagesWithCacheBreakpoint`) che aggiungono `cache_control: {type: "ephemeral"}` al payload Anthropic.

### Come funziona
- **System prompt**: wrapped in `cacheableSystem()` → breakpoint sulla fine del system prompt (Anthropic lo cacha come prefisso stabile).
- **Ultimo messaggio**: `messagesWithCacheBreakpoint()` aggiunge un secondo breakpoint alla fine dell'array messaggi → ogni turno il prefisso crescente viene cachato.
- **Eccezione** — `clinicalRecord` (analisi cartella clinica, chiamata one-shot): **caching disabilitato** per evitare il write-premium senza successivo re-read.
- **Minimo cacheabile**: 4096 token (Haiku 4.5). Se il payload è sotto soglia il caching si no-oppa silenziosamente senza costi aggiuntivi.

### Costi con caching
| Token type | Moltiplicatore vs input pieno |
|---|---|
| Cache read (`cache_read_input_tokens`) | 0.1× |
| Cache write (`cache_creation_input_tokens`) | 1.25× |
| Output | invariato |

### Calcolo costi aggiornato
```javascript
const costUsd =
  (inputTokens / 1_000_000) * inputUsdPer1M +
  (cacheReadTokens / 1_000_000) * inputUsdPer1M * 0.1 +
  (cacheWriteTokens / 1_000_000) * inputUsdPer1M * 1.25 +
  (outputTokens / 1_000_000) * outputUsdPer1M;
```

### Diagnostica nei log
I log di `askAI` espongono `cacheReadTokens`, `cacheWriteTokens` e `cacheHitRatio` (0.00–1.00) per monitorare l'efficacia del caching su Firebase Functions → Logs.

### Interazione con la compattazione iOS (`HealthAIChatViewModel`)
- **Compattazione client** (`compactIfNeeded`, soglia 60% del limite giornaliero): riduce il volume dei messaggi nell'array → meno token inviati.
- **Prompt caching** (server): riduce il prezzo dei token inviati a ripetizione → 0.1× su cache hit.
- I due sistemi sono **complementari** e non si interferiscono. La compattazione azzera lo storico messaggi (→ cache miss su quel turno), ma poi il nuovo storico compatto si ri-scalda nei turni successivi.

---

## 4-bis. Conteggio unità messaggio (`askAI`)

Ogni chiamata `askAI` scala N **unità** dal contatore giornaliero famiglia (`ai_usage/family_{fid}/daily/{day}.count`). Le unità si calcolano in `askAIMessageUnitsForPayload(totalChars)` = `ceil(totalChars / 50.000)`, minimo 1.

### Modelli per `purpose`
| `purpose` | Modello | Prezzo input/output per 1M |
|---|---|---|
| `clinicalRecord` | **Sonnet 4.5** | $3 / $15 |
| `support`, default (chat salute/visite/esami) | **Haiku 4.5** | $1 / $5 |

> La chat di supporto (`SupportChatViewModel`, `purpose: "support"`) usa **Haiku** — solo `clinicalRecord` passa a Sonnet.

### Costo extra cartella clinica
La cartella clinica gira su Sonnet (~3× Haiku per token) **e non beneficia del caching** (chiamata one-shot). Per riflettere il costo reale scala un **minimo fisso di unità**:
```javascript
const messageUnits = clinicalRecord
  ? Math.max(CLINICAL_RECORD_MIN_UNITS, payloadUnits)  // CLINICAL_RECORD_MIN_UNITS = 3
  : payloadUnits;
```
⚠️ **Parity client**: il valore `3` è duplicato in iOS `AIAskAIPayload.clinicalRecordMinUnits` (usato dal pre-check `ClinicalRecordAISynthesizer.estimatePayload`). Se cambi una costante, **allinea l'altra** o il pre-check client e il conteggio server divergono.

---

## 5. Quando modifichi qui

- Nuova sezione dati sincronizzata → valuta: trigger di notifica? conteggio storage? va in `FAMILY_SUBCOLLECTIONS`? rule Firestore?
- Nuova quota/limite AI → tocca `askAI` + `getAIUsage` + `ai_usage`/`ai_costs`.
- Le `storage.rules` **non sono nel repo** (gestite da console Firebase): se cambi i path Storage, aggiornale lì.
