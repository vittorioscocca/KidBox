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

@main
struct KidBoxApp: App {
    private var modelContainer: ModelContainer
    @StateObject private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notifications = NotificationManager.shared

    init() {
        KBLog.app.info("KidBoxApp init")
        
        let container = ModelContainerProvider.makeContainer(inMemory: false)
        self.modelContainer = container
        
        // ✅ Migration/backfill: cattura SOLO `container`, non `self`
        Task {
            do {
                let migrator = KidBoxMigrationActor(modelContainer: container)
                try await migrator.runAll()
                KBLog.persistence.info("Migrations OK")
            } catch {
                KBLog.persistence.error("Migrations FAILED: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        KBLog.app.info("KidBoxApp ready")
    }
    
    var body: some Scene {
        WindowGroup {
            RootHostView()
                .environmentObject(coordinator)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                    
                    // trigger post-login
                    let context = modelContainer.mainContext
                    SyncCenter.shared.flushGlobal(modelContext: context)
                }
                .onAppear {
                    let context = modelContainer.mainContext
                    
                    #if DEBUG
                    #if targetEnvironment(simulator)
                    if Auth.auth().currentUser == nil {
                        DebugSeeder.seedIfNeeded(context: context)
                    } else {
                        KBLog.persistence.info("DEBUG seed skipped (authenticated user)")
                    }
                    #else
                    KBLog.persistence.info("DEBUG seed disabled on real device")
                    #endif
                    #endif
                }
                .task {
                #if DEBUG
                    FirestorePingService().ping { _ in }
                #endif
                }
                .onReceive(notifications.$pendingDeepLink) { link in
                    guard let link else { return }
                    
                    switch link {
                    case .document(let familyId, let docId):
                        coordinator.openDocumentFromPush(familyId: familyId, docId: docId)
                    }
                    
                    notifications.consumeDeepLink()
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            let context = modelContainer.mainContext
            if newPhase == .active {
                SyncCenter.shared.startAutoFlush(modelContext: context)
                SyncCenter.shared.flushGlobal(modelContext: context)
            } else {
                SyncCenter.shared.stopAutoFlush()
                // opzionale ma consigliato: stop listeners quando vai in background
                SyncCenter.shared.stopFamilyBundleRealtime()
            }
        }
        
    }
}
