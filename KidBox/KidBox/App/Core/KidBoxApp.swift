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
    @StateObject private var subscriptionManager = KBSubscriptionManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notifications = NotificationManager.shared
    @State private var showLaunch = true
    @State private var lastForegroundMaintenanceAt: Date?
    
    init() {
        KBFileLogger.shared.performStartupMaintenance()
        KBCrashHandler.install()
        KBLog.app.kbInfo("KidBoxApp init")
        let container = ModelContainerProvider.makeContainer(inMemory: false)
        self.modelContainer = container
        _appDelegate.wrappedValue.modelContainer = container
        if ModelContainerProvider.didQuarantineCorruptedStoreThisLaunch {
            KBLog.sync.kbInfo("SwiftData store was quarantined — scheduling bootstrap + flushGlobal")
            Task { @MainActor in
                let ctx = container.mainContext
                await FamilyBootstrapService(modelContext: ctx).bootstrapIfNeeded()
                SyncCenter.shared.flushGlobal(modelContext: ctx)
            }
        }
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
                    .environmentObject(subscriptionManager)
                    .environment(\.locale, kbDeviceLocale())
                    .environment(\.calendar, kbDeviceCalendar())
                // ── Mac Catalyst: rimuove lo sfondo ovale automatico da tutti i Button
                #if targetEnvironment(macCatalyst)
                    .buttonStyle(.plain)
                #endif
                // ── Tema chiaro / scuro / sistema ──────────────────────────
                    .preferredColorScheme(coordinator.appearanceMode.colorScheme)
                    .onReceive(NotificationCenter.default.publisher(for: .kidBoxFamilyKeyDidChange)) { _ in
                        AutoFillSnapshotWriter.scheduleRebuild(modelContext: modelContainer.mainContext)
                    }
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
                        
                        if url.scheme == "kidbox", url.host == "control",
                           url.path == "/open-family-photos-camera" || url.path == "open-family-photos-camera" {
                            KBLog.sync.kbInfo("onOpenURL control -> family photos camera shortcut")
                            coordinator.openFamilyPhotosWithCameraShortcut(
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
                        VehicleAttachmentService.shared.start(modelContext: modelContainer.mainContext)
                        HomeAttachmentService.shared.start(modelContext: modelContainer.mainContext)
                        PetEventAttachmentService.shared.start(modelContext: modelContainer.mainContext)
                        ExpenseAttachmentService.shared.start(modelContext: modelContainer.mainContext)
                        await OCRRecoveryMigration.runIfNeeded(modelContext: modelContainer.mainContext)
                        await OCRRecoveryMigration.runLifeAreaIfNeeded(modelContext: modelContainer.mainContext)
#if DEBUG
                        KBLog.sync.kbDebug("DEBUG FirestorePingService ping()")
                        FirestorePingService().ping { _ in }
#endif
                    }
                
                // MARK: Push deep link consumption
                    .onReceive(notifications.$pendingDeepLink) { link in
                        guard let link else { return }
                        KBLog.auth.kbInfo("[KidBoxApp] Pending deep link received: \(String(describing: link))")
                        switch link {
                            
                        case .document(let familyId, let docId):
                            KBLog.navigation.kbInfo("Deep link -> open document")
                            // ✅ Reset badge documenti
                            Task { @MainActor in
                                BadgeManager.shared.clearDocuments()
                                await CountersService.shared.reset(familyId: familyId, field: .documents)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openDocumentFromPush(
                                    familyId: familyId,
                                    docId: docId,
                                    modelContext: modelContainer.mainContext
                                )
                            }

                        case .chat(let familyId, let messageId):
                            KBLog.navigation.kbInfo("Deep link -> open chat familyId=\(familyId) messageId=\(messageId ?? "nil")")
                            Task { @MainActor in
                                BadgeManager.shared.clearChat()
                                await CountersService.shared.reset(familyId: familyId, field: .chat)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.pendingChatMentionMessageId = messageId
                                coordinator.navigate(to: .chat)
                            }

                        case .familyLocation(familyId: let familyId):
                            KBLog.navigation.kbInfo("Deep link -> open family location")
                            // ✅ Reset badge location (se presente)
                            Task { @MainActor in
                                BadgeManager.shared.clearLocation()
                                await CountersService.shared.reset(familyId: familyId, field: .location)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(to: .familyLocation(familyId: familyId))
                            }

                        case .todo(familyId: let familyId, childId: let childId, listId: let listId, todoId: let todoId):
                            KBLog.navigation.kbInfo("[DeepLink] todo -> openTodoFromPush listId=\(listId) todoId=\(todoId)")
                            // ✅ Reset badge todo
                            Task { @MainActor in
                                BadgeManager.shared.clearTodos()
                                await CountersService.shared.reset(familyId: familyId, field: .todos)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openTodoFromPush(
                                    familyId:    familyId,
                                    childId:     childId,
                                    listId:      listId,
                                    todoId:      todoId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .groceryItem(let familyId, _):
                            KBLog.navigation.kbInfo("Deep link -> open shopping list")
                            // ✅ Reset badge spesa
                            Task { @MainActor in
                                BadgeManager.shared.clearShopping()
                                await CountersService.shared.reset(familyId: familyId, field: .shopping)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(to: .shoppingList(familyId: familyId))
                            }

                        case .note(let familyId, let noteId):
                            KBLog.navigation.kbInfo("Deep link -> open note noteId=\(noteId)")
                            // ✅ Reset badge note
                            Task { @MainActor in
                                BadgeManager.shared.clearNotes()
                                await CountersService.shared.reset(familyId: familyId, field: .notes)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openNoteFromPush(
                                    familyId: familyId,
                                    noteId: noteId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .calendarEvent(let familyId, let eventId):
                            KBLog.navigation.kbInfo("Deep link -> open calendar eventId=\(eventId)")
                            Task { @MainActor in
                                BadgeManager.shared.clearCalendar()
                                await CountersService.shared.reset(familyId: familyId, field: .calendar)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openCalendarEventFromPush(
                                    familyId: familyId,
                                    eventId: eventId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .pediatricVisit(let familyId, let childId, let visitId):
                            KBLog.navigation.kbInfo("Deep link -> open pediatric visit visitId=\(visitId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openVisitFromPush(
                                    familyId: familyId,
                                    childId: childId,
                                    visitId: visitId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                            // ── promemoria cura ────────────────────────────
                        case .treatmentReminder(let familyId, let childId, let treatmentId):
                            KBLog.navigation.kbInfo("Deep link -> open treatment treatmentId=\(treatmentId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openTreatmentFromPush(
                                    familyId: familyId,
                                    childId: childId,
                                    treatmentId: treatmentId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                            // ── promemoria esame ───────────────────────────
                        case .examReminder(let familyId, let childId, let examId):
                            KBLog.navigation.kbInfo("Deep link -> open exam examId=\(examId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openExamFromPush(
                                    familyId: familyId,
                                    childId: childId,
                                    examId: examId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .expense(let familyId, let expenseId):
                            KBLog.navigation.kbInfo("Deep link -> open expense expenseId=\(expenseId)")
                            // ✅ Reset badge spese
                            Task { @MainActor in
                                BadgeManager.shared.clearExpenses()
                                await CountersService.shared.reset(familyId: familyId, field: .expenses)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(to: .expenseDetail(familyId: familyId, expenseId: expenseId))
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .askExpert(let familyId):
                            KBLog.navigation.kbInfo("Deep link -> open planning AI chat (AI summary) familyId=\(familyId ?? "nil")")
                            // La chat AI usa la famiglia attiva: se il contenuto è di un'altra
                            // famiglia, switcha PRIMA di navigare (mirror degli altri deep link).
                            if let familyId, !familyId.isEmpty {
                                coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                    coordinator.navigate(to: .askExpert)
                                }
                            } else {
                                coordinator.navigate(to: .askExpert)
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .walletTicket(let familyId, let ticketId):
                            KBLog.navigation.kbInfo("Deep link -> open wallet ticket ticketId=\(ticketId)")
                            Task { @MainActor in
                                BadgeManager.shared.clearWallet()
                                await CountersService.shared.reset(familyId: familyId, field: .wallet)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openWalletTicketFromPush(
                                    familyId: familyId,
                                    ticketId: ticketId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .passwordExpiry(let familyId, let entryId):
                            KBLog.navigation.kbInfo("Deep link -> password detail entryId=\(entryId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(to: .passwordDetail(familyId: familyId, entryId: entryId))
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .passwordSecurity(let familyId):
                            KBLog.navigation.kbInfo("Deep link -> password security")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(to: .passwordsSecurity(familyId: familyId))
                            }
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
                
            }
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
                Task { await KBAnalytics.shared.logSessionStart(entryPoint: .icon) }
                Task { await KBSubscriptionManager.shared.refreshCurrentEntitlement() }
                // Throttlato internamente a una chiamata ogni 6 ore.
                Task { await AppUpdateChecker.shared.checkForUpdate() }

                // Safety net: se la Share Extension ha salvato un "pendingShare"
                // nell'App Group ma il deep link kidbox://share non è stato
                // consegnato (può succedere: UIApplication.open dal responder
                // chain può fallire silenziosamente), drenalo qui comunque.
                // handleIncomingShare è idempotente: no-op se la chiave è vuota.
                coordinator.handleIncomingShare(modelContext: context)
                let now = Date()
                let canRunForegroundMaintenance: Bool = {
                    guard let last = lastForegroundMaintenanceAt else { return true }
                    return now.timeIntervalSince(last) >= 120
                }()
                if canRunForegroundMaintenance {
                    lastForegroundMaintenanceAt = now
                    // ── Rischedula notifiche cure (finestra scorrevole) ──────────────
                    // Avanza la finestra di 7 giorni se le notifiche pendenti sono poche.
                    Task {
                        let descriptor = FetchDescriptor<KBTreatment>(
                            predicate: #Predicate {
                                $0.reminderEnabled == true &&
                                $0.isActive        == true &&
                                $0.isDeleted       == false
                            }
                        )
                        guard let treatments = try? context.fetch(descriptor) else { return }
                        for treatment in treatments {
                            let displayName: String
                            if treatment.petId.isEmpty {
                                let cid = treatment.childId
                                let childDesc = FetchDescriptor<KBChild>(
                                    predicate: #Predicate { $0.id == cid }
                                )
                                displayName = (try? context.fetch(childDesc).first?.name) ?? ""
                            } else {
                                let pid = treatment.petId
                                let petDesc = FetchDescriptor<KBPet>(
                                    predicate: #Predicate { $0.id == pid }
                                )
                                displayName = (try? context.fetch(petDesc).first?.name) ?? "Animale domestico"
                            }
                            TreatmentNotificationManager.rescheduleIfNeeded(
                                treatment: treatment,
                                childName: displayName
                            )
                        }
                        KBLog.sync.kbDebug("Treatment notifications rescheduled on foreground")
                    }
                    Task { @MainActor in
                        await HousePaymentReminderService.shared.rescheduleAllActive(modelContext: context)
                    }
                } else {
                    KBLog.sync.kbDebug("ScenePhase active -> skip heavy foreground maintenance (throttled)")
                }
            case .inactive:
                KBLog.sync.kbDebug("ScenePhase inactive")
            case .background:
                KBLog.sync.kbInfo("ScenePhase background -> stopAutoFlush + stopFamilyBundleRealtime")
                // Le letture sono bufferizzate in memoria: qui è l'unico punto
                // in cui partono. Se si perde qualcosa è un costo accettabile.
                Task { await KBAnalytics.shared.flush() }
                SyncCenter.shared.stopAutoFlush()
                SyncCenter.shared.stopFamilyBundleRealtime()
                SyncCenter.shared.stopPetsRealtime()
                SyncCenter.shared.stopPetEventsRealtime()
                SyncCenter.shared.stopHomeItemsRealtime()
                SyncCenter.shared.stopHousePaymentsRealtime()
                SyncCenter.shared.stopVehiclesRealtime()
                SyncCenter.shared.stopVehicleEventsRealtime()
            @unknown default:
                KBLog.sync.kbDebug("ScenePhase unknown default")
            }
        }
    }
}
