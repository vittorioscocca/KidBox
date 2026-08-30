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
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var currentSection = 0
    @State private var showDeleteConfirm = false

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
        .kbRefreshable { await syncFromRemote() }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Piano Alimentare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadCached()
            Task { await syncFromRemote() }
        }
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

            Label("Per un piano completo collega i dati dell'app Salute: peso, altezza, età e allenamenti vengono letti da lì. Se non sono disponibili, inserisci tu età, peso e altezza qui sotto.", systemImage: "heart.text.square")
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

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
                Text("Peso e altezza sono obbligatori: aggiornali nell'app Salute, nella Scheda Medica, oppure inseriscili a mano qui sotto.")
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

    /// Peso e altezza: dall'app Salute oppure inseriti a mano nel form.
    private var hasBodyMetrics: Bool {
        let snap = snapshot
        let weight = snap?.weightKg ?? input.manualWeightValue
        let height = snap?.heightCm ?? input.manualHeightValue
        return weight != nil && height != nil
    }

    /// Vero quando l'app Salute non copre peso o altezza: allora li chiediamo all'utente.
    private var needsManualMetrics: Bool {
        let snap = snapshot
        return snap?.weightKg == nil || snap?.heightCm == nil || (child?.birthDate ?? snap?.birthDate) == nil
    }

    private var dataSourceRows: [DataSourceRow] {
        let snap = snapshot
        let notAvailable = NSLocalizedString("non disponibile", comment: "Missing health data value")

        let manualSuffix = NSLocalizedString(" (inserito da te)", comment: "Manually entered health value")

        let ageValue: String
        let ageAvailable: Bool
        if let birth = child?.birthDate ?? snap?.birthDate {
            let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
            ageValue = String(format: NSLocalizedString("%d anni", comment: "Age in years"), years)
            ageAvailable = true
        } else if let age = input.manualAgeValue {
            ageValue = String(format: NSLocalizedString("%d anni", comment: "Age in years"), age) + manualSuffix
            ageAvailable = true
        } else {
            ageValue = notAvailable
            ageAvailable = false
        }

        let weightValue: String
        if let weight = snap?.weightKg {
            weightValue = String(format: "%.1f kg", weight)
        } else if let weight = input.manualWeightValue {
            weightValue = String(format: "%.1f kg", weight) + manualSuffix
        } else {
            weightValue = notAvailable
        }

        let heightValue: String
        if let height = snap?.heightCm {
            heightValue = "\(Int(height.rounded())) cm"
        } else if let height = input.manualHeightValue {
            heightValue = "\(Int(height.rounded())) cm" + manualSuffix
        } else {
            heightValue = notAvailable
        }

        return [
            DataSourceRow(id: "age", label: "Età", value: ageValue, available: ageAvailable),
            DataSourceRow(
                id: "weight",
                label: "Peso",
                value: weightValue,
                available: snap?.weightKg != nil || input.manualWeightValue != nil
            ),
            DataSourceRow(
                id: "height",
                label: "Altezza",
                value: heightValue,
                available: snap?.heightCm != nil || input.manualHeightValue != nil
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
            Text("Le tue preferenze")
                .font(.subheadline.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            if needsManualMetrics {
                manualMetricsSection
                Divider()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Obiettivo")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                MealPlanFlowLayout(spacing: 8) {
                    ForEach(MealPlanGoal.allCases) { goal in
                        chip(goal.label, selected: input.goal == goal) { input.goal = goal }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Livello di attività")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                MealPlanFlowLayout(spacing: 8) {
                    ForEach(MealPlanActivityLevel.allCases) { level in
                        chip(level.label, selected: input.activityLevel == level) { input.activityLevel = level }
                    }
                }
            }

            textField("Alimenti che ti piacciono", text: $input.preferredFoods)
            textField("Alimenti da evitare o intolleranze", text: $input.avoidedFoods)
            textField("Note aggiuntive", text: $input.notes)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .onChange(of: input.manualAgeYears) { _, _ in refreshEstimate() }
        .onChange(of: input.manualWeightKg) { _, _ in refreshEstimate() }
        .onChange(of: input.manualHeightCm) { _, _ in refreshEstimate() }
    }

    /// Chiesti solo quando l'app Salute non fornisce età, peso o altezza.
    private var manualMetricsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Età, peso e altezza", systemImage: "figure.stand")
                .font(.caption.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("L'app Salute non ha tutti i dati: inseriscili qui, servono per stimare le calorie.")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            HStack(spacing: 8) {
                numberField("Età (anni)", text: $input.manualAgeYears)
                numberField("Peso (kg)", text: $input.manualWeightKg)
                numberField("Altezza (cm)", text: $input.manualHeightCm)
            }
        }
    }

    private func numberField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            TextField(title, text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// Capsula identica a quella Android (MealPlanChoiceChip): stesso raggio,
    /// stesso bordo, stesso riempimento al 18% del tint.
    private func chip(_ title: LocalizedStringKey, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(selected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(selected ? tint : KBTheme.primaryText(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(selected ? tint.opacity(0.18) : KBTheme.secondaryText(colorScheme).opacity(0.08))
                )
                .overlay(
                    Capsule().stroke(
                        selected ? tint : KBTheme.secondaryText(colorScheme).opacity(0.28),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: selected)
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
        let sections = document.sections
        return VStack(alignment: .leading, spacing: 12) {
            planHeader(document, sections: sections)

            if sections.isEmpty {
                Text(document.text)
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
            } else {
                sectionTabs(sections)

                TabView(selection: $currentSection) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        sectionCard(section, index: index, total: sections.count)
                            .padding(.bottom, 6)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 470)
                .animation(.easeInOut(duration: 0.2), value: currentSection)

                pageIndicator(count: sections.count)
            }
        }
        .onChange(of: document.generatedAt) { _, _ in currentSection = 0 }
    }

    private func planHeader(_ document: MealPlanDocument, sections: [MealPlanSection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Il tuo piano")
                    .font(.subheadline.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Spacer()
                ShareLink(item: document.text) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("Elimina piano")
            }
            Text(
                String(
                    format: NSLocalizedString("Generato il %@", comment: "Meal plan generated at"),
                    formattedDate(document.generatedAt)
                )
            )
            .font(.caption)
            .foregroundStyle(KBTheme.secondaryText(colorScheme))

            if !sections.isEmpty {
                Label("Scorri di lato per passare da una scheda all'altra.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(tint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .confirmationDialog(
            "Vuoi eliminare il piano alimentare?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina piano", role: .destructive) { deletePlan() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il piano viene rimosso da questo dispositivo. Rigenerarlo costa di nuovo messaggi AI.")
        }
    }

    /// Striscia di capsule con i titoli: salta a una scheda senza scorrere tutte le altre.
    private func sectionTabs(_ sections: [MealPlanSection]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        let selected = index == currentSection
                        Button {
                            withAnimation { currentSection = index }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: icon(for: section))
                                    .font(.caption2.weight(.semibold))
                                Text(sectionTitle(section, index: index))
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? tint : KBTheme.secondaryText(colorScheme))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selected ? tint.opacity(0.18) : KBTheme.secondaryText(colorScheme).opacity(0.08)))
                            .overlay(Capsule().stroke(selected ? tint : .clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: currentSection) { _, index in
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func sectionCard(_ section: MealPlanSection, index: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: icon(for: section))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(sectionTitle(section, index: index))
                    .font(.subheadline.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(index + 1)/\(total)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tint.opacity(0.12)))
            }
            .padding(16)

            Divider().padding(.horizontal, 16)

            ScrollView(showsIndicators: true) {
                Text(section.body)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.9),
                        .init(color: .black.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 10, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }

    private func pageIndicator(count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentSection ? tint : KBTheme.secondaryText(colorScheme).opacity(0.28))
                    .frame(width: index == currentSection ? 18 : 6, height: 6)
                    .onTapGesture { withAnimation { currentSection = index } }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: currentSection)
    }

    /// Titolo leggibile: l'AI scrive i titoli in MAIUSCOLO, qui li ammorbidiamo.
    private func sectionTitle(_ section: MealPlanSection, index: Int) -> String {
        let raw = section.title.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else {
            return String(format: NSLocalizedString("Scheda %d", comment: "Meal plan untitled card"), index + 1)
        }
        // L'AI scrive i titoli tutti in MAIUSCOLO: li riportiamo a maiuscola iniziale
        // sola, come su Android.
        let locale = kbDeviceLocale()
        return raw.prefix(1).uppercased(with: locale) + raw.dropFirst().lowercased(with: locale)
    }

    /// Icona scelta sul titolo di sezione, con fallback neutro.
    private func icon(for section: MealPlanSection) -> String {
        let title = section.title.lowercased()
        let map: [(keys: [String], symbol: String)] = [
            (["calor", "calorie", "energ"], "flame"),
            (["macro", "protein", "carboidr", "grass"], "chart.pie"),
            (["pasti", "pasto", "meal", "menu"], "fork.knife"),
            (["idrat", "acqua", "water"], "drop"),
            (["spesa", "shopping", "lista"], "cart"),
            (["90", "giorni", "progress", "piano"], "calendar"),
            (["salute", "note", "health", "clinic"], "heart.text.square"),
            (["allenam", "workout", "training"], "figure.run"),
        ]
        for entry in map where entry.keys.contains(where: { title.contains($0) }) {
            return entry.symbol
        }
        return "list.bullet"
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

    private func deletePlan() {
        MealPlanStore.clear(childId: childId)
        document = nil
        lastUsage = nil
        currentSection = 0
        let cid = childId
        Task { await MealPlanRemoteStore.delete(childId: cid) }
    }

    /// Allinea la copia locale con Firestore: vince il piano generato più di
    /// recente, e un'eliminazione fatta su un altro device svuota anche qui.
    @MainActor
    private func syncFromRemote() async {
        switch await MealPlanRemoteStore.fetch(childId: childId) {
        case .none:
            // Mai sincronizzato: se qui c'è un piano locale, è quello da caricare
            // sul remoto (piano generato prima che il sync esistesse).
            if let document {
                await MealPlanRemoteStore.upsert(document, childId: childId)
            }
        case .deleted:
            if document != nil {
                MealPlanStore.clear(childId: childId)
                document = nil
                lastUsage = nil
                currentSection = 0
            }
        case .plan(let remote):
            guard remote.generatedAt > (document?.generatedAt ?? .distantPast) else { return }
            document = remote
            input = remote.input
            currentSection = 0
            MealPlanStore.save(remote, childId: childId)
            refreshEstimate()
        }
    }

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
            currentSection = 0
            MealPlanStore.save(result.document, childId: childId)
            await MealPlanRemoteStore.upsert(result.document, childId: childId)
        } catch {
            alertMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showAlert = true
        }
    }
}

// MARK: - Flow layout per le capsule (equivalente di FlowRow su Android)

private struct MealPlanFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
