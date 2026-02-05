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
/// `AppCoordinator` owns the navigation path and decides which screen should be
/// presented based on the current application state (authentication, family setup, etc.).
///
/// - Important: Views and ViewModels must not perform navigation directly.
///   All routing decisions go through the coordinator.
@MainActor
final class AppCoordinator: ObservableObject {
    
    @Published var path: [Route] = []
    
    /// Global auth/session state (persisted by FirebaseAuth)
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var uid: String?
    
    private var authHandle: AuthStateDidChangeListenerHandle?
    
    func startSessionListener(modelContext: ModelContext) {
        guard authHandle == nil else { return }
        
        authHandle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                if let user {
                    self.isAuthenticated = true
                    self.uid = user.uid
                    KBLog.auth.info("Auth state: logged in uid=\(user.uid, privacy: .public)")
                    self.upsertUserProfile(from: user, modelContext: modelContext)
                   
                    await FamilyBootstrapService(modelContext: modelContext).bootstrapIfNeeded()
                } else {
                    self.isAuthenticated = false
                    self.uid = nil
                    KBLog.auth.info("Auth state: logged out")
                    self.resetToRoot()
                }
            }
        }
    }
    
    private func upsertUserProfile(from user: User, modelContext: ModelContext) {
        do {
            let uid = user.uid   // ✅ cattura prima
            
            let descriptor = FetchDescriptor<KBUserProfile>(
                predicate: #Predicate { $0.uid == uid }   // ✅ usa uid “stabile”
            )
            let existing = try modelContext.fetch(descriptor).first
            
            if let existing {
                existing.email = user.email
                existing.displayName = user.displayName
                existing.updatedAt = Date()
                KBLog.data.debug("UserProfile updated uid=\(uid, privacy: .public)")
            } else {
                let profile = KBUserProfile(uid: uid, email: user.email, displayName: user.displayName)
                modelContext.insert(profile)
                KBLog.data.debug("UserProfile created uid=\(uid, privacy: .public)")
            }
            
            try modelContext.save()
        } catch {
            KBLog.data.error("UserProfile upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func makeRootView() -> some View {
        RootGateView()
    }
    
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
            
        case .profile:
            ProfileView()
            
        case .setupFamily:
            SetupFamilyView(mode: .create)
            
        case let .editFamily(familyId, childId):
            SetupFamilyDestinationView(familyId: familyId, childId: childId)
        }
    }

    func navigate(to route: Route) {
        KBLog.navigation.debug("Navigate to \(String(describing: route), privacy: .public)")
        path.append(route)
        KBLog.navigation.debug("Path count now = \(self.path.count, privacy: .public)")
    }
    
    func resetToRoot() {
        KBLog.navigation.debug("Reset to root (clearing path)")
        path.removeAll()
    }
    
    @MainActor
    func signOut(modelContext: ModelContext) {
        do {
            try LocalDataWiper.wipeAll(context: modelContext)
        } catch {
            KBLog.persistence.error("Local wipe failed: \(error.localizedDescription, privacy: .public)")
        }
        
        do {
            try Auth.auth().signOut()
            KBLog.auth.info("Firebase sign-out OK")
            resetToRoot()
        } catch {
            KBLog.auth.error("Sign-out failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
