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
import FBSDKCoreKit

@main
struct KidBoxApp: App {
    
    private var modelContainer: ModelContainer
    @StateObject private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notifications = NotificationManager.shared
    @State private var showLaunch = true
    
    init() {
        KBLog.app.kbInfo("KidBoxApp init")
        let container = ModelContainerProvider.makeContainer(inMemory: false)
        self.modelContainer = container
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
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                RootHostView()
                    .environmentObject(coordinator)
                // ── Tema chiaro / scuro / sistema ──────────────────────────
                    .preferredColorScheme(coordinator.appearanceMode.colorScheme)
                // ──────────────────────────────────────────────────────────
                
                // MARK: URL handling
                    .onOpenURL { url in
                        KBLog.auth.kbInfo("[KidBoxApp] onOpenURL -> \(url.absoluteString)")
                        if url.scheme == "kidbox", url.host == "share" {
                            KBLog.sync.kbInfo("onOpenURL share scheme -> handleIncomingShare")
                            coordinator.handleIncomingShare(
                                modelContext: modelContainer.mainContext
                            )
                            return
                        }
                        
                        KBLog.auth.kbInfo("onOpenURL received url=\(url.absoluteString)")
                        
                        // 1) Facebook
                        let handledByFacebook = ApplicationDelegate.shared.application(
                            UIApplication.shared,
                            open: url,
                            sourceApplication: nil,
                            annotation: nil
                        )
                        if handledByFacebook {
                            KBLog.auth.kbInfo("onOpenURL handled by Facebook SDK")
                            let context = modelContainer.mainContext
                            Task { SyncCenter.shared.flushGlobal(modelContext: context) }
                            return
                        }
                        
                        // 2) Google
                        KBLog.auth.kbInfo("onOpenURL forwarded to GoogleSignIn handler")
                        GIDSignIn.sharedInstance.handle(url)
                        let context = modelContainer.mainContext
                        SyncCenter.shared.flushGlobal(modelContext: context)
                    }
                
                // MARK: Debug-only services
                    .task {
                        TreatmentAttachmentService.shared.start(modelContext: modelContainer.mainContext)
                        VisitAttachmentService.shared.start(modelContext: modelContainer.mainContext)
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
                            coordinator.openDocumentFromPush(
                                familyId: familyId,
                                docId: docId,
                                modelContext: modelContainer.mainContext
                            )
                        case .chat:
                            KBLog.navigation.kbInfo("Deep link -> open chat")
                            coordinator.navigate(to: .chat)
                        case .familyLocation(familyId: let familyId):
                            KBLog.navigation.kbInfo("Deep link -> open family location")
                            coordinator.setActiveFamily(familyId)
                            coordinator.navigate(to: .familyLocation(familyId: familyId))
                        case .todo(familyId: let familyId, childId: let childId, listId: let listId, todoId: let todoId):
                            KBLog.navigation.kbInfo("[DeepLink] todo -> navigate todoList listId=\(listId) todoId=\(todoId)")
                            TodoHighlightStore.shared.set(todoId)
                            coordinator.navigate(to: .todoList(familyId: familyId, childId: childId, listId: listId))
                            NotificationManager.shared.consumeDeepLink()
                        case .groceryItem(let familyId, _):
                            KBLog.navigation.kbInfo("Deep link -> open shopping list")
                            coordinator.setActiveFamily(familyId)
                            coordinator.navigate(to: .shoppingList(familyId: familyId))
                        case .note(let familyId, let noteId):
                            KBLog.navigation.kbInfo("Deep link -> open note noteId=\(noteId)")
                            coordinator.setActiveFamily(familyId)
                            coordinator.openNoteFromPush(
                                familyId: familyId,
                                noteId: noteId,
                                modelContext: modelContainer.mainContext
                            )
                            NotificationManager.shared.consumeDeepLink()
                        case .calendarEvent(let familyId, let eventId):
                            KBLog.navigation.kbInfo("Deep link -> open calendar eventId=\(eventId)")
                            coordinator.setActiveFamily(familyId)
                            coordinator.navigate(to: .calendar(familyId: familyId, highlightEventId: eventId))
                            NotificationManager.shared.consumeDeepLink()
                        }
                        notifications.consumeDeepLink()
                        KBLog.auth.kbDebug("Deep link consumed")
                    }
                
                // Launch screen
                if showLaunch {
                    LaunchScreenView()
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    showLaunch = false
                                }
                            }
                        }
                }
                
            } // ZStack
        }
        .modelContainer(modelContainer)
        
        // MARK: Scene lifecycle
        .onChange(of: scenePhase) { _, newPhase in
            let context = modelContainer.mainContext
            switch newPhase {
            case .active:
                KBLog.sync.kbInfo("ScenePhase active -> startAutoFlush + flushGlobal")
                SyncCenter.shared.startAutoFlush(modelContext: context)
                SyncCenter.shared.flushGlobal(modelContext: context)
                BadgeManager.shared.refreshAppBadge()
            case .inactive:
                KBLog.sync.kbDebug("ScenePhase inactive")
            case .background:
                KBLog.sync.kbInfo("ScenePhase background -> stopAutoFlush + stopFamilyBundleRealtime")
                SyncCenter.shared.stopAutoFlush()
                SyncCenter.shared.stopFamilyBundleRealtime()
            @unknown default:
                KBLog.sync.kbDebug("ScenePhase unknown default")
            }
        }
    }
}
