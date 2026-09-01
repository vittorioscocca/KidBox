//
//  FitnessPlanSetupView.swift
//  KidBox
//
//  Wizard di configurazione degli obiettivi (sezione 2 delle specifiche) e, con
//  lo stesso codice, la schermata Impostazioni (sezione 7): le due schermate
//  mostrano le stesse scelte, cambiano solo la navigazione e il pulsante finale.
//
//  Non genera nulla da sé: restituisce l'input al chiamante, che è l'unico a
//  parlare con l'AI e a mostrare il costo in messaggi.
//

import SwiftUI

struct FitnessPlanSetupView: View {

    enum Mode {
        /// Prima configurazione: passi guidati.
        case onboarding
        /// Revisione delle scelte su un piano esistente: modulo unico + ricalcolo.
        case settings
    }

    let mode: Mode
    let subjectName: String
    let estimatedUnits: Int
    /// L'app Salute non copre età, peso o altezza: li chiediamo qui.
    let needsManualMetrics: Bool
    /// Piano corrente: in modalità impostazioni la schermata mostra anche la sua
    /// scheda informativa e gli adattamenti clinici, che nella dashboard
    /// toglievano spazio al calendario.
    let plan: FitnessPlanDocument?
    let lastUsage: FitnessPlanAIUsageInfo?
    let onDelete: () -> Void
    let onConfirm: (FitnessPlanInput) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var input: FitnessPlanInput
    @State private var step = 0
    @State private var showRecalcConfirm = false
    @State private var showDeleteConfirm = false
    @State private var hasRaceDate: Bool

    private let tint = FitnessPlanTheme.tint
    private let lastStep = 2

    init(
        mode: Mode,
        subjectName: String,
        input: FitnessPlanInput,
        estimatedUnits: Int,
        needsManualMetrics: Bool,
        plan: FitnessPlanDocument? = nil,
        lastUsage: FitnessPlanAIUsageInfo? = nil,
        onDelete: @escaping () -> Void = {},
        onConfirm: @escaping (FitnessPlanInput) -> Void
    ) {
        self.mode = mode
        self.subjectName = subjectName
        self.estimatedUnits = estimatedUnits
        self.needsManualMetrics = needsManualMetrics
        self.plan = plan
        self.lastUsage = lastUsage
        self.onDelete = onDelete
        self.onConfirm = onConfirm
        _input = State(initialValue: input)
        _hasRaceDate = State(initialValue: input.raceDate != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if mode == .onboarding {
                        progressHeader
                        stepContent
                    } else {
                        goalSection
                        scheduleSection
                        detailsSection
                        recalcSection
                        if let plan {
                            if !plan.safetyNotes.isEmpty {
                                safetyNotesSection(plan)
                            }
                            planInfoSection(plan)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle(mode == .onboarding ? "Configura il piano" : "Impostazioni piano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if mode == .onboarding { wizardFooter }
            }
        }
        .confirmationDialog(
            "Ricalcolare tutto il piano?",
            isPresented: $showRecalcConfirm,
            titleVisibility: .visible
        ) {
            Button("Ricalcola piano", role: .destructive) { confirm() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(
                String(
                    format: NSLocalizedString(
                        "Il piano attuale viene sostituito da un calendario nuovo, costruito sui parametri aggiornati e sull'ultimo stato di salute. Costa circa %d messaggi AI e lo stato delle sedute già svolte va perso.",
                        comment: "Fitness plan recalculation confirmation"
                    ),
                    estimatedUnits
                )
            )
        }
    }

    // MARK: - Wizard

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? tint : KBTheme.secondaryText(colorScheme).opacity(0.2))
                        .frame(height: 4)
                }
            }
            Text(stepTitle)
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text(stepSubtitle)
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepTitle: LocalizedStringKey {
        switch step {
        case 0:  return "Qual è il tuo obiettivo?"
        case 1:  return "Quando ti alleni?"
        default: return "Come ti alleni?"
        }
    }

    private var stepSubtitle: LocalizedStringKey {
        switch step {
        case 0:  return "L'AI costruisce il piano attorno a questo obiettivo."
        case 1:  return "Scegli i giorni disponibili e l'orario dei promemoria."
        default: return "Ultimi dettagli, poi il piano è pronto per essere generato."
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:  goalSection
        case 1:  scheduleSection
        default: detailsSection
        }
    }

    private var wizardFooter: some View {
        VStack(spacing: 8) {
            if step == lastStep {
                Label(
                    String(
                        format: NSLocalizedString(
                            "La generazione del piano consumerà circa %d messaggi AI",
                            comment: "Fitness plan AI cost notice"
                        ),
                        estimatedUnits
                    ),
                    systemImage: "sparkles"
                )
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                if step > 0 {
                    Button("Indietro") {
                        withAnimation { step -= 1 }
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if step < lastStep {
                        withAnimation { step += 1 }
                    } else {
                        confirm()
                    }
                } label: {
                    Text(step < lastStep ? "Avanti" : "Genera il piano")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .disabled(!canContinue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            if input.goal != .race { return true }
            guard let raceType = input.raceType else { return false }
            return raceType != .other
                || !input.raceDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return !input.trainingWeekdays.isEmpty
        default:
            return input.isComplete
        }
    }

    // MARK: - Sezioni

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Obiettivo principale")
            FitnessFlowLayout(spacing: 8) {
                ForEach(FitnessGoal.allCases) { goal in
                    FitnessChoiceChip(
                        goal.label,
                        systemImage: goal.systemImage,
                        selected: input.goal == goal
                    ) {
                        input.goal = goal
                        if goal != .race {
                            input.raceType = nil
                            input.raceDate = nil
                            hasRaceDate = false
                        } else if input.raceType == nil {
                            input.raceType = input.sortedSports.first ?? .running
                            input.preferredSports.insert(input.raceType ?? .running)
                        }
                    }
                }
            }

            Divider()

            sectionTitle("Sport che vuoi praticare")
            Text("Vale per qualsiasi obiettivo: l'AI costruisce le sedute attorno a questi sport. Puoi sceglierne più di uno, oppure nessuno e decide lei.")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            FitnessFlowLayout(spacing: 8) {
                ForEach(FitnessSport.allCases) { sport in
                    FitnessChoiceChip(
                        sport.label,
                        selected: input.preferredSports.contains(sport)
                    ) {
                        if input.preferredSports.contains(sport) {
                            input.preferredSports.remove(sport)
                        } else {
                            input.preferredSports.insert(sport)
                        }
                    }
                }
            }

            if input.goal == .race {
                Divider()
                sectionTitle("Gara o evento di riferimento")
                FitnessFlowLayout(spacing: 8) {
                    ForEach(FitnessSport.raceOptions) { type in
                        FitnessChoiceChip(type.label, selected: input.raceType == type) {
                            input.raceType = type
                            // Chi prepara una gara pratica quello sport: evita di
                            // doverlo selezionare due volte.
                            input.preferredSports.insert(type)
                        }
                    }
                }
                textField(
                    input.raceType == .other
                        ? "Descrivi la gara (obbligatorio)"
                        : "Dettagli: distanza, livello, obiettivo di tempo",
                    text: $input.raceDetail
                )

                Toggle(isOn: $hasRaceDate.animation()) {
                    Text("Ho una data")
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                }
                .tint(tint)
                .onChange(of: hasRaceDate) { _, enabled in
                    input.raceDate = enabled
                        ? (input.raceDate ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()))
                        : nil
                }

                if hasRaceDate {
                    DatePicker(
                        "Data della gara",
                        selection: Binding(
                            get: { input.raceDate ?? Date() },
                            set: { input.raceDate = $0 }
                        ),
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .font(.subheadline)
                }
            }
        }
        .fitnessCard()
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Giorni disponibili")
            FitnessWeekdayPicker(weekdays: $input.trainingWeekdays)
            if input.trainingWeekdays.isEmpty {
                Text("Scegli almeno un giorno.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            Toggle(isOn: $input.reminderEnabled.animation()) {
                Text("Promemoria di allenamento")
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
            }
            .tint(tint)

            if input.reminderEnabled {
                DatePicker(
                    "Orario preferito",
                    selection: Binding(
                        get: {
                            var components = DateComponents()
                            components.hour = input.reminderHour
                            components.minute = input.reminderMinute
                            return Calendar.current.date(from: components) ?? Date()
                        },
                        set: { date in
                            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                            input.reminderMinutesFromMidnight =
                                (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .font(.subheadline)

                Text("Il promemoria arriva a quest'ora nei giorni di allenamento, con i pulsanti Fatto e Sposta.")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }

            Divider()

            sectionTitle("Durata di una seduta")
            FitnessFlowLayout(spacing: 8) {
                ForEach([20, 30, 45, 60, 90], id: \.self) { minutes in
                    FitnessChoiceChip(
                        LocalizedStringKey("\(minutes) min"),
                        selected: input.sessionMinutes == minutes
                    ) {
                        input.sessionMinutes = minutes
                    }
                }
            }
        }
        .fitnessCard()
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Esperienza")
            FitnessFlowLayout(spacing: 8) {
                ForEach(FitnessExperience.allCases) { level in
                    FitnessChoiceChip(level.label, selected: input.experience == level) {
                        input.experience = level
                    }
                }
            }

            sectionTitle("Dove ti alleni")
            FitnessFlowLayout(spacing: 8) {
                ForEach(FitnessPlace.allCases) { place in
                    FitnessChoiceChip(place.label, selected: input.place == place) {
                        input.place = place
                    }
                }
            }

            if needsManualMetrics {
                Divider()
                Label("Età, peso e altezza", systemImage: "figure.stand")
                    .font(.caption.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Text("L'app Salute non ha tutti i dati: inseriscili qui, servono per calibrare i carichi.")
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                HStack(spacing: 8) {
                    numberField("Età (anni)", text: $input.manualAgeYears)
                    numberField("Peso (kg)", text: $input.manualWeightKg)
                    numberField("Altezza (cm)", text: $input.manualHeightCm)
                }
            }

            textField("Infortuni, limiti o preferenze da tenere presenti", text: $input.notes)

            Label("L'AI legge referti, patologie e terapie già presenti in Salute per evitare esercizi controindicati.", systemImage: "cross.case")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .fitnessCard()
    }

    private var recalcSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                String(
                    format: NSLocalizedString(
                        "Il ricalcolo consumerà circa %d messaggi AI",
                        comment: "Fitness plan recalculation cost"
                    ),
                    estimatedUnits
                ),
                systemImage: "sparkles"
            )
            .font(.subheadline.bold())
            .foregroundStyle(KBTheme.primaryText(colorScheme))

            Text("Cambiare obiettivo, giorni o orari disattiva il piano attuale: serve un ricalcolo totale su un calendario nuovo.")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

            Button {
                showRecalcConfirm = true
            } label: {
                Text("Ricalcola il piano")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(!input.isComplete)
        }
        .fitnessCard()
    }

    // MARK: - Informazioni sul piano (solo impostazioni)

    private func safetyNotesSection(_ plan: FitnessPlanDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Adattamenti per la tua salute", systemImage: "cross.case")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Come l'AI ha adattato il piano ai tuoi dati clinici.")
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            ForEach(plan.safetyNotes, id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(tint)
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                }
            }
        }
        .fitnessCard()
    }

    private func planInfoSection(_ plan: FitnessPlanDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Il piano attuale")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }

            Text(
                String(
                    format: NSLocalizedString("Generato il %@", comment: "Fitness plan generated at"),
                    FitnessPlanFormat.dateTime(plan.generatedAt)
                )
            )
            .font(.footnote)
            .foregroundStyle(KBTheme.secondaryText(colorScheme))

            if let lastUsage {
                Text(lastUsage.usageSummary)
                    .font(.footnote)
                    .foregroundStyle(tint)
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Elimina il piano", systemImage: "trash")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
        .fitnessCard()
        .confirmationDialog(
            "Vuoi eliminare il piano fitness?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina piano", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il piano e i promemoria vengono rimossi. Rigenerarlo costa di nuovo messaggi AI.")
        }
    }

    // MARK: - Pezzi riutilizzati

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(KBTheme.primaryText(colorScheme))
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

    private func confirm() {
        onConfirm(input)
        dismiss()
    }
}
