# ARCHITECTURE — KidBox iOS

> Documento di riferimento per chi entra nel progetto. Tutti i path sono relativi a `/Users/vscocca/KidBox/KidBox/` salvo diversa indicazione. I riferimenti `file:riga` sono mappati 1:1 sulla codebase corrente.

---

## 1. Overview del progetto

KidBox è un'app iOS **per la gestione condivisa della vita di famiglia**: chat E2E, documenti crittografati, note ricche, calendario, foto/video di famiglia, salute pediatrica (visite, esami, terapie, vaccini), wallet di biglietti, password manager, viaggi, spese, posizioni in tempo reale, animali domestici, casa e veicoli. Target utenti: **genitori e nuclei familiari** che vogliono un'unica app privata e crittografata per coordinare la vita quotidiana.

- **Bundle identifier**: `it.vittorioscocca.KidBox` — versione marketing **1.1.6**, build **65**, deployment target **iOS 26.2**, Swift 5.0, target device family iPhone + iPad. Gira anche come app **Mac Catalyst** con una shell desktop dedicata (sidebar + split view, vedi §6.7).
- **CFBundleDisplayName**: `KidBox` (impostato in `INFOPLIST_KEY_CFBundleDisplayName` nel `project.pbxproj`).
- **URL scheme** principali: `kidbox://` (routing interno `share`, `control/open-family-photos-camera`), `com.googleusercontent.apps.52613538008-...` (Google Sign-In), `fb25962552233393986` (Facebook SDK).
- **Tipo esportato**: `it.vittorioscocca.kidbox.kbpw` (estensioni `.kbpw` / `.txt` per export password).
- **App Group condiviso**: `group.it.vittorioscocca.kidbox` (presente in tutte le entitlements main app + estensioni).
- **Keychain access groups**: `$(AppIdentifierPrefix)it.vittorioscocca.KidBox` (default condiviso) e `$(AppIdentifierPrefix)it.vittorioscocca.kidbox.shared` (mirror dedicato per AutoFill, dichiarato come `KidBoxSharedKeychainAccessGroup`).
- **Permessi dichiarati in `Info.plist`** (descrizione in italiano):
  - `NSContactsUsageDescription`, `NSHealthShareUsageDescription` (passi/peso/frequenza/pressione/ossigeno/ECG/allenamenti), `NSHealthUpdateUsageDescription` (KidBox **non** scrive in Salute).
  - `UIBackgroundModes`: `remote-notification`, `location`. `com.apple.security.device.audio-input = true`.
- **Firebase project**: `kidbox-42cd7` (bucket `kidbox-42cd7-eu`, regione UE), file `KidBox/Support/Firebase/GoogleService-Info.plist`.
- **StoreKit**: `KidBox/KidBox.storekit` con due abbonamenti recurring nel gruppo `kidbox_premium`:
  - `it.vittorioscocca.kidbox.pro.monthly` — 5 GB / 20 msg AI/giorno (€3,99).
  - `it.vittorioscocca.kidbox.max.monthly` — 20 GB / 100 msg AI/giorno (€8,99).
- **Localizzazioni**: `it`, `en`, `en-GB`, `es`, `zh-Hans` (`*.lproj/Localizable.strings`). I file `Localizable.strings` sono **minimali** (solo 6 chiavi `passwords.group.*`); la gran parte dei testi UI è hardcoded in italiano nei sorgenti.

### Target Xcode

Il progetto `KidBox.xcodeproj` contiene 6 target di codice + 2 di test:

| Target | Bundle ID | Tipo |
|---|---|---|
| `KidBox` | `it.vittorioscocca.KidBox` | App principale |
| `KidBoxAutoFill` | `it.vittorioscocca.KidBox.KidBoxAutoFill` | Credential Provider (AutoFill password + OTP) |
| `KidBoxControlsExtension` | `it.vittorioscocca.KidBox.KidBoxControlsExtension` | Control Widget iOS 18+ (camera Foto famiglia) |
| `KidBoxNotificationService` | `it.vittorioscocca.KidBox.KidBoxNotificationService` | Notification Service Extension (decrypt push chat) |
| `KidBoxShareExtension` | `it.vittorioscocca.KidBox.KidBoxShareExtension` | Share Sheet (chat/documenti/note/wallet/foto) |
| `KidBoxWidget` | placeholder | Cartella attualmente solo con `Assets.xcassets` |
| `KidBoxTests` | `it.vittorioscocca.KidBoxTests` | Unit test (`AuthFacadeTests`, `PasswordCypherTests`, `SyncCenterNotesTests`, ecc.) |
| `KidBoxUITests` | — | UI test |

Tutte le `.appex` sono firmate con team `5WA8KG2G2W`.

---

## 2. Struttura delle cartelle

```
KidBox/                                ← target principale
├── App/
│   ├── AI Core/                       ← AIService, AISettings, chat AI per area
│   │   ├── AIChatHealth/              ← chat AI salute
│   │   ├── AIChatExams/AIChatExams/
│   │   └── AIChatVisits/{AISingleVisit,AITotalVisits}/
│   ├── Core/                          ← @main, AppCoordinator, AppDelegate, KBEventBus
│   ├── Intents/                       ← OpenKidBoxFamilyPhotosCameraIntent (Control Widget)
│   ├── Notification/                  ← NotificationManager, BadgeManager, CountersService
│   ├── Root/                          ← Route, RootGateView, RootHostView
│   └── Session/                       ← Session, SessionManager (legacy)
├── Data/
│   ├── AIMessage/                     ← KBAIConversation/KBAIMessage SwiftData
│   ├── Auth/                          ← AppleAuth/GoogleAuth/FacebookAuth + Firebase* + AuthFacade
│   ├── KeyMigration/                  ← (placeholder vuoto)
│   ├── MasterKeyMigration.swift
│   ├── Models/                        ← 45 @Model SwiftData per dominio
│   │   ├── Calendar/  Document/  Expenses/  Family/  Health/  Home/  Location/
│   │   ├── Pet/  PhotoVideo/  Routine/  ToDo/  Travel/  Vehicle/  Wallet/
│   │   └── (root: KBChatMessage, KBNote, KBEvent, KBGroceryItem, ChatMention, PasswordEntry, …)
│   ├── Persistence/                   ← ModelContainerProvider, KidBoxMigrations, DocumentLocalCache
│   ├── Remote/                        ← layer Firestore/Storage
│   │   ├── AI/  Calendar/  ChatStore/  DocumentStore/  Expenses/  FamilyRemote/
│   │   ├── Health/  LocationRemote/  Note/  Passwords/  PhotoVideoRemote/
│   │   ├── RemoteStores/  Support/  Sync/  TodoRemote/  Travel/  Wallet/
│   │   └── (root: AccountDeletionService, AvatarRemoteStore, FirestorePingService, LinkPreviewStore, UserProfileRemoteSync)
│   ├── Repositories/                  ← Protocols + SwiftData/, FamilyJoinService, ChildSyncService
│   └── Support/                       ← Date+DayKey, DocumentTextExtractor (OCR)
├── Domain/
│   ├── Auth/                          ← AuthService (protocol), AuthProvider (enum)
│   ├── Models/KBUserProfile.swift     ← unico modello in Domain/
│   ├── DomainModels.md                ← file vuoto
│   └── FamilyBootstrapService.swift
├── Features/                          ← 27 aree funzionali, una cartella ciascuna
│   ├── AIAgent/  Auth/  Calendar/  Chat/  Documents/  DynamicIsland/  Expenses/
│   ├── Family/  FamilyLocation/  Grocery/  Health/  Home/  HomeItems/  Note/
│   ├── Passwords/  Pets/  PhotoVideo/  Settings/  ShoppingList/  Subscription/
│   ├── Todo/  Travel/  Vehicles/  Wallet/  Wiki/
├── Support/                           ← KBLog, KBFileLogger, KBCrashHandler, FamilyKeychainStore,
│                                        FamilyKeyEscrowService, InviteCrypto, SharedFamilyKey,
│                                        TOTPCodeGenerator, KBVisibilityScope, LocalDataWiper,
│                                        AutoFillSnapshot, Firebase/, Health/, UIKit/
├── UI/VisibilityPickerSheet.swift
├── UIComponent/                       ← KBTheme, HomeHeroCard, KBSettingsCard, ecc.
├── Info.plist  KidBox.entitlements  KidBox.storekit
├── Facebook.xcconfig + Facebook.local.xcconfig{,.example}
└── *.lproj/Localizable.strings
```

I 5 target di estensione vivono come fratelli in `/Users/vscocca/KidBox/KidBox/` (stessa cartella di `KidBox/`): `KidBoxAutoFill/`, `KidBoxControlsExtension/`, `KidBoxNotificationService/`, `KidBoxShareExtension/`, `KidBoxWidget/`.

### Cartelle critiche

- **`Data/Remote/Sync/`** — il cuore del sync: `SyncCenter.swift` (~1460 righe) + 24 extension `SyncCenter+<Dominio>.swift` (AIChat, Calendar, Children, DocumentCategories, DocumentsEvents, Expenses, FamilyBundle, Grocery, HomeItems, HousePayments, MedicalExams, Notes, Passwords, PediatricProfile, Pets, Treatments, Trips, Vaccines, Vehicles, Visits, Wallet, photos) + `KBSyncOp`, `KBSyncState`, `SyncEntityType`. **Nota**: `SyncCenter+AIChat` è l'unico che NON sincronizza sotto `families/...` ma sotto `users/{uid}/aiConversations` (chat AI private per-utente, vedi §AI).
- **`Data/Models/`** — 45 entità `@Model final class`, prefisso `KB` sistematico (eccezioni: `PasswordEntry`/`PasswordGroup` per coerenza con `AuthenticationServices`, `SharedUserLocation` come DTO Codable).
- **`Features/Health/`** — la più ricca: `Home/`, `AppleHealth/`, `ClinicalRecord/` (28 file, generazione cartella clinica AI + PDF), `MedicalRecord/`, `Visits/`, `Exames/`, `Treatments/`, `Vaccines/`, `Shared/`, `AI/`, `KBHealthCalendarService.swift`.

---

## 3. Architettura generale

Il pattern è una **MVVM + Coordinator + Services/RemoteStores** con **SwiftData come source of truth locale** e **Firebase (Firestore + Storage + Auth + FCM)** come backend di sincronizzazione. **Non è MVVM puro** (molte View leggono direttamente SwiftData via `@Query` senza ViewModel), **non è Clean Architecture canonica** (il `Domain/` è quasi vuoto, le entità di dominio sono i modelli SwiftData stessi), **non è strict MVVM-C** (esiste un solo coordinator globale).

### Layer

1. **Presentation** (`Features/` + `UIComponent/` + `UI/`) — SwiftUI. Le View "grosse" hanno un `*ViewModel` `@MainActor ObservableObject`; le View più semplici usano `@State`/`@Query` direttamente.
2. **Coordinator** (`App/Core/AppCoordinator.swift`, ~1220 righe) — singolo coordinator globale che gestisce navigation, auth, famiglia attiva, deep link, share extension drop, appearance.
3. **Domain** (`Domain/`) — **molto sottile**: solo `AuthService` (protocol) + `KBUserProfile` (modello SwiftData) + `FamilyBootstrapService`. Nessuno use case formale.
4. **Data — Remote** (`Data/Remote/`) — `*RemoteStore` per ogni dominio, wrapper di Firestore/Storage. Usano `addSnapshotListener` in lettura e `setData(merge: true) + serverTimestamp()` in scrittura.
5. **Data — Sync** (`Data/Remote/Sync/`) — `SyncCenter.shared` (singleton `@MainActor`) orchestra ~17 listener realtime + outbox `KBSyncOp` con backoff esponenziale.
6. **Data — Persistence** (`Data/Persistence/`) — `ModelContainerProvider.makeContainer()` + recovery quarantena store + `KidBoxMigrationActor` per backfill.
7. **Data — Models** (`Data/Models/`) — 45 `@Model final class` SwiftData con `@Attribute(.unique) id: String`.
8. **Repository** (`Data/Repositories/`) — pattern repository **minimale**: solo 3 protocolli (`RoutineRepository`, `TodoRepository`, `EventRepository`) e 3 impl SwiftData. Tutto il resto va dritto su `ModelContext` + `SyncCenter`.
9. **Support** (`Support/`) — crypto (`FamilyKeychainStore`, `FamilyKeyEscrowService`, `InviteCrypto`, `SharedFamilyKey`), logging (`KBLog`, `KBFileLogger`), crash (`KBCrashHandler`, `CrashAnalyzer`), `LocalDataWiper`, `KBVisibilityScope`, `AutoFillSnapshot`.

### Flusso lettura tipico (es. documenti)

1. Firestore `addSnapshotListener` su `families/{familyId}/documents` → `DocumentRemoteStore` produce `[DocumentRemoteChange]`.
2. `SyncCenter.startDocumentsRealtime(...)` applica i cambi a SwiftData (LWW su `updatedAt`, soft-delete remoto → hard-delete locale).
3. La View osserva `@Query` SwiftData (es. `RootHostView` ha `@Query(sort: \KBFamily.updatedAt, order: .reverse) var families: [KBFamily]`).
4. Il ViewModel legge/scrive su SwiftData con `modelContext` iniettato via `bind(modelContext:)`.

### Flusso scrittura tipico (offline-first, outbox)

1. View/VM scrive direttamente su SwiftData (`modelContext.insert(...)` + `try modelContext.save()`).
2. Chiama `SyncCenter.shared.enqueue*Upsert(...)` che crea/aggiorna un `KBSyncOp` deduplicato per `(familyId, entityType, entityId)`.
3. `SyncCenter.flushGlobal` o `startAutoFlush` (loop ogni 30 s) processa la outbox tramite `process(op:modelContext:remote:)` (uno `switch` su `entityTypeRaw` che chiama il `*RemoteStore.upsert(...)` corrispondente).
4. Su successo: `KBSyncOp` cancellato, `KBFamily.lastSyncAt` bumpato. Su errore: `attempts++`, `lastError` salvato, backoff `min(2^(attempts-1), 300) s`.

### Testability

Bassa: l'unico vero protocollo di astrazione attivo è `AuthService`. La maggior parte dei service è singleton (`SyncCenter.shared`, `NotificationManager.shared`, `BadgeManager.shared`, `KBSubscriptionManager.shared`, `KBEventBus.shared`, `AISettings.shared`, `AIService.shared`) e le View accedono direttamente a SwiftData via `@Query`, quindi non c'è DI generalizzata.

---

## 4. Gestione dello stato

### Property wrapper SwiftUI usati

- **`@State`** ovunque per UI ephemerale (toggle sheet, testo `TextField`, picker selection).
- **`@StateObject`** per istanziare il VM "proprietario" della view (es. `@StateObject private var viewModel: ChatViewModel` in `Features/Chat/ChatView.swift:428`).
- **`@ObservedObject`** raro, usato solo per singleton già condivisi (es. `BadgeManager.shared`, `KBSubscriptionManager.shared`).
- **`@EnvironmentObject`** **solo** per `AppCoordinator` e `KBSubscriptionManager`, propagati dal root `KidBoxApp.body` → `RootHostView` in giù.
- **`@Environment(\.modelContext)`** in **99 file View** per leggere il `ModelContext` SwiftData iniettato globalmente da `.modelContainer(modelContainer)` (`App/Core/KidBoxApp.swift:337`).
- **`@Query`** SwiftData usato dappertutto come "stream reattivo locale" — sostituisce di fatto i `@Published` di un VM "viewer".
- **`@AppStorage`** per preferenze persistite (es. `documentsLayoutMode`, `documentsSortMode`).
- **`@FocusState`** per gestire focus campi input.
- **`@Binding`** per il classico pattern parent-child.

#### Pattern `@Query` con predicato dinamico

Molte subview costruiscono il `Query` con `#Predicate` filtrato per `familyId` direttamente dentro `init`:

```swift
_passwordEntries = Query(
    filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil },
    sort: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
)
```

Esempi: `Features/Home/HomeView.swift:588-597`, `Features/Documents/DocumentFolderView/DocumentFolderView.swift:84-128`, `Features/Chat/ChatView.swift:38,429,554-558`.

### Pattern ViewModel

Tutti i VM produttivi seguono questo template (~23 totali):

```swift
@MainActor
final class XViewModel: ObservableObject {
    let familyId: String                    // input immutabile
    @Published var ...                      // UI state esposto
    private var modelContext: ModelContext? // settato via bind(modelContext:)
    private var cancellables = Set<AnyCancellable>()
    private let remote = SomeRemoteStore()  // dipendenze hard-coded (no DI)

    init(familyId: String) { ... }
    func bind(modelContext: ModelContext) { self.modelContext = modelContext }
    func startListening() / startObservingChanges() / reload()
}
```

**Modularizzazione via extension**: `DocumentFolderViewModel.swift` (1390 righe) è split in 4 file di extension (`+Merge`, `+SendToChat`, `+Share`, `+Unlock`). Stesso pattern per `SyncCenter+*`.

### Stato globale / singleton

KidBox usa **molti** singleton — è una scelta architetturale forte:

- `AppCoordinator` (non `.shared`, ma è `@StateObject` root in `KidBoxApp` e propagato come `@EnvironmentObject`): auth, famiglia attiva, navigation `path: [Route]`, deep link, share extension drop, appearance mode.
- `SyncCenter.shared` — listener realtime + outbox.
- `NotificationManager.shared` — FCM, deep link, autorizzazioni, preferenze remote.
- `BadgeManager.shared` — `@Published var chat/documents/.../wallet: Int = 0` con listener Firestore su `families/{fid}/counters/{uid}`, propaga sull'icona app via `UNUserNotificationCenter.setBadgeCount`.
- `KBSubscriptionManager.shared` — StoreKit + `isFamilyOwner`.
- `AISettings.shared`, `AIService.shared`, `AIUsageStore.shared`.
- `KBEventBus.shared` — `PassthroughSubject<KBAppEvent, Never>` Combine globale per "attachment pending" (cure, visite, spese, veicoli, casa, animali).
- `CountersService.shared`, `FamilyMemoryService.shared`, `WeeklySummaryService.shared`, `DailyBriefingService.shared`, `HealthPatternAnalyzerService.shared`, `HousePaymentReminderService.shared`, `WalletReminderService.shared`, `CrashReportPromptCenter.shared`, `KBFileLogger.shared`.

`AppState` (`App/Core/AppState.swift`) e `SessionManager` (`App/Session/SessionManager.swift`) sono **residui legacy MVP** non più cablati nel `body`; il vero session listener è dentro `AppCoordinator.startSessionListener(modelContext:)` (`App/Core/AppCoordinator.swift:291-419`), chiamato da `RootGateView.task`.

### Concorrenza

L'app è in transizione da Combine puro a `async/await`:

- **`async/await` + `@MainActor`**: schema dominante per scritture e flussi UI. Tutti i VM produttivi sono `@MainActor`. Il loop di `SyncCenter.startAutoFlush` usa `while !Task.isCancelled { try? await Task.sleep(...) }`.
- **`Combine`** sopravvive in 3 modalità:
  1. `@Published` di tutti gli ObservableObject (Combine sotto al cofano).
  2. `PassthroughSubject` globali in singleton: `KBEventBus.subject`, `SyncCenter._docsChanged`, `SyncCenter._currentUserRevoked`.
  3. `.sink` / `.onReceive` consumati da View / Coordinator (es. `RootHostView` ascolta `currentUserRevoked` per espellere l'utente; `AppCoordinator.switchFamilyIfNeededThenNavigate` usa `$rootDataRefreshToken.dropFirst()...sink { action() }` come "await rebuild del root").

### SwiftData: `@Model`, schema, container, migrations

- **45 modelli** registrati in `Data/Persistence/ModelContainerProvider.swift:129-177`.
- Container costruito con `groupContainer: .identifier("group.it.vittorioscocca.kidbox")` + `cloudKitDatabase: .automatic` (replicazione CloudKit privata).
- **Probe d'integrità** post-load (`probeStoreIntegrity`) fa `try context.fetch(...)` su 7 entità chiave (`KBDocument`, `KBNote`, `KBTodoItem`, `KBWalletTicket`, `PasswordEntry`, `PasswordGroup`, `KBCalendarEvent`) per beccare migration faults.
- **Recovery quarantena**: se il container fallisce con `SwiftDataError` o `NSCocoaErrorDomain 134110`, sposta `default.store`, `-wal`, `-shm` con suffisso `.bak.<timestamp>` (`quarantinePersistentStoreArtifacts`) e ricrea il container. `didQuarantineCorruptedStoreThisLaunch = true` triggera `FamilyBootstrapService.bootstrapIfNeeded()` + `flushGlobal` per ripristinare i dati da Firestore senza reinstall.
- **Migration**: nessun versioning formale (`SchemaMigrationPlan`/`VersionedSchema` non sono usati). Strategia: lightweight automatic migration di SwiftData + quarantena + backfill via `@ModelActor KidBoxMigrationActor.runAll()` (oggi solo `backfillChildFamilyIdIfNeeded`).
- Migration crittografica: `Data/MasterKeyMigration.swift` chiamata da `RootHostView.onAppear { MasterKeyMigration.migrateAllFamilies(modelContext:) }`.

---

## 5. Firebase

- **Progetto**: `kidbox-42cd7` (`/Users/vscocca/KidBox/.firebaserc`)
- **Bucket Storage**: `kidbox-42cd7-eu` (regione UE, hardcoded in `functions/index.js:7`)
- **Region Cloud Functions**: `europe-west1`
- **Bootstrap iOS**: `KidBox/Support/Firebase/FirebaseBootstrap.swift` + `GoogleService-Info.plist`. `AppDelegate.application(_:didFinishLaunchingWithOptions:)` invoca `FirebaseApp.configure()` e logga `projectID` / `storageBucket`.

### 5.1 Firestore

#### Collezioni top-level

- **`users/{uid}`** — solo il proprietario può read/create/update/delete (rules righe 42-43). Campi: `email`, `displayName`, `photoURL`, `avatarURL`, `plan` (`"free"|"pro"|"max"`), `notificationPrefs` (mappa con `notifyOnNewDocs`, `notifyOnNewMessages`, `notifyOnLocationSharing`, `notifyOnTodoAssigned`, `notifyOnNewGroceryItem`, `notifyOnNewNote`, `notifyOnNewCalendarEvent`, `notifyOnNewExpense`, `notifyOnNewWalletTicket`, `notifyOnWalletReminder`, `aiEnabled`), `aiPrefs` (`healthContextSendPreference`, `healthContextSendPreferenceUpdatedAt`).
- **`users/{uid}/memberships/{familyId}`** — solo proprietario. Campi: `familyId`, `role` (`"owner"|"member"`), `createdAt`. Sorgente di verità per la CF `deleteAccount`.
- **`users/{uid}/fcmTokens/{tokenId}`** — `{token, platform: "ios", updatedAt}`, scritti da `NotificationManager.persistFCMToken`.
- **`users/{uid}/aiConversations/{docId}`** — chat AI **private per-utente**, sincronizzate solo tra i device dello stesso utente (`AIChatRemoteStore`). `docId` deterministico sullo scope (provider + visitId); messaggi incorporati come array, merge LWW su `updatedAt`. Vedi §AI per i dettagli.
- **`families/{familyId}`** — `create` se `request.resource.data.ownerUid == request.auth.uid`; `read/update/delete` se `isMemberOrOwner`. Campi: `name`, `ownerUid`, `plan`/`planOverride` (impostato solo dalla CF `setFamilyPlanOverride`), `planOverrideNote`/`SetAt`/`SetBy`, `heroPhotoURL`, `heroPhotoUpdatedAt`, `heroPhotoScale`, `heroPhotoOffsetX/Y`, `createdAt`, `updatedAt`, `updatedBy`.
- **`invites/{code}`** flat (codici a 6 caratteri da `Support/InviteCodeGenerator.swift`) — `read/create` per qualsiasi signed-in; `update` solo se `usedAt == null` e la diff tocca solo `usedAt`/`usedBy`.
- **`support_tickets/{ticketId}`** — `create` se `validSupportTicketData()`; campi obbligatori validati: `id, familyId, uid, userEmail, type ∈ {question,bug,suggestion}, title (≤200), summary (≤2000), conversation: list, images: list (≤5), platform ∈ {ios,android}, appVersion, osVersion, device, status == "new", createdAt`. Costruito da `SupportTicketFirestorePayload.buildDocumentData`.
- **`crash_reports/{reportId}`** — `create` se `userId == request.auth.uid`, `platform ∈ {ios, android}`, `status == "new"`, `rawLogs` ≤ 51200 byte. Scritti da `Support/CrashAnalyzer.swift`.
- **`diagnostics/{doc}`** — `read/write: true` (ping non sensibile, `Data/Remote/FirestorePingService.swift`).

#### Sotto-collezioni di `families/{familyId}` (autorizzate dal catch-all `subpath=**`)

| Path | Store iOS principale |
|---|---|
| `members/{uid}` | `Data/Remote/FamilyRemote/FamilyMemberRemoteStore.swift` |
| `children/{childId}` | `Data/Remote/FamilyRemote/FamilyRemoteStore.swift` + `Data/Repositories/ChildSyncService.swift` |
| `invites/{inviteId}` (UUID, crypto-wrapped) | `Support/InviteWrapService.swift` (create), `Features/Settings/SetupFamily/JoinFamily/JoinWrapService.swift` (consume) |
| `counters/{uid}` | letti da `App/Notification/CountersService.swift`. **Solo Cloud Functions** scrivono (`incrementCounterAndGetBadge`) — il client non ha rule di write. |
| `geofences/{geofenceId}` | `Data/Remote/LocationRemote/GeofenceRemoteStore.swift` |
| `geofenceEvents/{eventId}` | append-only (validato da rules), `Data/Remote/LocationRemote/GeofenceRemoteEvent.swift` |
| `locations/{uid}` | `Data/Remote/LocationRemote/LocationRemoteStore.swift` (campi `isSharing`, `mode`, `name`, `lat`, `lon`, `accuracy`, `startedAt`, `lastUpdateAt`, `expiresAt?`, `avatarURL?`, `lastNotifyAt?`, `stoppedReason?`) |
| `documents/{docId}` | `Data/Remote/DocumentStore/DocumentRemoteStore.swift` |
| `documents/{docId}/extractedValues/{...}` | `ClinicalExtractedValuesRemoteStore.swift` |
| `documentCategories/{categoryId}` | `DocumentCategoryRemoteStore.swift` |
| `chatMessages/{messageId}` | `Data/Remote/ChatStore/ChatRemoteStore.swift` (testo cifrato in `textEnc`, mention con `mentions: [{uid,displayName}]` + `mentionedUids: [String]`) |
| `typing/{uid}` | indicatore "sta scrivendo" (`isTyping`, `name`, `updatedAt`) |
| `notes/{noteId}` | `Data/Remote/Note/NotesRemoteStore.swift` (`titleEnc`/`bodyEnc` AES-GCM) |
| `todos/{todoId}` + `todoLists/{listId}` | `Data/Remote/TodoRemote/TodoRemoteStore.swift` |
| `calendarEvents/{eventId}` | `Data/Remote/Calendar/CalendarRemoteStore.swift` |
| `expenses/{expenseId}` | `Data/Remote/Expenses/ExpenseRemoteStore.swift` |
| `groceries/{itemId}` | `Features/Chat/GroceryRemoteStore.swift` |
| `walletTickets/{ticketId}` | `Data/Remote/Wallet/WalletRemoteStore.swift` (titolo/location/seat/PNR/notes/PDF cifrati `*Enc`; `kindRaw`, `eventDate`, `pdfStorageURL`, `pdfStorageBytes`, `addToAppleWalletURL`, `barcodeFormat`, `reminded24h`/`2h` flag idempotenti in chiaro) |
| `passwords/{id}` + `passwordGroups/{id}` | `Data/Remote/Passwords/PasswordRemoteStore.swift` (tutti i campi sensibili `*CipherB64` AES-GCM) |
| `medicalVisits/{visitId}` | `Data/Remote/Health/VisitRemoteStore.swift` (con `photoURLs: [String]` per stats salute) |
| `medicalExams/{examId}` | `Data/Remote/Health/MedicalExamRemoteStore.swift` |
| `treatments/{treatmentId}` + `doseLogs/{doseId}` | `TreatmentRemoteStore.swift` (con `KBDoseLog.stableDocumentId(treatmentId, dayNumber, slotIndex)` ID deterministico cross-device) |
| `vaccines/{vaccineId}` | `VaccineRemoteStore.swift` |
| `pediatricProfiles/{profileId}` | `PediatricProfileRemoteStore.swift` |
| `photos/{photoId}` + `photoAlbums/{albumId}` | `Data/Remote/PhotoVideoRemote/Photoremotestore.swift` |
| `memoryFacts/{factId}` | `Data/Remote/AI/MemoryFactRemoteStore.swift` |
| `memberKeyBackups/{userId}` | `Support/FamilyKeyEscrowService.swift` (escrow chiave family AES-GCM) |
| `pets/{petId}` + `petEvents/{eventId}` | `Data/Remote/RemoteStores/PetRemoteStore.swift` / `PetEventRemoteStore.swift` |
| `homeItems/{itemId}` + `housePayments/{paymentId}` | `HomeItemRemoteStore.swift` / `HousePaymentRemoteStore.swift` |
| `vehicles/{vehicleId}` + `vehicleEvents/{eventId}` | `VehicleRemoteStore.swift` / `VehicleEventRemoteStore.swift` |
| `trips/{tripId}` (+ sub `legs/`, `dayPlans/`, `packingItems/`, `expenses/`) | `Data/Remote/Travel/TripRemoteStore.swift` |
| `routines/{routineId}` (+ `routineChecks/`) | letti da `FamilyReadRemoteStore.fetchRoutines` |
| `events/{eventId}` (legacy) | letti da `FamilyReadRemoteStore.fetchEvents` |
| `stats/storage` | scritto **solo da Cloud Functions** (`updateStorageBytes` / `initStorageUsage`). Campi: `usedBytes`, `sections{documents, wallet, chat, photos, salute, expenses, notes?, calendar?, todo?}`, `lastUpdatedAt`. |

#### Convenzioni comuni nei documenti `families/...`

Pressoché tutti i documenti di sezione condividono:

- `familyId: String` (ridondato per indici / restore).
- `createdAt`, `updatedAt` (`FieldValue.serverTimestamp()`).
- `createdBy`, `updatedBy` (UID), spesso `createdByName`/`updatedByName`.
- `isDeleted: Bool` (soft-delete; GC notturno + trigger riducono contatori storage).
- `visibilityScope: "family" | "private" | "memberIds"` + `visibilityMemberIds: [String]` (definito in `Support/KBVisibilityScope.swift`, usato da note, todo, documenti, calendar, wallet, passwords).
- `schemaVersion: 1` su note, wallet, passwords.

#### Indici (`firestore.indexes.json`)

Solo due indici composti, entrambi sulla collezione `cases`:

1. `cases` su `(affectedModule ASC, platform ASC, status ASC, createdAt ASC)` — deduplica `onNewCrashReport`.
2. `cases` su `(status ASC, createdAt DESC)` — console admin + `cleanupResolvedCases`.

Tutte le query usate dall'app iOS sono single-field; Firestore le crea automaticamente.

### 5.2 Authentication

#### Provider abilitati

Definiti in `Domain/Auth/AuthProvider.swift` (`enum AuthProvider { apple, google, facebook }`) e iniettati in `Data/Auth/AuthFacade.swift` (`@MainActor final class AuthFacade` con `init(services: [AuthService])`):

| Provider | Wrapper "puro" | Implementazione Firebase |
|---|---|---|
| Apple | `AppleAuthService.swift` | `FirebaseAppleAuthService.swift` (CryptoKit nonce SHA-256 + `ASAuthorizationAppleIDProvider` + `OAuthProvider.appleCredential(...)`) |
| Google | `GoogleAuthService.swift` | `FirebaseGoogleAuthService.swift` (`GoogleSignIn`, `GoogleAuthProvider.credential(...)`) |
| Facebook | `FacebookAuthService.swift` | `FirebaseFacebookAuthService.swift` (Limited Login OIDC `OAuthProvider.credential(providerID: .facebook, idToken:rawNonce:)` o classic `FacebookAuthProvider.credential(withAccessToken:)`) |
| Email/Password | — (gestito direttamente da `LoginViewModel`) | `Auth.auth().signIn(withEmail:password:)`, `createUser(...)`, `sendEmailVerification()`, `sendPasswordReset(withEmail:)`. Dopo `createUser` il VM esegue subito `signOut()` finché l'utente non verifica l'email. |

**Provider NON usati**: `PhoneAuthProvider`.

#### Bootstrap

In `App/Core/AppDelegate.swift:61-126`:

- `FirebaseApp.configure()` (riga 68).
- `Auth.auth().useUserAccessGroup(...)` con valore letto da `KEYCHAIN_ACCESS_GROUP` in Info.plist (riga 82-87) — condivide la sessione con la Share Extension via Keychain.
- Configurazione Facebook SDK via `Facebook.xcconfig` (chiave `FacebookAppID` / `FacebookClientToken`).
- `Messaging.messaging().delegate = self` (riga 107) per ricevere i token FCM.
- Registrazione `BGAppRefreshTask` `it.vittorioscocca.kidbox.password-security-refresh` per scan sicurezza password (riga 128-149).

#### Onboarding e creazione profilo Firestore

1. `SessionManager.startListening(modelContext:)` registra `Auth.auth().addStateDidChangeListener` e su login chiama `upsertUserProfile(from:)` che salva `KBUserProfile` **in SwiftData** (non subito su Firestore).
2. Il documento `users/{uid}` lato Firestore viene popolato pigramente: da `NotificationManager` quando l'utente attiva preferenze, da `ProfileView` su edit nome/avatar (scrive anche `families/{familyId}/members/{uid}`), da `KBSubscriptionManager` su update plan, da `AvatarRemoteStore.uploadUserAvatar`.
3. Onboarding "famiglia": `FamilyRemoteStore.createFamilyWithChild` (batch `families/{id}` + `members/{uid}` + `users/{uid}/memberships/{familyId}` + `children/{childId}`) o join via codice/QR (`FamilyJoinService.joinFamily`, `Support/InviteWrapService`, `JoinWrapService`).

#### Persistenza, refresh, FCM token

- Persistenza credenziali: SDK Firebase Auth nel Keychain. Lo "shared access group" è definito da `KEYCHAIN_ACCESS_GROUP` (Info.plist) → consente alle estensioni (Share, Notification Service) di riusare lo stesso `currentUser`.
- Refresh token: gestito automaticamente dall'SDK; `AccountDeletionService.deleteMyAccount()` forza `user.getIDTokenResult(forcingRefresh: true)` prima di chiamare la CF `deleteAccount`.
- FCM: `AppDelegate` inoltra APNs/FCM token a `NotificationManager.shared.handleAPNSToken` / `handleFCMToken`. `persistFCMToken(_:)` salva `users/{uid}/fcmTokens/{token}` con `{token, platform: "ios", updatedAt}`.

#### Logout

`LoginViewModel.signOut()` → `AuthFacade.signOut()` → `Auth.auth().signOut()` + `KBSubscriptionManager.shared.resetOnSignOut()` + `KidBoxLocalNotificationsCleanup.cancelAllScheduledAccountReminders`. Logout Facebook esplicito (`LoginManager().logOut()`). Cancellazione completa: `AccountDeletionService.deleteMyAccount` → CF `deleteAccount` → `LocalDataWiper.wipeAll` → `Auth.auth().signOut()`.

### 5.3 Cloud Functions

- Codice in `/Users/vscocca/KidBox/functions/index.js` (~4700 righe, JavaScript, niente TypeScript). `engines.node = "22"`.
- Tutte le funzioni v2 (`firebase-functions/v2/...`), regione `europe-west1`, bucket `kidbox-42cd7-eu` hardcoded.
- Secrets: `ANTHROPIC_API_KEY`, `GOOGLE_PLACES_API_KEY`, `GEMINI_API_KEY` (`defineSecret`).
- Admin UID: `efw85HN41nb1rmslevC3wkFpVUo1` (anche in rules `isAdmin()`).

#### Callable HTTPS invocate dall'app iOS

| Funzione | Auth | Caller iOS | Scopo |
|---|---|---|---|
| `askAI` | Sì + plan check | `AIService.sendMessages` (`App/AI Core/AIService.swift:243`) | Chat AI Anthropic Haiku/Sonnet, vision blocks (max 5/img, ≤5MB), payload ≤500k char, contatore `ai_usage/family_{familyId}/daily/{YYYY-MM-DD}` |
| `getAIUsage` | Sì | `AIService.fetchUsage` (`AIService.swift:300`) | `{usageToday, dailyLimit}` |
| `generateTravelPlan` | Sì | `AIService.generateTravelPlan` (`AIService.swift:423`) | Itinerario AI (Sonnet); 2 messaggi/3 giorni |
| `suggestTravelDestinations` | Sì | `AIService.suggestTravelDestinations` (`AIService.swift:365`) | Suggerimenti destinazioni |
| `getTravelPlaceDetails` | Sì | `Features/Travel/TravelPlacesService.fetchDetails:21` | Dettagli + foto Google Places |
| `getStorageUsage` | Sì + membership | `Features/Settings/Storage/StorageUsageViewModel.swift:77,118` | `{usedBytes, quotaBytes, breakdown}` |
| `initStorageUsage` | Sì + membership | `StorageUsageView.swift:204` | Ricalcola da zero `families/{familyId}/stats/storage` |
| `deleteAccount` | Sì | `AccountDeletionService.deleteMyAccount` (`AccountDeletionService.swift:39`) | Wipe membership/famiglie senza altri membri, FCM token, `users/{uid}`, blob Storage `users/{uid}/`, contatori AI, `Auth.deleteUser` |
| `deleteFamily` | Sì + ultimo membro | `FamilyLeaveService.swift:150` | Pulisce famiglia completa (tutte le sottocollezioni `FAMILY_SUBCOLLECTIONS`) |

#### Trigger Firestore (selezione)

- `notifyNewDocument` (`families/{fid}/documents/{docId}`, create) → push + storage stats.
- `onDocumentSoftDeleted/HardDeleted` → decrementa `stats/storage.sections.documents`.
- `notifyNewChatMessage` (chat con cifratura `textEnc` + mention dedicate, `mutable-content` per la NSE iOS) + `onChatMessageSoftDeleted`.
- `onPhotoCreated/SoftDeleted/HardDeleted` (`stats/storage.sections.photos`).
- `onMedicalVisitWritten` (`stats/storage.sections.salute` in base a `photoURLs.length * 200 KB`).
- `notifyLocationSharingChanged` (cooldown 15 s).
- `onGeofenceEvent`, `notifyTodoAssigned`, `notifyNewGroceryItem`, `notifyNewNote`, `notifyNewCalendarEvent` (Europe/Rome), `notifyNewExpense` (€), `onWalletTicketStorageChanged`, `notifyNewWalletTicket`.
- `onNewCrashReport` → dedup su `cases/{caseId}`. `onCaseStatusChange`. `notifyCriticalCase` (push admin).

#### Schedulati

- `expireTemporaryLocations` ogni 5 min (Europe/Rome) — `collectionGroup("locations")`, `mode == "temporary"` con `expiresAt <= now`.
- `garbageCollectDeleted` (`0 3 */5 * *`, 540 s, 512 MiB) — cancella `isDeleted == true` in `documents`, `chatMessages`, `photos`, `walletTickets` + relativi blob Storage.
- `notifyUpcomingWalletTickets` ogni 60 min — promemoria wallet T-24h e T-2h con flag idempotenti.
- `cleanupResolvedCases` ogni 24 h.

#### Collezioni server-only (rules wildcard `if false`)

`families/{fid}/counters/{uid}`, `families/{fid}/stats/storage`, `ai_usage/{userId-or-family_*}/daily/{YYYY-MM-DD}` (`count`, `updatedAt`, `familyId`, `lastUid`, key giornata in Europe/Rome), `cases/{caseId}` (crash triage), `admin/config`.

> **Whitelist** di sottocollezioni cancellate da `deleteFamilyCompletely` (`functions/index.js:3679-3723`): se aggiungi una nuova sottocollezione con dati di famiglia, **devi** estendere `FAMILY_SUBCOLLECTIONS` per non lasciare orphan data.

### 5.4 Firebase Storage

- Bucket: `kidbox-42cd7-eu` (UE).
- **Non esiste `storage.rules` nel repo**: le rules attive sul progetto sono presumibilmente definite via Console Firebase / file non versionato. Modificare i path sotto richiede aggiornare anche le rules in console.
- Convenzione encryption: i blob "sensibili" sono cifrati lato client con AES-GCM tramite la family master key (Keychain, `DocumentCryptoService` / `WalletCryptoService`). Estensione `.kbenc` per i payload cifrati; `contentType = application/octet-stream` + customMetadata `kb_encrypted=1`, `kb_alg=AES-GCM`, `kb_orig_mime`, `kb_orig_name`.

#### Layout dei path

| Path | File responsabile | Cifratura |
|---|---|---|
| `users/{uid}/avatar.jpg` | `AvatarRemoteStore.uploadUserAvatar:94` | JPEG in chiaro |
| `families/{familyId}/avatars/{uid}.jpg` | `AvatarRemoteStore.uploadAvatar:36` | JPEG in chiaro |
| `families/{familyId}/hero/hero.jpg` | `FamilyHeroPhotoService.swift:52` | JPEG in chiaro |
| `families/{familyId}/documents/{docId}/{fileName}.kbenc` | `DocumentStorageService.upload:72` | AES-GCM |
| `families/{familyId}/exam-attachments/{examId}/{docId}/{fileName}.kbenc` | `ExamAttachmentService:56` | AES-GCM |
| `families/{familyId}/visit-attachments/{visitId}/{docId}/{fileName}.kbenc` | `VisitAttachmentService:113` | AES-GCM |
| `families/{familyId}/treatment-attachments/{treatmentId}/{docId}/{fileName}.kbenc` | `TreatmentAttachmentService:149` | AES-GCM |
| `families/{familyId}/photos/{photoId}/original.enc` | `Photoremotestore.swift:204` | AES-GCM (foto+video, thumbnail JPEG ≤200 px in chiaro su Firestore) |
| `families/{familyId}/chat/{messageId}/{fileName}` | `ChatStorageService.swift:25-29` | **In chiaro** (sicurezza affidata a Storage Rules; nome standard `photo.jpg`/`video.mp4`/`audio.m4a`) |
| `families/{familyId}/wallet/{ticketId}/ticket.pdf.kbenc` | `WalletPDFStore.swift:37` | AES-GCM (raw bytes, watchdog timeout 90 s) |

#### Cancellazione massiva

`deleteStoragePrefix` in `functions/index.js:3746-3756` usata da `deleteAccount` e `deleteFamily` per pulire `users/{uid}/` e `families/{familyId}/`.

---

## 6. Navigazione

### 6.1 NavigationStack unico, niente TabView

L'app ha **un solo `NavigationStack` a livello root** ancorato al path del coordinator (`App/Root/RootHostView.swift:81-86`):

```swift
NavigationStack(path: $coordinator.path) {
    coordinator.makeRootView()
        .navigationDestination(for: Route.self) {
            coordinator.makeDestination(for: $0)
        }
}
```

- **Nessuna `TabView`** di sezione principale: la "home" è semplicemente `HomeView` con una griglia di card draggabili (`Features/Home/HomeView.swift:569-954`, `HomeCardGrid`). L'unica `TabView` nell'app è dentro `Features/Travel/TravelPlaceDetailView.swift:97` per il carosello immagini di un place — UI locale, non root navigation.
- **Nessuna `NavigationView`** legacy. Su iPhone/iPad l'app usa il singolo `NavigationStack` a colonna unica. La **`NavigationSplitView`** esiste **solo su Mac Catalyst** (`App/Root/MacShellView.swift`, compilato dentro `#if targetEnvironment(macCatalyst)`); su iOS/iPadOS la UI resta invariata a colonna unica (vedi §6.7).
- Dentro alcuni sheet/full-screen modali si annidano altri `NavigationStack` isolati (es. `DocumentFolderView`, `FamilySettingsView`, `SupportChatView`, `CalendarView`).

### 6.2 Coordinator unico

Non esistono coordinator per-feature. `AppCoordinator` (`App/Core/AppCoordinator.swift:25-26`, `@MainActor final class AppCoordinator: ObservableObject`) è l'unico routing layer e contiene:

- `@Published var path: [Route] = []` — la pila di navigazione.
- `@Published var isAuthenticated/isCheckingAuth/hasSeenOnboarding/uid`.
- `@Published var activeFamilyId: String?` (con `didSet` che persiste in `UserDefaults.standard` + App Group).
- `@Published var appearanceMode: AppearanceMode`.
- ~15 `@Published var pendingShare*` per i payload incoming dalla Share Extension.
- `@Published var pendingOpenDocumentId/pendingChatMentionMessageId/pendingChatDocumentURL` per i deep link cross-feature.

API di navigazione:

- `func navigate(to route: Route)` — `path.append(route)`.
- `func navigateBack()` — `path.removeLast()`.
- `func resetToRoot()` — `path.removeAll()` + bump di `rootDataRefreshToken` per forzare il rebuild di `RootHostView`.
- `func switchFamilyIfNeededThenNavigate(to:action:)` — usa Combine `$rootDataRefreshToken.dropFirst().filter(...).first().sink { action() }` per attendere il rebuild della root prima di eseguire la navigazione (caso multi-famiglia su deep link push).
- `func makeDestination(for route: Route)` (`App/Core/AppCoordinator.swift:469-613`) — gigantesco `switch` su `Route` che ritorna la View corretta per ogni caso.
- Per i push richiamati da `KidBoxApp.onReceive(notifications.$pendingDeepLink)` ci sono varianti che ricostruiscono lo stack completo prima del target: `openDocumentFromPush`, `openVisitFromPush`, `openTreatmentFromPush`, `openExamFromPush`, `openNoteFromPush`, `openCalendarEventFromPush`, `openTodoFromPush`, `openWalletTicketFromPush`, `openFamilyPhotosWithCameraShortcut`.

### 6.3 `Route` enum

`App/Root/Route.swift:30-115` definisce `enum Route: Hashable` con ~60 case organizzati per area: `home, today, calendar, todo, settings, supportChat, profile, familySettings, inviteCode, joinFamily, chat, shoppingList, familyLocation, todoList, document, documentsHome, documentsCategory, todoSmart, editChild, setupFamily, editFamily` + Pediatria, Note, Foto, Spese, Wallet, Password, Animali, Casa, Garage, Viaggi.

Pattern duplice "dentro la View":

- **Imperativo** (preferito): `coordinator.navigate(to: .documentsCategory(...))`.
- **Dichiarativo**: `NavigationLink(value: Route.documentsCategory(...)) { ... }` (funziona perché il `navigationDestination(for: Route.self)` è registrato sul root `NavigationStack`).

### 6.4 Niente tab bar

L'app **non** ha tab bar. La "home" sostitutiva è `HomeView` + `HomeCardGrid` (`Features/Home/HomeView.swift:569-954`) — griglia 2 colonne con card per `note`, `todo`, `shopping`, `calendar`, `care` (salute), `chat`, `documents`, `expenses`, `wallet`, `passwords`, `location`, `photos`, `family`, `pets`, `homeItems`, `vehicles`, `travel`, `expert` (AI). L'ordine è draggabile e persistito in `UserDefaults["kb.home.cardOrder.<familyId>"]`. Ogni card resetta i badge della sezione (`BadgeManager.shared.clearXxx()` + `CountersService.shared.reset(...)`) e poi `coordinator.navigate(to: .xxx)`.

### 6.5 Sheet, alert, fullScreenCover

- **`.sheet(isPresented: $showXxx)`** è il pattern dominante; le 7 sheet di `DocumentFolderView` sono raccolte in `CommonModifiers.applySheets(_:)` (`DocumentFolderView.swift:1119-1205`): staging visibilità, FolderPicker, MergePDF, UnlockPDF, ActivitySheet, photosPicker, fileImporter.
- **`.sheet(item: Binding<Identifiable?>)`** quando si presenta un oggetto specifico (es. `IdentifiableURL` per QuickLook, `DocumentDetailSheetItem`, `PendingShareEventDraft`).
- **`.alert(...)`** state-based con `@State private var showXxxAlert = false`.
- **`.fullScreenCover`** sporadico (camera picker, media).
- **`.confirmationDialog`** per scelte distruttive.
- **`.toolbar { ToolbarItemGroup(placement:) ... }`** per i menu (es. `Menu { ... } label: { Image(systemName: "ellipsis.circle") }` in `ChatView.swift:83-118`).

### 6.6 Deep link e custom URL scheme

#### URL scheme `kidbox://`

Gestiti in `KidBoxApp.onOpenURL` (`App/Core/KidBoxApp.swift:71-111`):

- `kidbox://share` → `coordinator.handleIncomingShare(modelContext:)` — legge `UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")["pendingShare"]`, switch su `destination` (`chat`, `todo`, `grocery`, `event`, `document`, `wallet`, `encryptedMedia`, `note`), valorizza i `pending*` del coordinator e chiama `navigate(to:)`.
- `kidbox://control/open-family-photos-camera` → `coordinator.openFamilyPhotosWithCameraShortcut(modelContext:)` (Control Widget iOS 18+).
- Altri URL: prima `ApplicationDelegate.shared.application(...)` (Facebook), poi `GIDSignIn.sharedInstance.handle(url)` (Google).

**Non esiste un `DeepLinkRouter` dedicato** — tutta la logica è inline tra `KidBoxApp.onOpenURL` (URL scheme) e il `switch link { ... }` per i push.

#### Universal Links

**Non implementati.** Nessun handler per `application(_:continue:restorationHandler:)` né `Associated Domains` con `applinks:`. Solo custom scheme `kidbox://`.

#### Push notifications routing

1. **`AppDelegate`** (`App/Core/AppDelegate.swift:38-42`) è `UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate, CLLocationManagerDelegate`.
2. **APNs**: `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` inoltra a `NotificationManager.shared.handleAPNSToken`.
3. **FCM**: `messaging(_:didReceiveRegistrationToken:)` inoltra a `handleFCMToken` che persiste su `users/{uid}/fcmTokens/{tokenId}`.
4. **Tap notifica**: `userNotificationCenter(_:didReceive:)` prima prova le quick action cure (`TreatmentDoseActionHandler.handle(response:modelContext:)`); se non gestite, `NotificationManager.handleNotificationUserInfo(userInfo)` fa il **parsing per `type`** e valorizza `@Published var pendingDeepLink: DeepLink?`.
5. **`enum DeepLink`** (`App/Notification/NotificationManager.swift:71-90`) — 15 casi: `.document, .chat, .familyLocation, .todo, .groceryItem, .note, .calendarEvent, .pediatricVisit, .treatmentReminder, .examReminder, .expense, .walletTicket, .askExpert(familyId:), .passwordExpiry, .passwordSecurity`. Le notifiche AI locali (`weekly_summary`, `daily_briefing`, `health_pattern`) includono `familyId` nello `userInfo` e mappano a `.askExpert(familyId:)`: il routing switcha alla famiglia corretta prima di aprire l'Assistente (la chat usa `coordinator.activeFamilyId`).
6. **Consumo**: `KidBoxApp.body` ha `.onReceive(notifications.$pendingDeepLink) { link in switch link { ... } }` (`KidBoxApp.swift:130-318`) che per ogni caso:
   - resetta i badge locali (`BadgeManager.shared.clearXxx()`) e i contatori Firestore (`CountersService.shared.reset(familyId:field:)`),
   - chiama `coordinator.switchFamilyIfNeededThenNavigate(to: familyId) { coordinator.navigate(to: .xxx) }` (oppure le varianti `openXxxFromPush` quando serve ricostruire una pila di route),
   - chiude con `notifications.consumeDeepLink()`.
   - **Multi-famiglia**: `switchFamilyIfNeededThenNavigate(to:)` (`AppCoordinator.swift`) se la famiglia del deep link ≠ attiva esegue `setActiveFamily(.., force: true)`, attende il rebuild della root (`rootDataRefreshToken`) e poi naviga; il caso `.askExpert(familyId:)` segue lo stesso schema quando il `familyId` è presente.
7. **Foreground**: `userNotificationCenter(_:willPresent:)` mostra banner+suono **solo** per `visit_reminder`, `treatment_reminder`, `todo_reminder` (le altre sono soppresse perché aprono via deep link).
8. **Notification Service Extension** separata: `KidBoxNotificationService/NotificationService.swift` per arricchire/decifrare i payload chat (vedi §11.3).

#### Control Widget (iOS Control Center)

`App/Intents/OpenKidBoxFamilyPhotosCameraIntent.swift` definisce un App Intent eseguito dall'estensione Control Widget; scrive `kidbox.controlWidget.pendingRoute = "openFamilyPhotosCamera"` nell'App Group, consumato da `AppCoordinator.consumePendingControlWidgetRouteIfNeeded(modelContext:)` su `RootHostView.onAppear` + `UIApplication.didBecomeActiveNotification`.

#### Posizione famiglia e geofence (background)

`UIBackgroundModes` include `location`. Due meccanismi distinti:

- **Condivisione live in background**: `AppDelegate.setupBackgroundLocationManager()` usa `startMonitoringSignificantLocationChanges()`; al relaunch in background iOS chiama `didUpdateLocations`, che scrive su Firestore via `LocationRemoteStore` leggendo uid/familyId/displayName dai `UserDefaults` (chiavi `KBLocationDefaults`), gate su `isSharing`.
- **Geofence (arrivo/uscita zona)**: `Features/FamilyLocation/GeofenceMonitorService.swift` è un **singleton a vita-app** (`static let shared`) con un solo `CLLocationManager` il cui delegate resta vivo a ogni avvio → riceve `didEnter/ExitRegion` anche dopo un relaunch in background (le `CLCircularRegion` persistono a livello OS tra i lanci). Il monitoraggio è **indipendente** dalla condivisione live (`FamilyLocationViewModel.syncGeofenceMonitor()` non è più gated su `sharingRequested/isSharing`). Il contesto (familyId/uid/displayName) è persistito nei `UserDefaults` (chiavi `geofence*` in `KBLocationDefaults`) per attribuire correttamente gli eventi; `AppDelegate.didFinishLaunching` istanzia `GeofenceMonitorService.shared` (via `MainActor.assumeIsolated`). Gli eventi vengono scritti su `families/{familyId}/geofenceEvents/{eventId}` → Cloud Function `onGeofenceEvent` invia le push ai membri.

### 6.7 Shell desktop Mac Catalyst

L'app gira anche come **Mac Catalyst**. Tutto il codice desktop-specifico vive in `App/Root/` dentro `#if targetEnvironment(macCatalyst)`, quindi **la UI iPhone/iPad è completamente intatta**.

- **`App/Root/MacShellView.swift`** (~352 righe) — root su Mac. È una `NavigationSplitView` con:
  - **sidebar persistente** guidata dall'enum `MacSection` (l'ordine dei case = ordine in sidebar): `dashboard, calendar, todo, notes, shopping, photos, health, chat, documents, expenses, wallet, passwords, location, pets, homeItems, vehicles, travel, assistant` + gruppo Account (`family, profile, settings`). Il mapping sezione→view rispecchia le card della Home grid (titoli/icone/colori coerenti).
  - **colonna detail** che ospita un proprio `NavigationStack` legato a `coordinator.path`, così il drill-down (es. aprire il dettaglio di una nota) continua a funzionare via `coordinator.navigate(to:)` riusando lo stesso `AppCoordinator.makeDestination(for:)` di iOS/iPad.
  - sul Mac la Home grid è ridondante (la sostituisce la sidebar): la sezione `dashboard` mostra `MacDashboardView` al posto di `HomeView`.
- **`App/Root/MacPresentation.swift`** — adatta le presentazioni modali al desktop:
  - `View.sheetOrMacPush(isPresented:hideMacNavBar:content:)` — su iOS presenta una `.sheet`, su Mac fa `navigationDestination(isPresented:)` (push in-place nel `NavigationStack`). Usato per chat AI e gallerie media/link/documenti della chat.
  - `ModalNavContainer` — avvolge il contenuto in un `NavigationStack` solo su iOS (dove la view è modale e serve un proprio contesto di navigazione); su Mac no, per evitare una nav bar duplicata.
- **Entry point**: `App/Root/RootGateView.swift:56` istanzia `MacShellView()` sotto `#if targetEnvironment(macCatalyst)`; `RootHostView` salta il suo `NavigationStack` a colonna unica sul Mac (delega a `MacShellView`).

---

## 7. Modelli dati

### 7.1 Schema SwiftData e contenitore

- File: `KidBox/Data/Persistence/ModelContainerProvider.swift`.
  - `enum ModelContainerProvider.makeContainer(inMemory: Bool) -> ModelContainer`.
  - Dichiara lo `Schema([...])` con **45 modelli persistenti** (righe 129-177).
  - Config: `groupContainer: .identifier("group.it.vittorioscocca.kidbox")` (App Group condiviso con Share/Widget/AutoFill) e `cloudKitDatabase: .automatic`.
  - Probe d'integrità (`probeStoreIntegrity`) e **quarantena automatica** del file SQLite + WAL/SHM in caso di migrazione fallita (`NSCocoaErrorDomain 134110` / `SwiftDataError`). Se la quarantena scatta, `didQuarantineCorruptedStoreThisLaunch = true` triggera `FamilyBootstrapService.bootstrapIfNeeded()` + `SyncCenter.shared.flushGlobal()` da `KidBoxApp.init()`.

Membri dello `Schema([...])`:

`KBFamily, KBFamilyMember, KBChild, KBRoutine, KBRoutineCheck, KBEvent, KBTodoItem, KBTodoList, KBCustodySchedule, KBUserProfile, KBDocument, KBDocumentCategory, KBSyncOp, KBChatMessage, KBGroceryItem, KBNote, KBTreatment, KBMedicalVisit, KBPediatricProfile, KBVaccine, KBDoseLog, KBAIConversation, KBAIMessage, KBMemoryFact, KBCustomDrug, KBMedicalExam, KBHealthInsight, KBCalendarEvent, KBFamilyPhoto, KBPhotoAlbum, KBExpenseCategory, KBExpense, KBWalletTicket, PasswordEntry, PasswordGroup, KBPet, KBPetEvent, KBHomeItem, KBHousePayment, KBVehicle, KBVehicleEvent, KBTrip, KBTripLeg, KBTripDayPlan, KBTripExpense, KBPackingItem, KBGeofence`.

Protocollo di scope per i wipe:

- `protocol HasFamilyId { var familyId: String { get } }` (in `Support/LocalDataWiper.swift`). Implementato dai modelli "family-scoped" (`KBDocument`, `KBNote`, `KBTodoItem`, `KBChatMessage`, `KBVehicle`, `KBHomeItem`, `KBPet`, `KBGeofence`, …).

### 7.2 Modelli per area funzionale (campi chiave)

Tutti i modelli sono `@Model final class`, persistenti, con `@Attribute(.unique) var id: String`.

#### Famiglia / utenti

- `Data/Models/Family/KBFamily.swift` — `id, name, heroPhotoURL, heroPhotoUpdatedAt, heroPhotoScale/OffsetX/OffsetY, createdBy, updatedBy, createdAt, updatedAt, lastSyncAt, lastSyncError`. `@Relationship(deleteRule: .cascade, inverse: \KBChild.family) var children: [KBChild]`.
- `Data/Models/Family/KBChild.swift` — `id, familyId: String? (opzionale per migrazione), name, birthDate, weightKg, heightCm, …`. `@Relationship var family: KBFamily?`. Extension con `ageYears`, `ageDescription`, `avatarEmoji`.
- `Data/Models/Family/KBFamilyMember.swift` — `id, familyId, userId, role ("admin" | "member" | "owner"), displayName?, email?, photoURL?, …`.
- `Domain/Models/KBUserProfile.swift` — unico modello in `Domain/Models/`. `@Attribute(.unique) var uid: String, email?, displayName?, firstName?, lastName?, familyAddress?, avatarData: Data?, …`.

#### Documenti

- `Data/Models/Document/KBDocument.swift` — `id, familyId, childId?, categoryId?, title, fileName, mimeType, fileSize: Int64, localPath?, storagePath, downloadURL?, notes?, extractedText?, extractionStatusRaw (KBTextExtractionStatus), visibilityScope (default KBVisibilityScope.family), visibilityMemberIds: [String], createdBy, …, isDeleted, syncStateRaw, lastSyncError`. Utility: `localFileURL`, `isImageDocument`, `isPDFDocument`, `markExtraction(Pending|Processing|Completed|Failed)`, `isVisibleToCurrentUser(currentUid:)`.
- `Data/Models/Document/KBDocumentCategory.swift` — `id, familyId, title, sortOrder, parentId?, …`.

#### Note, Todo, Calendario, Spesa

- `Data/Models/KBNote.swift` — `id, familyId, title, body, visibilityScope?, visibilityMemberIds?: [String]?, createdBy/Name, updatedBy/Name, …`. Helper `isVisible(to:)`.
- `Data/Models/ToDo/KBTodoItem.swift` — `id, familyId, childId, title, notes?, dueAt?, isDone, doneAt?, doneBy?, listId?, reminderEnabled, reminderId?, assignedTo?, priorityRaw?, visibilityScope?, visibilityMemberIds?, …`.
- `Data/Models/ToDo/KBTodoList.swift` — `id, familyId, childId, name, …`.
- `Data/Models/KBEvent.swift` — `id, familyId, childId, type, title, startAt, endAt?, notes?, …`.
- `Data/Models/Calendar/KBCalendarEvent.swift` — `id, familyId, childId?, title, notes?, location?, startDate, endDate, isAllDay, categoryRaw (KBEventCategory), recurrenceRaw (KBEventRecurrence), reminderMinutes?, linkedHealthItemId?, linkedHealthItemType?, visibilityScope/Members, …`.
- `Data/Models/Expenses/KBExpense.swift` — `id, familyId, title, amount: Double, date, categoryId?, notes?, attachedDocumentId?, @Attribute(.externalStorage) receiptThumbnailData: Data?, …`.
- `Data/Models/KBGroceryItem.swift` — `id, familyId, name, category?, notes?, isPurchased, purchasedAt?, purchasedBy?, …`.

#### Salute

- `Data/Models/Health/KBPediatricProfile.swift` — uno per bambino (`id == childId`); blood group, allergies, doctor, `emergencyContactsData: Data?` (JSON), `doctorOfficeHoursData: Data?` (JSON).
- `Data/Models/Health/KBTreatment.swift` — `drugName, dosageValue, dosageUnit, isLongTerm, durationDays, dailyFrequency, intervalBetweenDosesDays, scheduleTimesData ("08:00,14:00,20:00"), prescribingVisitId?, petId` (per cure animali). Computed `scheduleTimes`, `totalDoses`, `usesIntervalSchedule`.
- `Data/Models/Health/KBMedicalVisit.swift` — workflow 5-step: medico/data, esito, prescrizioni (`linkedTreatmentIds: [String]`, `linkedExamIds: [String]`), foto/appunti, prossima visita. Campi `Data?` con codec custom `kbEncode/kbDecode` per `[KBPrescribedExam]`, `[KBAsNeededDrug]`, `KBTravelDetails`. Stato visita (`KBVisitStatus`).
- `Data/Models/Health/KBMedicalExam.swift` — `id, familyId, childId, name, isUrgent, deadline?, preparation?, location?, statusRaw (KBExamStatus), resultText?, resultDate?, prescribingVisitId?`.
- `Data/Models/Health/KBVaccine.swift` — `vaccineTypeRaw, statusRaw, commercialName?, doseNumber, totalDoses, administeredDate?, scheduledDate?, lotNumber?, nextDoseDate?`.
- `Data/Models/Health/KBDoseLog.swift` — `(dayNumber, slotIndex, scheduledTime, takenAt?, taken)`. `static func stableDocumentId(treatmentId, dayNumber, slotIndex)` per **ID deterministico cross-device**.
- `Data/Models/Health/KBHealthInsight.swift` — insight mensile generato da AI.

#### AI

- `Data/AIMessage/KBAIConversation.swift` — `id, familyId, childId, visitId, providerRaw (AIProvider .claude|.openai), createdAt, summary?, summaryUpdatedAt?, summarizedMessageCount`. `@Relationship(deleteRule: .cascade, inverse: \KBAIMessage.conversation) var messages: [KBAIMessage]`.
- `Data/AIMessage/KBAIMessage.swift`.
- **Sync cross-device delle chat AI** (`Data/Remote/RemoteStores/AIChatRemoteStore.swift` + `Data/Remote/Sync/SyncCenter+AIChat.swift`): le conversazioni AI sono **private per-utente** e vengono sincronizzate solo tra i device dello stesso utente sotto `users/{uid}/aiConversations/{docId}` (nessun membro famiglia le vede). L'id del documento è **deterministico** sullo scope (provider + visitId), così ogni device converge sullo stesso documento; i messaggi sono incorporati come array nel documento, con merge a livello di conversazione **Last-Writer-Wins su `updatedAt`** (propaga anche "pulisci chat" e la compattazione `summary`). `SyncCenter.startAIChatRealtime(modelContext:)` avvia il listener + riconciliazione una-tantum (pull + backfill); `SyncCenter.aiChatChanged` notifica i ViewModel delle chat aperte di ricaricare da SwiftData.
- `Data/Models/KBMemoryFact.swift` — fatti persistenti (`content, categoryRaw (MemoryFactCategory), sourceConversationId?`).

#### Chat di famiglia

- `Data/Models/KBChatMessage.swift` — `id, familyId, senderId, senderName, typeRaw (KBChatMessageType), text?, latitude?/longitude?, mediaStoragePath?, mediaURL?, mediaThumbnailURL?, mediaDurationSeconds?, mediaFileSize?, mediaLocalPath?, mediaGroupURLsJSON?/TypesJSON? (max 10 media), replyToId?, reactionsJSON?, readByJSON?, mentionsJSON?, contactPayloadJSON?, transcript* (Apple Speech Analyzer), createdAt, editedAt?, isDeleted, isDeletedForEveryone, syncStateRaw`. Computed `reactions`, `readBy`, `mentions`, `mediaGroupURLs/Types`.
- `Data/Models/ChatMention.swift` — `struct ChatMention: Codable { uid; displayName }` (estratto a parte perché serve anche alla `KidBoxShareExtension`).

#### Foto / Wallet / Password / Casa / Auto / Animali / Viaggi / Posizione

Vedere §11 e i file in `Data/Models/{PhotoVideo,Wallet,Home,Vehicle,Pet,Travel,Location}/`.

#### Outbox di sync

- `Data/Remote/Sync/KBSyncOp.swift` — `@Model` con `id, familyId, entityTypeRaw (SyncEntityType), entityId, opType ("upsert"|"delete"), payloadJSON?, createdAt, nextRetryAt, attempts: Int, lastError?`.
- `Data/Remote/Sync/KBSyncState.swift` — `enum: Int { synced=0, pendingUpsert=1, pendingDelete=2, error=3 }`. **Memorizzato su quasi ogni modello** come `syncStateRaw: Int` con getter computed `syncState`.
- `Data/Remote/Sync/SyncEntityType.swift` — enum string con i tipi di entità sincronizzati (todo, document, documentCategory, note, treatment, doseLog, visit, pediatricProfile, vaccine, medicalExam, calendarEvent, expense, walletTicket, passwordEntry, passwordGroup, pet, petEvent, homeItem, housePayment, vehicle, vehicleEvent, familyBundle, grocery, todoList).

### 7.3 DTO / Payload Firestore

Vivono in `Data/Remote/...` accanto al relativo store. Pattern uniforme: per ogni entità c'è un `*RemoteStore.swift` con una `struct *DTO: Codable` + un `enum *RemoteChange { .upsert(dto) / .remove(id) }`.

| File | DTO / payload |
|---|---|
| `Data/Remote/DocumentStore/DocumentRemoteStore.swift` | `struct RemoteDocumentDTO`, `enum DocumentRemoteChange` |
| `Data/Remote/Note/NotesRemoteStore.swift` | `struct NoteDTO` (titleEnc/bodyEnc base64 + fallback `titlePlain/bodyPlain` legacy) |
| `Data/Remote/FamilyRemote/FamilyRemoteStore.swift` | `RemoteFamilyPayload`, `RemoteChildPayload`, `RemoteFamilyUpdatePayload`, `RemoteChildUpdatePayload` |
| `Data/Remote/FamilyRemote/FamilyMemberRemoteStore.swift` | `struct FamilyMemberRemoteDTO` |
| `Data/Remote/FamilyRemote/FamilyReadRemoteStore.swift` | `RemoteFamilyRead`, `RemoteChildRead`, `RemoteRoutineRead`, `RemoteTodoRead`, `RemoteTodoListRead`, `RemoteEventRead` |
| `Data/Remote/Wallet/WalletRemoteStore.swift` | `struct WalletTicketDTO` (campi `*Enc: String?` base64) |
| `Data/Remote/Passwords/PasswordRemoteStore.swift` | `struct PasswordEntryDTO`, `struct PasswordGroupDTO`, `enum PasswordRemoteChange` |
| `Data/Remote/ChatStore/ChatRemoteStore.swift` | `struct RemoteChatMessageDTO` |
| `Data/Remote/Calendar/CalendarRemoteStore.swift` | `KBCalendarEventDTO` |
| `Data/Remote/AI/MemoryFactRemoteStore.swift` | `struct RemoteMemoryFactDTO: Sendable` |
| `Data/Remote/Support/SupportTicketFirestorePayload.swift` | `struct SupportTicketSubmitPayload`, `struct SupportConversationMessagePayload` (cap 1 MiB) |

I `RemoteStore` "thin" sotto `Data/Remote/RemoteStores/` (HomeItem, HousePayment, Pet, PetEvent, Vehicle, VehicleEvent) usano dictionary `[String: Any]` direttamente senza struct DTO formali.

---

## 8. Servizi e layer

### 8.1 Authentication (`Data/Auth/` + `Domain/Auth/`)

- Protocollo `protocol AuthService { var provider: AuthProvider; func signIn(presentation:) async throws -> User }` (`Domain/Auth/AuthService.swift`).
- `enum AuthProvider { apple, google, facebook }` (`Domain/Auth/AuthProvider.swift`).
- Wrapper "puri" (`Apple/Google/FacebookAuthService.swift`) + implementazioni Firebase (`FirebaseAppleAuthService.swift`, `FirebaseGoogleAuthService.swift`, `FirebaseFacebookAuthService.swift`).
- Facade `AuthFacade.swift` (`@MainActor final class AuthFacade`) che riceve `[AuthService]` e li indicizza per `AuthProvider`.

### 8.2 Family bootstrap & join

- `Domain/FamilyBootstrapService.swift` — `@MainActor` boot della famiglia attiva dopo login (memberships → family → children → routines → todos → events). Retry con delays `[0,250,500,900,1400,2200,3300]` ms saltando `PERMISSION_DENIED`. Recupera la key da `FamilyKeyEscrowService` se manca in Keychain.
- `Data/Repositories/FamilyJoinService.swift` — `@MainActor func joinFamily(code:coordinator:) async throws`:
  1. Risolve invite via `InviteRemoteStore`.
  2. Pulisce outbox della vecchia famiglia (`SyncCenter.removePendingSyncOperations`).
  3. `LocalDataWiper.wipeJoinStaleData(...)` per evitare scritture `PERMISSION_DENIED`.
  4. `MembershipRemoteStore` + fetch bundle (`FamilyReadRemoteStore`).
  5. `coordinator.setActiveFamily(...)`.
  6. Start listeners + `flushGlobal`.

  Wrappato da `SyncCenter.beginFamilyJoin/endFamilyJoin` per sopprimere il `handleFamilyAccessLost` spurio durante il transitorio.
- `Data/Repositories/FamilyRepository+Remote.swift` → `FamilyCreationService.createFamily(name, childName, childBirthDate)`. Batch Firestore: `families/{id}` + `families/{id}/members/{uid}` + `users/{uid}/memberships/{familyId}` + `families/{id}/children/{childId}`. Wrappato in `beginFamilyCreation/endFamilyCreation`.
- `Data/Repositories/ChildSyncService.swift`, `RepositoryErrors.swift`.

### 8.3 Repository (minimi)

- `Data/Repositories/Protocols.swift` — `RoutineRepository`, `TodoRepository`, `EventRepository` (CRUD locali con append-only `addRoutineCheck`).
- `Data/Repositories/SwiftData/` — `SwiftDataEventRepository`, `SwiftDataRoutineRepository`, `SwiftDataTodoRepository`. **Le uniche tre vere repository pattern**; non sono usate dai ViewModel principali, sopravvivono per todo/routine/event MVP. La vera "repository" produttiva è la coppia `RemoteStore` ↔ `SwiftData` + `SyncCenter`.

### 8.4 Sync layer (`Data/Remote/Sync/`)

Tutto orchestrato da `SyncCenter.swift` (~1460 righe, `@MainActor final class SyncCenter: ObservableObject`, singleton `SyncCenter.shared`), suddiviso in 22 estensioni per dominio.

Responsabilità:

- **Inbound realtime**: tiene `ListenerRegistration?` per ogni entità (`todoListener`, `notesListener`, `documentsListener`, `walletListener`, `petListener`, `vehicleListener`, `passwordEntriesListener`, `passwordGroupsListener`, `treatmentListener`, `visitListener`, `vaccineListener`, `medicalExamListener`, `pediatricProfileListener`, `calendarListener`, `expenseListener`, `tripsListener`, `homeItemListener`, `housePaymentListener`, ecc.). Avvio/stop con `start*Realtime(familyId:modelContext:)` / `stop*Realtime()`.
- **Outbox**: `enqueue*Upsert(...)` / `enqueue*Delete(...)` → `upsertOp(familyId, entityType, entityId, opType, modelContext)` deduplicato su `(familyId, entityType, entityId)`.
- **Auto flush** ogni 30 s: `startAutoFlush(modelContext:)` / `stopAutoFlush()` / `flushGlobal(modelContext:)` con backoff esponenziale `min(2^(attempts-1), 300) s`.
- **Dispatch**: `process(op:modelContext:remote:)` con `switch op.entityTypeRaw` instrada su `processTodo`, `processDocument`, `processNote`, `processWalletTicket`, `processVaccine`, `processVisit`, `processTreatment`, `processMedicalExam`, `processCalendarEvent`, `processExpense`, `processPasswordEntry/Group`, `processPet/PetEvent`, `processHomeItem/HousePayment`, `processVehicle/VehicleEvent`, `processFamilyBundle`, `processPhotoOp`, `processDoseLog`, `processPediatricProfile`.
- **Pull incrementale**: `pullTodoIncremental(familyId:childId:modelContext:remote:)` usa `KBFamily.lastSyncAt` come cursore.
- **LWW** (Last-Write-Wins) su `updatedAt` per inbound; remote `isDeleted=true` → hard delete locale; eccezioni anti-resurrect (es. note locale `pendingDelete` ignora upsert remoto; eccezione "locale vuota" accetta remoto per deep link).
- **Permission handling**: `Self.isPermissionDenied(error)` rileva `FirestoreErrorDomain`/`permissionDenied`; `handleFamilyAccessLost(familyId:source:error:)` chiude tutti i listener e pubblica `_currentUserRevoked` (Combine). Soppressione con `isFamilyBeingCreated`/`isJoiningFamily`/`isWipingLocalData`.
- **Revocation broadcasting**: `static let _currentUserRevoked: PassthroughSubject<String, Never>` consumato da `RootHostView`/`AppCoordinator` per espellere l'utente dalla UI.

Estensioni per dominio (firme `start/stop/enqueue/process/apply` simili):
`SyncCenter+Children.swift, +DocumentCategories, +DocumentsEvents, +Expenses, +FamilyBundle, +Grocery, +HomeItems, +HousePayments, +Pets, +Vehicles, +Notes, +Calendar, +MedicalExams, +Treatments, +Vaccines, +Visits, +PediatricProfile, +Wallet, +Passwords, +Trips, Synccenter+photos`.

### 8.5 Documents stack

- `DocumentRemoteStore.swift` — `families/{familyId}/documents/{docId}` (upsert / softDelete / delete / `listenDocuments`).
- `DocumentCategoryRemoteStore.swift` — `families/{familyId}/documentCategories/{categoryId}`.
- `DocumentStorageService.swift` — `upload(familyId, docId, fileName, originalMimeType, encryptedData)` → path `.kbenc` con metadata `kb_encrypted=1, kb_alg=AES-GCM, kb_orig_mime, kb_orig_name`.
- `DocumentCryptoService.swift` — AES-GCM combined (nonce+ciphertext+tag) usando `FamilyKeychainStore.loadFamilyKey(familyId:userId:)`. Funzioni: `encrypt(_:familyId:userId:)`, `decrypt(_:familyId:userId:)`. Helper `decryptStoredKBDocumentPayload` con 3 fallback (path `/chat/` plain, `notes == "chat_plain"`, magic bytes su `%PDF`, `PNG`, `JPEG`, `ZIP`, `OLE`).
- `DocumentDeleteService.swift` — `deleteDocumentHard(familyId:doc:)` best-effort Storage cleanup + Firestore delete.
- `Data/Persistence/DocumentLocalCache.swift` — `<Application Support>/KidBoxDocs/`. **Persiste SOLO ciphertext**; il plaintext finisce solo in `FileManager.default.temporaryDirectory`.

### 8.6 Crypto / Keychain / sicurezza

- `Support/FamilyKeychainStore.swift` — chiave AES-256 (32B) per coppia `{userId}.{familyId}` in `kSecClassGenericPassword`, service `"KidBox"`, `kSecAttrAccessibleAfterFirstUnlock`, **`kSecAttrSynchronizable: true`** (iCloud Keychain multi-device). Identificazione: `kidbox.family.masterkey.{userId}.{familyId}` (un dispositivo con due Apple ID ha due chiavi distinte per la stessa famiglia). **Cache in-memory** (dizionario `[account: SymmetricKey]` protetto da `NSLock`): `loadFamilyKey` interroga il Keychain solo al primo accesso, poi serve dalla cache — evita query `SecItemCopyMatching` sincrone ripetute a ogni `decrypt` (causava freeze della lista Password). Aggiornata in `saveFamilyKey`, invalidata con `clearKeyCache()` al logout/cambio account (chiamata da `AppCoordinator`).
- `Support/FamilyKeyEscrowService.swift` — backup cifrato della chiave su `families/{familyId}/memberKeyBackups/{userId}`. La wrap key è derivata HKDF-SHA256 da `userId + familyId + escrowSalt + escrowContext`. Permette recovery dopo reinstall / cambio account / iCloud Keychain disattivato.
- `Support/InviteCrypto.swift` — primitive: `randomBytes`, `sha256Base64`, `deriveWrapKey(secret:salt:familyId:)` HKDF-SHA256, `wrapFamilyKey/unwrapFamilyKey` AES-GCM (nonce 12B, tag 16B).
- `Support/InviteWrapService.swift` — wrap della family key con il `secret` veicolato nel QR invito.
- `Support/SharedFamilyKey.swift` — **mirror dedicato** della family key nel keychain group `*.kidbox.shared` (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, NO iCloud sync) per AutoFill extension.
- `Support/InviteCodeGenerator.swift`, `OtpKeychainStore.swift`, `TOTPCodeGenerator.swift`, `WatchOtpSyncService.swift`.
- `Data/Remote/Note/NoteCryptoService.swift` — wrapper string → base64 (delega a `DocumentCryptoService.encrypt`).
- `Data/Remote/Wallet/WalletCryptoService.swift` — wrapper string + helper PDF (`encryptPDF/decryptPDF`).
- `Data/MasterKeyMigration.swift` — migrazione storica della master key.

**Cosa è cifrato → cosa è in chiaro**:

| Modulo | Cifrato | In chiaro su Firestore/Storage |
|---|---|---|
| Documenti | Blob Storage AES-GCM | title, fileName, mimeType, fileSize, storagePath, downloadURL, **extractedText**, visibilityScope, createdBy/updatedBy |
| Note | `titleEnc/bodyEnc` | autore, visibilità, timestamp |
| Wallet | `titleEnc/locationEnc/seatEnc/bookingCodeEnc/notesEnc/barcodeTextEnc/fileNameEnc` + PDF Storage | `kindRaw, emitter, eventDate, pdfStorageURL, barcodeFormat` (per icone/ricerca server-side) |
| Password | Tutti i `*Cipher: Data` AES-GCM | `groupId, iconURL, expiresAt, pwnedCount, isFavorite` |
| Chat | `textEnc` | metadata + **media plaintext** su `families/{familyId}/chat/...` |

### 8.7 Notifiche push (FCM + locali)

- `App/Notification/NotificationManager.swift` (~1022 righe) — `@MainActor final class NotificationManager: NSObject, ObservableObject`, singleton `.shared`. `@Published authorizationStatus: UNAuthorizationStatus`, `@Published pendingDeepLink: DeepLink?`.
- Osserva `Auth.auth().addStateDidChangeListener` e su cambio uid: `deleteCurrentFCMToken` + `requestFCMToken` + `persistFCMToken` su `users/{uid}/fcmTokens/{token}`.
- `handleNotificationUserInfo(_ userInfo:)` parsifica `type` e setta `pendingDeepLink`.
- `App/Notification/BadgeManager.swift` — gestione badge applicazione con listener Firestore su `families/{fid}/counters/{uid}`.
- `App/Notification/CountersService.swift` — reset contatori per chat/notifiche.
- `App/Notification/KidBoxLocalNotificationsCleanup.swift` — pulizia notifiche locali su sign out / leave.

### 8.8 Servizi AI (`App/AI Core/`)

- `AIService.swift` — dispatcher OpenAI/Anthropic + prompt building + summarisation conversazioni (`KBAIConversation.summary`).
- `AIAskAIPayload.swift` — payload per "Chiedi all'esperto".
- `AISettings.swift`, `AIUsageStore.swift`.
- `AIChatBubbleView.swift`, `AIChatMessageListView.swift`, `AIChatMarkdownPlainText.swift`.
- Sotto-cartelle: `AIChatExams/`, `AIChatVisits/`, `AIChatHealth/`.
- `AIConsentSheet.swift`.
- `Kbsaveclassifier.swift` — classifier locale per categorizzare i fatti da salvare in `KBMemoryFact`.

#### Chat AI Salute — costruzione contesto (`AIChatHealth/`)

- **`HealthAIChatViewModel.swift`** — ViewModel principale della chat. In `rebuildHealthSystemPrompts()`:
  1. Carica lo snapshot Apple Health persistito: `KBHealthLinkStore.load(childId: subjectId)` (nil se non collegato).
  2. Chiama `HealthContextBuilder.buildSystemPrompt(…, healthSnapshot:, visitsForWearableContext:)` per entrambi i prompt (standard con referti troncati, full con referti completi).
  3. Gestisce la **compattazione** (`compactIfNeeded`, soglia 60% del limite giornaliero): azzera `conversation.messages`, inserisce un messaggio di summary e aggiorna `conversation.summary`.
- **`Features/Health/Home/HealthContextBuilder.swift`** — assembla il system prompt AI. Sezioni: istruzioni role, profilo, cure attive (+ referti), vaccini, visite (+ referti), esami (+ referti). Se `healthSnapshot != nil` appende la sezione wearable via `ClinicalRecordAppleHealthNarrative.appendToPrompt` — **sia per `healthChat` che per `clinicalRecord`** (il guard era solo su `clinicalRecord`: rimosso).
- **`Features/Health/ClinicalRecord/ClinicalRecordAppleHealthNarrative.swift`** — narrativa wearable (FC a riposo, VO₂ max, passi, workout, ECG) condivisa tra chat salute e cartella clinica PDF.
- **`Support/Health/KBHealthLinkStore.swift`** — carica/salva `KBHealthImportSnapshot` su `UserDefaults` per `childId`. Usato da `HealthAIChatViewModel` (chat) e da `ClinicalRecordGenerator` (PDF).

### 8.8-bis Sistema messaggi / token AI

KidBox astrae i token Anthropic dietro un'unità chiamata **"messaggio"**. L'utente vede un budget giornaliero (Pro 30, Max 100, Free 0); il server traduce ogni richiesta in N unità e le scala dal contatore famiglia.

**Token Anthropic → unità KidBox**

Le unità **non** si basano sui token reali ma sulla **dimensione del payload in caratteri** (`AIAskAIPayload`, `App/AI Core/AIAskAIPayload.swift`):

| Costante | Valore | Significato |
|---|---|---|
| `standardChars` | 50.000 | 1 unità messaggio = 50k caratteri di payload (system + storico + nuovo testo) |
| `absoluteMaxChars` | 500.000 | hard limit anti-abuso: oltre → errore client e server |
| `clinicalRecordMinUnits` | 3 | minimo fisso per la cartella clinica (Sonnet ~3× Haiku, no caching) |

`messageUnits(totalChars) = max(1, ceil(totalChars / 50.000))`. Per la cartella clinica: `clinicalRecordMessageUnits = max(3, messageUnits)`.

**Flusso di conteggio**

1. **Client pre-check** (`ClinicalRecordAISynthesizer.estimatePayload`, `HealthAIChatViewModel.estimatedMessageUnits`): stima le unità *prima* dell'invio. Se superano le rimanenti → blocca con messaggio (`ClinicalRecordAIError.quotaWouldExceed`) senza chiamare il server.
2. **Server enforcement** (`functions/index.js` `askAI`): ricalcola `messageUnits` sul payload effettivo, applica il minimo cartella clinica, poi `checkAndIncrementAIUsage(familyId, uid, dailyLimit, messageUnits)` in transazione atomica su `ai_usage/family_{fid}/daily/{day}.count`. Se l'incremento supera il limite → `resource-exhausted`.
3. **Costo reale tracciato** (`ai_costs`): il server calcola il costo USD dai token Anthropic effettivi (input/cache-read/cache-write/output) e lo scrive su `ai_costs/{monthKey}` per la console admin. **Le unità ≠ il costo**: le unità sono il "prezzo" mostrato all'utente, `ai_costs` è il costo reale per te.

**Modelli per purpose** (decisi server-side):
- `clinicalRecord` → **Sonnet 4.5** (più caro, scala min 3 unità).
- `support` (`Features/Settings/Support/SupportChatViewModel.swift`, `purpose: "support"`), chat salute/visite/esami e default → **Haiku 4.5**.

**Contesto ampio & compattazione**: quando il contesto salute supera `standardChars`, l'utente può scegliere tra contesto pieno (più unità) o riassunto compatto (`HealthContextCompaction`). Vedi `AIAskAIPayload.choiceDialogMessage`. La compattazione conversazione (`compactIfNeeded`, 60% del limite) riduce lo storico per contenere le unità nei turni successivi.

> ⚠️ **Parity obbligatoria**: `standardChars` (50k), `clinicalRecordMinUnits` (3) e `absoluteMaxChars` (500k) sono duplicati in iOS (`AIAskAIPayload`), Android (`AIAskAIPayload.kt`) e server (`functions/index.js`: `AI_STANDARD_PAYLOAD_CHARS`, `CLINICAL_RECORD_MIN_UNITS`, `AI_ABSOLUTE_MAX_PAYLOAD_CHARS`). Se cambi un valore, **allinea tutti e tre** o il pre-check client diverge dal conteggio server.

### 8.9 Logging / Crash

`Support/`:

- `KBLog.swift` + `KBFileLogger.swift` — wrapper `os.Logger` con 16 categorie (`app, navigation, data, persistence, sync, home, routine, calendar, todo, auth, storage, ui, settings, crypto, security, ai`). API `KBLog.<cat>.kbDebug/kbInfo/kbWarning/kbError/kbCrash` + persistenza file in `~/Library/Application Support/KidBox/kidbox_log.txt` (500 KB rotante, retention 3 giorni). Per dati sensibili `writeToFile: false`.
- `KBCrashHandler.swift`, `CrashAnalyzer.swift` (~470 righe, parser del log file per CrashReport), `CrashReportPromptCenter.swift`.
- `KBDeviceInfo.swift`, `LocalDataWiper.swift`.

---

## 9. Dipendenze esterne (Swift Package Manager)

Estratte dalle sezioni `XCRemoteSwiftPackageReference` e `XCSwiftPackageProductDependency` di `KidBox.xcodeproj/project.pbxproj` (linee 1457-1563). **Nessuna dipendenza SPM locale (path)** né `Package.swift` nel repo: tutto è remoto via Xcode SPM.

### 9.1 Pacchetti

| Repository | Requirement | Prodotti |
|---|---|---|
| `https://github.com/firebase/firebase-ios-sdk.git` | `upToNextMajorVersion` da **12.9.0** | `FirebaseCore`, `FirebaseAuth`, `FirebaseFirestore`, `FirebaseStorage`, `FirebaseMessaging`, `FirebaseFunctions`, `FirebaseRemoteConfig` |
| `https://github.com/google/GoogleSignIn-iOS` | `upToNextMajorVersion` da **9.1.0** | `GoogleSignIn`, `GoogleSignInSwift` |
| `https://github.com/facebook/facebook-ios-sdk` | `upToNextMajorVersion` da **18.0.2** | `FacebookLogin` (+ `FBSDKCoreKit/LoginKit`) |
| `https://github.com/weichsel/ZIPFoundation` | `upToNextMajorVersion` da **0.9.20** | `ZIPFoundation` |

### 9.2 Distribuzione sui target

- Target **KidBox** (main app): tutti i Firebase + GoogleSignIn + FacebookLogin + ZIPFoundation.
- Target **KidBoxShareExtension**: solo `FirebaseAuth, FirebaseFirestore, FirebaseStorage`.
- Target **KidBoxAutoFill / KidBoxNotificationService / KidBoxControlsExtension**: nessuna SPM diretta (Foundation/UIKit/UserNotifications/AppIntents/WidgetKit). La NSE accede al keychain condiviso direttamente, non via FirebaseAuth.

### 9.3 Uso effettivo

- **`FirebaseAuth`**: pervasivo. `Auth.auth().useUserAccessGroup(accessGroup)` per condividere la sessione con la Share Extension via Keychain.
- **`FirebaseFirestore`**: tutti i `*RemoteStore`, `SyncCenter` + extension, `NotificationManager`, `FamilyBootstrapService`, `RootHostView`. Nella Share Extension: `MemoryCacheSettings()` per ridurre l'impronta.
- **`FirebaseStorage`**: tutti gli `*AttachmentService`, `AvatarRemoteStore`, `DocumentStorageService`, `ChatStorageService`, `Photoremotestore`, `WalletPDFStore`, `FamilyHeroPhotoService`.
- **`FirebaseMessaging`**: `NotificationManager`, `AppDelegate`.
- **`FirebaseFunctions`**: `AIService`, `AccountDeletionService`, `FamilyLeaveService`, `StorageUsageView/ViewModel`, `KBSubscriptionManager`, `TravelPlacesService`.
- **`FirebaseRemoteConfig`**: **collegato ma mai importato** (riserva per future feature flag).
- **`GoogleSignIn`**: `KidBoxApp` (`onOpenURL`) e `FirebaseGoogleAuthService`.
- **`FBSDKCoreKit/LoginKit`**: `KidBoxApp` + `AppDelegate` (init SDK) + `FirebaseFacebookAuthService` (login).
- **`ZIPFoundation`**: unico consumer `Data/Support/DocumentTextExtractor/MedicalDocumentTextExtractorError.swift`.

### 9.4 Framework Apple non-SPM rilevanti

`SwiftData`, `SwiftUI` + `Combine`, `PDFKit`, `HealthKit`, `AuthenticationServices`, `LocalAuthentication`, `CryptoKit`, `CoreLocation`, `MapKit`, `Contacts`, `UserNotifications`, `WidgetKit` + `AppIntents`, `StoreKit 2`, `AVFoundation`, `Vision` / `VisionKit`, `BackgroundTasks`, `OSLog`.

---

## 10. Convenzioni di codice

### 10.1 Naming modelli

- **Prefisso `KB` sistematico** per i modelli SwiftData (`KBFamily`, `KBChild`, `KBChatMessage`, `KBDocument`, ecc.). Eccezioni: `PasswordEntry`/`PasswordGroup` (per coerenza con `AuthenticationServices` `ASPasswordCredentialIdentity`), `SharedUserLocation` (DTO Codable, non `@Model`).
- **Naming non uniforme**: alcuni file Swift hanno lowercase casing difforme dalla classe contenuta (`Kbfamilyphoto.swift` → classe `KBFamilyPhoto`, `Kbexamreminderservice.swift`, `Kblocationsearchfield.swift`, `Photoremotestore.swift`, `Photoeditorview.swift`, `Cameracaptureview.swift`, `Notesremotestore.swift`, `Synccenter+photos .swift` con spazio prima dell'estensione). Incoerenza storica.
- **`@Attribute(.unique) var id: String`** per tutti i modelli SwiftData (allineamento con Firestore document id).

### 10.2 Naming View / ViewModel / Sheet / Card / Service

- **View**: suffisso `View`, `struct ...: View` SwiftUI.
- **ViewModel**: suffisso `ViewModel`, sempre `@MainActor final class ...ViewModel: ObservableObject`. 23 ViewModel totali — non tutte le View ne hanno uno.
- **Modularizzazione via extension**: `DocumentFolderViewModel` è split in 4 file (`+Merge`, `+SendToChat`, `+Share`, `+Unlock`). Stesso pattern per `SyncCenter+*`.
- **Sheet**: 21 file con suffisso `Sheet` (`MergePDFSheet`, `UnlockPDFSheet`, `FolderPickerSheet`, `ChatSaveSheet`, `LocationPickerSheet`, `AIConsentSheet`, ecc.). Presentati con `.sheet(isPresented:)` o `.sheet(item:)`.
- **Card**: 5 file con suffisso `Card` (`HomeHeroCard`, `KBSettingsCard`, `CategoryCard`, `FolderGridCard`, `DocumentGridCard`); ulteriori con `CardView` (`HomeCardView`, `InviteCardView`, `LogoutCardView`, `KBNoteCardView`).
- **Service**: 62 file con `Service` nel nome (`*RemoteStore` per Firestore, `*AttachmentService` per upload binari, `*ReminderService` per notifiche locali, `*CryptoService` per cifratura, `*BootstrapService`, `*PingService`).

### 10.3 Logging

Sistema centralizzato in `Support/KBLog.swift` + `Support/KBFileLogger.swift`:

- 16 categorie statiche (`KBLog.app`, `KBLog.sync`, `KBLog.security`, ecc.).
- `KBLoggingLogger` (`struct Sendable`) incapsula un `os.Logger` (subsystem = `Bundle.main.bundleIdentifier`).
- 5 metodi: `kbDebug`, `kbInfo`, `kbWarning`, `kbError`, `kbCrash`. Include automaticamente `#fileID`, `#function`, `#line`.
- Tutti i log scritti anche su file (`writeToFile: true` default) in `~/Library/Application Support/KidBox/kidbox_log.txt`, retention 3 giorni, max 500 KB con rotation.
- Per dati sensibili (PII, token) impostare `writeToFile: false`.

### 10.4 Code style / linter

**Assenti**: `.swiftlint.yml`, `.swift-format`, `AGENTS.md`, `.cursor/rules/`. La code style è governata implicitamente dalle convenzioni Swift Apple + abitudini del progetto.

### 10.5 `MARK:` headers e doc comments

- Uso massiccio di `// MARK: -` per organizzare i file (`AppCoordinator.swift` ha decine di marker; `KBTheme.swift` ne ha 11).
- Doc comments `///` Apple-style standard. Ogni servizio/protocollo ha un blocco docstring iniziale.
- File con header: `//  <FileName>.swift\n//  KidBox / KidBoxAutoFill / ...\n//  Created by vscocca on <data>.`.
- Commenti UI spesso in **italiano**, docstring API tecniche tendenzialmente in inglese.

### 10.6 Entitlements e capability

| File | Capability |
|---|---|
| `KidBox.entitlements` | `aps-environment = development`, `authentication-services.autofill-credential-provider`, `healthkit`, `applesignin = ["Default"]`, App Group `group.it.vittorioscocca.kidbox`, audio input, keychain groups `it.vittorioscocca.KidBox` + `it.vittorioscocca.kidbox.shared` |
| `KidBoxAutoFill.entitlements` | `autofill-credential-provider`, App Group, keychain groups condivisi |
| `KidBoxNotificationService.entitlements` | App Group, keychain group `it.vittorioscocca.KidBox` (per decifrare chat) |
| `KidBoxShareExtension.entitlements` | App Group, keychain group `it.vittorioscocca.KidBox` (per `Auth.useUserAccessGroup`) |
| `KidBoxControlsExtension.entitlements` | Solo App Group |

### 10.7 Facebook config

Tre file in `KidBox/KidBox/`:

1. `Facebook.xcconfig` (versionato): contiene `#include "Facebook.local.xcconfig"` e rimappa `FACEBOOK_APP_ID = $(FACEBOOK_APP_ID_LOCAL)` / `FACEBOOK_CLIENT_TOKEN = $(FACEBOOK_CLIENT_TOKEN_LOCAL)`. Iniettati in `Info.plist` come `$(FACEBOOK_APP_ID)` / `$(FACEBOOK_CLIENT_TOKEN)`.
2. `Facebook.local.xcconfig` (versionato con placeholder): override locale. Da modificare con i valori reali Meta e `git update-index --skip-worktree` per non committare credenziali.
3. `Facebook.local.xcconfig.example`: template di riferimento.

In CI (Xcode Cloud) `ci_scripts/ci_post_clone.sh` sovrascrive il file con i secret `FACEBOOK_APP_ID_LOCAL` / `FACEBOOK_CLIENT_TOKEN_LOCAL` del workflow.

### 10.8 File più grandi (>1000 righe)

| Righe | File | Ruolo |
|---|---|---|
| 2092 | `Features/Chat/ChatView.swift` | UI chat famiglia |
| 1892 | `Features/Chat/ChatViewModel.swift` | Logica chat (multimedia, mention, reazioni, sync, AVAudioEngine pipeline manuale) |
| 1865 | `Features/Chat/ChatBubble.swift` | Render polimorfico per 8 `KBChatMessageType` |
| 1597 | `Features/AIAgent/PlanningAIChatView.swift` | Chat AI di pianificazione |
| 1507 | `Features/Health/Visits/PediatricVisitEditView.swift` | Edit visita pediatrica |
| 1460 | `Data/Remote/Sync/SyncCenter.swift` | Orchestratore sync Firestore ↔ SwiftData |
| 1407 | `Features/Health/Treatments/TreatmentDetailView.swift` | Dettaglio terapia + dose scheduling |
| 1390 | `Features/Documents/DocumentFolderView/DocumentFolderViewModel.swift` | ViewModel root Documenti |
| 1331 | `KidBoxShareExtension/KBShareEditView.swift` | UI Share Extension |
| 1225 | `Features/Travel/TravelItineraryBuilder.swift` | Builder itinerari AI |
| 1220 | `App/Core/AppCoordinator.swift` | Source of truth navigation/auth/share/family |
| 1164 | `Features/AIAgent/PlanningContextBuilder.swift` | Contesto per CF `askAI` |
| 1022 | `App/Notification/NotificationManager.swift` | Push, FCM, deep link, preferenze |

---

## 11. Flussi utente principali

### 11.1 Login / Onboarding / Creazione famiglia

1. **Avvio**: `KidBoxApp.init()` (`App/Core/KidBoxApp.swift:27-53`) — `ModelContainerProvider.makeContainer()`, recovery quarantena, `KidBoxMigrationActor.runAll()`.
2. **Splash**: `RootHostView` mostra `LaunchScreenView` per 2.6 s.
3. **Gate**: `RootGateView.body` (`App/Root/RootGateView.swift:46`):
   - `coordinator.isCheckingAuth` → schermo arancione anti-flash.
   - `!isAuthenticated` → `LoginView` (`Features/Auth/LoginView.swift:13`).
   - Auth ok + famiglia → `HomeView`; auth ok senza famiglia → `OnboardingWalkthroughView`.
4. **Login**: `LoginView` istanzia `LoginViewModel(auth: AuthFacade(services: [Apple, Google, Facebook]))`. Tap provider → `vm.signInGoogle/Apple/Facebook(...)` → `AuthFacade.signIn(with:presentation:)`. Email gestita direttamente con `Auth.auth().signIn(withEmail:password:)`.
5. **Session listener**: `AppCoordinator.startSessionListener(modelContext:)` aggiunge `Auth.auth().addStateDidChangeListener`:
   - Se email non verificata → signOut.
   - `upsertUserProfile` (KBUserProfile SwiftData).
   - `await FamilyBootstrapService(modelContext:).bootstrapIfNeeded()` (memberships → family → children → routines → todos → events).
   - Scrive App Group: `currentUserUID`, `currentUserDisplayName`, `firebaseIDToken`, `activeFamilyId`.
   - `UserProfileRemoteSync.mergeFirestoreUserIntoLocal`, `KBSubscriptionManager.shared.loadPlan()`.
   - `AutoFillSnapshotWriter.rebuildNow(modelContext:)`.
6. **Onboarding "create"**: `MultiFamilyService.createEmptyFamily(name:)` → crea `KBFamily` + `KBFamilyMember(role: "owner")` locale, poi in `Task.detached` scrive Firestore (`families/{id}` + `members/{uid}` + `users/{uid}/memberships/{familyId}`).
7. **Onboarding "join"**: `FamilyJoinService.joinFamily(code:coordinator:)` (vedi §8.2).
8. **Post-login**: `RootHostView.startFamilyRealtimeIfPossible()` avvia 19 listener Firestore. `MasterKeyMigration.migrateAllFamilies(modelContext:)` per ogni famiglia senza chiave → recovery via `FamilyKeyEscrowService.recover` o generazione random + backup escrow.

### 11.2 Caricamento documento PDF

1. **Entry**: `DocumentFolderView` (toolbar "Carica" / "Fotocamera" / "Libreria foto"). Prima si apre `DocumentUploadView` per scegliere `visibilityScope` + `visibilityMemberIds`.
2. **View → ViewModel**: `viewModel.handleImport(_:activeChildId:)` (`DocumentFolderViewModel.swift:1348`). Per più file usa un `TaskGroup` con `AsyncSemaphore(3)` (max 3 upload paralleli).
3. **`uploadSingleFileFromURL`** (riga 829):
   - `startAccessingSecurityScopedResource()` (per file iCloud/Files).
   - **Magic-number guard**: controlla `%PDF`, `ZIP`, `OLE`, `JPEG`, `PNG` per rifiutare **placeholder iCloud non scaricati** (`DocumentFolderViewModel.swift:838-862`).
   - **Cifra** con `DocumentCryptoService.encrypt(plaintext, familyId, userId)`.
   - **Cache locale**: `DocumentLocalCache.write(...)` salva il **ciphertext** in `<Application Support>/KidBoxDocs/{familyId}/{docId}_{fileName}.kbenc` (pattern "encrypt-before-cache").
   - Crea `KBDocument` con `syncState = .pendingUpsert`, `storagePath = "families/{familyId}/documents/{documentId}/{fileName}.kbenc"`, `localPath = relPath`, applica `applyPendingUploadVisibility(...)`, salva.
   - `SyncCenter.shared.enqueueDocumentUpsert(documentId:familyId:modelContext:)`.
4. **Upload Storage**: `DocumentStorageService.upload(...)` salva in `families/{familyId}/documents/{docId}/{fileName}.kbenc` con metadata `kb_encrypted=1`, `kb_alg=AES-GCM`, `kb_orig_mime`, `kb_orig_name`. Ritorna `(storagePath, downloadURL)`.
5. **Upsert Firestore metadata**: `SyncCenter` processa il `KBSyncOp` con `processDocument(...)` → `DocumentRemoteStore.upsert(dto:)` → `setData(..., merge: true)` su `families/{familyId}/documents/{docId}` con `serverTimestamp()` per `createdAt/updatedAt`.
6. **`flushGlobal` + reload**: a fine `handleImport` chiama `SyncCenter.shared.flushGlobal(modelContext:)` e `reload()`.

**Apertura preview** (`DocumentFolderViewModel.open(_:)`):

1. `FamilyKeyEscrowService.ensureFamilyKeyAvailable`.
2. Cache HIT → `DocumentLocalCache.readEncrypted` → `DocumentCryptoService.decryptStoredKBDocumentPayload` → write a `temporaryDirectory` → `previewURL` aperto da `QuickLookPreview`.
3. Cache MISS → `downloadToLocalWithProgress(...)`: scarica ciphertext da Storage, scrive **encrypted bytes** in cache, decifra **solo per il file di preview temporaneo** (il `localPath` resta cifrato).

**Presentazione a tutto schermo + rotazione**: l'anteprima PDF/immagini in Documenti (`QuickLookPreview`) e il PDF biglietto in Wallet (`WalletPDFViewer`/PDFKit) sono presentati con **`.fullScreenCover`** (non più `.sheet`) per zoom/rotazione liberi. `QuickLookPreview` espone `onFinished` (chiamato in `previewControllerDidDismiss`) per azzerare il binding di presentazione a tutto schermo. La rotazione è abilitata solo durante l'anteprima: l'app è portrait-only su iPhone (`AppDelegate.supportedOrientations`); il modifier `.allowsAllOrientationsWhileVisible()` (`Features/Documents/Utility/AppOrientation.swift`) imposta `.allButUpsideDown` in `onAppear` e ripristina il default in `onDisappear`, forzando l'aggiornamento via `requestGeometryUpdate` (iOS 16+). `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` restituisce la maschera dinamica.

### 11.3 Chat di famiglia

1. **Entry**: route `.chat` → `ChatView` (`Features/Chat/ChatView.swift:33`). Usa `coordinator.activeFamilyId` come fonte di verità e monta `ChatConversationView(familyId:...).id(activeFamilyId)` per ricreare il VM allo switch famiglia.
2. **`ChatViewModel.init(familyId:)`** (riga 120) carica `inputText` da `UserDefaults["chatDraft_<familyId>"]`.
3. **`startListening()`** (riga 137): due listener Firestore via `ChatRemoteStore`:
   - `listenMessages(familyId:limit:150,...)` → `applyRemoteChanges` con `applyUpsert`.
   - `listenTyping(familyId:excludeUID:...)` con throttling 500 ms.
4. **`sendText()`** (riga 483):
   - Trim + `pendingMentions(in:trimmed)` → risolve menzioni `@displayName` → `[ChatMention]`.
   - Pulisce `inputText` e draft, poi `send(type:.text, text:trimmed, replyToId:replyId, mentions:mentions)`.
5. **Crypto outbound**: `RemoteChatMessageDTO` con `textEnc = NoteCryptoService.encryptString(text, familyId, userId)` (base64 AES-GCM combined). **I media chat NON vengono cifrati** (vedi `ChatStorageService.swift:26-29`: sicurezza affidata alle Storage Rules, streaming nativo non supporta AES-GCM).
6. **Upload media**: `ChatStorageService.upload(...)` su `families/{familyId}/chat/{messageId}/{fileName}`. Esempio video: `ChatViewModel.sendVideo(from:)` comprime con `AVAssetExportSession(presetName: AVAssetExportPresetMediumQuality)`.
7. **Inbound realtime** (`applyUpsert`):
   - Decifra `textEnc` con `NoteCryptoService.decryptString(...)`. Su fallimento fallback al `dto.text` plaintext invece di cancellare.
   - Marca tombstone se `dto.isDeleted == true` (deleteForEveryone) ma mantiene la riga locale per visualizzare "messaggio eliminato".
   - Se `existing.type == .audio` e non sono io → `startTranscriptIfNeeded` (trascrizione locale via `SpeechTranscriptionService`).
8. **Push notification chat**: cifratura end-to-end. La CF manda push con `mutable-content:1` e `userInfo["textEnc"]`. La `KidBoxNotificationService` decifra in-process prima di mostrare il banner (vedi §12.3).

> Nota: la chat **non passa dall'outbox `KBSyncOp`** — `ChatViewModel` chiama `remoteStore.upsert` direttamente dentro `send(...)`.

### 11.4 Sincronizzazione realtime

**Pattern listener inbound** (per ogni dominio `SyncCenter+<Dominio>.swift`):

- `start<Dominio>Realtime(familyId:modelContext:)` registra un `addSnapshotListener` (es. `families/{id}/documents` o `families/{id}/walletTickets`).
- `apply<Dominio>Inbound(changes:familyId:modelContext:)` applica LWW su `updatedAt`, soft-delete remoto → hard-delete locale, anti-resurrect su locale `pendingDelete`.
- Emette `SyncCenter.shared.emitDocsChanged(familyId)` (o equivalente) via `KBEventBus`.

**Outbox offline-first**:

1. View/VM scrive su SwiftData.
2. `SyncCenter.shared.enqueue*Upsert(...)` → `upsertOp(...)` idempotente.
3. `startAutoFlush` (ogni 30 s) o `flushGlobal(modelContext:)` manuale processa la coda.
4. `process(op:...)` instrada per `entityTypeRaw` su `process<Entità>(...)` → `*RemoteStore.upsert(...)`.
5. **Backoff esponenziale** `min(2^(attempts-1), 300) s`.

**Cambio famiglia (multi-family)**:

- `coordinator.activeFamilyId` persistito in `UserDefaults["KidBox.activeFamilyId"]` + App Group `activeFamilyId`.
- `RootHostView.onChange(of: activeFamilyId)` ferma listener vecchi e avvia quelli nuovi.
- `removePendingSyncOperations(retainingFamilyId:modelContext:)` (`SyncCenter.swift:541`): all'inizio del join elimina dall'outbox tutte le `KBSyncOp` con `familyId != retainingFamilyId` per evitare scritture su path Firestore della vecchia famiglia → **`PERMISSION_DENIED`** spuri.

**Revoca utente**:

- `handleFamilyAccessLost(familyId:source:error:)` (`SyncCenter.swift:124`) intercetta `permissionDenied`. Stop listener + `_currentUserRevoked.send(familyId)` (Combine).
- `RootHostView` ascolta `SyncCenter.shared.currentUserRevoked` e chiama `FamilyLeaveService.leaveFamily` per wipe locale + alert.
- **Soppressione race**: `isFamilyBeingCreated`/`isJoiningFamily` sopprimono `handleFamilyAccessLost` durante creazione/join.

### 11.5 Gestione note (visibilità + remote-while-editing)

1. **Entry**: route `.notesHome(familyId:)` → `NotesHomeView`; route `.noteDetail(familyId:noteId:isNewNote:)` → `NoteDetailView`. Deep link push → `AppCoordinator.openNoteFromPush` con retry-then-fetch via `SyncCenter.shared.fetchNotesOnce` (`SyncCenter+Notes.swift:238`).
2. **`NoteDetailView`** usa `@Query` per la nota corrente e i `KBFamilyMember` per il visibility picker. Stato locale: `titleText`, `bodyHTML`, `isDirty`, `pendingRemoteTitle`, `pendingRemoteBody`.
3. **`loadOrCreate()`**: se esiste legge, se nuova (deep link FAB) inserisce un `KBNote` vuoto con `syncState = .synced`.
4. **Dirty flag**: `onChange(of: titleText)` / `bodyHTML` → `isDirty = true`. Il bottone "salva" appare solo se `isDirty`.
5. **Pattern "remote-while-editing"**: `onChange(of: noteRemoteVersion)`:
   - Se `isDirty == true`: salva il remoto in `pendingRemoteTitle/Body` ma NON sovrascrive l'UI (per non perdere modifiche utente).
   - Se nessuna modifica locale: aggiorna l'UI con il remoto (LWW visivo).
6. **Save** (`commitSave()`):
   - Aggiorna `note.title/body/updatedAt/updatedBy/visibilityScope/visibilityMemberIds`, marca `syncState = .pendingUpsert`.
   - `try? modelContext.save()`.
   - `SyncCenter.shared.enqueueNoteUpsert(noteId:familyId:modelContext:)`.
   - `flushGlobal` per push immediato.
7. **`processNote`** → `NotesRemoteStore.upsert(note:)` cifra titolo+body via `NoteCryptoService.encryptString` (AES-GCM con la family key). Scrive `titleEnc/bodyEnc` + `FieldValue.delete()` sui legacy `title/body`.
8. **Inbound** (`applyNotesInbound`): decifra `dto.titleEnc/bodyEnc`. Su fallimento → `"⚠️ Nota non decifrabile"` invece di crashare. Anti-resurrect + eccezione LWW per locale vuota (deep link).

---

## 12. Decisioni architetturali rilevanti

### 12.1 SwiftData over Core Data / Realm

- **Schema unico** (45 modelli) condiviso con estensioni via App Group `group.it.vittorioscocca.kidbox` + replica CloudKit privata (`cloudKitDatabase: .automatic`).
- **Quarantena store corrotto** (`probeStoreIntegrity` + `quarantinePersistentStoreArtifacts`): se il container fallisce con `NSCocoaErrorDomain 134110` (mandatory destination attribute, errore tipico durante migrazione lightweight), sposta `default.store`/`-wal`/`-shm` con suffisso `.bak.<timestamp>` e ricrea il container. Trigger automatico di `FamilyBootstrapService.bootstrapIfNeeded()` + `flushGlobal` per ripristinare i dati da Firestore senza reinstall.
- **Niente versioning formale**: niente `SchemaMigrationPlan`/`VersionedSchema`. Strategia "campi opzionali + default inline" + `@ModelActor KidBoxMigrationActor` per backfill ad-hoc.

### 12.2 Cifratura lato client (E2E per famiglia)

- KidBox dichiara `ITSAppUsesNonExemptEncryption=false` (`Info.plist`) ma cifra comunque i payload sensibili: il backend Firestore/Storage vede solo ciphertext.
- **Chiave per (famiglia, utente)**: `kidbox.family.masterkey.{userId}.{familyId}` in iCloud Keychain (`kSecAttrSynchronizable=true`, `kSecAttrAccessibleAfterFirstUnlock`). Razionale: un dispositivo con due Apple ID ha due chiavi distinte per la stessa famiglia, evitando conflitti.
- **Escrow su Firestore**: la chiave è wrappata con una **escrow key derivata deterministicamente** da HKDF-SHA256 con IKM = SHA-256(`{userId}:{familyId}:{escrowContext}`). Recovery solo con Firebase UID → security rules limitano a `request.auth.uid == userId`. Permette recovery dopo reinstall / cambio account / iCloud Keychain disattivato.
- **Backward compatibility**: `decryptStoredKBDocumentPayload` riconosce 3 casi (path `/chat/` plain, AES-GCM combined valido, fallback magic bytes per blob legacy salvati in chiaro).

### 12.3 Mirror dedicato per AutoFill (Keychain group separato)

L'extension `KidBoxAutoFill` non può importare Firebase / SwiftData (sandbox + processo isolato), quindi:

- L'app principale scrive uno **snapshot AutoFill cifrato** in App Group via `AutoFillSnapshotWriter.rebuild` (`App/Core/AutoFillSnapshotWriter.swift:33-74`).
- La family key è mirrorata in un **keychain group dedicato** (`*.kidbox.shared`) come `SharedFamilyKey` (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, **NO iCloud sync**) — separato dal Keychain principale (sync ON) per ridurre la superficie di attacco dell'extension.
- L'extension legge solo questo item + lo snapshot per decifrare runtime.

### 12.4 Encrypt-before-cache per documenti

La cache locale (`DocumentLocalCache`) contiene **solo ciphertext**. La preview Quick Look usa file decrittato in `FileManager.default.temporaryDirectory` non persistente.

Razionale: se conservassimo il plaintext, ogni backup iCloud / Spotlight / Handoff esfiltrerebbe dati sensibili. Avere solo ciphertext locale + file temporanei per preview garantisce che `localPath` sia sempre cifrato come la copia su Storage.

### 12.5 Magic-number guard sugli upload

In `DocumentFolderViewModel.uploadSingleFileFromURL` (`:838-862`): si controllano i primi byte (`%PDF`, `ZIP`, `OLE`, `JPEG`, `PNG`) per **rifiutare placeholder iCloud non scaricati**. La Share Extension può consegnare 198 byte di placeholder che verrebbero cifrati e caricati come "file".

### 12.6 Decifratura inline nella push (Notification Service Extension)

`KidBoxNotificationService/NotificationService.swift` (~169 righe) decifra inline i payload chat (`textEnc` AES-GCM) prima della consegna:

1. Legge `textEnc` + `familyId` dal payload.
2. Legge `currentUserUID` dall'App Group.
3. `NoteCryptoService.decryptString(textEnc, familyId, userId)` decifra in-process (chiave dal Keychain condiviso via `FamilyKeychainStore`).
4. Sostituisce `bestAttemptContent.body` con il plaintext (truncato a 180 char).
5. Per `chat_mention` prefissa il titolo: "{senderName} ti ha menzionato".

**Fallback**: se la chiave manca o il decrypt fallisce → `applyFallback` usa `userInfo["fallbackBody"]` precomputato dalla Cloud Function. Limite 30 s gestito da `serviceExtensionTimeWillExpire`.

### 12.7 Direct write parallelo

Pattern in `DocumentFolderViewModel.moveDocument/copyDocument/copyFolder/moveFolder`: oltre a inserire `KBSyncOp` e fare `flushGlobal`, scrive **anche direttamente** a Firestore in `Task.detached(priority: .userInitiated)`. Razionale: garantire sync immediato sull'altro account senza aspettare il loop dell'outbox (che è per la persistenza offline-first).

### 12.8 Audio recording manuale via AVAudioConverter

In `ChatViewModel` (commenti riga 96-110): pipeline `AVAudioEngine` + `AVAudioConverter` manuale per aggirare un bug noto di `AVAssetExportSession` in iOS 26 beta su A15 che produce M4A da ~1600 byte silenzioso.

### 12.9 Throttling foreground maintenance

`lastForegroundMaintenanceAt` in `KidBoxApp.body` (riga 357-401): le manutenzioni heavy (riordino notifiche treatment, `HousePaymentReminderService.rescheduleAllActive`) girano max ogni 120 s per non riordinare le 100+ notifiche treatment ad ogni return-to-foreground.

### 12.10 Singleton come scelta architetturale

L'app fa uso estensivo di singleton (`SyncCenter.shared`, `NotificationManager.shared`, `BadgeManager.shared`, `KBSubscriptionManager.shared`, `KBEventBus.shared`, `AISettings.shared`, ...). Scelta deliberata che semplifica l'accesso ai service "cross-cutting" ma riduce la testability. L'unico vero protocollo di astrazione attivo è `AuthService`.

### 12.11 Localizzazione hardcoded in italiano

I file `Localizable.strings` sono **minimali** (solo 6 chiavi `passwords.group.*` per categorie password). La gran parte dei testi UI è hardcoded in italiano nei sorgenti Swift (es. `String("Solo io")`, alert "Famiglia non trovata", `KBVisibilityScope.chipLabel`, `AIService.errorDescription`). Le 5 lingue (`it`, `en`, `en-GB`, `es`, `zh-Hans`) servono principalmente per la metadata App Store.

---

## 13. Estensioni di target

### 13.1 KidBoxAutoFill — Credential Provider Extension

- **Bundle ID**: `it.vittorioscocca.KidBox.KidBoxAutoFill`.
- **Capability** (`Info.plist:25-37`): `ASCredentialProviderExtensionCapabilities` con `ProvidesPasswords=true`, `ProvidesOneTimeCodes=true` (iOS 18+), `ShowsConfigurationUI=true`.
- **Entry point**: `CredentialProviderViewController` (`CredentialProviderViewController.swift:11`, ~520 righe), eredita da `ASCredentialProviderViewController`.
- **API**:
  - `prepareInterfaceForExtensionConfiguration` → onboarding "Apri KidBox per accedere".
  - `prepareCredentialList(for:)` → lista password filtrate per host.
  - `provideCredentialWithoutUserInteraction` → QuickType silenzioso.
  - `prepareInterfaceToProvideCredential` → QuickType con Face ID (`LAContext` con `.deviceOwnerAuthentication`, reason "Sblocca KidBox per AutoFill").
  - `prepareOneTimeCodeCredentialList` (iOS 18+) → TOTP via `TOTPCodeGenerator.currentCode(secretBase32:digits:period:algorithm:)`.
- **Architettura non-Firebase**: NON importa Firebase né SwiftData. Legge solo `SharedFamilyKey.loadMirroredFamilyKey()` (keychain group `*.kidbox.shared`) e `AutoFillSnapshotFileStore.loadDecrypted(using:)` (file cifrato in App Group, scritto dall'app principale).

### 13.2 KidBoxControlsExtension — Control Widget (iOS 18+)

- **Bundle ID**: `it.vittorioscocca.KidBox.KidBoxControlsExtension`.
- **Entry point**: `@main struct KidBoxControlsExtensionBundle: WidgetBundle` (`KidBoxControlsExtensionBundle.swift:9`).
- **Capability**: un singolo `ControlWidgetButton` che esegue `OpenKidBoxFamilyPhotosCameraIntent()` (`AppIntent` con `openAppWhenRun=true`).
- **Handoff App Group**: l'intent scrive `kidbox.controlWidget.pendingRoute = "openFamilyPhotosCamera"`, consumato dall'app via `AppCoordinator.consumePendingControlWidgetRouteIfNeeded(modelContext:)`. Razionale: `OpenURLIntent` accetta solo universal link, non scheme `kidbox://`.

### 13.3 KidBoxNotificationService — Notification Service Extension

Vedi §12.6 per il flusso di decifratura inline. Bundle ID `it.vittorioscocca.KidBox.KidBoxNotificationService`. Entitlements: App Group + keychain group `it.vittorioscocca.KidBox` (per `FamilyKeychainStore`).

### 13.4 KidBoxShareExtension — Share Sheet

- **Bundle ID**: `it.vittorioscocca.KidBox.KidBoxShareExtension`.
- **Activation rules** (`Info.plist:11-23`): `Image≤10`, `Movie≤10`, `WebURL≤1`, `Text=true`, `File≤10`.
- **Entry point**: `ShareViewController` (`ShareViewController.swift:15`, ~315 righe).
- **Capability**: accetta foto, video (priorità su `UTType.movie` per non scambiare WhatsApp video per documenti), file (con detection UTI→ext, `loadFileURL` riga 148-280), URL web, plain text.
- **Auth condivisa**: `Auth.auth().useUserAccessGroup(KEYCHAIN_ACCESS_GROUP)`.
- **Firebase init**: `FirebaseApp.configure()` con `FirestoreSettings().cacheSettings = MemoryCacheSettings()` (niente cache su disco).
- **AI classification**: `KBSharePayload.classify()` (`KBShareSheet.swift:79`) usa Apple Intelligence per suggerire destinazioni (chat, todo, event, grocery, note, document, encryptedMedia, wallet).
- **Handoff app principale**: invece di `extensionContext.open` (che restituisce sempre `false` dalle Share Extensions), risale il responder chain fino a `UIApplication` e chiama `app.open(url, options:)` con scheme `kidbox://share`. L'app consuma `pendingShare` dall'App Group via `AppCoordinator.handleIncomingShare(modelContext:)`.
- **File**: `ShareViewController.swift`, `KBShareSheet.swift`, `KBShareEditView.swift` (~1331 righe), `KBShareModels.swift`, `Notesremotestore.swift`.

### 13.5 KidBoxWidget — placeholder

Cartella minima (solo `Assets.xcassets` con `AccentColor`, `AppIcon`, `WidgetBackground`). **Nessun sorgente Swift attivo**: il bundle Widget è attualmente vuoto/dummy (placeholder per sviluppo futuro di widget Home Screen).

---

## Appendice — Riferimenti rapidi

| Cosa | Dove |
|---|---|
| Entry point app | `App/Core/KidBoxApp.swift` (`@main`) |
| Coordinator globale | `App/Core/AppCoordinator.swift` |
| AppDelegate (Firebase, FCM, APNs, BGTask) | `App/Core/AppDelegate.swift` |
| Routes | `App/Root/Route.swift` |
| NavigationStack root | `App/Root/RootHostView.swift` |
| Gate auth/onboarding | `App/Root/RootGateView.swift` |
| Schema SwiftData | `Data/Persistence/ModelContainerProvider.swift:129-177` |
| Migrazioni dati | `Data/Persistence/KidBoxMigrations.swift` |
| Cache documenti locale | `Data/Persistence/DocumentLocalCache.swift` |
| Outbox sync | `Data/Remote/Sync/SyncCenter.swift` (+22 extension) |
| Outbox model | `Data/Remote/Sync/KBSyncOp.swift`, `KBSyncState.swift`, `SyncEntityType.swift` |
| Crypto core documenti | `Data/Remote/DocumentStore/DocumentCryptoService.swift` |
| Crypto note | `Data/Remote/Note/NoteCryptoService.swift` |
| Crypto wallet | `Data/Remote/Wallet/WalletCryptoService.swift` |
| Keychain famiglia | `Support/FamilyKeychainStore.swift` |
| Escrow chiavi | `Support/FamilyKeyEscrowService.swift` |
| Mirror AutoFill key | `Support/SharedFamilyKey.swift` |
| Auth facade | `Data/Auth/AuthFacade.swift` |
| Family bootstrap | `Domain/FamilyBootstrapService.swift` |
| Family join | `Data/Repositories/FamilyJoinService.swift` |
| Notifiche / deep link | `App/Notification/NotificationManager.swift` |
| Badge | `App/Notification/BadgeManager.swift` |
| Logging | `Support/KBLog.swift` + `KBFileLogger.swift` |
| Wipe locale | `Support/LocalDataWiper.swift` |
| Visibilità record | `Support/KBVisibilityScope.swift` |
| AI dispatcher | `App/AI Core/AIService.swift` |
| Subscription manager | `Features/Subscription/KBSubscriptionManager.swift` |
| Bootstrap Firebase | `Support/Firebase/FirebaseBootstrap.swift` + `GoogleService-Info.plist` |
