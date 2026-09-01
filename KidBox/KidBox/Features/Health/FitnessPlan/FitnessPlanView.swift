//
//  FitnessPlanView.swift
//  KidBox
//
//  Dashboard del Piano Fitness: calendario delle sedute, stato di
//  completamento, sincronizzazione con Apple Salute, report settimanale e
//  accesso al copilota AI.
//

import SwiftUI
import SwiftData

struct FitnessPlanView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var subscriptionManager = KBSubscriptionManager.shared

    let familyId: String
    let childId: String

    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]
    @Query private var allTreatments: [KBTreatment]
    @Query private var allLogs: [KBDoseLog]
    @Query private var allVaccines: [KBVaccine]
    @Query private var allVisits: [KBMedicalVisit]
    @Query private var allExams: [KBMedicalExam]

    @State private var plan: FitnessPlanDocument?
    @State private var input = FitnessPlanInput()
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    /// Mese mostrato dal calendario: segue il giorno selezionato.
    @State private var displayedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var estimatedUnits = AIAskAIPayload.fitnessPlanMinUnits
    @State private var lastUsage: FitnessPlanAIUsageInfo?

    @State private var isGenerating = false
    @State private var isSyncingHealth = false
    @State private var isAdjusting = false
    @State private var generatingMessage: LocalizedStringKey = "Creazione del piano in corso…"

    @State private var pendingInput: FitnessPlanInput?
    @State private var showCostConfirm = false
    @State private var showSetup = false
    @State private var setupMode: FitnessPlanSetupView.Mode = .onboarding
    @State private var showUpgrade = false
    @State private var showCopilot = false
    @State private var showCopilotConsent = false
    @State private var showHealthPermission = false
    @State private var showMoveSheet: FitnessSession?

    @State private var weeklyReport: FitnessWeeklyReport?
    @State private var adjustmentProposal: FitnessAdjustmentProposal?

    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var infoBanner: String?

    private let tint = FitnessPlanTheme.tint

    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId = childId
        let cid = childId
        let fid = familyId
        _children = Query(filter: #Predicate<KBChild> { $0.id == cid })
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.userId == cid })
        _allTreatments = Query(filter: #Predicate<KBTreatment> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false && $0.isActive == true
        })
        _allLogs = Query(filter: #Predicate<KBDoseLog> {
            $0.familyId == fid && $0.childId == cid && $0.taken == true && $0.isDeleted == false
        })
        _allVaccines = Query(filter: #Predicate<KBVaccine> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allVisits = Query(filter: #Predicate<KBMedicalVisit> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
        _allExams = Query(filter: #Predicate<KBMedicalExam> {
            $0.familyId == fid && $0.childId == cid && $0.isDeleted == false
        })
    }

    private var child: KBChild? { children.first }
    private var member: KBFamilyMember? { members.first }
    private var subjectName: String { child?.name ?? member?.displayName ?? "Profilo" }
    private var snapshot: KBHealthImportSnapshot? { KBHealthLinkStore.load(childId: childId) }
    private var isPaidPlan: Bool { subscriptionManager.currentPlan != .free }

    private var activeTreatments: [KBTreatment] {
        let today = Calendar.current.startOfDay(for: Date())
        return allTreatments.filter { treatment in
            if !treatment.petId.isEmpty { return false }
            if treatment.isLongTerm { return true }
            if let end = treatment.endDate, end < today { return false }
            let total = treatment.totalDoses
            if total > 0, allLogs.filter({ $0.treatmentId == treatment.id }).count >= total { return false }
            return true
        }
    }

    /// Peso e altezza: dall'app Salute oppure inseriti a mano nel wizard.
    private var hasBodyMetrics: Bool {
        let snap = snapshot
        return (snap?.weightKg ?? input.manualWeightValue) != nil
            && (snap?.heightCm ?? input.manualHeightValue) != nil
    }

    private var needsManualMetrics: Bool {
        let snap = snapshot
        return snap?.weightKg == nil || snap?.heightCm == nil
            || (child?.birthDate ?? snap?.birthDate) == nil
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let infoBanner {
                    bannerCard(infoBanner)
                }

                if !isPaidPlan {
                    introCard
                    lockedCard
                } else if let plan {
                    if let weeklyReport, !isReviewed(weeklyReport) {
                        weeklyReportCard(weeklyReport)
                    }
                    calendarCard(plan)
                    dayDetailCard(plan)
                    healthSyncCard
                } else {
                    introCard
                    dataSourcesCard
                    setupCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .kbRefreshable { await refresh() }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Piano Fitness")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if plan != nil, isPaidPlan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        setupMode = .settings
                        showSetup = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Impostazioni piano")
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if plan != nil, isPaidPlan {
                copilotButton
            }
        }
        .onAppear { Task { await onAppear() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await FitnessPlanForegroundSync.runIfNeeded(childId: childId); reloadFromStore() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .fitnessPlanDidChange)) { _ in
            reloadFromStore()
        }
        .sheet(isPresented: $showSetup) {
            FitnessPlanSetupView(
                mode: setupMode,
                subjectName: subjectName,
                input: input,
                estimatedUnits: estimatedUnits,
                needsManualMetrics: needsManualMetrics,
                plan: setupMode == .settings ? plan : nil,
                lastUsage: lastUsage,
                onDelete: { Task { await deletePlan() } },
                onConfirm: { confirmed in
                    pendingInput = confirmed
                    showCostConfirm = true
                }
            )
        }
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(triggerFeature: "fitness_plan_lock")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .sheet(isPresented: $showCopilotConsent) {
            AIConsentSheet { showCopilot = true }
        }
        .sheetOrMacPush(isPresented: $showCopilot) {
            if let plan {
                FitnessCopilotView(
                    familyId: familyId,
                    childId: childId,
                    subjectName: subjectName,
                    plan: plan,
                    treatments: activeTreatments,
                    vaccines: allVaccines,
                    visits: allVisits,
                    exams: allExams
                ) { updatedPlan in
                    Task { await persist(updatedPlan, rescheduleNotifications: true) }
                }
            }
        }
        .sheet(item: $showMoveSheet) { session in
            FitnessMoveSessionSheet(session: session) { newDate in
                Task { await move(session: session, to: newDate) }
            }
        }
        .sheet(isPresented: $showHealthPermission) {
            FitnessHealthPermissionSheet {
                Task { await requestHealthAccess() }
            }
            .presentationDetents([.medium])
        }
        .alert("Generare il piano?", isPresented: $showCostConfirm) {
            Button("Annulla", role: .cancel) { pendingInput = nil }
            Button("Genera") {
                if let pendingInput {
                    Task { await generate(with: pendingInput) }
                }
            }
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "La generazione di questo piano consumerà circa %d messaggi AI, scalati dal limite della famiglia.",
                        comment: "Fitness plan generation cost confirmation"
                    ),
                    estimatedUnits
                )
            )
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        }
        .overlay { generatingOverlay }
    }

    // MARK: - Introduzione e paywall

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "figure.run")
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Piano Fitness")
                        .font(.headline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Text("Allenamenti creati dall'AI sui tuoi dati di salute")
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Spacer(minLength: 0)
            }

            Text("L'assistente costruisce un piano di allenamento mensile partendo da quello che c'è già in Salute: età, peso, altezza, referti, patologie in corso, terapie e allenamenti registrati.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            Text("Ricevi quattro settimane di sedute nei giorni che scegli, con esercizi e obiettivi misurabili, promemoria con i pulsanti Fatto e Sposta, e il confronto automatico con gli allenamenti registrati da Apple Salute.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            Label("L'AI adatta intensità ed esercizi alle controindicazioni che trova nei tuoi dati clinici.", systemImage: "cross.case")
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            Label("Il piano è educativo: validalo sempre con il tuo medico. Interrompi l'allenamento se compare dolore.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        }
        .fitnessCard()
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Incluso in Pro e Max", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Il Piano Fitness è disponibile solo con un piano a pagamento. Passa a Pro o Max per generarlo con l'AI.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            Button { showUpgrade = true } label: {
                Text("Scopri i piani")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .fitnessCard()
    }

    // MARK: - Dati usati

    private var dataSourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dati usati per il piano")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            ForEach(dataSourceRows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.available ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(row.available ? tint : Color.orange)
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            }

            if !hasBodyMetrics {
                Text("Peso e altezza sono obbligatori: aggiornali nell'app Salute, nella Scheda Medica, oppure inseriscili durante la configurazione.")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .fitnessCard()
    }

    private struct DataSourceRow: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
        let available: Bool
    }

    private var dataSourceRows: [DataSourceRow] {
        let snap = snapshot
        let notAvailable = NSLocalizedString("non disponibile", comment: "Missing health data value")

        let ageValue: String
        let ageAvailable: Bool
        if let birth = child?.birthDate ?? snap?.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
            ageValue = String(format: NSLocalizedString("%d anni", comment: "Age in years"), years)
            ageAvailable = true
        } else if let age = input.manualAgeValue {
            ageValue = String(format: NSLocalizedString("%d anni", comment: "Age in years"), age)
            ageAvailable = true
        } else {
            ageValue = notAvailable
            ageAvailable = false
        }

        let weight = snap?.weightKg ?? input.manualWeightValue
        let height = snap?.heightCm ?? input.manualHeightValue

        return [
            DataSourceRow(id: "age", label: "Età", value: ageValue, available: ageAvailable),
            DataSourceRow(
                id: "weight",
                label: "Peso",
                value: weight.map { String(format: "%.1f kg", $0) } ?? notAvailable,
                available: weight != nil
            ),
            DataSourceRow(
                id: "height",
                label: "Altezza",
                value: height.map { "\(Int($0.rounded())) cm" } ?? notAvailable,
                available: height != nil
            ),
            DataSourceRow(
                id: "workouts",
                label: "Allenamenti registrati",
                value: "\(snap?.recentWorkouts.count ?? 0)",
                available: !(snap?.recentWorkouts.isEmpty ?? true)
            ),
            DataSourceRow(id: "visits", label: "Visite mediche", value: "\(allVisits.count)", available: !allVisits.isEmpty),
            DataSourceRow(id: "exams", label: "Analisi & Esami", value: "\(allExams.count)", available: !allExams.isEmpty),
            DataSourceRow(id: "treatments", label: "Cure attive", value: "\(activeTreatments.count)", available: !activeTreatments.isEmpty),
        ]
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(
                    format: NSLocalizedString(
                        "Generare il piano costa circa %d messaggi AI",
                        comment: "Fitness plan AI cost"
                    ),
                    estimatedUnits
                ),
                systemImage: "sparkles"
            )
            .font(.headline)
            .foregroundStyle(KBTheme.primaryText(colorScheme))

            Text("I messaggi sono scalati dal limite giornaliero della famiglia. Il piano resta salvato: si rigenera solo quando cambiano obiettivo, giorni o stato di salute.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            Button {
                setupMode = .onboarding
                showSetup = true
            } label: {
                Text("Configura e genera il piano")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .fitnessCard()
    }

    // MARK: - Calendario

    private func calendarCard(_ plan: FitnessPlanDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calendario")
                    .font(.headline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Spacer()
                if let weekIndex = plan.weekIndex(for: selectedDay) {
                    Text(
                        String(
                            format: NSLocalizedString("Settimana %d", comment: "Fitness week number"),
                            weekIndex
                        )
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(tint.opacity(0.12)))
                }
            }

            monthHeader(plan)
            weekdayHeader
            monthGrid(plan)

            HStack(spacing: 16) {
                ForEach([FitnessSessionStatus.done, .planned, .skipped], id: \.rawValue) { status in
                    HStack(spacing: 5) {
                        Image(systemName: status.systemImage)
                            .font(.footnote)
                            .foregroundStyle(status.tint)
                        Text(status.label)
                            .font(.footnote)
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    }
                }
            }
        }
        .fitnessCard()
        .onAppear { alignDisplayedMonth() }
        .onChange(of: selectedDay) { _, day in
            displayedMonth = startOfMonth(day)
        }
    }

    // MARK: - Vista mensile

    /// Intestazione con il mese e le frecce, limitate ai mesi coperti dal piano.
    private func monthHeader(_ plan: FitnessPlanDocument) -> some View {
        let cal = Calendar.current
        let first = startOfMonth(plan.startDate)
        let last = startOfMonth(plan.allSessions.last?.date ?? plan.startDate)

        return HStack {
            Button {
                guard let previous = cal.date(byAdding: .month, value: -1, to: displayedMonth),
                      previous >= first
                else { return }
                withAnimation { displayedMonth = previous }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(displayedMonth > first ? tint : KBTheme.secondaryText(colorScheme).opacity(0.35))
            .disabled(displayedMonth <= first)

            Spacer()

            Text(FitnessPlanFormat.monthTitle(displayedMonth))
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            Spacer()

            Button {
                guard let next = cal.date(byAdding: .month, value: 1, to: displayedMonth),
                      next <= last
                else { return }
                withAnimation { displayedMonth = next }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(displayedMonth < last ? tint : KBTheme.secondaryText(colorScheme).opacity(0.35))
            .disabled(displayedMonth >= last)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(FitnessPlanFormat.orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Griglia del mese: le celle vuote iniziali allineano il primo giorno alla
    /// sua colonna, i giorni fuori dal piano restano visibili ma spenti.
    private func monthGrid(_ plan: FitnessPlanDocument) -> some View {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: displayedMonth) ?? 1..<29
        let firstWeekday = cal.component(.weekday, from: displayedMonth)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        let days: [Date?] = Array(repeating: nil, count: leading)
            + range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: displayedMonth) }

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 6
        ) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, plan: plan)
                } else {
                    Color.clear.frame(height: 54)
                }
            }
        }
    }

    private func startOfMonth(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    /// All'apertura si parte dal mese del giorno selezionato (di norma oggi).
    private func alignDisplayedMonth() {
        displayedMonth = startOfMonth(selectedDay)
    }

    private func dayCell(_ day: Date, plan: FitnessPlanDocument) -> some View {
        let cal = Calendar.current
        let sessions = plan.sessions(on: day)
        let isSelected = cal.isDate(day, inSameDayAs: selectedDay)
        let isToday = cal.isDateInToday(day)
        let inPlan = plan.weekIndex(for: day) != nil
        let status = sessions.first?.status

        return Button {
            withAnimation { selectedDay = cal.startOfDay(for: day) }
        } label: {
            VStack(spacing: 3) {
                Text(FitnessPlanFormat.dayNumber(day))
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : (inPlan
                               ? KBTheme.primaryText(colorScheme)
                               : KBTheme.secondaryText(colorScheme).opacity(0.45))
                    )
                Group {
                    if let status {
                        Image(systemName: status.systemImage)
                            .font(.footnote)
                            .foregroundStyle(isSelected ? Color.white : status.tint)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? tint
                            : (sessions.isEmpty
                               ? Color.clear
                               : KBTheme.secondaryText(colorScheme).opacity(0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isToday && !isSelected ? tint : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FitnessPlanFormat.mediumDate(day))
    }

    // MARK: - Dettaglio giornata

    private func dayDetailCard(_ plan: FitnessPlanDocument) -> some View {
        let sessions = plan.sessions(on: selectedDay)
        return VStack(alignment: .leading, spacing: 12) {
            Text(FitnessPlanFormat.mediumDate(selectedDay))
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            if sessions.isEmpty {
                // Fuori dal piano non è riposo: il piano semplicemente non
                // copre quel giorno, e dirlo evita di far sembrare vuoto un
                // mese che il piano non tocca.
                let inPlan = plan.weekIndex(for: selectedDay) != nil
                HStack(spacing: 10) {
                    Image(systemName: inPlan ? "moon.zzz" : "calendar.badge.exclamationmark")
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    Text(
                        inPlan
                            ? "Giorno di riposo: nessuna seduta prevista."
                            : "Questo giorno è fuori dalle quattro settimane del piano."
                    )
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            } else {
                ForEach(sessions) { session in
                    sessionCard(session)
                }
            }
        }
        .fitnessCard()
    }

    private func sessionCard(_ session: FitnessSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: session.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.headline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Text(sessionSubtitle(session))
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Spacer(minLength: 8)
                Label(session.status.label, systemImage: session.status.systemImage)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(session.status.tint)
            }

            if !session.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(session.exercises) { exercise in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(tint)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(exercise.name)
                                    .font(.body)
                                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                                if !exercise.detail.isEmpty {
                                    Text(exercise.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                                }
                                if let notes = exercise.notes {
                                    Text(notes)
                                        .font(.footnote)
                                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                                }
                            }
                        }
                    }
                }
            }

            if !session.targets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Obiettivi")
                        .font(.subheadline.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    ForEach(session.targets, id: \.self) { target in
                        Label(target, systemImage: "target")
                            .font(.subheadline)
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    }
                }
            }

            if let notes = session.notes {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }

            if session.status == .done {
                completedSummary(session)
            } else {
                HStack(spacing: 8) {
                    Button {
                        Task { await mark(session: session, status: .done) }
                    } label: {
                        Label("Fatto", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)

                    Button {
                        showMoveSheet = session
                    } label: {
                        Label("Sposta", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await mark(session: session, status: .skipped) }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Salta questa seduta")
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(KBTheme.secondaryText(colorScheme).opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(session.status == .done ? session.status.tint.opacity(0.4) : .clear, lineWidth: 1)
        )
    }

    private func sessionSubtitle(_ session: FitnessSession) -> String {
        var parts: [String] = []
        if session.durationMinutes > 0 {
            parts.append(
                String(
                    format: NSLocalizedString("%d min", comment: "Session duration in minutes"),
                    session.durationMinutes
                )
            )
        }
        if !session.intensity.isEmpty { parts.append(session.intensity) }
        if let kcal = session.targetKcal {
            parts.append("\(kcal) kcal")
        }
        return parts.joined(separator: " · ")
    }

    private func completedSummary(_ session: FitnessSession) -> some View {
        HStack(spacing: 8) {
            Image(systemName: session.completionSource == .healthKit ? "applewatch" : "checkmark.seal")
                .foregroundStyle(session.status.tint)
            Text(completionText(session))
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            Spacer(minLength: 8)
            Button("Annulla") {
                Task { await mark(session: session, status: .planned) }
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundStyle(tint)
        }
    }

    private func completionText(_ session: FitnessSession) -> String {
        switch session.completionSource {
        case .healthKit:
            let minutes = session.actualMinutes ?? session.durationMinutes
            if let kcal = session.actualKcal {
                return String(
                    format: NSLocalizedString(
                        "Chiusa da Apple Salute: %1$d min, %2$d kcal",
                        comment: "Session closed by HealthKit with calories"
                    ),
                    minutes, kcal
                )
            }
            return String(
                format: NSLocalizedString(
                    "Chiusa da Apple Salute: %d min",
                    comment: "Session closed by HealthKit"
                ),
                minutes
            )
        case .notification:
            return NSLocalizedString("Segnata come fatta dalla notifica", comment: "Session done from notification")
        default:
            return NSLocalizedString("Segnata come fatta", comment: "Session done manually")
        }
    }

    // MARK: - Sincronizzazione Salute

    private var healthSyncCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Salute")
                        .font(.headline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Text(lastSyncText)
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Spacer(minLength: 8)
                Button {
                    Task { await syncHealthNow() }
                } label: {
                    if isSyncingHealth {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Sincronizza ora")
                    }
                }
                .buttonStyle(.bordered)
                .font(.subheadline)
                .disabled(isSyncingHealth)
            }

            Text("Le attività registrate da iPhone, Apple Watch o dagli accessori collegati chiudono da sole le sedute corrispondenti.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            Button("Rivedi i permessi Salute") { showHealthPermission = true }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(tint)
        }
        .fitnessCard()
    }

    private var lastSyncText: String {
        guard let last = FitnessPlanStore.lastHealthSync(childId: childId) else {
            return NSLocalizedString("Mai sincronizzato", comment: "Fitness health never synced")
        }
        return String(
            format: NSLocalizedString("Ultima sincronizzazione: %@", comment: "Fitness last sync"),
            FitnessPlanFormat.dateTime(last)
        )
    }

    // MARK: - Report settimanale

    private func weeklyReportCard(_ report: FitnessWeeklyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(tint)
                Text(
                    String(
                        format: NSLocalizedString(
                            "Report settimana %d",
                            comment: "Fitness weekly report title"
                        ),
                        report.weekIndex
                    )
                )
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
                Spacer(minLength: 8)
                // Percentuale nuda: `verbatim` evita che diventi una chiave da tradurre.
                Text(verbatim: "\(report.completionPercent)%")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(tint)
            }

            ProgressView(value: report.completionRate)
                .tint(tint)

            Text(report.headline)
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            HStack(spacing: 16) {
                reportMetric("Completate", value: "\(report.completedSessions)/\(report.plannedSessions)")
                reportMetric("Minuti", value: "\(report.totalMinutes)")
                if report.totalKcal > 0 {
                    reportMetric("kcal", value: "\(report.totalKcal)")
                }
            }

            if let proposal = adjustmentProposal, proposal.weekIndex == report.weekIndex + 1 {
                Divider()
                Text("Proposta dell'AI")
                    .font(.subheadline.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                if !proposal.rationale.isEmpty {
                    Text(proposal.rationale)
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                ForEach(proposal.changes, id: \.self) { change in
                    Label(change, systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                HStack(spacing: 8) {
                    Button("Mantieni il piano") {
                        adjustmentProposal = nil
                        markReviewed(report)
                    }
                    .buttonStyle(.bordered)
                    Button("Applica le modifiche") {
                        Task { await applyProposal(proposal, report: report) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .disabled(proposal.updatedSessions.isEmpty)
                }
                .font(.subheadline)
            } else {
                HStack(spacing: 8) {
                    Button("Mantieni il piano") { markReviewed(report) }
                        .buttonStyle(.bordered)
                    Button {
                        Task { await askAdjustment(for: report) }
                    } label: {
                        if isAdjusting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Chiedi un adeguamento", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .disabled(isAdjusting)
                }
                .font(.subheadline)

                Text("La proposta costa 1 messaggio AI.")
                    .font(.footnote)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
        }
        .fitnessCard()
    }

    private func reportMetric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text(title)
                .font(.footnote)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
    }

    // MARK: - Copilota

    /// Stesso FAB arancione di tutte le altre chat AI dell'app, con lo stesso
    /// passaggio dal consenso: cambia solo il contesto che porta con sé.
    private var copilotButton: some View {
        AskAIControl(
            style: .circle,
            accessibilityLabel: "Chiedi al Fitness Copilot"
        ) {
            if AISettings.shared.consentGiven {
                showCopilot = true
            } else {
                showCopilotConsent = true
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    private func bannerCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Spacer(minLength: 8)
            Button {
                withAnimation { infoBanner = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .fitnessCard()
    }

    @ViewBuilder
    private var generatingOverlay: some View {
        if isGenerating {
            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12)
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text(generatingMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Ciclo di vita

    @MainActor
    private func onAppear() async {
        reloadFromStore()
        await refresh()
        await FitnessPlanForegroundSync.runIfNeeded(childId: childId)
        reloadFromStore()
        await runPendingRescheduleIfNeeded()
    }

    @MainActor
    private func refresh() async {
        await syncFromRemote()
        refreshEstimate()
        refreshWeeklyReport()
    }

    private func reloadFromStore() {
        guard let stored = FitnessPlanStore.load(childId: childId) else { return }
        plan = stored
        input = stored.input
        refreshWeeklyReport()
    }

    /// Allinea la copia locale con Firestore: vince il piano più recente, e
    /// un'eliminazione fatta su un altro device svuota anche qui.
    @MainActor
    private func syncFromRemote() async {
        switch await FitnessPlanRemoteStore.fetch(childId: childId) {
        case .none:
            if let plan {
                await FitnessPlanRemoteStore.upsert(plan, childId: childId)
            }
        case .deleted:
            if plan != nil {
                FitnessPlanStore.clear(childId: childId)
                await FitnessPlanNotificationManager.removePlan(childId: childId)
                plan = nil
                weeklyReport = nil
            }
        case .plan(let remote):
            guard remote.generatedAt >= (plan?.generatedAt ?? .distantPast) else { return }
            // Stessa generazione: vince chi ha più sedute chiuse, così un
            // "Fatto" segnato su un altro device non viene riportato indietro.
            if let current = plan,
               remote.generatedAt == current.generatedAt,
               doneCount(remote) <= doneCount(current) {
                return
            }
            plan = remote
            input = remote.input
            FitnessPlanStore.save(remote, childId: childId)
            refreshWeeklyReport()
        }
    }

    private func doneCount(_ document: FitnessPlanDocument) -> Int {
        document.allSessions.filter { $0.status == .done }.count
    }

    private func refreshEstimate() {
        let payload = FitnessPlanGenerator.buildPayload(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId,
            subjectName: subjectName,
            birthDate: child?.birthDate,
            input: input,
            treatments: activeTreatments,
            vaccines: allVaccines,
            visits: allVisits,
            exams: allExams
        )
        estimatedUnits = FitnessPlanGenerator.estimate(payload: payload).messageUnits
    }

    private func refreshWeeklyReport() {
        guard let plan,
              let weekIndex = FitnessWeeklyReportBuilder.lastCompletedWeekIndex(plan: plan)
        else {
            weeklyReport = nil
            return
        }
        weeklyReport = FitnessWeeklyReportBuilder.report(for: weekIndex, plan: plan)
    }

    private func isReviewed(_ report: FitnessWeeklyReport) -> Bool {
        FitnessPlanStore.reviewedWeeks(childId: childId).contains(report.weekIndex)
    }

    private func markReviewed(_ report: FitnessWeeklyReport) {
        FitnessPlanStore.markWeekReviewed(report.weekIndex, childId: childId)
        weeklyReport = nil
        adjustmentProposal = nil
    }

    // MARK: - Azioni AI

    @MainActor
    private func generate(with confirmedInput: FitnessPlanInput) async {
        guard !isGenerating else { return }
        pendingInput = nil
        input = confirmedInput
        isGenerating = true
        generatingMessage = "Creazione del piano in corso…"
        defer { isGenerating = false }

        let payload = FitnessPlanGenerator.buildPayload(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId,
            subjectName: subjectName,
            birthDate: child?.birthDate,
            input: confirmedInput,
            treatments: activeTreatments,
            vaccines: allVaccines,
            visits: allVisits,
            exams: allExams
        )
        estimatedUnits = FitnessPlanGenerator.estimate(payload: payload).messageUnits

        do {
            let result = try await FitnessPlanGenerator.generate(
                payload: payload,
                subjectName: subjectName,
                input: confirmedInput
            )
            lastUsage = result.usage
            selectedDay = Calendar.current.startOfDay(for: Date())
            adjustmentProposal = nil
            await persist(result.document, rescheduleNotifications: true)
            if KBHealthKitService.shared.isAvailable {
                showHealthPermission = true
            }
        } catch {
            present(error)
        }
    }

    @MainActor
    private func askAdjustment(for report: FitnessWeeklyReport) async {
        guard let plan, !isAdjusting else { return }
        isAdjusting = true
        defer { isAdjusting = false }
        do {
            let result = try await FitnessPlanGenerator.weeklyAdjustment(plan: plan, report: report)
            adjustmentProposal = result.proposal
            lastUsage = result.usage
        } catch {
            present(error)
        }
    }

    @MainActor
    private func applyProposal(_ proposal: FitnessAdjustmentProposal, report: FitnessWeeklyReport) async {
        guard let plan else { return }
        let updated = FitnessPlanGenerator.apply(proposal.updatedSessions, to: plan)
        await persist(updated, rescheduleNotifications: true)
        adjustmentProposal = nil
        markReviewed(report)
        infoBanner = NSLocalizedString(
            "Piano aggiornato con le modifiche proposte dall'AI.",
            comment: "Fitness proposal applied banner"
        )
    }

    @MainActor
    private func move(session: FitnessSession, to newDate: Date) async {
        guard let plan, !isGenerating else { return }
        isGenerating = true
        generatingMessage = "Riorganizzazione della settimana…"
        defer { isGenerating = false }
        do {
            let outcome = try await FitnessPlanGenerator.reschedule(
                plan: plan,
                sessionId: session.id,
                newDate: newDate
            )
            lastUsage = outcome.usage
            await persist(outcome.plan, rescheduleNotifications: true)
            selectedDay = Calendar.current.startOfDay(for: newDate)
            if !outcome.rationale.isEmpty {
                infoBanner = outcome.rationale
            }
        } catch {
            // Lo spostamento resta valido anche se l'AI non risponde: è la data
            // scelta dall'utente, non una proposta.
            var fallback = plan
            fallback.updateSession(id: session.id) { moved in
                moved.originalDate = moved.originalDate ?? moved.date
                moved.date = Calendar.current.startOfDay(for: newDate)
                moved.status = .planned
            }
            await persist(fallback, rescheduleNotifications: true)
            present(error)
        }
    }

    /// Spostamento fatto dalla notifica: la riorganizzazione AI è rimasta in
    /// sospeso perché richiede rete, e la eseguiamo alla prima apertura.
    @MainActor
    private func runPendingRescheduleIfNeeded() async {
        guard
            isPaidPlan,
            let plan,
            let sessionId = FitnessPlanPendingReschedule.pending(childId: childId),
            let session = plan.session(id: sessionId)
        else { return }
        FitnessPlanPendingReschedule.clear(childId: childId)
        await move(session: session, to: session.date)
    }

    // MARK: - Azioni locali

    @MainActor
    private func mark(session: FitnessSession, status: FitnessSessionStatus) async {
        guard var updated = plan else { return }
        updated.updateSession(id: session.id) { target in
            target.status = status
            target.completedAt = status == .done ? Date() : nil
            target.completionSource = status == .done ? .manual : nil
            if status != .done {
                target.matchedWorkoutId = nil
                target.actualMinutes = nil
                target.actualKcal = nil
            }
        }
        await persist(updated, rescheduleNotifications: true)
    }

    @MainActor
    private func syncHealthNow() async {
        guard let plan, !isSyncingHealth else { return }
        isSyncingHealth = true
        defer { isSyncingHealth = false }

        let result = await FitnessHealthSync.reconcile(plan: plan)
        FitnessPlanStore.setLastHealthSync(Date(), childId: childId)
        guard result.didChange else {
            infoBanner = NSLocalizedString(
                "Nessuna nuova attività da abbinare alle sedute in programma.",
                comment: "Fitness sync no match"
            )
            return
        }
        await persist(result.plan, rescheduleNotifications: true)
        infoBanner = String(
            format: NSLocalizedString(
                "Sedute completate con i dati di Apple Salute: %d",
                comment: "Fitness sync matched count"
            ),
            result.matchedSessions.count
        )
    }

    @MainActor
    private func requestHealthAccess() async {
        do {
            try await KBHealthKitService.shared.requestAuthorization()
            await syncHealthNow()
        } catch {
            present(error)
        }
    }

    @MainActor
    private func persist(_ updated: FitnessPlanDocument, rescheduleNotifications: Bool) async {
        plan = updated
        input = updated.input
        FitnessPlanStore.save(updated, childId: childId)
        refreshWeeklyReport()
        await FitnessPlanRemoteStore.upsert(updated, childId: childId)
        if rescheduleNotifications {
            await FitnessPlanNotificationManager.reschedule(
                plan: updated,
                childId: childId,
                familyId: familyId
            )
        }
    }

    @MainActor
    private func deletePlan() async {
        FitnessPlanStore.clear(childId: childId)
        await FitnessPlanNotificationManager.removePlan(childId: childId)
        await FitnessPlanRemoteStore.delete(childId: childId)
        plan = nil
        weeklyReport = nil
        adjustmentProposal = nil
        lastUsage = nil
    }

    private func present(_ error: Error) {
        alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showAlert = true
    }
}

// MARK: - Sposta una seduta

private struct FitnessMoveSessionSheet: View {
    let session: FitnessSession
    let onMove: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var newDate: Date

    init(session: FitnessSession, onMove: @escaping (Date) -> Void) {
        self.session = session
        self.onMove = onMove
        _newDate = State(
            initialValue: Calendar.current.date(byAdding: .day, value: 1, to: session.date) ?? session.date
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text(
                    String(
                        format: NSLocalizedString(
                            "Prevista per il %@",
                            comment: "Fitness session originally scheduled on"
                        ),
                        FitnessPlanFormat.mediumDate(session.date)
                    )
                )
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

                DatePicker(
                    "Nuova data",
                    selection: $newDate,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)

                Text("L'AI riorganizza i giorni rimanenti della settimana per non perdere l'obiettivo. Costa 1 messaggio AI.")
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))

                Spacer(minLength: 0)

                Button {
                    onMove(Calendar.current.startOfDay(for: newDate))
                    dismiss()
                } label: {
                    Text("Sposta la seduta")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(FitnessPlanTheme.tint)
            }
            .padding(16)
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Sposta seduta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Permessi Apple Salute

private struct FitnessHealthPermissionSheet: View {
    let onAuthorize: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(FitnessPlanTheme.tint.opacity(0.15)).frame(width: 64, height: 64)
                Image(systemName: "heart.text.square.fill")
                    .font(.title)
                    .foregroundStyle(FitnessPlanTheme.tint)
            }
            .padding(.top, 24)

            Text("Collega Apple Salute")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            Text("Con l'accesso ai dati di attività, KidBox riconosce gli allenamenti registrati da iPhone, Apple Watch e accessori collegati e segna da sé le sedute completate.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                .padding(.horizontal, 8)

            Button {
                onAuthorize()
                dismiss()
            } label: {
                Text("Consenti l'accesso")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(FitnessPlanTheme.tint)

            Button("Non ora") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
    }
}
