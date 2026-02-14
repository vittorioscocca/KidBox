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
    
    // MARK: - Private
    
    /// Firebase Auth listener handle. Non-nil when the session listener is active.
    private var authHandle: AuthStateDidChangeListenerHandle?
    
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
                    
                    // Bootstraps family state if needed (e.g. first run after login).
                    KBLog.sync.kbDebug("Calling FamilyBootstrapService.bootstrapIfNeeded")
                    await FamilyBootstrapService(modelContext: modelContext).bootstrapIfNeeded()
                    
                } else {
                    self.isAuthenticated = false
                    self.uid = nil
                    
                    KBLog.auth.kbInfo("Auth state changed: logged out")
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
        // Logging each destination build is helpful during navigation debugging.
        
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
    /// Current behavior (unchanged):
    /// - Navigate to `.documentsHome`
    /// - Store `pendingOpenDocumentId` so the documents UI can consume it when ready.
    @MainActor
    func openDocumentFromPush(familyId: String, docId: String) {
        KBLog.navigation.kbInfo("openDocumentFromPush familyId=\(familyId) docId=\(docId)")
        
        // Go to documents home (existing screen)
        navigate(to: .documentsHome)
        
        // Save pending id to be consumed when UI is ready
        pendingOpenDocumentId = docId
        KBLog.navigation.kbDebug("pendingOpenDocumentId set")
    }
    
    /// Resets navigation to the root (clears the NavigationStack path).
    func resetToRoot() {
        KBLog.navigation.kbInfo("Reset to root (clearing path)")
        
        path.removeAll()
        
        KBLog.navigation.kbDebug("Path cleared")
    }
    
    // MARK: - Sign out
    
    /// Signs out the current user.
    ///
    /// Current behavior (unchanged):
    /// - Best-effort wipe of local data
    /// - Firebase sign out
    /// - Reset navigation to root
    ///
    /// - Parameter modelContext: SwiftData context used for local wipe.
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
            resetToRoot()
        } catch {
            KBLog.auth.kbError("Sign-out failed: \(error.localizedDescription)")
        }
    }
}
