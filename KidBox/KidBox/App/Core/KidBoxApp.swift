//
//  KidBoxApp.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import SwiftData
import Combine
import OSLog
import GoogleSignIn
import FirebaseAuth
import FBSDKCoreKit

@main
struct KidBoxApp: App {
    
    private var modelContainer: ModelContainer
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var subscriptionManager = KBSubscriptionManager.shared
    // Osservato solo per invalidare la view quando l'utente cambia lingua nei
    // Settings: forza il ricalcolo di kbDeviceLocale() sotto, senza riavvio.
    @StateObject private var languageManager = LanguageManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notifications = NotificationManager.shared
    @State private var showLaunch = true
    @State private var lastForegroundMaintenanceAt: Date?
    /// Annuncio dalla console admin da mostrare in `BroadcastMessageView`.
    /// Sta qui e non nel coordinator perché non è navigazione: non ha famiglia,
    /// non ha destinazione, e non deve entrare nello stack di nessuna sezione.
    @State private var broadcastMessage: BroadcastMessage?
    
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
    
    /// Traduce la destinazione di un nudge in una rotta reale.
    ///
    /// Le destinazioni sono un insieme chiuso (`NudgeDestination`) proprio
    /// perché devono atterrare su schermate che esistono: un catalogo remoto
    /// non può inventare un posto dove mandare l'utente.
    @MainActor
    private func navigateToNudgeDestination(_ destination: NudgeDestination) {
        // Le sezioni di famiglia hanno bisogno della famiglia attiva. Se non
        // c'è (caso raro: utente senza famiglia) l'unica destinazione sensata
        // resta l'invito, che di famiglia non ha bisogno.
        guard let familyId = coordinator.activeFamilyId else {
            coordinator.navigate(to: .inviteCode)
            return
        }
        switch destination {
        case .invite:    coordinator.navigate(to: .inviteCode)
        case .documents: coordinator.navigate(to: .documentsHome)
        case .wallet:    coordinator.navigate(to: .walletHome(familyId: familyId))
        case .health:    coordinator.navigate(to: .pediatricChildSelector(familyId: familyId))
        case .ai:        coordinator.navigate(to: .askExpert)
        case .chat:      coordinator.navigate(to: .chat)
        case .calendar:  coordinator.navigate(to: .calendar(familyId: familyId))
        }
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
                
                // MARK: Universal Link — invito famiglia
                //
                // Il link viene solo messo da parte, non applicato qui: chi lo
                // riceve di norma non ha ancora un account, e il join richiede
                // l'utente autenticato. Chi non ha ancora finito l'onboarding
                // lo trova in `OnboardingWalkthroughView` (LinkInviteConfirmCard);
                // chi ce l'ha già finito, in `RootHostView`. Vedi `PendingFamilyInvite`.
                    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                        guard let url = activity.webpageURL else { return }
                        guard let invite = PendingFamilyInvite.parse(from: url) else {
                            KBLog.sync.kbDebug("Universal link ignorato (non è un invito): \(url.path)")
                            return
                        }
                        KBLog.sync.kbInfo("Universal link invito ricevuto familyId=\(invite.familyId)")
                        invite.store()
                    }

                // MARK: URL handling
                    .onOpenURL { url in
                        KBLog.auth.kbInfo("[KidBoxApp] onOpenURL -> \(url.absoluteString)")

                        // Invito da link. Va gestito QUI e non solo in
                        // `onContinueUserActivity`: SwiftUI consegna gli
                        // Universal Link a `onOpenURL` in diversi casi — è quello
                        // che succede davvero, e finora il link finiva dritto al
                        // gestore di Google Sign-In, che lo ignorava. Risultato:
                        // nessun invito messo da parte e wizard manuale.
                        if let invite = PendingFamilyInvite.parse(from: url) {
                            KBLog.sync.kbInfo("onOpenURL: invito da link familyId=\(invite.familyId)")
                            invite.store()
                            return
                        }

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
                // `receive(on:)` rimanda la consegna al giro di runloop
                // successivo. Serve al cold start: `@Published` rigioca il
                // valore alla sottoscrizione, cioè DURANTE la prima
                // costruzione del body, e un `path.append` dentro quel
                // passaggio di rendering può essere scartato dal
                // NavigationStack (tap sulla notifica che non apre nulla).
                    .onReceive(notifications.$pendingDeepLink.receive(on: DispatchQueue.main)) { link in
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

                        case .vehicle(let familyId, let vehicleId):
                            KBLog.navigation.kbInfo("Deep link -> open vehicle vehicleId=\(vehicleId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openVehicleFromPush(
                                    familyId: familyId,
                                    vehicleId: vehicleId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .subscriptionExpiring(let familyId):
                            KBLog.navigation.kbInfo("Deep link -> open profile (subscription expiring) familyId=\(familyId ?? "nil")")
                            if let familyId, !familyId.isEmpty {
                                coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                    coordinator.navigate(to: .profile)
                                }
                            } else {
                                coordinator.navigate(to: .profile)
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .housePayment(let familyId, let paymentId):
                            KBLog.navigation.kbInfo("Deep link -> open house payment paymentId=\(paymentId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openHousePaymentFromPush(
                                    familyId: familyId,
                                    paymentId: paymentId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .walletDocument(let familyId, let documentId):
                            KBLog.navigation.kbInfo("Deep link -> open wallet document documentId=\(documentId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openWalletDocumentFromPush(
                                    familyId: familyId,
                                    documentId: documentId,
                                    modelContext: modelContainer.mainContext
                                )
                            }
                            NotificationManager.shared.consumeDeepLink()

                        case .vaccine(let familyId, let childId, let vaccineId):
                            KBLog.navigation.kbInfo("Deep link -> open vaccine vaccineId=\(vaccineId)")
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.openVaccineFromPush(
                                    familyId: familyId,
                                    childId: childId,
                                    vaccineId: vaccineId,
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
                            // Si passa dalla lista spese e non dritti al dettaglio:
                            // è la lista a tenere acceso il realtime delle spese,
                            // quindi è lì che la spesa può arrivare quando la push
                            // precede la sincronizzazione. La home apre poi il
                            // dettaglio da sé. Come su Android.
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(
                                    to: .expensesHome(familyId: familyId, highlightExpenseId: expenseId))
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

                        case .loyaltyCard(let familyId, let cardId):
                            KBLog.navigation.kbInfo("Deep link -> open loyalty card cardId=\(cardId)")
                            Task { @MainActor in
                                BadgeManager.shared.clearWallet()
                                await CountersService.shared.reset(familyId: familyId, field: .wallet)
                            }
                            coordinator.switchFamilyIfNeededThenNavigate(to: familyId) {
                                coordinator.navigate(to: .loyaltyCardDetail(familyId: familyId, cardId: cardId))
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

                        case .broadcast(let id, let title, let body):
                            KBLog.navigation.kbInfo("Deep link -> broadcast id=\(id)")
                            // Nessuno switch di famiglia e nessuna navigazione:
                            // l'annuncio non appartiene a una famiglia. Il testo
                            // arriva già nel payload, quindi la sheet si apre
                            // anche offline.
                            broadcastMessage = BroadcastMessage(id: id, title: title, body: body)
                            NotificationManager.shared.consumeDeepLink()

                        case .nudge(let campaignId, let title, let body, let destination):
                            KBLog.navigation.kbInfo("Deep link -> nudge campaignId=\(campaignId)")
                            // Stessa sheet del broadcast, con in più la
                            // destinazione: il tap sul pulsante primario
                            // naviga, "Non ora" no.
                            broadcastMessage = BroadcastMessage(
                                id: campaignId,
                                title: title,
                                body: body,
                                campaignId: campaignId,
                                destination: destination
                            )
                            NotificationManager.shared.consumeDeepLink()
                        }
                        notifications.consumeDeepLink()
                        KBLog.auth.kbDebug("Deep link consumed")
                    }
                    .sheet(item: $broadcastMessage) { msg in
                        BroadcastMessageView(
                            title: msg.title,
                            message: msg.body,
                            actionTitle: msg.destination.map { _ in "Vai" },
                            onAction: {
                                if let campaignId = msg.campaignId {
                                    KBAnalytics.shared.logNudge(
                                        name: "nudge_opened", campaignId: campaignId)
                                }
                                if let destination = msg.destination {
                                    navigateToNudgeDestination(destination)
                                }
                            },
                            onDismiss: {
                                if let campaignId = msg.campaignId {
                                    KBAnalytics.shared.logNudge(
                                        name: "nudge_dismissed", campaignId: campaignId)
                                }
                            }
                        )
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
                AppAnalytics.trackAppOpen()
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
                    Task { @MainActor in
                        // Prima dei refresh: le notifiche già in coda vanno riconosciute
                        // come armate da questo device, altrimenti i filtri qui sotto le
                        // ignorerebbero e nessuno le rinnoverebbe più.
                        await KBDeviceReminderLedger.adoptExistingPendingIfNeeded()
                        TreatmentNotificationManager.rescheduleActiveTreatments(context: context)
                        KBLog.sync.kbDebug("Treatment notifications rescheduled on foreground")
                        await HousePaymentReminderService.shared.rescheduleAllActive(modelContext: context)
                        await VehicleReminderService.shared.rescheduleAllActive(modelContext: context)
                        // Dopo i refresh: la coda è al completo, e se nel
                        // frattempo è cambiata la lingua di sistema va riscritta
                        // — chi la cambia da lì non passa dal selettore in-app.
                        await KBNotificationLocalization.relocalizePendingIfLanguageChanged()
                    }
                    // Ricalcolo della coda nudge. Sta dentro il throttle dei
                    // 120s come il resto della manutenzione: è una lettura
                    // locale, ma non ha senso rifarla a ogni rientro rapido.
                    Task { @MainActor in
                        await NudgeEngine.shared.refresh(modelContext: context)
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
                if let lastStep = coordinator.lastOnboardingStepSeen {
                    AppAnalytics.onboardingAbandoned(lastStepSeen: lastStep)
                }
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
