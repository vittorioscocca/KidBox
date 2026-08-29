//
//  MealPlanView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct MealPlanView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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

    @State private var input = MealPlanInput()
    @State private var document: MealPlanDocument?
    @State private var lastUsage: MealPlanAIUsageInfo?
    @State private var estimatedUnits = AIAskAIPayload.mealPlanMinUnits
    @State private var isGenerating = false
    @State private var showUpgrade = false
    @State private var showForm = false
    @State private var alertMessage = ""
    @State private var showAlert = false

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

    private let tint = Color(red: 0.4, green: 0.72, blue: 0.5)

    private var child: KBChild? { children.first }
    private var member: KBFamilyMember? { members.first }
    private var subjectName: String { child?.name ?? member?.displayName ?? "Profilo" }
    private var snapshot: KBHealthImportSnapshot? { KBHealthLinkStore.load(childId: childId) }
    private var isPaidPlan: Bool { subscriptionManager.currentPlan != .free }

    private var activeTreatments: [KBTreatment] {
        let today = Calendar.current.startOfDay(for: Date())
        return allTreatments.filter { t in
            if !t.petId.isEmpty { return false }
            if t.isLongTerm { return true }
            if let end = t.endDate, end < today { return false }
            let total = t.totalDoses
            if total > 0, allLogs.filter({ $0.treatmentId == t.id }).count >= total { return false }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                introCard
                dataSourcesCard
                if !isPaidPlan {
                    lockedCard
                } else {
                    formCard
                    costCard
                    generateButton
                }
                if let document {
                    planCard(document)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Piano Alimentare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadCached)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheetView(triggerFeature: "meal_plan_lock")
                .environmentObject(KBSubscriptionManager.shared)
        }
        .alert(alertMessage, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        }
        .overlay { generatingOverlay }
    }

    // MARK: - Spiegazione

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "fork.knife")
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Piano Alimentare")
                        .font(.headline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Text("Creato dall'AI sui tuoi dati di salute")
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Spacer(minLength: 0)
            }

            Text("In questa sezione l'assistente AI crea un piano alimentare personalizzato partendo dalle informazioni già presenti in Salute: visite mediche, cure in corso, analisi ed esami, peso, altezza, età e gli allenamenti registrati nell'app Salute.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            Text("Ricevi la stima delle calorie di mantenimento, un deficit realistico, gli obiettivi di proteine, carboidrati e grassi, i pasti con porzioni e alternative, gli spuntini proteici, le opzioni pre e post allenamento, l'idratazione, la lista della spesa e una progressione su 90 giorni.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            Label("Il piano è educativo: validalo sempre con il tuo medico o nutrizionista.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Dati usati

    private var dataSourcesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dati usati per il piano")
                .font(.subheadline.bold())
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
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            }

            if !hasBodyMetrics {
                Text("Peso e altezza sono obbligatori: aggiornali in Apple App Salute o nella Scheda Medica.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private struct DataSourceRow: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
        let available: Bool
    }

    private var hasBodyMetrics: Bool {
        let snap = snapshot
        return snap?.weightKg != nil && snap?.heightCm != nil
    }

    private var dataSourceRows: [DataSourceRow] {
        let snap = snapshot
        let notAvailable = NSLocalizedString("non disponibile", comment: "Missing health data value")

        let ageValue: String
        if let birth = child?.birthDate ?? snap?.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
            ageValue = String(format: NSLocalizedString("%d anni", comment: "Age in years"), years)
        } else {
            ageValue = notAvailable
        }

        return [
            DataSourceRow(id: "age", label: "Età", value: ageValue, available: (child?.birthDate ?? snap?.birthDate) != nil),
            DataSourceRow(
                id: "weight",
                label: "Peso",
                value: snap?.weightKg.map { String(format: "%.1f kg", $0) } ?? notAvailable,
                available: snap?.weightKg != nil
            ),
            DataSourceRow(
                id: "height",
                label: "Altezza",
                value: snap?.heightCm.map { "\(Int($0.rounded())) cm" } ?? notAvailable,
                available: snap?.heightCm != nil
            ),
            DataSourceRow(
                id: "workouts",
                label: "Allenamenti",
                value: "\(snap?.recentWorkouts.count ?? 0)",
                available: !(snap?.recentWorkouts.isEmpty ?? true)
            ),
            DataSourceRow(id: "visits", label: "Visite mediche", value: "\(allVisits.count)", available: !allVisits.isEmpty),
            DataSourceRow(id: "exams", label: "Analisi & Esami", value: "\(allExams.count)", available: !allExams.isEmpty),
            DataSourceRow(id: "treatments", label: "Cure attive", value: "\(activeTreatments.count)", available: !activeTreatments.isEmpty),
        ]
    }

    // MARK: - Piano bloccato (Free)

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Incluso in Pro e Max", systemImage: "lock.fill")
                .font(.subheadline.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Il Piano Alimentare è disponibile solo con un piano a pagamento. Passa a Pro o Max per generarlo con l'AI.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            Button { showUpgrade = true } label: {
                Text("Scopri i piani")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    // MARK: - Form

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation { showForm.toggle() } } label: {
                HStack {
                    Text("Le tue preferenze")
                        .font(.subheadline.bold())
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                    Spacer()
                    Image(systemName: showForm ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showForm {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Obiettivo")
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    Picker("Obiettivo", selection: $input.goal) {
                        ForEach(MealPlanGoal.allCases) { goal in
                            Text(goal.label).tag(goal)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Livello di attività")
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    Picker("Livello di attività", selection: $input.activityLevel) {
                        ForEach(MealPlanActivityLevel.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                textField("Alimenti che ti piacciono", text: $input.preferredFoods)
                textField("Alimenti da evitare o intolleranze", text: $input.avoidedFoods)
                textField("Note aggiuntive", text: $input.notes)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func textField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            TextField(title, text: text, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Costo AI

    private var costCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                String(
                    format: NSLocalizedString(
                        "Generare il piano costa %d messaggi AI",
                        comment: "Meal plan AI cost"
                    ),
                    estimatedUnits
                ),
                systemImage: "sparkles"
            )
            .font(.subheadline.bold())
            .foregroundStyle(KBTheme.primaryText(colorScheme))

            Text("I messaggi sono scalati dal limite giornaliero della famiglia. Il piano resta salvato: rigeneralo solo quando cambiano peso, allenamenti o obiettivo.")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            if let lastUsage {
                Text(lastUsage.usageSummary)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var generateButton: some View {
        Button {
            Task { await generate() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating { ProgressView().controlSize(.small) }
                Text(document == nil ? "Crea piano alimentare" : "Rigenera piano")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isGenerating || !hasBodyMetrics)
    }

    // MARK: - Piano generato

    private func planCard(_ document: MealPlanDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Il tuo piano")
                    .font(.subheadline.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Spacer()
                ShareLink(item: document.text) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            Text(
                String(
                    format: NSLocalizedString("Generato il %@", comment: "Meal plan generated at"),
                    formattedDate(document.generatedAt)
                )
            )
            .font(.caption)
            .foregroundStyle(KBTheme.secondaryText(colorScheme))

            ForEach(document.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if !section.title.isEmpty {
                        Text(section.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(tint)
                    }
                    if !section.body.isEmpty {
                        Text(section.body)
                            .font(.subheadline)
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    @ViewBuilder
    private var generatingOverlay: some View {
        if isGenerating {
            ZStack {
                Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12)
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large)
                    Text("Creazione del piano alimentare in corso…")
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

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(KBTheme.cardBackground(colorScheme))
            .shadow(color: KBTheme.shadow(colorScheme), radius: 6, x: 0, y: 2)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = kbDeviceLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Azioni

    private func loadCached() {
        guard document == nil, let cached = MealPlanStore.load(childId: childId) else {
            refreshEstimate()
            return
        }
        document = cached
        input = cached.input
        refreshEstimate()
    }

    private func refreshEstimate() {
        let payload = MealPlanGenerator.buildPayload(
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
        estimatedUnits = MealPlanGenerator.estimate(payload: payload).messageUnits
    }

    @MainActor
    private func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }

        let payload = MealPlanGenerator.buildPayload(
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
        estimatedUnits = MealPlanGenerator.estimate(payload: payload).messageUnits

        do {
            let result = try await MealPlanGenerator.generate(
                payload: payload,
                subjectName: subjectName,
                input: input
            )
            document = result.document
            lastUsage = result.usage
            MealPlanStore.save(result.document, childId: childId)
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAlert = true
        }
    }
}
