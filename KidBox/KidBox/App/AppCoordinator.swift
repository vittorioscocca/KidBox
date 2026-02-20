//
//  AppCoordinator.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import Combine
import OSLog
import FirebaseAuth
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
    @Published var path: [Route] = []
    
    // MARK: - Session state
    
    /// Whether there is a currently authenticated Firebase user.
    @Published private(set) var isAuthenticated: Bool = false
    
    /// Cached Firebase UID of the current user (if authenticated).
    @Published private(set) var uid: String?
    
    /// Document id pending to be opened once the UI is ready (e.g. after a push notification).
    @Published var pendingOpenDocumentId: String? = nil
    
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
    
    // MARK: - Private
    
    /// Firebase Auth listener handle. Non-nil when the session listener is active.
    private var authHandle: AuthStateDidChangeListenerHandle?
    
    // MARK: - Init
    
    init() {
        // Restore persisted active family from previous session.
        activeFamilyId = UserDefaults.standard.string(forKey: Self.activeFamilyIdKey)
        if let id = activeFamilyId {
            KBLog.sync.kbInfo("activeFamilyId restored from UserDefaults familyId=\(id)")
        }
    }
    
    // MARK: - Active family management
    
    /// Sets the active family explicitly (e.g. after join or user-initiated family switch).
    ///
    /// - Parameter familyId: The family to make active. Pass `nil` to clear.
    func setActiveFamily(_ familyId: String?) {
        guard activeFamilyId != familyId else {
            KBLog.sync.kbDebug("setActiveFamily no-op familyId=\(familyId ?? "nil")")
            return
        }
        KBLog.sync.kbInfo("setActiveFamily familyId=\(familyId ?? "nil")")
        activeFamilyId = familyId
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
            // The listener may call back on a non-main thread; we re-enter MainActor explicitly.
            Task { @MainActor in
                if let user {
                    self.isAuthenticated = true
                    self.uid = user.uid
                    
                    KBLog.auth.kbInfo("Auth state changed: logged in uid=\(user.uid)")
                    
                    self.upsertUserProfile(from: user, modelContext: modelContext)
                    
                    // Bootstrap syncs all known families locally.
                    // It does NOT change activeFamilyId — that is set explicitly
                    // by join/switch actions or restored from UserDefaults.
                    KBLog.sync.kbDebug("Calling FamilyBootstrapService.bootstrapIfNeeded")
                    await FamilyBootstrapService(modelContext: modelContext).bootstrapIfNeeded()
                    
                    // If no active family is pinned yet, pick the first available one
                    // after bootstrap (first-run or after sign-out).
                    if self.activeFamilyId == nil {
                        KBLog.sync.kbInfo("No activeFamilyId after bootstrap — will fall back to families.first in RootHostView")
                    }
                    
                } else {
                    self.isAuthenticated = false
                    self.uid = nil
                    
                    KBLog.auth.kbInfo("Auth state changed: logged out")
                    self.setActiveFamily(nil)
                    self.resetToRoot()
                }
            }
        }
    }
    
    // MARK: - User profile persistence
    
    /// Creates or updates the local `KBUserProfile` based on Firebase user info.
    ///
    /// This keeps local metadata aligned with the remote auth identity.
    /// Logic is LWW-style:
    /// - If profile exists → update fields and `updatedAt`.
    /// - Else → create and insert.
    ///
    /// - Important: This function never throws; it logs errors and continues.
    private func upsertUserProfile(from user: User, modelContext: ModelContext) {
        KBLog.data.kbDebug("Upserting local user profile")
        
        do {
            let uid = user.uid // capture stable value for predicate
            
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
            
        } catch {
            KBLog.data.kbError("UserProfile upsert failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Root + Destinations
    
    /// The app root view (authentication gate).
    func makeRootView() -> some View {
        RootGateView()
    }
    
    /// Builds a destination view for a given route.
    ///
    /// - Note: This is the single routing map for the entire app.
    @ViewBuilder
    func makeDestination(for route: Route) -> some View {
        switch route {
        case .home:
            HomeView()
        case .today:
            Text("Today")
        case .calendar:
            Text("Calendar")
        case .todo:
            TodoListView()
        case .settings:
            SettingsView()
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
        }
    }
    
    // MARK: - Navigation actions
    
    /// Pushes a new route onto the navigation stack.
    ///
    /// - Parameter route: The route to navigate to.
    func navigate(to route: Route) {
        KBLog.navigation.kbInfo("Navigate to route=\(String(describing: route))")
        
        path.append(route)
        
        KBLog.navigation.kbDebug("Path updated count=\(self.path.count)")
    }
    
    /// Handles a "open document" action coming from a push notification.
    ///
    /// Ricostruisce l'intero path di navigazione (root → cartelle intermedie → documento)
    /// leggendo `categoryId` e la catena di `parentId` da SwiftData.
    ///
    /// Se il documento non è ancora sincronizzato localmente (race condition),
    /// attende fino a `maxWait` secondi con polling, poi fa fallback a `.documentsHome`.
    @MainActor
    func openDocumentFromPush(familyId: String, docId: String, modelContext: ModelContext) {
        KBLog.navigation.kbInfo("openDocumentFromPush familyId=\(familyId) docId=\(docId)")
        
        Task { @MainActor in
            // ── 1. Prova a trovare il documento, con retry per la race condition sync ──
            let maxAttempts = 8
            let delayNs: UInt64 = 500_000_000  // 0.5s tra un tentativo e l'altro
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
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: delayNs)
                }
            }
            
            // ── 2. Se il documento non è ancora disponibile → fallback alla root ──
            guard let doc else {
                KBLog.navigation.kbError("openDocumentFromPush: document not found after retries, fallback to documentsHome")
                path.removeAll()
                path.append(.documentsHome)
                pendingOpenDocumentId = docId
                return
            }
            
            // ── 3. Risali la catena di cartelle: categoryId → parentId → ... → nil (root) ──
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
                categoryChain.insert(cat, at: 0)  // prepend → ordine root-first
                currentCategoryId = cat.parentId
            }
            
            KBLog.navigation.kbDebug("openDocumentFromPush: categoryChain depth=\(categoryChain.count)")
            
            // ── 4. Ricostruisci il NavigationStack path ──
            path.removeAll()
            path.append(.documentsHome)
            
            for cat in categoryChain {
                path.append(.documentsCategory(
                    familyId: familyId,
                    categoryId: cat.id,
                    title: cat.title
                ))
            }
            
            // ── 5. Setta il pending doc: la DocumentFolderView foglia lo aprirà in onAppear ──
            pendingOpenDocumentId = docId
            KBLog.navigation.kbDebug("openDocumentFromPush: path rebuilt count=\(path.count), pendingOpenDocumentId set")
        }
    }
    
    /// Resets navigation to the root (clears the NavigationStack path).
    func resetToRoot() {
        KBLog.navigation.kbInfo("Reset to root (clearing path)")
        path.removeAll()
        KBLog.navigation.kbDebug("Path cleared")
    }
    
    // MARK: - Sign out
    
    /// Signs out the current user.
    @MainActor
    func signOut(modelContext: ModelContext) {
        KBLog.auth.kbInfo("Sign out requested")
        
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
            setActiveFamily(nil)
            resetToRoot()
        } catch {
            KBLog.auth.kbError("Sign-out failed: \(error.localizedDescription)")
        }
    }
}
