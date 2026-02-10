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
        //FirebaseBootstrap.configureIfNeeded()
        KBLog.app.info("KidBoxApp init")
        self.modelContainer = ModelContainerProvider.makeContainer(inMemory: false)
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
                    if Auth.auth().currentUser == nil {
                        DebugSeeder.seedIfNeeded(context: context)
                    } else {
                        KBLog.persistence.info("DEBUG seed skipped (authenticated user)")
                    }
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
