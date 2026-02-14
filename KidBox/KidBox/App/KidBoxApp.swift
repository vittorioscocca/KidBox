//
//  KidBoxApp.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import SwiftData
import OSLog
import GoogleSignIn
import FirebaseAuth

/// Main application entry point for KidBox.
///
/// Responsibilities:
/// - Build and provide the SwiftData `ModelContainer` to the view hierarchy.
/// - Own global singletons/state: `AppCoordinator`, `NotificationManager`, `AppDelegate`.
/// - Run migrations/backfills at startup (best effort).
/// - Handle URL callbacks (Google Sign-In).
/// - React to scene lifecycle changes (foreground/background) to drive sync behaviors.
///
/// Logging:
/// - Uses `KBLog` with `kb*` helpers to include file/function/line.
/// - Avoids explicit OSLog privacy annotations; keep logs non-sensitive.
@main
struct KidBoxApp: App {
    
    // MARK: - State & dependencies
    
    /// SwiftData container used by the whole app.
    /// Stored as a plain property because `ModelContainer` is not a SwiftUI state type.
    private var modelContainer: ModelContainer
    
    /// Global navigation coordinator (single source of truth for routing).
    @StateObject private var coordinator = AppCoordinator()
    
    /// Scene lifecycle phase (active/inactive/background).
    @Environment(\.scenePhase) private var scenePhase
    
    /// UIKit application delegate adapter (push / Firebase messaging integration).
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    /// Shared notifications manager (push deep link bridge).
    @StateObject private var notifications = NotificationManager.shared
    
    // MARK: - Init
    
    /// Initializes the app and prepares the persistence layer.
    ///
    /// - Important:
    ///   Migration/backfill is started asynchronously and must not capture `self`.
    ///   It uses the local `container` value.
    init() {
        KBLog.app.kbInfo("KidBoxApp init")
        
        let container = ModelContainerProvider.makeContainer(inMemory: false)
        self.modelContainer = container
        
        // Best-effort migrations/backfills.
        KBLog.persistence.kbInfo("Starting migrations (best effort)")
        Task {
            do {
                let migrator = KidBoxMigrationActor(modelContainer: container)
                try await migrator.runAll()
                KBLog.persistence.kbInfo("Migrations OK")
            } catch {
                KBLog.persistence.kbError("Migrations FAILED: \(error.localizedDescription)")
            }
        }
        
        KBLog.app.kbInfo("KidBoxApp ready")
    }
    
    // MARK: - Scene
    
    var body: some Scene {
        WindowGroup {
            RootHostView()
                .environmentObject(coordinator)
            
            // MARK: URL handling (Google Sign-In)
                .onOpenURL { url in
                    KBLog.auth.kbInfo("onOpenURL received (GoogleSignIn handler)")
                    GIDSignIn.sharedInstance.handle(url)
                    
                    // Trigger post-login / post-deeplink sync flush.
                    let context = modelContainer.mainContext
                    KBLog.sync.kbInfo("Triggering post-URL flushGlobal")
                    SyncCenter.shared.flushGlobal(modelContext: context)
                }
            
            // MARK: Debug seeding (simulator-only)
                .onAppear {
                    let context = modelContainer.mainContext
                    KBLog.app.kbDebug("Root window appeared")
                    
#if DEBUG
#if targetEnvironment(simulator)
                    if Auth.auth().currentUser == nil {
                        KBLog.persistence.kbInfo("DEBUG seeding (simulator, no authenticated user)")
                        DebugSeeder.seedIfNeeded(context: context)
                    } else {
                        KBLog.persistence.kbInfo("DEBUG seed skipped (authenticated user)")
                    }
#else
                    KBLog.persistence.kbInfo("DEBUG seed disabled on real device")
#endif
#endif
                }
            
            // MARK: Debug-only services
                .task {
#if DEBUG
                    KBLog.sync.kbDebug("DEBUG FirestorePingService ping()")
                    FirestorePingService().ping { _ in }
#endif
                }
            
            // MARK: Push deep link consumption
                .onReceive(notifications.$pendingDeepLink) { link in
                    guard let link else { return }
                    
                    KBLog.auth.kbInfo("Pending deep link received")
                    
                    switch link {
                    case .document(let familyId, let docId):
                        KBLog.navigation.kbInfo("Deep link -> open document")
                        coordinator.openDocumentFromPush(familyId: familyId, docId: docId)
                    }
                    
                    notifications.consumeDeepLink()
                    KBLog.auth.kbDebug("Deep link consumed")
                }
        }
        .modelContainer(modelContainer)
        
        // MARK: Scene lifecycle -> sync behavior
        .onChange(of: scenePhase) { _, newPhase in
            let context = modelContainer.mainContext
            
            switch newPhase {
            case .active:
                KBLog.sync.kbInfo("ScenePhase active -> startAutoFlush + flushGlobal")
                SyncCenter.shared.startAutoFlush(modelContext: context)
                SyncCenter.shared.flushGlobal(modelContext: context)
                
            case .inactive:
                KBLog.sync.kbDebug("ScenePhase inactive")
                
            case .background:
                KBLog.sync.kbInfo("ScenePhase background -> stopAutoFlush + stopFamilyBundleRealtime")
                SyncCenter.shared.stopAutoFlush()
                
                // Optional but recommended: stop listeners when going to background.
                SyncCenter.shared.stopFamilyBundleRealtime()
                
            @unknown default:
                KBLog.sync.kbDebug("ScenePhase unknown default")
            }
        }
    }
}
