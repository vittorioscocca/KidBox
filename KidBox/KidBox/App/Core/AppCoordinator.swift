//
//  AppCoordinator.swift
//  KidBox
// vscocc

import SwiftUI
import Combine
import OSLog
import FirebaseAuth
import FirebaseFirestore
import SwiftData

/// Central coordinator responsible for navigation and flow control.
///
/// `AppCoordinator` owns the navigation `path` and decides which screen should be
/// presented based on the current application state (authentication, onboarding, etc.).
///
/// Design goals:
/// - Views and ViewModels **must not** perform navigation directly.
/// - All routing decisions go through the coordinator to keep flows consistent.
/// - Keeps state changes (auth/login/logout) in one place.
///
/// Logging:
/// - Uses `KBLog` (OSLog) and the `kb*` helpers to automatically include file/function/line.
/// - Avoid logging PII. Prefer `.private` for user-generated fields.
@MainActor
final class AppCoordinator: ObservableObject {
    
    // MARK: - Navigation
    
    /// Current navigation path for the app's `NavigationStack`.
    @Published var path: [Route] = [] {
        didSet {
            trackScreenViewIfNeeded()
        }
    }

    /// Ultimo `screen_name` inviato a GA4, per evitare fire duplicati su path invariato.
    private var lastFiredScreenName: String?

    // MARK: - Session state
    
    /// Whether there is a currently authenticated Firebase user.
    @Published private(set) var isAuthenticated: Bool = false
    
    /// True finché Firebase non ha risposto con lo stato auth iniziale.
    /// Evita il flash della login screen all'avvio quando l'utente è già loggato.
    @Published private(set) var isCheckingAuth: Bool = true
    
    // MARK: - Onboarding
    
    private static let onboardingKey = "hasSeenOnboarding"
    
    /// true se l'utente ha già completato il walkthrough di benvenuto.
    @Published var hasSeenOnboarding: Bool =
    UserDefaults.standard.bool(forKey: AppCoordinator.onboardingKey)

    /// True mentre l'utente è nel percorso "crea famiglia" dell'onboarding e non ha ancora
    /// finito la pagina di invito (QR). Impedisce a `RootGateView` di completare l'onboarding
    /// automaticamente non appena la `KBFamily` appena creata compare in SwiftData — cosa che
    /// altrimenti farebbe saltare la pagina del QR mandando l'utente dritto in Home.
    /// In-memory only: si azzera al riavvio (recupero desiderato) e in `completeOnboarding()`.
    @Published var isCreatingFamilyInOnboarding = false

    /// Nome dell'ultimo step di onboarding mostrato, usato per capire se il
    /// wizard è ancora aperto quando l'app va in background (onboarding_abandoned).
    @Published var lastOnboardingStepSeen: String?

    /// Timestamp d'apertura del wizard, per calcolare la durata di onboarding_completed.
    var onboardingStartedAt: Date?

    /// Cached Firebase UID of the current user (if authenticated).
    @Published private(set) var uid: String?
    
    /// Document id pending to be opened once the UI is ready (e.g. after a push notification).
    @Published var pendingOpenDocumentId: String? = nil
    
    /// Control Widget iOS / URL `kidbox://control/...` → aprire fotocamera in **Foto e video** per questo `familyId`.
    @Published var openFamilyPhotosCameraForFamilyId: String? = nil
    
    
    @Published var pendingShareText: String? = nil
    
    /// Path locale di un'immagine/file copiata nell'App Group, da inviare in chat.
    @Published var pendingShareImagePath: String? = nil
    
    @Published var pendingShareVideoPath: String? = nil
    @Published var pendingShareEventDraft: PendingShareEventDraft? = nil
    @Published var pendingShareTodoDraft: PendingShareTodoDraft? = nil
    @Published var pendingShareMediaCaption: String? = nil
    
    /// Path locale (App Group) di una foto/video condivisi verso Foto e video crittografati.
    @Published var pendingShareEncryptedMediaPath: String? = nil
    /// "image" | "file" (video). Letto da FamilyPhotosView insieme a pendingShareEncryptedMediaPath.
    @Published var pendingShareEncryptedMediaType: String? = nil
    
    /// Path locale (App Group) di un documento condiviso verso la sezione Documenti.
    @Published var pendingShareDocumentPath: String? = nil
    /// Nome originale del file documento condiviso.
    @Published var pendingShareDocumentTitle: String? = nil

    /// Path locale (App Group) di un PDF condiviso verso il Wallet.
    /// Consumato da `WalletHomeView` per pre-aprire la sheet di import.
    @Published var pendingShareWalletPDFPath: String? = nil
    /// Titolo o filename suggerito per il ticket Wallet importato dalla share extension.
    @Published var pendingShareWalletTitle: String? = nil
    @Published var globalBannerMessage: String? = nil

    /// Testo dello spinner mostrato mentre si aspetta che la risorsa di una
    /// notifica arrivi dalla sincronizzazione; `nil` quando non si aspetta
    /// nulla. Senza un segnale visibile l'utente resta fermo sulla panoramica
    /// senza capire che sta per succedere qualcosa. Gemello del Dialog di
    /// attesa in `AppNavGraph` su Android.
    @Published var deepLinkLoadingMessage: String? = nil

    /// Attesa in corso di una risorsa da notifica, per poterla annullare
    /// quando l'utente tocca fuori dallo spinner.
    private var deepLinkResolutionTask: Task<Void, Never>?

    /// L'utente ha rinunciato ad aspettare la risorsa della notifica.
    @MainActor
    func cancelDeepLinkResolution() {
        KBLog.navigation.kbInfo("[push] attesa risorsa annullata dall'utente")
        deepLinkResolutionTask?.cancel()
        deepLinkResolutionTask = nil
        deepLinkLoadingMessage = nil
    }
    
    /// URL temporaneo decriptato di un documento da inviare in chat.
    /// Impostato da DocumentFolderViewModel.sendToChat, consumato da ChatView.
    @Published var pendingChatDocumentURL: URL? = nil

    /// ID del messaggio chat da evidenziare allo scroll, impostato da una notifica di menzione.
    /// Consumato da ChatView all'apertura.
    @Published var pendingChatMentionMessageId: String? = nil
    
    // MARK: - Appearance
    
    /// Preferenza tema dell'app (Chiaro / Scuro / Sistema).
    /// Letta dalla root dell'app per applicare `.preferredColorScheme`.
    /// Persistita in `UserDefaults` con chiave `kb_appearanceMode`.
    @Published private(set) var appearanceMode: AppearanceMode = .system
    
    private static let appearanceModeKey = "kb_appearanceMode"
    
    // MARK: - Active family
    
    /// The explicitly selected active family ID.
    ///
    /// This is the source of truth for which family is currently displayed.
    /// It takes priority over any implicit ordering (e.g. updatedAt DESC).
    ///
    /// Persisted in UserDefaults so it survives app restarts.
    /// Set explicitly after a join or family switch.
    /// Cleared on sign-out.
    @Published private(set) var activeFamilyId: String? {
        didSet {
            KBSubscriptionManager.shared.currentFamilyId = activeFamilyId
            if let id = activeFamilyId {
                UserDefaults.standard.set(id, forKey: Self.activeFamilyIdKey)
                KBLog.sync.kbInfo("activeFamilyId persisted familyId=\(id)")
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeFamilyIdKey)
                KBLog.sync.kbInfo("activeFamilyId cleared")
            }
        }
    }
    
    private static let activeFamilyIdKey = "KidBox.activeFamilyId"
    
    /// Incrementato in `resetToRoot()` quando c’è una famiglia attiva, così `RootHostView` può
    /// forzare il riavvio dei listener / il ricalcolo senza restare agganciati a una sessione precedente.
    @Published private(set) var rootDataRefreshToken: UInt64 = 0
    
    // MARK: - Private
    
    /// Firebase Auth listener handle. Non-nil when the session listener is active.
    private var authHandle: AuthStateDidChangeListenerHandle?
    
    struct PendingShareEventDraft: Identifiable {
        let id = UUID()
        let title: String
        let notes: String
        let startDate: Date?
        let targetFamilyId: String
    }
    
    struct PendingShareTodoDraft: Identifiable {
        let id = UUID()
        let title: String
    }
    
    // MARK: - Init
    
    init() {
        // Restore persisted active family from previous session.
        activeFamilyId = UserDefaults.standard.string(forKey: Self.activeFamilyIdKey)
        KBSubscriptionManager.shared.currentFamilyId = activeFamilyId
        if let id = activeFamilyId {
            KBLog.sync.kbInfo("activeFamilyId restored from UserDefaults familyId=\(id)")
            let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
            sharedDefaults?.set(id, forKey: "activeFamilyId")
        }
        
        // Restore persisted appearance mode.
        let rawAppearance = UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? AppearanceMode.system.rawValue
        appearanceMode = AppearanceMode(rawValue: rawAppearance) ?? .system
        KBLog.settings.kbDebug("AppCoordinator init appearanceMode=\(rawAppearance)")
        KBLog.navigation.kbInfo("hasSeenOnboarding = \(UserDefaults.standard.bool(forKey: "hasSeenOnboarding"))")

        lastFiredScreenName = "home"
        AppAnalytics.screenView(name: "home")
    }
    
    // MARK: - Appearance management
    
    /// Aggiorna il tema e lo persiste in UserDefaults.
    /// Chiamato da `SettingsViewModel.setAppearanceMode(_:coordinator:)`.
    func setAppearanceMode(_ mode: AppearanceMode) {
        guard appearanceMode != mode else { return }
        KBLog.settings.kbInfo("AppCoordinator setAppearanceMode mode=\(mode.rawValue)")
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.appearanceModeKey)
    }
    
    
    func completeOnboarding() {
        isCreatingFamilyInOnboarding = false
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        hasSeenOnboarding = true
        KBLog.navigation.kbInfo("Onboarding completed")

        let duration = onboardingStartedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        AppAnalytics.onboardingCompleted(totalDurationSeconds: duration)
        lastOnboardingStepSeen = nil
        onboardingStartedAt = nil
    }
    
    // MARK: - Active family management

    /// Sottoscrizione Combine usata da `switchFamilyIfNeededThenNavigate(to:action:)`
    /// per attendere il primo cambio di `rootDataRefreshToken` dopo lo switch famiglia.
    private var familySwitchWaitCancellable: AnyCancellable?

    /// Sets the active family explicitly (e.g. after join or user-initiated family switch).
    ///
    /// - Parameter familyId: The family to make active. Pass `nil` to clear.
    /// - Parameter force: Se `true`, riapplica persistenza e notifica le view anche quando
    ///   `familyId` è già uguale a `activeFamilyId` (es. dopo join + bootstrap) così
    ///   `RootHostView` e i listener si riallineano invece di fare no-op.
    ///
    /// Cambi di `familyId` (switch famiglia) aggiornano sempre UserDefaults e App Group; stesso id con
    /// `force: true` riesegue la persistenza e `objectWillChange` per risvegliare la UI.
    func setActiveFamily(_ familyId: String?, force: Bool = false) {
        if !force && activeFamilyId == familyId {
            KBLog.sync.kbDebug("setActiveFamily no-op familyId=\(familyId ?? "nil")")
            return
        }
        
        if force, activeFamilyId == familyId {
            KBLog.sync.kbInfo("setActiveFamily force refresh familyId=\(familyId ?? "nil")")
            if let id = familyId {
                UserDefaults.standard.set(id, forKey: Self.activeFamilyIdKey)
                UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.set(id, forKey: "activeFamilyId")
            } else {
                UserDefaults.standard.removeObject(forKey: Self.activeFamilyIdKey)
                UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.removeObject(forKey: "activeFamilyId")
            }
            objectWillChange.send()
            return
        }
        
        KBLog.sync.kbInfo("setActiveFamily familyId=\(familyId ?? "nil")")
        activeFamilyId = familyId
        let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
        if let id = familyId {
            sharedDefaults?.set(id, forKey: "activeFamilyId")
        } else {
            sharedDefaults?.removeObject(forKey: "activeFamilyId")
        }
    }

    // MARK: - Deep link family switch

    /// Esegue lo switch alla famiglia indicata se diversa da quella attiva,
    /// attende il rebuild della root (`rootDataRefreshToken` cambia) e quindi
    /// invoca `action`. Se la famiglia è già attiva, esegue `action` subito.
    ///
    /// Pensato per i deep link da notifiche push multi-famiglia:
    /// `setActiveFamily(.., force: true)` triggera `resetToRoot()` che azzera
    /// il `path` e ricostruisce `RootHostView`; qualsiasi `navigate(to:)`
    /// emesso prima del rebuild verrebbe scartato. Aspettiamo il bump del
    /// token e diamo a SwiftUI un breve frame per montare i nuovi listener.
    func switchFamilyIfNeededThenNavigate(
        to familyId: String,
        action: @escaping () -> Void,
    ) {
        if activeFamilyId == familyId {
            KBLog.navigation.kbDebug("[DeepLink] family already active familyId=\(familyId), navigate immediately")
            action()
            return
        }

        let previousFamilyId = activeFamilyId ?? "nil"
        let currentToken = rootDataRefreshToken
        KBLog.navigation.kbInfo("[DeepLink] family switch required: \(previousFamilyId) → \(familyId), waiting for root rebuild")

        familySwitchWaitCancellable?.cancel()
        familySwitchWaitCancellable = $rootDataRefreshToken
            .dropFirst()
            .filter { $0 != currentToken }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                KBLog.navigation.kbInfo("[DeepLink] root rebuilt, executing deep link action familyId=\(familyId)")
                self.familySwitchWaitCancellable?.cancel()
                self.familySwitchWaitCancellable = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    action()
                }
            }

        setActiveFamily(familyId, force: true)
        // `force: true` con stesso id passa dal ramo veloce: in quel caso il token
        // non cambia, quindi ricaviamo manualmente il bump tramite resetToRoot().
        if rootDataRefreshToken == currentToken {
            resetToRoot()
        }
    }

    // MARK: - Session listener
    
    /// Starts the FirebaseAuth session listener.
    ///
    /// - Important:
    ///   This must be called once (idempotent) early in app lifecycle.
    ///   It updates `isAuthenticated/uid`, upserts the local user profile,
    ///   and triggers the family bootstrap when a user becomes available.
    ///
    /// - Parameter modelContext: SwiftData context used for profile upsert and bootstrap.
    func startSessionListener(modelContext: ModelContext) {
        guard authHandle == nil else {
            KBLog.auth.kbDebug("startSessionListener ignored (already started)")
            return
        }
        
        KBLog.auth.kbInfo("Starting FirebaseAuth state listener")
        
        authHandle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                self.isCheckingAuth = false
                if let user {
                    let isEmailProvider = user.providerData.contains { $0.providerID == "password" }
                    if isEmailProvider && !user.isEmailVerified {
                        KBLog.auth.kbInfo("Email not verified for uid=\(user.uid) — signing out")
                        await KidBoxLocalNotificationsCleanup.cancelAllScheduledAccountReminders()
                        try? Auth.auth().signOut()
                        KBSubscriptionManager.shared.resetOnSignOut()
                        self.isAuthenticated = false
                        self.uid = nil
                        return
                    }
                    self.isAuthenticated = true
                    self.uid = user.uid
                    
                    KBLog.auth.kbInfo("Auth state changed: logged in uid=\(user.uid)")
                    
                    self.upsertUserProfile(from: user, modelContext: modelContext)

                    try? await Firestore.firestore().collection("users").document(user.uid)
                        .setData(["platform": "ios"], merge: true)

                    KBLog.sync.kbDebug("Calling FamilyBootstrapService.bootstrapIfNeeded")
                    await FamilyBootstrapService(modelContext: modelContext).bootstrapIfNeeded()
                    
                    // ── Prefetch piano + storage per il gate upload ───────────
                    // Fatto in background dopo il bootstrap: popola
                    // KBStorageGate.cachedUsedBytes e il piano abbonamento
                    // così tutti i gate sono operativi prima del primo upload.
                    let gateFamilyId = self.activeFamilyId ?? {
                        let desc = FetchDescriptor<KBFamily>(
                            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                        )
                        return (try? modelContext.fetch(desc).first)?.id ?? ""
                    }()
                    Task.detached(priority: .utility) {
                        await StorageUsageViewModel.prefetchForGate(familyId: gateFamilyId)
                    }
                    
                    let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
                    sharedDefaults?.set(user.uid, forKey: "currentUserUID")
                    // Salva il Firebase ID token per la NotificationServiceExtension
                    user.getIDToken { token, error in
                        guard let token, error == nil else { return }
                        UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                            .set(token, forKey: "firebaseIDToken")
                    }
                    sharedDefaults?.set(
                        user.displayName ?? user.email ?? "Utente",
                        forKey: "currentUserDisplayName"
                    )
                    
                    // ── Onboarding gate ──────────────────────────────────────────
                    // Utenti esistenti (già con famiglia) → salta il walkthrough
                    // Utenti nuovi (nessuna famiglia ancora) → mostreranno il walkthrough
                    // tramite RootGateView che legge hasSeenOnboarding
                    if !self.hasSeenOnboarding {
                        let familyDescriptor = FetchDescriptor<KBFamily>()
                        let hasFamily = ((try? modelContext.fetch(familyDescriptor)) ?? []).isEmpty == false
                        if hasFamily {
                            // Utente esistente aggiornato all'app con onboarding → skip
                            self.completeOnboarding()
                            KBLog.navigation.kbInfo("Onboarding skipped: existing user with family")
                        }
                        // Se non ha famiglia → hasSeenOnboarding rimane false
                        // → RootGateView mostrerà OnboardingWalkthroughView
                    }
                    
                    if let fid = self.activeFamilyId {
                        sharedDefaults?.set(fid, forKey: "activeFamilyId")
                        KBLog.sync.kbInfo("AppGroup: activeFamilyId synced fid=\(fid)")
                    } else {
                        _ = user.uid
                        let descriptor = FetchDescriptor<KBFamily>(
                            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                        )
                        if let firstFamily = try? modelContext.fetch(descriptor).first {
                            sharedDefaults?.set(firstFamily.id, forKey: "activeFamilyId")
                            KBLog.sync.kbInfo("AppGroup: fallback activeFamilyId saved fid=\(firstFamily.id)")
                        } else {
                            KBLog.sync.kbInfo("No activeFamilyId after bootstrap — will fall back to families.first in RootHostView")
                        }
                    }
                    
                    // Nome/cognome e display name “veri” stanno su Firestore `users/{uid}`.
                    // `upsertUserProfile` usa solo Auth: senza questo merge, Todo / Family settings / ecc.
                    // restano con etichette sbagliate finché non apri Profilo.
                    await UserProfileRemoteSync.mergeFirestoreUserIntoLocal(uid: user.uid, modelContext: modelContext)
                    
                    // Dopo logout `resetOnSignOut()` mette `isFamilyOwner = false`.
                    // `refreshCurrentEntitlement()` non ripristina il ruolo: serve `loadPlan()`
                    // dopo che `activeFamilyId` è in App Group (non solo al primo skip onboarding).
                    await KBSubscriptionManager.shared.loadPlan()

                    let memoryFamilyId = self.activeFamilyId
                        ?? sharedDefaults?.string(forKey: "activeFamilyId")
                        ?? gateFamilyId
                    if !memoryFamilyId.isEmpty {
                        await FamilyMemoryService.shared.loadFactsFromFirestore(
                            familyId: memoryFamilyId,
                            modelContext: modelContext
                        )
                    }

                    UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.set(user.uid, forKey: "kidbox.autofill.currentUid")
                    await AutoFillSnapshotWriter.rebuildNow(modelContext: modelContext)

                } else {
                    self.isAuthenticated = false
                    self.uid = nil

                    UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.removeObject(forKey: "kidbox.autofill.currentUid")
                    AutoFillSnapshotWriter.clearAllAutoFillSharedArtifacts()

                    KBLog.auth.kbInfo("Auth state changed: logged out")
                    FamilyMemoryService.shared.clearFirestoreLoadCache()
                    FamilyKeychainStore.clearKeyCache()
                    self.setActiveFamily(nil)
                    self.resetToRoot()
                }
            }
        }
    }
    
    // MARK: - User profile persistence
    
    private func upsertUserProfile(from user: User, modelContext: ModelContext) {
        KBLog.data.kbDebug("Upserting local user profile")
        
        do {
            let uid = user.uid
            
            let descriptor = FetchDescriptor<KBUserProfile>(
                predicate: #Predicate { $0.uid == uid }
            )
            
            let existing = try modelContext.fetch(descriptor).first
            
            if let existing {
                existing.email = user.email
                existing.displayName = user.displayName
                existing.updatedAt = Date()
                KBLog.data.kbInfo("UserProfile updated uid=\(uid)")
            } else {
                let profile = KBUserProfile(uid: uid, email: user.email, displayName: user.displayName)
                modelContext.insert(profile)
                KBLog.data.kbInfo("UserProfile created uid=\(uid)")
            }
            
            try modelContext.save()
            KBLog.persistence.kbDebug("SwiftData save OK (user profile)")
            
            let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
            sharedDefaults?.set(uid, forKey: "currentUserUID")
            sharedDefaults?.set(
                user.displayName ?? user.email ?? "Utente",
                forKey: "currentUserDisplayName"
            )
            KBLog.data.kbDebug("App Group: currentUserUID + displayName saved")
            
        } catch {
            KBLog.data.kbError("UserProfile upsert failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Root + Destinations

    func makeRootView() -> some View {
        RootGateView()
    }

    // MARK: - Analytics (screen_view)

    private func trackScreenViewIfNeeded() {
        let route = path.last
        let name = route.flatMap { screenName(for: $0) } ?? (path.isEmpty ? "home" : nil)
        guard let name else { return }
        guard name != lastFiredScreenName else { return }
        lastFiredScreenName = name
        AppAnalytics.screenView(name: name)
    }

    private func screenName(for route: Route) -> String? {
        switch route {
        case .home:
            return "home"
        case .calendar:
            return "calendario"
        case .documentsHome, .documentsCategory, .document:
            return "documenti"
        case .chat:
            return "chat_famiglia"
        case .supportChat:
            return "chat_supporto"
        case .askExpert:
            return "assistente_ai"
        case .expensesHome, .expenseDetail:
            return "spese"
        case .shoppingList:
            return "lista_spesa"
        case .passwordsHome, .passwordsSecurity, .passwordDetail:
            return "password"
        case .walletHome, .walletTicketDetail, .walletDocumentDetail, .loyaltyCardDetail:
            return "wallet"
        case .notesHome, .noteDetail:
            return "note"
        case .todo, .todoList, .todoSmart:
            return "todo"
        case .familyPhotos, .photoAlbumDetail:
            return "foto"
        case .petsHome, .petDetail, .petEventDetail:
            return "animali"
        case .homeItemsHome, .homeItemDetail, .housePaymentDetail:
            return "casa"
        case .vehiclesHome, .vehicleDetail, .vehicleEventsList, .vehicleEventDetail:
            return "veicoli"
        case .travelList:
            return "viaggi"
        case .travelAllTrips:
            return "viaggi_tutti"
        case .travelTripDetail:
            return "viaggi_dettaglio"
        case .travelDiscover:
            return "viaggi_scopri"
        case .travelDestinationDetail:
            return "viaggi_destinazione"
        case .familyLocation:
            return "posizione"
        case .familySettings:
            return "impostazioni_famiglia"
        case .pediatricChildSelector, .pediatricHome:
            return "salute"
        case .pediatricVisits:
            return "salute_visite"
        case .pediatricVisitDetail:
            return "salute_visita_dettaglio"
        case .pediatricExams:
            return "salute_esami"
        case .examDetail:
            return "salute_esame_dettaglio"
        case .pediatricVaccines:
            return "salute_vaccini"
        case .pediatricTreatments:
            return "salute_trattamenti"
        case .pediatricTreatmentDetail:
            return "salute_trattamento_dettaglio"
        case .pediatricTimeline:
            return "salute_timeline"
        case .pediatricClinicalRecord, .pediatricMedicalRecord, .appleHealthApp:
            return "salute_cartella_clinica"
        default:
            return nil
        }
    }

    @ViewBuilder
    func makeDestination(for route: Route) -> some View {
        switch route {
        case .home:
            HomeView()
        case .today:
            Text("Today")
        case .calendar(let familyId, let highlightEventId):
            CalendarView(familyId: familyId, highlightEventId: highlightEventId)
        case .todo:
            TodoHomeView()
        case .settings:
            SettingsView()
        case .supportChat:
            SupportChatView()
        case .familySettings:
            FamilySettingsView()
        case .inviteCode:
            InviteCodeView()
        case .joinFamily:
            JoinFamilyView()
        case .document:
            DocumentsHomeView()
        case .profile:
            ProfileView()
        case .setupFamily:
            SetupFamilyView(mode: .create)
        case let .editFamily(familyId, childId):
            SetupFamilyDestinationView(familyId: familyId, childId: childId)
        case .documentsHome:
            DocumentsHomeView()
        case .documentsCategory(familyId: let familyId, categoryId: let categoryId, title: let title):
            DocumentFolderView(familyId: familyId, folderId: categoryId, folderTitle: title)
        case .editChild(familyId: _, childId: let childId):
            ChildDestinationView(childId: childId)
        case .chat:
            ChatView()
        case let .familyLocation(familyId):
            FamilyLocationView(familyId: familyId)
        case .shoppingList(familyId: let familyId):
            GroceryListView(familyId: familyId)
        case .todoList(familyId: let familyId, childId: let childId, listId: let listId):
            TodoListView(familyId: familyId, childId: childId, listId: listId)
        case .todoSmart(familyId: let familyId, childId: let childId, kind: let kind):
            TodoSmartListView(familyId: familyId, childId: childId, kind: kind)
            
        case .pediatricChildSelector(familyId: let familyId):
            PediatricChildSelectorView(familyId: familyId)
        case .pediatricHome(familyId: let familyId, childId: let childId):
            PediatricHomeView(familyId: familyId, childId: childId)
        case .pediatricMedicalRecord(familyId: let familyId, childId: let childId):
            PediatricMedicalRecordView(familyId: familyId, childId: childId)
        case .appleHealthApp(familyId: let familyId, childId: let childId):
            AppleHealthAppView(familyId: familyId, childId: childId)
        case .pediatricVisits(familyId: let familyId, childId: let childId):
            PediatricVisitsView(familyId: familyId, childId: childId)
        case .pediatricVaccines(familyId: let familyId, childId: let childId):
            PediatricVaccinesView(familyId: familyId, childId: childId)
        case .pediatricTreatments(familyId: let familyId, childId: let childId):
            PediatricTreatmentsView(familyId: familyId, childId: childId)
        case .pediatricTreatmentDetail(let fid, let cid, let tid):
            TreatmentDetailDestinationView(treatmentId: tid, familyId: fid, childId: cid)
            
        case .notesHome(familyId: let familyId):
            NotesHomeView(familyId: familyId)
        case .noteDetail(familyId: let familyId, noteId: let noteId, isNewNote: _):
            NoteDetailView(familyId: familyId, noteId: noteId)
            
        case .familyPhotos(familyId: let familyId):
            FamilyPhotosView(familyId: familyId)
        case .photoAlbumDetail(familyId: let familyId, albumId: let albumId, albumTitle: let title, isTripAlbum: let isTripAlbum):
            PhotoAlbumDetailView(
                familyId: familyId,
                albumId: albumId,
                albumTitle: title,
                showTripDedicatedBanner: isTripAlbum
            )
            
        case .pediatricVisitDetail(familyId: let familyId, childId: let childId, visitId: let visitId):
            PediatricVisitDetailView(familyId: familyId, childId: childId, visitId: visitId)
        case .pediatricExams(familyId: let familyId, childId: let childId):
            PediatricExamsView(familyId: familyId, childId: childId)
        case .examDetail(familyId: let familyId, childId: let childId, examId: let examId):
            PediatricExamDetailView(familyId: familyId, childId: childId, examId: examId)
        case .pediatricTimeline(familyId: let familyId, childId: let childId):
            PediatricTimelineDestinationView(familyId: familyId, childId: childId)
        case .pediatricClinicalRecord(familyId: let familyId, childId: let childId):
            ClinicalRecordView(familyId: familyId, childId: childId)
        case .expensesHome(familyId: let familyId, highlightExpenseId: let highlightExpenseId):
            ExpensesHomeView(familyId: familyId, highlightExpenseId: highlightExpenseId)
        case .expenseDetail(familyId: let familyId, expenseId: let expenseId):
            ExpenseDetailView(familyId: familyId, expenseId: expenseId)
        case .walletHome(familyId: let familyId):
            WalletHomeView(familyId: familyId)
        case .walletTicketDetail(familyId: let familyId, ticketId: let ticketId):
            WalletTicketDetailView(familyId: familyId, ticketId: ticketId)
        case .walletDocumentDetail(familyId: let familyId, documentId: let documentId):
            WalletDocumentDetailView(familyId: familyId, documentId: documentId)
        case .loyaltyCardDetail(familyId: let familyId, cardId: let cardId):
            LoyaltyCardDetailView(familyId: familyId, cardId: cardId)
        case .passwordsHome(familyId: let familyId):
            PasswordsHomeView(familyId: familyId)
        case .passwordsSecurity(familyId: let familyId):
            PasswordsSecurityView(familyId: familyId)
        case .passwordDetail(familyId: let familyId, entryId: let entryId):
            PasswordDetailView(familyId: familyId, entryId: entryId)
        case .askExpert:
            PlanningAIChatView()

        case .petsHome(let familyId):
            PetsHomeView(familyId: familyId)
        case .petDetail(let familyId, let petId):
            PetDetailView(familyId: familyId, petId: petId)
        case .petEventDetail(let familyId, let petId, let eventId):
            PetEventDetailView(familyId: familyId, petId: petId, eventId: eventId)
        case .homeItemsHome(let familyId):
            HomeItemsHomeView(familyId: familyId)
        case .homeItemDetail(let familyId, let itemId):
            HomeItemDetailView(familyId: familyId, itemId: itemId)
        case .housePaymentDetail(let familyId, let paymentId):
            HousePaymentDetailView(familyId: familyId, paymentId: paymentId)
        case .vehiclesHome(let familyId):
            VehiclesHomeView(familyId: familyId)
        case .vehicleDetail(let familyId, let vehicleId):
            VehicleDetailView(familyId: familyId, vehicleId: vehicleId)
        case .vehicleEventsList(let familyId, let vehicleId):
            VehicleEventsListView(familyId: familyId, vehicleId: vehicleId)
        case .vehicleEventDetail(let familyId, let vehicleId, let eventId):
            VehicleEventDetailView(familyId: familyId, vehicleId: vehicleId, eventId: eventId)

        case .travelList(let familyId):
            TravelListView(familyId: familyId)
        case .travelAllTrips(let familyId):
            TravelAllTripsView(familyId: familyId)
        case .travelTripDetail(let familyId, let tripId):
            TravelDetailView(tripId: tripId, familyId: familyId)
        case .travelDiscover(let familyId):
            TravelDiscoverView(familyId: familyId, userId: Auth.auth().currentUser?.uid ?? "")
        case .travelDestinationDetail(let familyId, let destinationId):
            if let destination = TravelSuggestionCache.destination(familyId: familyId, destinationId: destinationId) {
                TravelDestinationDetailView(destination: destination, familyId: familyId)
            } else {
                ContentUnavailableView(
                    "Suggerimento non trovato",
                    systemImage: "map",
                    description: Text("Torna alla lista e riprova.")
                )
            }
        }
    }
    
    func handleIncomingShare(modelContext: ModelContext) {
        let defaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
        guard let data = defaults?.dictionary(forKey: "pendingShare") as? [String: String],
              let destString = data["destination"] else { return }
        
        defaults?.removeObject(forKey: "pendingShare")
        defaults?.synchronize()
        
        let title    = data["title"] ?? ""
        let text     = data["text"]  ?? ""
        let filePath = data["sharedFilePath"] ?? ""
        
        KBLog.sync.kbInfo("handleIncomingShare destination=\(destString) hasFile=\(!filePath.isEmpty)")
        
        switch destString {
            
        case "chat":
            navigate(to: .chat)
            let caption = data["caption"].flatMap { $0.isEmpty ? nil : $0 }
            if !filePath.isEmpty {
                let fileType = data["sharedFileType"] ?? ""
                pendingShareMediaCaption = caption
                switch fileType {
                case "video":    pendingShareVideoPath = filePath
                case "document": pendingShareImagePath = filePath
                default:         pendingShareImagePath = filePath
                }
            } else {
                pendingShareText = text.isEmpty ? title : text
            }
            
        case "todo":
            let todoTitle = title.isEmpty ? text : title
            pendingShareTodoDraft = PendingShareTodoDraft(title: todoTitle)
            navigate(to: .todo)
            
        case "grocery":
            let familyId: String
            if let fid = activeFamilyId {
                familyId = fid
            } else if let fid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId"), !fid.isEmpty {
                KBLog.sync.kbInfo("handleIncomingShare grocery: activeFamilyId nil, fallback to AppGroup fid=\(fid)")
                familyId = fid
            } else {
                KBLog.sync.kbError("handleIncomingShare grocery: activeFamilyId nil — abort")
                return
            }
            navigate(to: .shoppingList(familyId: familyId))
            pendingShareText = text.isEmpty ? title : text
            
        case "event":
            let familyId: String
            if let fid = activeFamilyId {
                familyId = fid
            } else if let fid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId"), !fid.isEmpty {
                KBLog.sync.kbInfo("handleIncomingShare event: activeFamilyId nil, fallback to AppGroup fid=\(fid)")
                familyId = fid
            } else {
                KBLog.sync.kbError("handleIncomingShare event: activeFamilyId nil even in AppGroup — abort")
                return
            }
            let startDate = data["eventStartDate"].flatMap { ISO8601DateFormatter().date(from: $0) }
            KBLog.sync.kbInfo("handleIncomingShare event: navigating to calendar familyId=\(familyId)")
            navigate(to: .calendar(familyId: familyId, highlightEventId: nil))
            pendingShareEventDraft = PendingShareEventDraft(
                title: title.isEmpty ? text : title,
                notes: "",
                startDate: startDate,
                targetFamilyId: familyId
            )
            KBLog.sync.kbInfo("handleIncomingShare event: draft set title=\(title.isEmpty ? text : title)")
            
        case "document":
            let familyId: String
            if let fid = activeFamilyId {
                familyId = fid
            } else if let fid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "activeFamilyId"), !fid.isEmpty {
                KBLog.sync.kbInfo("handleIncomingShare document: activeFamilyId nil, fallback AppGroup fid=\(fid)")
                familyId = fid
            } else {
                KBLog.sync.kbError("handleIncomingShare document: activeFamilyId nil — abort")
                return
            }
            guard !filePath.isEmpty else {
                KBLog.sync.kbError("handleIncomingShare document: filePath empty — abort")
                return
            }
            pendingShareDocumentPath  = filePath
            let uuidPattern = #"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#
            let isUUIDTitle = title.range(of: uuidPattern, options: .regularExpression) != nil
            pendingShareDocumentTitle = (!title.isEmpty && !isUUIDTitle) ? title
            : (data["sharedFileName"].flatMap {
                let base = ($0 as NSString).deletingPathExtension
                return base.range(of: uuidPattern, options: .regularExpression) != nil ? nil : base
            })
            let alreadyInStack = path.contains { if case .documentsHome = $0 { return true }; return false }
            if !alreadyInStack { navigate(to: .documentsHome) }
            KBLog.sync.kbInfo("handleIncomingShare document: alreadyInStack=\(alreadyInStack) familyId=\(familyId) path=\(filePath)")
            
        case "wallet":
            let familyId: String
            if let fid = activeFamilyId {
                familyId = fid
            } else if let fid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "activeFamilyId"), !fid.isEmpty {
                KBLog.sync.kbInfo("handleIncomingShare wallet: activeFamilyId nil, fallback AppGroup fid=\(fid)")
                familyId = fid
            } else {
                KBLog.sync.kbError("handleIncomingShare wallet: activeFamilyId nil — abort")
                return
            }
            guard !filePath.isEmpty else {
                KBLog.sync.kbError("handleIncomingShare wallet: filePath empty — abort")
                return
            }
            pendingShareWalletPDFPath = filePath
            pendingShareWalletTitle = title.isEmpty ? (data["sharedFileName"] ?? "") : title
            let alreadyInStack = path.contains {
                if case .walletHome(let fid) = $0 { return fid == familyId }
                return false
            }
            if !alreadyInStack { navigate(to: .walletHome(familyId: familyId)) }
            KBLog.sync.kbInfo("handleIncomingShare wallet: alreadyInStack=\(alreadyInStack) familyId=\(familyId) path=\(filePath)")

        case "encryptedMedia":
            let familyId: String
            if let fid = activeFamilyId {
                familyId = fid
            } else if let fid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "activeFamilyId"), !fid.isEmpty {
                KBLog.sync.kbInfo("handleIncomingShare encryptedMedia: activeFamilyId nil, fallback AppGroup fid=\(fid)")
                familyId = fid
            } else {
                KBLog.sync.kbError("handleIncomingShare encryptedMedia: activeFamilyId nil — abort")
                return
            }
            guard !filePath.isEmpty else {
                KBLog.sync.kbError("handleIncomingShare encryptedMedia: filePath empty — abort")
                return
            }
            pendingShareEncryptedMediaPath = filePath
            pendingShareEncryptedMediaType = data["sharedFileType"] ?? "image"
            let alreadyInStack = path.contains {
                if case .familyPhotos(let fid) = $0 { return fid == familyId }
                return false
            }
            if !alreadyInStack { navigate(to: .familyPhotos(familyId: familyId)) }
            KBLog.sync.kbInfo("handleIncomingShare encryptedMedia: alreadyInStack=\(alreadyInStack) familyId=\(familyId) path=\(filePath)")

        case "note":
            let familyId: String
            if let fid = activeFamilyId {
                familyId = fid
            } else if let fid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "activeFamilyId"), !fid.isEmpty {
                KBLog.sync.kbInfo("handleIncomingShare note: activeFamilyId nil, fallback AppGroup fid=\(fid)")
                familyId = fid
            } else {
                KBLog.sync.kbError("handleIncomingShare note: activeFamilyId nil — abort")
                return
            }
            pendingShareText = text.isEmpty ? title : text
            let alreadyInNotes = path.contains {
                if case .notesHome(let fid) = $0 { return fid == familyId }
                return false
            }
            if !alreadyInNotes { navigate(to: .notesHome(familyId: familyId)) }
            KBLog.sync.kbInfo("handleIncomingShare note: familyId=\(familyId)")
            
        default:
            break
        }
    }
    
    // MARK: - Control Widget / deep link → Foto e video + fotocamera
    
    /// Control Widget: URL `kidbox://control/open-family-photos-camera` **oppure** handoff App Group
    /// (`consumePendingControlWidgetRouteIfNeeded`) → **Foto e video** + fotocamera.
    @MainActor
    func openFamilyPhotosWithCameraShortcut(modelContext: ModelContext) {
        guard isAuthenticated else {
            KBLog.navigation.kbInfo("Control shortcut: skipped — not authenticated")
            return
        }
        
        let suite = "group.it.vittorioscocca.kidbox"
        let defs = UserDefaults(suiteName: suite)
        let fid = activeFamilyId
            ?? defs?.string(forKey: "activeFamilyId")
            ?? (try? modelContext.fetch(
                FetchDescriptor<KBFamily>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            ))?.first?.id
        
        guard let familyId = fid, !familyId.isEmpty else {
            globalBannerMessage = "Apri KidBox e attendi il caricamento della famiglia, poi riprova dal controllo."
            KBLog.navigation.kbError("Control shortcut: no familyId")
            return
        }
        
        setActiveFamily(familyId, force: false)
        path.removeAll()
        path.append(.familyPhotos(familyId: familyId))
        openFamilyPhotosCameraForFamilyId = familyId
        KBLog.navigation.kbInfo("Control shortcut: familyPhotos + camera pending fid=\(familyId)")
    }

    /// Stessi valori scritti da `App/Intents/OpenKidBoxFamilyPhotosCameraIntent` (estensione + app).
    private static let controlWidgetPendingRouteKey = "kidbox.controlWidget.pendingRoute"
    private static let controlWidgetRouteFamilyPhotosCamera = "openFamilyPhotosCamera"

    /// Dopo tap sul Control Widget: l’estensione scrive l’App Group; qui consumiamo e navighiamo.
    /// Chiamare da `didBecomeActive` / `onAppear` (non usare `OpenURLIntent` con `kidbox://`).
    func consumePendingControlWidgetRouteIfNeeded(modelContext: ModelContext) {
        let suite = "group.it.vittorioscocca.kidbox"
        guard let defs = UserDefaults(suiteName: suite) else { return }
        let raw = defs.string(forKey: Self.controlWidgetPendingRouteKey)
        guard raw == Self.controlWidgetRouteFamilyPhotosCamera else { return }
        defs.removeObject(forKey: Self.controlWidgetPendingRouteKey)
        defs.synchronize()
        KBLog.navigation.kbInfo("Control widget handoff: consuming pending route familyPhotosCamera")
        openFamilyPhotosWithCameraShortcut(modelContext: modelContext)
    }
    
    // MARK: - Origine della navigazione (analytics)

    /// Come l'utente sta raggiungendo il prossimo contenuto.
    ///
    /// Serve solo a `KBAnalytics`: la vista di dettaglio non può sapere da sola se
    /// ci si è arrivati da una notifica, da una ricerca o sfogliando una lista, ma
    /// è esattamente la differenza tra "a portata di click" e "l'ho dovuto cercare".
    /// Chi naviga la imposta, il dettaglio la consuma. Vedi
    /// internal/analytics-active-users.md.
    private var pendingRetrievalOrigin: KBAnalyticsEntryPoint?

    func setRetrievalOrigin(_ origin: KBAnalyticsEntryPoint) {
        pendingRetrievalOrigin = origin
    }

    /// Legge e azzera l'origine. Azzerare è il punto: senza, una notifica
    /// "colorerebbe" tutte le aperture successive fatte sfogliando.
    func consumeRetrievalOrigin() -> KBAnalyticsEntryPoint {
        defer { pendingRetrievalOrigin = nil }
        return pendingRetrievalOrigin ?? .list
    }

    // MARK: - Navigation actions

    func navigate(to route: Route) {
        KBLog.navigation.kbInfo("Navigate to route=\(String(describing: route))")
        path.append(route)
        KBLog.navigation.kbDebug("Path updated count=\(self.path.count)")
    }

    /// Sostituisce l’ultima destinazione invece di impilarne una nuova.
    ///
    /// Serve alle schermate «di passaggio» che si aprono da sé (es. il selettore
    /// Salute quando il soggetto è uno solo): restando nello stack, il tap su
    /// «Indietro» ci rientrerebbe e verrebbe subito rilanciata la stessa
    /// navigazione, bloccando l’utente.
    func replaceTop(with route: Route) {
        KBLog.navigation.kbInfo("Replace top with route=\(String(describing: route))")
        if path.isEmpty {
            path = [route]
        } else {
            path[path.count - 1] = route
        }
    }

    /// Rimuove l’ultima destinazione dallo stack (equivalente al tap su «Indietro»).
    func navigateBack() {
        guard !path.isEmpty else { return }
        path.removeLast()
        KBLog.navigation.kbDebug("Path pop count=\(self.path.count)")
    }
    
    @MainActor
    func openDocumentFromPush(familyId: String, docId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openDocumentFromPush familyId=\(familyId) docId=\(docId)")
        setRetrievalOrigin(.notification)
        
        Task { @MainActor in
            let maxAttempts = 8
            let delayNs: UInt64 = 500_000_000
            var doc: KBDocument? = nil
            
            for attempt in 1...maxAttempts {
                let fid = familyId
                let did = docId
                let descriptor = FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.id == did }
                )
                doc = try? modelContext.fetch(descriptor).first
                if doc != nil {
                    KBLog.navigation.kbDebug("openDocumentFromPush: document found attempt=\(attempt)")
                    break
                }
                KBLog.navigation.kbDebug("openDocumentFromPush: document not found yet attempt=\(attempt)/\(maxAttempts)")
                if attempt < maxAttempts { try? await Task.sleep(nanoseconds: delayNs) }
            }
            
            guard let doc else {
                KBLog.navigation.kbError("openDocumentFromPush: document not found after retries, fallback to documentsHome")
                path.removeAll()
                path.append(.documentsHome)
                pendingOpenDocumentId = docId
                return
            }
            
            var categoryChain: [KBDocumentCategory] = []
            var currentCategoryId = doc.categoryId
            
            while let catId = currentCategoryId {
                let cid = catId
                let fid = familyId
                let catDescriptor = FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate { $0.id == cid && $0.familyId == fid }
                )
                guard let cat = try? modelContext.fetch(catDescriptor).first else {
                    KBLog.navigation.kbError("openDocumentFromPush: missing category catId=\(catId)")
                    break
                }
                categoryChain.insert(cat, at: 0)
                currentCategoryId = cat.parentId
            }
            
            KBLog.navigation.kbDebug("openDocumentFromPush: categoryChain depth=\(categoryChain.count)")
            
            path.removeAll()
            path.append(.documentsHome)
            for cat in categoryChain {
                path.append(.documentsCategory(familyId: familyId, categoryId: cat.id, title: cat.title))
            }
            pendingOpenDocumentId = docId
            KBLog.navigation.kbDebug("openDocumentFromPush: path rebuilt count=\(path.count), pendingOpenDocumentId set")
        }
    }
    
    // MARK: - Open Wallet ticket from Push

    /// Apre direttamente il biglietto Wallet che ha scatenato la notifica.
    /// Path: walletHome → walletTicketDetail.
    @MainActor
    func openWalletTicketFromPush(familyId: String, ticketId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openWalletTicketFromPush familyId=\(familyId) ticketId=\(ticketId)")
        setRetrievalOrigin(.notification)

        Task { @MainActor in
            await SyncCenter.shared.fetchWalletTicketsOnce(familyId: familyId, modelContext: modelContext)

            let tid = ticketId
            let desc = FetchDescriptor<KBWalletTicket>(predicate: #Predicate { $0.id == tid })
            let found = (try? modelContext.fetch(desc).first) != nil

            path.removeAll()
            path.append(.walletHome(familyId: familyId))
            if found {
                path.append(.walletTicketDetail(familyId: familyId, ticketId: ticketId))
                KBLog.navigation.kbInfo("openWalletTicketFromPush: navigating to walletTicketDetail")
            } else {
                KBLog.navigation.kbError("openWalletTicketFromPush: ticket not found after fetch, fallback to walletHome")
            }
        }
    }

    // MARK: - Open House Payment from Push

    /// Apre direttamente la scadenza pagamento casa che ha scatenato il promemoria.
    /// Path: homeItemsHome → housePaymentDetail
    @MainActor
    func openHousePaymentFromPush(familyId: String, paymentId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openHousePaymentFromPush familyId=\(familyId) paymentId=\(paymentId)")

        Task { @MainActor in
            let pid = paymentId
            let desc = FetchDescriptor<KBHousePayment>(predicate: #Predicate { $0.id == pid })
            let found = (try? modelContext.fetch(desc).first) != nil

            path.removeAll()
            path.append(.homeItemsHome(familyId: familyId))
            if found {
                path.append(.housePaymentDetail(familyId: familyId, paymentId: paymentId))
                KBLog.navigation.kbInfo("openHousePaymentFromPush: navigating to housePaymentDetail")
            } else {
                KBLog.navigation.kbError("openHousePaymentFromPush: payment not found, fallback to homeItemsHome")
            }
        }
    }

    // MARK: - Open Wallet Document from Push

    /// Apre direttamente il documento Wallet che ha scatenato il promemoria scadenza.
    /// Path: walletHome → walletDocumentDetail
    @MainActor
    func openWalletDocumentFromPush(familyId: String, documentId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openWalletDocumentFromPush familyId=\(familyId) documentId=\(documentId)")

        Task { @MainActor in
            let did = documentId
            let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
            let found = (try? modelContext.fetch(desc).first) != nil

            path.removeAll()
            path.append(.walletHome(familyId: familyId))
            if found {
                path.append(.walletDocumentDetail(familyId: familyId, documentId: documentId))
                KBLog.navigation.kbInfo("openWalletDocumentFromPush: navigating to walletDocumentDetail")
            } else {
                KBLog.navigation.kbError("openWalletDocumentFromPush: document not found, fallback to walletHome")
            }
        }
    }

    @MainActor
    func openNoteFromPush(familyId: String, noteId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openNoteFromPush familyId=\(familyId) noteId=\(noteId)")
        setRetrievalOrigin(.notification)

        // Come per i to-do: si apre subito la lista note e si aspetta lì, con
        // lo spinner. Da background e soprattutto ad app killata la nota non fa
        // in tempo ad arrivare — prima si tentava una sola `fetchNotesOnce` e
        // poi si mostrava "contenuto non più disponibile" per una nota che
        // sarebbe comparsa un attimo dopo.
        path.removeAll()
        path.append(.notesHome(familyId: familyId))

        startPushResolution(message: "Apro la nota…") { [weak self] in
            guard let self else { return }
            let currentUid = Auth.auth().currentUser?.uid
            let resolved = await self.awaitPushResource(
                label: "nota",
                fetch: { () -> KBNote? in
                    let nid = noteId
                    let desc = FetchDescriptor<KBNote>(predicate: #Predicate<KBNote> { $0.id == nid })
                    guard let note = try? modelContext.fetch(desc).first else { return nil }
                    // Una nota già in locale ma non ancora visibile (permessi
                    // arrivati con la riga vecchia) non va accettata: si
                    // continua ad aspettare l'aggiornamento.
                    return note.isVisible(to: currentUid) ? note : nil
                },
                refresh: {
                    await SyncCenter.shared.fetchNotesOnce(familyId: familyId, modelContext: modelContext)
                }
            )
            guard !Task.isCancelled else { return }

            guard resolved != nil else {
                self.globalBannerMessage = "Questo contenuto non è più disponibile."
                KBLog.navigation.kbError("openNoteFromPush: note missing or not visible, resto su notesHome")
                return
            }

            self.path.removeAll()
            self.path.append(.notesHome(familyId: familyId))
            self.path.append(.noteDetail(familyId: familyId, noteId: noteId, isNewNote: false))
            KBLog.navigation.kbInfo("openNoteFromPush: navigating to noteDetail")
        }
    }
    
    /// Deep link da notifica `new_calendar_event`: apre il calendario e evidenzia l'evento se visibile all'utente corrente.
    @MainActor
    func openCalendarEventFromPush(familyId: String, eventId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openCalendarEventFromPush familyId=\(familyId) eventId=\(eventId)")

        // Nessuna attesa qui: a sapere se l'evento c'è è la `@Query` che disegna
        // il calendario, non una lettura separata del contesto. Si naviga e
        // basta, poi `CalendarView` aspetta e apre la scheda dell'evento —
        // spinner compreso. Stessa divisione di `CalendarScreen` su Android.
        path.removeAll()
        path.append(.calendar(familyId: familyId, highlightEventId: eventId))
    }
    
    // MARK: - Open Visit from Push
    
    /// Apre direttamente la visita che ha scatenato il promemoria.
    /// Path: pediatricHome → pediatricVisits → pediatricVisitDetail
    @MainActor
    func openVisitFromPush(familyId: String, childId: String, visitId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openVisitFromPush familyId=\(familyId) childId=\(childId) visitId=\(visitId)")
        
        Task { @MainActor in
            let vid = visitId
            let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
            let found = (try? modelContext.fetch(desc).first) != nil
            
            path.removeAll()
            if found {
                path.append(.pediatricHome(familyId: familyId, childId: childId))
                path.append(.pediatricVisits(familyId: familyId, childId: childId))
                path.append(.pediatricVisitDetail(familyId: familyId, childId: childId, visitId: visitId))
                KBLog.navigation.kbInfo("openVisitFromPush: navigating to pediatricVisitDetail")
            } else {
                path.append(.pediatricHome(familyId: familyId, childId: childId))
                path.append(.pediatricVisits(familyId: familyId, childId: childId))
                KBLog.navigation.kbError("openVisitFromPush: visit not found, fallback to pediatricVisits")
            }
        }
    }
    
    // MARK: - Open Treatment from Push
    
    /// Apre direttamente la cura che ha scatenato il promemoria dose.
    /// Path: pediatricHome → pediatricTreatments → pediatricTreatmentDetail
    @MainActor
    func openTreatmentFromPush(familyId: String, childId: String, treatmentId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openTreatmentFromPush familyId=\(familyId) childId=\(childId) treatmentId=\(treatmentId)")
        
        Task { @MainActor in
            let tid = treatmentId
            let desc = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.id == tid })
            let found = (try? modelContext.fetch(desc).first) != nil
            
            path.removeAll()
            if found {
                path.append(.pediatricHome(familyId: familyId, childId: childId))
                path.append(.pediatricTreatments(familyId: familyId, childId: childId))
                path.append(.pediatricTreatmentDetail(familyId: familyId, childId: childId, treatmentId: treatmentId))
                KBLog.navigation.kbInfo("openTreatmentFromPush: navigating to pediatricTreatmentDetail")
            } else {
                path.append(.pediatricHome(familyId: familyId, childId: childId))
                path.append(.pediatricTreatments(familyId: familyId, childId: childId))
                KBLog.navigation.kbError("openTreatmentFromPush: treatment not found, fallback to pediatricTreatments")
            }
        }
    }
    
    // MARK: - Open Exam from Push
    
    /// Apre direttamente l'esame che ha scatenato il promemoria.
    /// Path: pediatricHome → pediatricExams → examDetail
    @MainActor
    func openExamFromPush(familyId: String, childId: String, examId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openExamFromPush familyId=\(familyId) childId=\(childId) examId=\(examId)")
        
        Task { @MainActor in
            let eid = examId
            let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })
            let found = (try? modelContext.fetch(desc).first) != nil
            
            path.removeAll()
            if found {
                path.append(.pediatricHome(familyId: familyId, childId: childId))
                path.append(.pediatricExams(familyId: familyId, childId: childId))
                path.append(.examDetail(familyId: familyId, childId: childId, examId: examId))
                KBLog.navigation.kbInfo("openExamFromPush: navigating to examDetail")
            } else {
                path.append(.pediatricHome(familyId: familyId, childId: childId))
                path.append(.pediatricExams(familyId: familyId, childId: childId))
                KBLog.navigation.kbError("openExamFromPush: exam not found, fallback to pediatricExams")
            }
        }
    }

    // MARK: - Open Vaccine from Push

    /// Apre direttamente la lista vaccini del bambino che ha scatenato il promemoria richiamo.
    /// Path: pediatricHome → pediatricVaccines
    /// (`PediatricVaccineEditView` richiede un callback `onSaved` legato al presenter della lista,
    /// quindi non è pushabile standalone: la lista è la destinazione più profonda raggiungibile in sicurezza.)
    @MainActor
    func openVaccineFromPush(familyId: String, childId: String, vaccineId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openVaccineFromPush familyId=\(familyId) childId=\(childId) vaccineId=\(vaccineId)")
        path.removeAll()
        path.append(.pediatricHome(familyId: familyId, childId: childId))
        path.append(.pediatricVaccines(familyId: familyId, childId: childId))
    }

    // MARK: - Open Vehicle from Push

    /// Apre direttamente il veicolo che ha scatenato il promemoria scadenza (bollo/assicurazione/revisione/tagliando).
    /// Path: vehiclesHome → vehicleDetail
    @MainActor
    func openVehicleFromPush(familyId: String, vehicleId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openVehicleFromPush familyId=\(familyId) vehicleId=\(vehicleId)")

        Task { @MainActor in
            let vid = vehicleId
            let desc = FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.id == vid })
            let found = (try? modelContext.fetch(desc).first) != nil

            path.removeAll()
            path.append(.vehiclesHome(familyId: familyId))
            if found {
                path.append(.vehicleDetail(familyId: familyId, vehicleId: vehicleId))
                KBLog.navigation.kbInfo("openVehicleFromPush: navigating to vehicleDetail")
            } else {
                KBLog.navigation.kbError("openVehicleFromPush: vehicle not found, fallback to vehiclesHome")
            }
        }
    }

    // MARK: - Attesa di una risorsa arrivata da notifica

    /// Quanto si aspetta la risorsa di una notifica prima di rinunciare. Oltre
    /// questo limite è più probabile che non arrivi mai (cancellata, non
    /// visibile, sync mai completata) che non un ritardo: meglio lasciare
    /// l'utente libero che tenerlo appeso.
    private static let pushResourceTimeout: TimeInterval = 25
    private static let pushResourcePollInterval: UInt64 = 500_000_000
    /// Ogni quanti giri di polling si ritenta anche una fetch una tantum.
    private static let pushResourceRefreshEvery = 4

    /// Aspetta che `fetch` trovi in locale la risorsa di una notifica.
    ///
    /// Si ASPETTA invece di leggere una volta sola: ad app chiusa la notifica
    /// viene toccata molto prima che la sincronizzazione abbia portato il
    /// contenuto in SwiftData — a freddo il grosso del tempo se ne va nel
    /// login e nel primo giro di sync — quindi una lettura immediata
    /// fallirebbe quasi sempre e si finiva sulla panoramica con "contenuto non
    /// più disponibile". Stessa attesa di `TodoDeepLinkResolverViewModel` su
    /// Android.
    ///
    /// - Parameter refresh: fetch una tantum da ritentare periodicamente, per
    ///   le sezioni il cui realtime potrebbe non essere ancora partito.
    @MainActor
    private func awaitPushResource<T>(
        label: String,
        fetch: @MainActor () -> T?,
        refresh: (@MainActor () async -> Void)? = nil
    ) async -> T? {
        let deadline = Date().addingTimeInterval(Self.pushResourceTimeout)
        var attempt = 0
        while !Task.isCancelled {
            attempt += 1
            if let found = fetch() {
                KBLog.navigation.kbDebug("[push] \(label) trovato attempt=\(attempt)")
                return found
            }
            guard Date() < deadline else {
                KBLog.navigation.kbInfo("[push] \(label): timeout dopo \(attempt) tentativi")
                return nil
            }
            if let refresh, attempt % Self.pushResourceRefreshEvery == 0 {
                await refresh()
                if Task.isCancelled { return nil }
                continue
            }
            try? await Task.sleep(nanoseconds: Self.pushResourcePollInterval)
        }
        return nil
    }

    /// Avvia un'attesa mostrando lo spinner, sostituendo quella eventualmente
    /// in corso. Lo spinner si spegne da sé quando `body` termina.
    @MainActor
    private func startPushResolution(message: String, body: @escaping @MainActor () async -> Void) {
        deepLinkResolutionTask?.cancel()
        deepLinkLoadingMessage = message
        deepLinkResolutionTask = Task { @MainActor in
            defer {
                deepLinkLoadingMessage = nil
                deepLinkResolutionTask = nil
            }
            await body()
        }
    }

    // MARK: - Open Todo from Push

    /// Apre direttamente il todo che ha scatenato il promemoria.
    /// Path: todo → todoList (con highlight sul todo specifico)
    @MainActor
    func openTodoFromPush(familyId: String, childId: String, listId: String, todoId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openTodoFromPush familyId=\(familyId) childId=\(childId) listId=\(listId) todoId=\(todoId)")

        // Si apre subito la panoramica To-Do: dà un contesto mentre si aspetta,
        // invece di lasciare l'utente dov'era senza spiegazioni. È anche ciò
        // che fa partire `startTodoRealtime`, cioè la sync che porterà il to-do.
        path.removeAll()
        path.append(.todo)

        startPushResolution(message: "Apro il to-do…") { [weak self] in
            guard let self else { return }
            let resolved = await self.awaitPushResource(label: "todo") {
                let tid = todoId
                let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate<KBTodoItem> { $0.id == tid })
                return try? modelContext.fetch(desc).first
            }
            guard !Task.isCancelled else { return }

            let currentUid = Auth.auth().currentUser?.uid
            guard let resolved, resolved.isVisible(to: currentUid) else {
                TodoHighlightStore.shared.set(nil)
                self.globalBannerMessage = "Questo contenuto non è più disponibile."
                KBLog.navigation.kbError("openTodoFromPush: todo missing or not visible todoId=\(todoId)")
                return
            }

            // `listId` e `childId` si prendono dal to-do vero: il payload del
            // server manda `after.listId || ""`, e con la stringa vuota la
            // rotta punterebbe a una lista che non esiste. Il valore della
            // notifica resta solo come ripiego.
            let resolvedListId = (resolved.listId?.isEmpty == false) ? resolved.listId! : listId
            let resolvedChildId = resolved.childId.isEmpty ? childId : resolved.childId
            guard !resolvedListId.isEmpty else {
                TodoHighlightStore.shared.set(nil)
                self.globalBannerMessage = "Questo contenuto non è più disponibile."
                KBLog.navigation.kbError("openTodoFromPush: listId non risolto todoId=\(todoId)")
                return
            }

            // L'highlight va impostato PRIMA della push: `TodoListView` lo
            // legge già al primo `onAppear`, così il flash parte da solo.
            TodoHighlightStore.shared.set(todoId)
            self.path.removeAll()
            self.path.append(.todo)
            self.path.append(.todoList(familyId: resolved.familyId, childId: resolvedChildId, listId: resolvedListId))
            KBLog.navigation.kbInfo("openTodoFromPush: aperta todoList listId=\(resolvedListId) todoId=\(todoId)")
        }
    }


    func resetToRoot() {
        KBLog.navigation.kbInfo("Reset to root (clearing path)")
        openFamilyPhotosCameraForFamilyId = nil
        path.removeAll()
        // `activeFamilyId` non viene azzerato qui: resta in UserDefaults / App Group
        // così dopo join + resetToRoot() la root vede ancora la famiglia attiva.
        if let id = activeFamilyId {
            UserDefaults.standard.set(id, forKey: Self.activeFamilyIdKey)
            UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.set(id, forKey: "activeFamilyId")
            rootDataRefreshToken &+= 1
            objectWillChange.send()
            KBLog.navigation.kbDebug("resetToRoot: reasserted activeFamilyId=\(id) refreshToken=\(rootDataRefreshToken)")
        }
        KBLog.navigation.kbDebug("Path cleared")
    }
    
    // MARK: - Sign out
    
    @MainActor
    func signOut(modelContext: ModelContext) async {
        KBLog.auth.kbInfo("Sign out requested")

        AutoFillSnapshotWriter.clearAllAutoFillSharedArtifacts()

        await KidBoxLocalNotificationsCleanup.cancelAllScheduledAccountReminders()
        
        do {
            KBLog.persistence.kbInfo("Wiping local data (best effort)")
            try LocalDataWiper.wipeAll(context: modelContext)
            KBLog.persistence.kbInfo("Local wipe OK")
        } catch {
            KBLog.persistence.kbError("Local wipe failed: \(error.localizedDescription)")
        }
        
        do {
            try Auth.auth().signOut()
            KBLog.auth.kbInfo("Firebase sign-out OK")
            KBSubscriptionManager.shared.resetOnSignOut()
            FamilyKeychainStore.clearKeyCache()
            setActiveFamily(nil)
            resetToRoot()
        } catch {
            KBLog.auth.kbError("Sign-out failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Active family resolution (multi-family)

/// Risolve la famiglia da mostrare: prima `AppCoordinator.activeFamilyId`, poi fallback SwiftData.
enum ActiveFamilyResolver {
    static func family(from families: [KBFamily], activeFamilyId: String?) -> KBFamily? {
        if let id = activeFamilyId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !id.isEmpty,
           let match = families.first(where: { $0.id == id }) {
            return match
        }
        return families.first
    }

    static func familyId(from families: [KBFamily], activeFamilyId: String?) -> String {
        family(from: families, activeFamilyId: activeFamilyId)?.id ?? ""
    }
}
