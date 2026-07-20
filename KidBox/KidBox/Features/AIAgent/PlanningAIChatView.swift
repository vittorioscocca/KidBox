//
//  PlanningaiChatView.swift
//  KidBox
//
//  Created by vscocca on 24/03/26.
//

//
//  PlanningAIChatView.swift
//  KidBox
//
//  Interfaccia chat per l'agente AI di pianificazione famiglia.
//
//  Design:
//  - Header compatto con briefing del giorno (eventi, todo urgenti, dosi)
//  - Chat con bolle AI riutilizzando AIChatBubbleView / AIChatTypingIndicator
//  - Action cards inline: quando l'agente propone un'azione appare una card
//    interattiva sotto la bolla con bottoni Conferma / Annulla
//  - Chip di suggerimento rapido sopra l'input bar
//  - Input bar con invio e tasto clear conversation
//
//  Accesso: dalla HomeView card "Assistente" → .askExpert route
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Entry point (gestisce il caricamento dei dati da SwiftData)

struct PlanningAIChatView: View {

    /// Se valorizzato (o da notifica), mostrato come primo messaggio assistente in chat.
    var initialMessage: String? = nil

    @Environment(\.modelContext)  private var modelContext
    @Environment(\.colorScheme)   private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // ── Family ────────────────────────────────────────────────────
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    @Query private var members: [KBFamilyMember]
    
    // ── Planning data queries ─────────────────────────────────────
    @Query private var allCalendarEvents: [KBCalendarEvent]
    @Query private var allTodos:          [KBTodoItem]
    @Query private var allRoutines:       [KBRoutine]
    @Query private var allRoutineChecks:  [KBRoutineCheck]
    @Query private var allTreatments:     [KBTreatment]
    @Query private var allVisits:         [KBMedicalVisit]
    @Query private var allVaccines:       [KBVaccine]
    @Query private var allChildren:       [KBChild]
    
    // ── Memoria famiglia ─────────────────────────────────────────
    @Query(sort: \KBNote.updatedAt, order: .reverse)         private var allNotes:    [KBNote]
    @Query(sort: \KBExpense.date, order: .reverse)           private var allExpenses: [KBExpense]
    @Query                                                   private var allExpCats:  [KBExpenseCategory]
    @Query(sort: \KBGroceryItem.createdAt, order: .reverse)  private var allGrocery:  [KBGroceryItem]
    @Query(sort: \KBChatMessage.createdAt, order: .reverse)  private var allChat:     [KBChatMessage]
    @Query(sort: \KBDocument.updatedAt, order: .reverse)     private var allDocuments: [KBDocument]
    @Query(sort: \KBWalletTicket.updatedAt, order: .reverse) private var allWalletTickets: [KBWalletTicket]
    
    @Query(sort: \KBPet.name) private var allPets: [KBPet]
    @Query(sort: \KBPetEvent.date, order: .reverse) private var allPetEvents: [KBPetEvent]
    @Query(sort: \KBHomeItem.name) private var allHomeItems: [KBHomeItem]
    @Query(sort: \KBHousePayment.name) private var allHousePayments: [KBHousePayment]
    @Query(sort: \KBVehicle.name) private var allVehicles: [KBVehicle]
    @Query(sort: \KBVehicleEvent.date, order: .reverse) private var allVehicleEvents: [KBVehicleEvent]
    
    // ── Pediatria avanzata ────────────────────────────────────────
    // allVisits e allVaccines già presenti sopra — riutilizzati
    @Query private var allProfiles:  [KBPediatricProfile]
    @Query(sort: \KBMedicalExam.updatedAt, order: .reverse) private var allExamsAdv: [KBMedicalExam]
    
    private var family: KBFamily? {
        ActiveFamilyResolver.family(from: families, activeFamilyId: coordinator.activeFamilyId)
    }
    private var familyId: String { family?.id ?? "" }
    private var familyName: String { family?.name ?? "Famiglia" }
    
    // ── Derived collections ───────────────────────────────────────
    
    private var memberNames: [String: String] {
        Dictionary(uniqueKeysWithValues:
                    members
            .filter { $0.familyId == familyId }
            .compactMap { m -> (String, String)? in
                guard let name = m.displayName else { return nil }
                return (m.userId, name)
            }
        )
    }
    
    private var childNames: [String: String] {
        Dictionary(uniqueKeysWithValues:
                    allChildren
            .filter { $0.familyId == familyId }
            .map { ($0.id, $0.name) }
        )
    }
    
    private var upcomingEvents: [KBCalendarEvent] {
        let now     = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        let uid = Auth.auth().currentUser?.uid
        return allCalendarEvents.filter {
            $0.familyId == familyId && !$0.isDeleted && $0.isVisible(to: uid) &&
            $0.startDate >= now && $0.startDate <= horizon
        }.sorted { $0.startDate < $1.startDate }
    }
    
    private var openTodos: [KBTodoItem] {
        allTodos.filter { $0.familyId == familyId && !$0.isDeleted && !$0.isDone }
    }
    
    private var activeRoutines: [KBRoutine] {
        allRoutines.filter { $0.familyId == familyId && !$0.isDeleted && $0.isActive }
    }
    
    private var todayChecks: Set<String> {
        let today = Date().kbDayKey()
        return Set(
            allRoutineChecks
                .filter { $0.familyId == familyId && $0.dayKey == today }
                .map { $0.routineId }
        )
    }
    
    private var activeTreatments: [KBTreatment] {
        allTreatments.filter {
            $0.familyId == familyId && !$0.isDeleted && $0.isActive && $0.petId.isEmpty
        }
    }
    
    private var visitsWithNextDate: [KBMedicalVisit] {
        allVisits.filter { $0.familyId == familyId && !$0.isDeleted && $0.nextVisitDate != nil }
    }
    
    private var visitsWithPendingExams: [KBMedicalVisit] {
        allVisits.filter { v in
            v.familyId == familyId && !v.isDeleted &&
            v.prescribedExams.contains { $0.deadline != nil }
        }
    }
    
    private var upcomingVaccines: [KBVaccine] {
        allVaccines.filter {
            $0.familyId == familyId && !$0.isDeleted &&
            ($0.status == .scheduled || $0.status == .planned)
        }
    }
    
    // ── Memoria famiglia ─────────────────────────────────────────
    
    private var recentNotes: [KBNote] {
        Array(allNotes
            .filter { $0.familyId == familyId && !$0.isDeleted }
            .prefix(10))
    }
    
    private var recentExpenses: [KBExpense] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return allExpenses.filter {
            $0.familyId == familyId && !$0.isDeleted && $0.date >= cutoff
        }
    }
    
    private var expenseCategoryNames: [String: String] {
        Dictionary(uniqueKeysWithValues:
                    allExpCats
            .filter { $0.familyId == familyId && !$0.isDeleted }
            .map { ($0.id, $0.name) }
        )
    }
    
    private var pendingGroceryItems: [KBGroceryItem] {
        allGrocery.filter {
            $0.familyId == familyId && !$0.isDeleted && !$0.isPurchased
        }
    }
    
    private var recentChatMessages: [KBChatMessage] {
        Array(allChat
            .filter { $0.familyId == familyId && !$0.isDeleted && $0.type == .text }
            .prefix(20))
    }

    private var recentDocuments: [KBDocument] {
        Array(allDocuments
            .filter { $0.familyId == familyId && !$0.isDeleted }
            .prefix(10))
    }

    private var recentWalletTickets: [KBWalletTicket] {
        Array(allWalletTickets
            .filter { $0.familyId == familyId && !$0.isDeleted }
            .prefix(10))
    }
    
    private var contextPets: [KBPet] {
        allPets.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var contextPetEvents: [KBPetEvent] {
        Array(allPetEvents.filter { $0.familyId == familyId && !$0.isDeleted }.prefix(50))
    }
    
    private var contextHomeItems: [KBHomeItem] {
        allHomeItems.filter { $0.familyId == familyId && !$0.isDeleted }
    }

    private var contextHousePayments: [KBHousePayment] {
        allHousePayments.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var contextVehicles: [KBVehicle] {
        allVehicles.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var contextVehicleEvents: [KBVehicleEvent] {
        Array(allVehicleEvents.filter { $0.familyId == familyId && !$0.isDeleted }.prefix(50))
    }
    
    // ── Pediatria avanzata ────────────────────────────────────────
    
    private var pediatricProfiles: [String: KBPediatricProfile] {
        Dictionary(uniqueKeysWithValues:
                    allProfiles
            .filter { $0.familyId == familyId }
            .map { ($0.childId, $0) }
        )
    }
    
    private var allVisitsForChildren: [KBMedicalVisit] {
        // Riusa allVisits già fetchata sopra — nessuna query duplicata
        allVisits.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var allExamsForChildren: [KBMedicalExam] {
        allExamsAdv.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var allVaccinesForChildren: [KBVaccine] {
        // Riusa allVaccines già fetchata sopra — nessuna query duplicata
        allVaccines.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    // ── Today briefing stats ──────────────────────────────────────
    
    private var todayEvents: [KBCalendarEvent] {
        let uid = Auth.auth().currentUser?.uid
        return allCalendarEvents.filter {
            $0.familyId == familyId && !$0.isDeleted && $0.isVisible(to: uid) &&
            Calendar.current.isDateInToday($0.startDate)
        }.sorted { $0.startDate < $1.startDate }
    }
    
    private var urgentTodos: [KBTodoItem] {
        openTodos.filter { ($0.priorityRaw ?? 0) == 1 || ($0.dueAt.map { $0 < Date() } ?? false) }
    }
    
    private var todayDosesCount: Int {
        activeTreatments.reduce(0) { $0 + $1.scheduleTimes.count }
    }
    
    // ── ViewModel — opzionale, creato una sola volta in .task ─────
    // Segue il pattern di HealthAIChatView: @State opzionale + .task
    // così SwiftUI mantiene viva l'istanza per tutta la vita della view
    // e non ne crea una nuova ad ogni render del body.
    @State private var vm: PlanningAIChatViewModel? = nil
    @State private var showUpgrade = false
    
    var body: some View {
        Group {
            if !KBSubscriptionManager.shared.currentPlan.includesAI {
                // ── Piano Free: schermata locked ─────────────────────
                aiLockedView
            } else if let vm {
                PlanningAIChatInnerView(
                    vm:               vm,
                    familyId:         familyId,
                    familyName:       familyName,
                    todayEvents:      todayEvents,
                    urgentTodosCount: urgentTodos.count,
                    todayDosesCount:  todayDosesCount,
                    memberNames:      memberNames,
                    childNames:       childNames
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Assistente")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView()
                .environmentObject(KBSubscriptionManager.shared)
        }
        .task(id: familyId) {
            guard KBSubscriptionManager.shared.currentPlan.includesAI else { return }
            guard !familyId.isEmpty else { return }
            let newVM = PlanningAIChatViewModel(
                familyId:               familyId,
                familyName:             familyName,
                memberNames:            memberNames,
                horizonDays:            14,
                calendarEvents:         upcomingEvents,
                openTodos:              openTodos,
                activeRoutines:         activeRoutines,
                todayChecks:            todayChecks,
                childNames:             childNames,
                activeTreatments:       activeTreatments,
                visitsWithNextDate:     visitsWithNextDate,
                visitsWithPendingExams: visitsWithPendingExams,
                upcomingVaccines:       upcomingVaccines,
                recentNotes:            recentNotes,
                recentExpenses:         recentExpenses,
                expenseCategoryNames:   expenseCategoryNames,
                pendingGroceryItems:    pendingGroceryItems,
                recentChatMessages:     recentChatMessages,
                recentDocuments:        recentDocuments,
                recentWalletTickets:    recentWalletTickets,
                children:               allChildren.filter { $0.familyId == familyId },
                pediatricProfiles:      pediatricProfiles,
                allVisits:              allVisitsForChildren,
                allExams:               allExamsForChildren,
                allVaccines:            allVaccinesForChildren,
                pets:                   contextPets,
                petEvents:              contextPetEvents,
                homeItems:              contextHomeItems,
                housePayments:          contextHousePayments,
                vehicles:               contextVehicles,
                vehicleEvents:          contextVehicleEvents,
                modelContext:           modelContext
            )
            vm = newVM
            await Task.yield()
            await newVM.loadOrCreateConversation()

            let healthInsight = HealthPatternAnalyzerService.shared.consumeUnreadInsightIfNeeded(
                familyId: familyId,
                modelContext: modelContext
            )
            let notifSeed = NotificationManager.shared.takePendingPlanningInitialMessage()
            let seed = healthInsight
                ?? initialMessage
                ?? notifSeed
            if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let forceInject = notifSeed != nil || initialMessage != nil
                newVM.injectInitialAssistantMessageIfNeeded(seed, force: forceInject)
            }
        }
    }
    
    // MARK: - AI locked view (piano Free)
    
    private var aiLockedView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Assistente AI")
                    .font(.title2.bold())
                Text("Disponibile con i piani Pro e Max")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Passa a Pro per accedere all'assistente che conosce calendario, spesa, salute dei tuoi figli, animali, casa, garage e molto altro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if KBSubscriptionManager.shared.isFamilyOwner {
                Button {
                    showUpgrade = true
                } label: {
                    Text("Scopri i piani")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color(red: 0.35, green: 0.6, blue: 0.85)))
                }
            } else {
                NonOwnerUpgradeNotice()
                    .padding(.horizontal, 16)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inner view (riceve il ViewModel già costruito)

private struct PlanningAIChatInnerView: View {
    
    @ObservedObject var vm: PlanningAIChatViewModel
    @Environment(\.colorScheme)  private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    let familyId:         String
    let familyName:       String
    let todayEvents:      [KBCalendarEvent]
    let urgentTodosCount: Int
    let todayDosesCount:  Int
    let memberNames:      [String: String]
    let childNames:       [String: String]
    
    // ── AI Settings ───────────────────────────────────────────────
    @ObservedObject private var aiSettings = AISettings.shared
    @State private var showAISettings = false
    
    // ── Action sheet state ────────────────────────────────────────
    @State private var pendingAction: PlanningAction? = nil
    @State private var showActionSheet = false
    @State private var showClearConfirm = false
    
    // ── Action result feedback ────────────────────────────────────
    @State private var actionResultMessage: String? = nil
    @State private var actionResultIsError  = false
    
    // ── New event / todo sheets ───────────────────────────────────
    @State private var showNewEventSheet = false
    @State private var showNewTodoSheet  = false
    @State private var prefillEventTitle = ""
    @State private var prefillTodoTitle  = ""
    
    // ── Scroll proxy ──────────────────────────────────────────────
    @Namespace private var bottomID
    
    private let tint = KBTheme.tint
    
    var body: some View {
        ZStack(alignment: .bottom) {
            KBTheme.background(colorScheme).ignoresSafeArea()
            
            // ── Gate: AI non abilitata ────────────────────────────
            if !aiSettings.isEnabled {
                aiDisabledState
            }
            // ── Stato: contesto in preparazione ──────────────────
            else if vm.isLoadingContext {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparazione contesto…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // ── Stato normale: chat ───────────────────────────────
            else {
                VStack(spacing: 0) {
                    // Provider badge
                    providerBadge
                    
                    // Today briefing pill strip
                    briefingStrip
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    
                    Divider().opacity(0.4)
                    
                    // Error banner (sotto il briefing, sopra i messaggi)
                    if let error = vm.errorMessage {
                        errorBanner(error)
                    }
                    
                    // Messages
                    AIChatMessageListView(
                        messages: vm.messages,
                        isLoading: vm.isLoading,
                        streamingMessageId: vm.streamingMessageId,
                        scrollButtonTint: tint,
                        bottomPadding: 140,
                        onStreamingComplete: { vm.finishStreaming(messageId: $0) },
                        intro: {
                            if vm.messages.isEmpty {
                                emptyState
                                    .padding(.top, 40)
                            }
                        },
                        messageRow: { message, isStreaming, onTick in
                            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                                AIChatBubbleView(
                                    text: message.content,
                                    isUser: message.role == .user,
                                    date: message.createdAt,
                                    streamReveal: isStreaming && message.role == .assistant,
                                    onStreamingTick: onTick,
                                    onStreamingComplete: { vm.finishStreaming(messageId: message.id) }
                                )
                                if message.role == .assistant, !isStreaming {
                                    actionCards(for: message)
                                }
                            }
                        }
                    )
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Input bar flottante
                VStack(spacing: 0) {
                    Spacer()
                    inputArea
                }
            }
        }
        .navigationTitle("Assistente")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showClearConfirm = true
                    } label: {
                        Label("Nuova conversazione", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        showAISettings = true
                    } label: {
                        Label("Impostazioni AI", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .confirmationDialog("Cancellare la conversazione?", isPresented: $showClearConfirm) {
            Button("Cancella", role: .destructive) { vm.clearConversation() }
            Button("Annulla", role: .cancel) { }
        }
        .onChange(of: vm.actionExecutionSummary) { _, summary in
            guard let summary, !summary.isEmpty else { return }
            actionResultIsError = false
            actionResultMessage = summary
        }
        // Feedback toast
        .overlay(alignment: .top) {
            if let msg = actionResultMessage {
                HStack(spacing: 8) {
                    Image(systemName: actionResultIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(msg)
                        .font(.footnote.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(actionResultIsError ? Color.red.opacity(0.85) : tint))
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { actionResultMessage = nil }
                    }
                }
            }
        }
        .sheet(isPresented: $showNewEventSheet) {
            CalendarEventFormView(
                familyId:     familyId,
                initialDate:  Date(),
                prefillTitle: prefillEventTitle
            )
        }
        .sheet(isPresented: $showAISettings) {
            NavigationStack { AISettingsView() }
        }
    }
    
    // MARK: - Provider badge
    
    private var providerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(tint)
            Text("Assistente AI KidBox")
                .font(.caption.bold())
            Text("· Calendario, to-do, salute")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.06))
    }
    
    // MARK: - AI disabled state
    
    private var aiDisabledState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.5))
            }
            
            VStack(spacing: 8) {
                Text("Assistente AI non attivato")
                    .font(.headline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text("Attiva l'assistente nelle impostazioni per usare questa funzione.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                showAISettings = true
            } label: {
                Label("Apri Impostazioni AI", systemImage: "gear")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error banner
    
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                vm.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }
    
    // MARK: - Briefing strip
    
    private var briefingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Data
                briefingChip(
                    icon: "calendar",
                    label: Date().formatted(.dateTime.weekday(.wide).day().month().locale(kbDeviceLocale())),
                    color: tint
                )
                
                // Eventi oggi
                if !todayEvents.isEmpty {
                    briefingChip(
                        icon: "clock",
                        label: "\(todayEvents.count) event\(todayEvents.count == 1 ? "o" : "i") oggi",
                        color: .blue
                    )
                }
                
                // Todo urgenti
                if urgentTodosCount > 0 {
                    briefingChip(
                        icon: "exclamationmark.circle.fill",
                        label: "\(urgentTodosCount) urgent\(urgentTodosCount == 1 ? "e" : "i")",
                        color: .red
                    )
                }
                
                // Dosi
                if todayDosesCount > 0 {
                    briefingChip(
                        icon: "pills.fill",
                        label: "\(todayDosesCount) dos\(todayDosesCount == 1 ? "e" : "i")",
                        color: .green
                    )
                }
            }
        }
    }
    
    private func briefingChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(KBTheme.primaryText(colorScheme))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 2, y: 1)
        )
    }
    
    // MARK: - Empty state
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            
            // ── Banner sintesi settimanale ────────────────────────────
            if let summary = WeeklySummaryService.shared.lastSummaryText {
                weeklySummaryBanner(text: summary)
            }
            
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tint)
            }
            
            VStack(spacing: 6) {
                Text("Ciao, sono il tuo assistente")
                    .font(.headline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text("Conosco il tuo calendario, i to-do, le cure, visite ed esami, i documenti, il wallet, le note, le spese e le scadenze sanitarie.\nChiedimi qualsiasi cosa.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            // Quick start chips
            quickStartChips
        }
    }
    
    @ViewBuilder
    private func weeklySummaryBanner(text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Text("Recap settimana")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
                .lineSpacing(3)
            Button {
                vm.inputText = "Dimmi di più sul recap di questa settimana"
                Task { await vm.send() }
            } label: {
                Text("Approfondisci →")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 4)
    }
    
    private var quickStartChips: some View {
        let suggestions = [
            "Cosa ho in programma questa settimana?",
            "Ci sono scadenze sanitarie urgenti?",
            "Quali to-do sono ancora aperti?",
            "Ho spazio libero domani pomeriggio?"
        ]
        
        return VStack(spacing: 8) {
            ForEach(suggestions, id: \.self) { s in
                Button {
                    vm.inputText = s
                    Task { await vm.send() }
                } label: {
                    HStack {
                        Text(s)
                            .font(.subheadline)
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(tint.opacity(0.6))
                            .font(.system(size: 18))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(KBTheme.cardBackground(colorScheme))
                            .shadow(color: KBTheme.shadow(colorScheme), radius: 3, y: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
    }
    
    // MARK: - Action cards inline
    
    @ViewBuilder
    private func actionCards(for message: KBAIMessage) -> some View {
        if !vm.autoExecutedMessageIds.contains(message.id) {
            let actions = PlanningActionParser.parse(
                from:       message.content,
                todos:      vm.openTodos,
                visits:     vm.visitsWithNextDate,
                treatments: vm.activeTreatments,
                childNames: childNames
            )
            if !actions.isEmpty {
                VStack(spacing: 8) {
                    ForEach(actions) { action in
                        PlanningActionCard(
                            action:      action,
                            tint:        tint,
                            colorScheme: colorScheme,
                            onConfirm:   { executeAction(action) },
                            onNavigate:  { navigateForAction(action) }
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
    
    // MARK: - Action execution
    
    private func executeAction(_ action: PlanningAction) {
        switch action.kind {
        case .createEvent:
            prefillEventTitle = action.title
            showNewEventSheet = true
            
        case .createTodo:
            Task { await persistTodoFromCard(action) }
            
        case .createGrocery:
            Task { await persistGroceryFromCard(action) }
            
        case .createNote:
            Task { await persistNoteFromCard(action) }
            
        case .setReminder:
            Task { await executeReminder(action) }
            
        case .navigate:
            navigateForAction(action)
        }
    }
    
    @MainActor
    private func persistGroceryFromCard(_ action: PlanningAction) async {
        let uid = Auth.auth().currentUser?.uid ?? "ai-agent"
        let executor = PlanningActionExecutor(
            modelContext: modelContext,
            familyId: familyId,
            uid: uid,
            children: vm.children,
            pendingGroceryNames: vm.pendingGroceryItems.map(\.name)
        )
        let payload = PlanningExecutableAction(
            type: "grocery_add",
            items: action.groceryItems,
            title: nil, body: nil, notes: nil, category: nil,
            dueAt: nil, startAt: nil, endAt: nil, isAllDay: nil,
            childId: nil, listId: nil
        )
        showExecutionResult(await executor.execute([payload]))
    }
    
    @MainActor
    private func persistTodoFromCard(_ action: PlanningAction) async {
        let uid = Auth.auth().currentUser?.uid ?? "ai-agent"
        let executor = PlanningActionExecutor(
            modelContext: modelContext,
            familyId: familyId,
            uid: uid,
            children: vm.children,
            pendingGroceryNames: vm.pendingGroceryItems.map(\.name)
        )
        let payload = PlanningExecutableAction(
            type: "todo_add",
            items: nil,
            title: action.title, body: nil, notes: nil, category: nil,
            dueAt: nil, startAt: nil, endAt: nil, isAllDay: nil,
            childId: nil, listId: nil
        )
        showExecutionResult(await executor.execute([payload]))
    }
    
    @MainActor
    private func persistNoteFromCard(_ action: PlanningAction) async {
        let uid = Auth.auth().currentUser?.uid ?? "ai-agent"
        let executor = PlanningActionExecutor(
            modelContext: modelContext,
            familyId: familyId,
            uid: uid,
            children: vm.children,
            pendingGroceryNames: vm.pendingGroceryItems.map(\.name)
        )
        let payload = PlanningExecutableAction(
            type: "note_add",
            items: nil,
            title: action.title,
            body: action.noteBody ?? action.title,
            notes: nil, category: nil,
            dueAt: nil, startAt: nil, endAt: nil, isAllDay: nil,
            childId: nil, listId: nil
        )
        showExecutionResult(await executor.execute([payload]))
    }
    
    private func showExecutionResult(_ summary: String?) {
        guard let summary, !summary.isEmpty else {
            actionResultIsError = true
            actionResultMessage = "Impossibile completare l'azione."
            return
        }
        actionResultIsError = false
        actionResultMessage = summary
    }
    
    // MARK: - Reminder execution
    
    @MainActor
    private func executeReminder(_ action: PlanningAction) async {
        let request = buildReminderRequest(from: action)
        let result  = await PlanningReminderService.schedule(
            request:      request,
            modelContext: modelContext
        )
        
        withAnimation {
            switch result {
            case .scheduled(let description):
                actionResultIsError    = false
                actionResultMessage    = description
            case .notAuthorized:
                actionResultIsError    = true
                actionResultMessage    = "Notifiche non autorizzate. Vai in Impostazioni per abilitarle."
            case .failed:
                actionResultIsError    = true
                actionResultMessage    = "Impossibile impostare il promemoria."
            }
        }
    }
    
    /// Costruisce la `PlanningReminderRequest` corretta in base al contesto
    /// incapsulato nell'azione. Se l'azione ha un oggetto SwiftData noto
    /// (todo, visita, esame, trattamento) lo usa direttamente.
    /// Altrimenti cade sul caso `.freeText` che crea un nuovo to-do.
    private func buildReminderRequest(from action: PlanningAction) -> PlanningReminderRequest {
        switch action.reminderContext {
            
        case .todo(let todo, let dueAt):
            return .existingTodo(todo: todo, dueAt: dueAt)
            
        case .visit(let visit, let childName):
            return .nextVisit(visit: visit, childName: childName)
            
        case .exam(let name, let examId, let childName, let childId, let deadline):
            return .prescribedExam(
                examName:  name,
                examId:    examId,
                childName: childName,
                familyId:  familyId,
                childId:   childId,
                deadline:  deadline
            )
            
        case .treatment(let treatment, let childName):
            return .treatment(treatment: treatment, childName: childName)
            
        case .freeText(let dueAt):
            return .freeText(
                title:    action.title,
                dueAt:    dueAt ?? Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                familyId: familyId,
                childId:  familyId,
                listId:   nil
            )
            
        case .none:
            return .freeText(
                title:    action.title,
                dueAt:    Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                familyId: familyId,
                childId:  familyId,
                listId:   nil
            )
        }
    }
    
    private func navigateForAction(_ action: PlanningAction) {
        switch action.navigationTarget {
        case .calendar:
            coordinator.navigate(to: .calendar(familyId: familyId))
        case .todo:
            coordinator.navigate(to: .todo)
        case .health:
            coordinator.navigate(to: .pediatricChildSelector(familyId: familyId))
        case .none:
            break
        }
    }
    
    // MARK: - Input area
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            // Suggerimenti contestuali rapidi
            if vm.messages.isEmpty == false && !vm.isLoading {
                quickInputChips
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            
            HStack(alignment: .center, spacing: 10) {
                // Input field — altezza fissa single-line, espande solo se l'utente
                // va a capo (maxHeight: 100 come safety cap)
                ZStack(alignment: .leading) {
                    if vm.inputText.isEmpty {
                        Text("Chiedi all'assistente…")
                            .foregroundStyle(.tertiary)
                            .font(.body)
                            .padding(.leading, 14)
                    }
                    TextEditor(text: $vm.inputText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                    // Altezza standard single-line: 20pt testo + 2×11pt padding = 42pt
                    // maxHeight permette espansione solo se l'utente scrive più righe
                        .frame(height: 42)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 0)
                }
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 21)
                        .fill(KBTheme.inputBackground(colorScheme))
                )
                
                // Send button
                Button {
                    Task { await vm.send() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading
                                  ? tint.opacity(0.3) : tint)
                            .frame(width: 38, height: 38)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
                .animation(.easeInOut(duration: 0.15), value: vm.inputText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                KBTheme.background(colorScheme)
                    .ignoresSafeArea(edges: .bottom)
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 8, y: -2)
            )
        }
    }
    
    private var quickInputChips: some View {
        // `String` (non `LocalizedStringKey`): il testo del chip diventa anche il
        // messaggio inviato all'AI (`vm.inputText = chip`), quindi passa da NSLocalizedString.
        let chips = [
            NSLocalizedString("Crea un evento", comment: "AI quick chip"),
            NSLocalizedString("Aggiungi to-do", comment: "AI quick chip"),
            NSLocalizedString("Mostra scadenze", comment: "AI quick chip"),
            NSLocalizedString("Orari liberi", comment: "AI quick chip"),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        vm.inputText = chip
                    } label: {
                        Text(chip)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                // Sfondo solido visibile sia in light che dark mode
                                    .fill(KBTheme.cardBackground(colorScheme))
                                    .overlay(
                                        Capsule().stroke(tint.opacity(0.5), lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2) // evita clipping del bordo
        }
    }
}

// MARK: - PlanningAction model

enum PlanningActionKind {
    case createEvent
    case createTodo
    case createGrocery
    case createNote
    case setReminder
    case navigate
}

enum PlanningNavigationTarget {
    case calendar
    case todo
    case health
    case none
}

/// Contesto specifico per le azioni di tipo `.setReminder`.
/// Permette a `executeReminder` di costruire la `PlanningReminderRequest` corretta
/// senza dover fare lookup aggiuntivi in SwiftData dalla view.
enum PlanningReminderContext {
    /// Reminder su un to-do già esistente in SwiftData.
    case todo(todo: KBTodoItem, dueAt: Date)
    /// Reminder per la nextVisitDate di una visita.
    case visit(visit: KBMedicalVisit, childName: String)
    /// Reminder per un esame prescritto con deadline.
    case exam(name: String, examId: String, childName: String, childId: String, deadline: Date)
    /// Reminder per un trattamento attivo.
    case treatment(treatment: KBTreatment, childName: String)
    /// Reminder libero: l'agente ha suggerito una data ma non c'è un oggetto esistente.
    case freeText(dueAt: Date?)
    /// Nessun contesto specifico — usa il titolo dell'azione + domani come data.
    case none
}

struct PlanningAction: Identifiable {
    let id               = UUID()
    let kind:             PlanningActionKind
    let title:            String
    let subtitle:         String
    let navigationTarget: PlanningNavigationTarget
    /// Solo per azioni `.setReminder` — porta il contesto necessario al service.
    var reminderContext:  PlanningReminderContext = .none
    /// Articoli spesa per `.createGrocery`.
    var groceryItems:     [String] = []
    /// Corpo nota per `.createNote`.
    var noteBody:         String?  = nil
}

// MARK: - PlanningActionParser
//
// Analizza il testo della risposta AI alla ricerca di frasi indicative
// di azioni proposte. Euristica leggera — in futuro può essere sostituita
// da structured outputs via function calling.
//
// Per i reminder l'euristica è volutamente conservativa: genera l'azione
// solo quando l'AI usa frasi esplicite di proposta ("vuoi che imposti",
// "posso impostare", "ti ricordo") così da evitare falsi positivi.

enum PlanningActionParser {

    /// Card solo per proposte ("vuoi che…", "posso…"), non dopo un'azione già completata ("ho aggiunto…").
    static func shouldOfferCreatableActionCard(lower: String) -> Bool {
        let completionPhrases = [
            "ho aggiunto", "ho creato", "ho inserito", "ho salvato", "ho registrato",
            "è stato aggiunto", "sono stati aggiunti", "li ho aggiunti", "l'ho aggiunto",
            "aggiunto alla lista", "inserito nella lista", "già aggiunto", "già inserito",
            "ho impostato", "promemoria attivo", "fatto!",
        ]
        if completionPhrases.contains(where: { lower.contains($0) }) { return false }

        let proposalPhrases = [
            "vuoi che", "posso ", "vuoi ", "desideri che", "preferisci che",
            "ti va se", "posso aggiungere", "posso creare", "posso inserire",
            "vuoi che aggiunga", "vuoi che crei", "vuoi che imposti",
            "crea un to-do", "creare un", "aggiungere al calendario",
        ]
        return proposalPhrases.contains(where: { lower.contains($0) })
    }
    
    // MARK: - Main parse — senza contesto SwiftData (fallback freeText)
    
    static func parse(from text: String) -> [PlanningAction] {
        parse(from: text, todos: [], visits: [], treatments: [], childNames: [:])
    }
    
    // MARK: - Parse con contesto SwiftData (versione completa)
    //
    // La view passa le collezioni SwiftData rilevanti così il parser può
    // abbinare un oggetto concreto all'azione di reminder invece di
    // ricadere sempre su .freeText.
    
    static func parse(
        from text:       String,
        todos:           [KBTodoItem],
        visits:          [KBMedicalVisit],
        treatments:      [KBTreatment],
        childNames:      [String: String]
    ) -> [PlanningAction] {
        
        var actions: [PlanningAction] = []
        let lower = text.lowercased()
        let offerCreatableCards = shouldOfferCreatableActionCard(lower: lower)
        
        // ── Crea evento ───────────────────────────────────────────
        if offerCreatableCards,
           lower.contains("vuoi che crei l'evento") || lower.contains("posso aggiungere al calendario") ||
            lower.contains("aggiungere al calendario") {
            let title = extractQuoted(from: text) ?? NSLocalizedString("Nuovo evento", comment: "")
            actions.append(PlanningAction(
                kind:             .createEvent,
                title:            title,
                subtitle:         NSLocalizedString("Apre il form pre-compilato", comment: ""),
                navigationTarget: .none
            ))
        }
        
        // ── Lista spesa ───────────────────────────────────────────
        let grocerySignals = [
            "lista della spesa", "lista spesa", "alla spesa", "nella spesa",
            "aggiungo alla lista", "aggiunto alla lista", "articoli alla spesa"
        ]
        if offerCreatableCards,
           grocerySignals.contains(where: { lower.contains($0) }),
           (lower.contains("vuoi che") || lower.contains("posso ")) {
            let items = extractGroceryItems(from: text)
            let title = items.first ?? extractQuoted(from: text) ?? NSLocalizedString("Articoli spesa", comment: "")
            var action = PlanningAction(
                kind:             .createGrocery,
                title:            title,
                subtitle:         items.count > 1
                    ? String(format: NSLocalizedString("%d articoli", comment: ""), items.count)
                    : NSLocalizedString("Aggiungi alla lista spesa", comment: ""),
                navigationTarget: .none
            )
            action.groceryItems = items.isEmpty ? [title] : items
            actions.append(action)
        }
        
        // ── Nota ──────────────────────────────────────────────────
        if offerCreatableCards,
           lower.contains("vuoi che") || lower.contains("posso "),
           lower.contains("nota") {
            let title = extractQuoted(from: text) ?? NSLocalizedString("Nuova nota", comment: "")
            var action = PlanningAction(
                kind:             .createNote,
                title:            title,
                subtitle:         NSLocalizedString("Salva nelle note famiglia", comment: ""),
                navigationTarget: .none
            )
            action.noteBody = title
            actions.append(action)
        }
        
        // ── Crea to-do ────────────────────────────────────────────
        if offerCreatableCards,
           lower.contains("vuoi che aggiunga il to-do") || lower.contains("crea un to-do") ||
            lower.contains("posso aggiungere il to-do") {
            let title = extractQuoted(from: text) ?? NSLocalizedString("Nuovo to-do", comment: "")
            actions.append(PlanningAction(
                kind:             .createTodo,
                title:            title,
                subtitle:         NSLocalizedString("Aggiunto alla lista condivisa", comment: ""),
                navigationTarget: .none
            ))
        }
        
        // ── Imposta reminder ──────────────────────────────────────
        let reminderPhrases = [
            "vuoi che imposti un promemoria",
            "posso impostare un promemoria",
            "ti ricordo con una notifica",
            "vuoi ricevere una notifica",
            "posso mandarti un reminder"
        ]
        if reminderPhrases.contains(where: { lower.contains($0) }) {
            let quoted = extractQuoted(from: text)
            
            // Cerca corrispondenza con to-do esistente
            let matchedTodo: KBTodoItem? = quoted.flatMap { q in
                todos.first { $0.title.localizedCaseInsensitiveContains(q) }
            }
            
            // Cerca corrispondenza con visita di controllo
            let matchedVisit: KBMedicalVisit? = visits.first { v in
                guard let d = v.nextVisitDate, d > Date() else { return false }
                if let q = quoted {
                    return v.reason.localizedCaseInsensitiveContains(q) ||
                    v.nextVisitReason?.localizedCaseInsensitiveContains(q) == true
                }
                return lower.contains("visita") || lower.contains("controllo")
            }
            
            // Cerca corrispondenza con trattamento attivo
            let matchedTreatment: KBTreatment? = quoted.flatMap { q in
                treatments.first { $0.drugName.localizedCaseInsensitiveContains(q) }
            }
            
            // Estrai data dal testo (euristica semplice: domani, dopodomani, ore HH:mm)
            let parsedDate = extractDate(from: lower)
            
            var reminderCtx: PlanningReminderContext = .freeText(dueAt: parsedDate)
            var subtitle = NSLocalizedString("Notifica locale programmata", comment: "")

            if let todo = matchedTodo {
                let dueAt = parsedDate ?? todo.dueAt ?? Calendar.current.date(byAdding: .hour, value: 9, to: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))) ?? Date()
                reminderCtx = .todo(todo: todo, dueAt: dueAt)
                subtitle = String(format: NSLocalizedString("Promemoria per \"%@\"", comment: ""), todo.title)
            } else if let visit = matchedVisit, let nextDate = visit.nextVisitDate {
                let childName = childNames[visit.childId] ?? NSLocalizedString("il bambino", comment: "")
                reminderCtx = .visit(visit: visit, childName: childName)
                subtitle = String(format: NSLocalizedString("Visita di controllo il %@", comment: ""), shortDate(nextDate))
            } else if let treatment = matchedTreatment {
                let childName = childNames[treatment.childId] ?? NSLocalizedString("il bambino", comment: "")
                reminderCtx = .treatment(treatment: treatment, childName: childName)
                subtitle = String(format: NSLocalizedString("Dosi %@ — %@", comment: ""), treatment.drugName, treatment.scheduleTimes.joined(separator: ", "))
            }

            var action = PlanningAction(
                kind:             .setReminder,
                title:            quoted ?? NSLocalizedString("Promemoria", comment: ""),
                subtitle:         subtitle,
                navigationTarget: .none
            )
            action.reminderContext = reminderCtx
            actions.append(action)
        }
        
        // ── Apri calendario ───────────────────────────────────────
        if lower.contains("apri il calendario") || lower.contains("vai al calendario") {
            actions.append(PlanningAction(
                kind:             .navigate,
                title:            NSLocalizedString("Apri Calendario", comment: ""),
                subtitle:         NSLocalizedString("Vai alla vista calendario", comment: ""),
                navigationTarget: .calendar
            ))
        }

        // ── Apri to-do ────────────────────────────────────────────
        if lower.contains("apri i to-do") || lower.contains("vai ai to-do") {
            actions.append(PlanningAction(
                kind:             .navigate,
                title:            NSLocalizedString("Apri To-Do", comment: ""),
                subtitle:         NSLocalizedString("Vai alla lista to-do", comment: ""),
                navigationTarget: .todo
            ))
        }

        // ── Apri salute ───────────────────────────────────────────
        if lower.contains("apri salute") || lower.contains("vai alla sezione salute") {
            actions.append(PlanningAction(
                kind:             .navigate,
                title:            NSLocalizedString("Apri Salute", comment: ""),
                subtitle:         NSLocalizedString("Vai alla sezione sanitaria", comment: ""),
                navigationTarget: .health
            ))
        }
        
        return actions
    }
    
    // MARK: - Helpers
    
    private static func extractQuoted(from text: String) -> String? {
        let patterns = [#""([^"]+)""#, #"«([^»]+)»"#, #"'([^']+)'"#]
        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression),
               let inner = text[range].firstMatch(of: /["«']([^"»']+)["»']/) {
                return String(inner.1)
            }
        }
        return nil
    }
    
    private static func extractGroceryItems(from text: String) -> [String] {
        var items: [String] = []
        let quotedPattern = #/["«']([^"»']+)["»']/#
        for match in text.matches(of: quotedPattern) {
            let value = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { items.append(value) }
        }
        if items.isEmpty {
            let lines = text.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                    let item = trimmed.drop(while: { $0 == "-" || $0 == "•" || $0 == " " })
                    if !item.isEmpty { items.append(String(item)) }
                }
            }
        }
        return items
    }
    
    /// Estrae una data approssimativa dal testo in italiano.
    /// Riconosce "domani", "dopodomani", "ore HH:mm", "alle HH".
    private static func extractDate(from lower: String) -> Date? {
        let cal = Calendar.current
        let now = Date()
        var base: Date = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now  // default: domani
        
        if lower.contains("dopodomani") {
            base = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) ?? base
        } else if lower.contains("domani") {
            base = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? base
        }
        
        // Cerca orario "alle 9" / "ore 08:30" / "alle 14:00"
        let timePatterns = [
            #"(?:alle|ore)\s+(\d{1,2}):(\d{2})"#,
            #"(?:alle|ore)\s+(\d{1,2})\b"#
        ]
        for pattern in timePatterns {
            if let range = lower.range(of: pattern, options: .regularExpression) {
                let match = String(lower[range])
                let digits = match.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .filter { !$0.isEmpty }
                    .compactMap { Int($0) }
                if let hour = digits.first {
                    let minute = digits.count > 1 ? digits[1] : 0
                    var comps  = cal.dateComponents([.year, .month, .day], from: base)
                    comps.hour   = hour
                    comps.minute = minute
                    return cal.date(from: comps)
                }
            }
        }
        
        // Nessun orario trovato: usa le 09:00 del giorno estratto
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour   = 9
        comps.minute = 0
        return cal.date(from: comps)
    }
    
    private static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale    = kbDeviceLocale()
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

// MARK: - PlanningActionCard

private struct PlanningActionCard: View {
    let action:      PlanningAction
    let tint:        Color
    let colorScheme: ColorScheme
    let onConfirm:   () -> Void
    let onNavigate:  () -> Void
    
    @State private var isConfirmed = false
    
    var body: some View {
        if isConfirmed {
            // Feedback confermato
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Fatto!")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
            )
            .transition(.scale.combined(with: .opacity))
        } else {
            HStack(spacing: 12) {
                // Icona azione
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(tint.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: iconForAction(action.kind))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Bottone azione
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        isConfirmed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        if action.kind == .navigate {
                            onNavigate()
                        } else {
                            onConfirm()
                        }
                    }
                } label: {
                    Text(buttonLabel(for: action.kind))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(KBTheme.cardBackground(colorScheme))
                    .shadow(color: KBTheme.shadow(colorScheme), radius: 4, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(tint.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }
    
    private func iconForAction(_ kind: PlanningActionKind) -> String {
        switch kind {
        case .createEvent:   return "calendar.badge.plus"
        case .createTodo:    return "checklist.checked"
        case .createGrocery: return "cart.badge.plus"
        case .createNote:    return "note.text.badge.plus"
        case .setReminder:   return "bell.badge"
        case .navigate:      return "arrow.right.circle"
        }
    }
    
    private func buttonLabel(for kind: PlanningActionKind) -> LocalizedStringKey {
        switch kind {
        case .navigate:      return "Vai"
        case .setReminder:   return "Attiva"
        case .createGrocery: return "Aggiungi"
        case .createNote:    return "Salva"
        default:             return "Crea"
        }
    }
}
