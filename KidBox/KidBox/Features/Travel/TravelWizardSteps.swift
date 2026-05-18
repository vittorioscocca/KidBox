//
//  TravelWizardSteps.swift
//  KidBox
//

import SwiftUI

private let wizardAccent = Color(red: 0.95, green: 0.38, blue: 0.10)

private struct WizardInfoTip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(wizardAccent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(wizardAccent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Chrome

struct TravelWizardStepLayout<Content: View>: View {
    let step: Int
    let totalSteps: Int
    let title: String
    let subtitle: String
    let canContinue: Bool
    let continueTitle: String
    let onBack: () -> Void
    let onContinue: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if step > 0 {
                    Button("Indietro", action: onBack)
                } else {
                    Color.clear.frame(width: 60, height: 1)
                }
                Spacer()
                Text("\(step + 1) di \(totalSteps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(wizardAccent)
                        .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.title.bold())
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)
            }

            Button(action: onContinue) {
                Text(continueTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canContinue ? wizardAccent : Color.gray.opacity(0.35))
                    .clipShape(Capsule())
            }
            .disabled(!canContinue)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Step 1 Destination

struct TravelWizardDestinationStep: View {
    @ObservedObject var vm: TravelPlanningViewModel

    var body: some View {
        TravelDestinationSearchField(
            destinationName: $vm.destinationName,
            destinationRegion: $vm.destinationRegion,
            onSelectionChanged: { vm.syncTripFromWizardInputs() }
        )
    }
}

// MARK: - Step 2 Dates

struct TravelWizardDatesStep: View {
    @ObservedObject var vm: TravelPlanningViewModel
    @State private var editingDeparture = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                dateCard(title: "PARTENZA", date: vm.startDate, highlighted: editingDeparture) {
                    editingDeparture = true
                }
                dateCard(title: "RITORNO", date: vm.endDate, highlighted: !editingDeparture) {
                    editingDeparture = false
                }
            }

            DatePicker(
                "Calendario",
                selection: activeDateBinding,
                in: editingDeparture ? Date()... : vm.startDate...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
    }

    private var activeDateBinding: Binding<Date> {
        Binding(
            get: { editingDeparture ? vm.startDate : vm.endDate },
            set: { newDate in
                if editingDeparture {
                    vm.startDate = newDate
                    if vm.endDate < newDate {
                        vm.endDate = newDate
                    }
                } else {
                    vm.endDate = max(newDate, vm.startDate)
                }
                vm.syncTripFromWizardInputs()
            }
        )
    }

    private func dateCard(title: String, date: Date, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.title2.bold())
                Text(date.formatted(.dateTime.weekday(.abbreviated).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(highlighted ? Color.primary : Color.primary.opacity(0.12), lineWidth: highlighted ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3 Transport

struct TravelWizardTransportStep: View {
    @ObservedObject var vm: TravelPlanningViewModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(WizardPrimaryTransport.allCases) { mode in
                Button {
                    vm.primaryTransport = mode
                    vm.syncTripFromWizardInputs()
                } label: {
                    HStack(spacing: 14) {
                        Text(mode.emoji).font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title).font(.headline).foregroundStyle(.primary)
                            Text(mode.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                vm.primaryTransport == mode ? wizardAccent : Color.primary.opacity(0.1),
                                lineWidth: vm.primaryTransport == mode ? 2 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Text("Scegli come raggiungerete la destinazione.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step 4 Participants

struct TravelWizardParticipantsStep: View {
    @ObservedObject var vm: TravelPlanningViewModel
    let members: [KBFamilyMember]
    let children: [KBChild]

    private var lines: [TravelWizardParticipantLine] {
        vm.participantLines(members: members, children: children)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if lines.isEmpty {
                Text("Aggiungi membri della famiglia in Impostazioni.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(lines) { line in
                        participantCard(line)
                    }
                }
            }

            if !vm.selectedParticipantIds.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SELEZIONATI")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(vm.selectedParticipantSummary(members: members, children: children))
                        .font(.headline)
                    Text("Perfetto. Pianificheremo per \(vm.selectedParticipantIds.count) \(vm.selectedParticipantIds.count == 1 ? "persona" : "persone").")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear {
            if vm.selectedParticipantIds.isEmpty {
                vm.selectAllParticipants(members: members, children: children)
            }
        }
    }

    private func participantCard(_ line: TravelWizardParticipantLine) -> some View {
        let selected = vm.selectedParticipantIds.contains(line.id)
        return Button {
            vm.setParticipantSelected(line.id, selected: !selected)
        } label: {
            VStack(spacing: 8) {
                Text(line.emoji).font(.largeTitle)
                Text(line.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(line.ageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? wizardAccent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(wizardAccent)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 5 Budget

struct TravelWizardBudgetStep: View {
    @ObservedObject var vm: TravelPlanningViewModel
    let members: [KBFamilyMember]
    let children: [KBChild]

    @FocusState private var customFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Valuta", selection: $vm.currency) {
                Text("EUR").tag("EUR")
                Text("USD").tag("USD")
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.currency) { _, _ in
                if vm.usesCustomBudget {
                    vm.updateCustomBudget(from: vm.customBudgetInput)
                } else if let preset = TravelWizardBudgetPreset.allCases.first(where: { vm.matchesBudgetPreset($0) }) {
                    vm.applyBudgetPreset(preset)
                }
            }

            VStack(spacing: 8) {
                Text(formattedBudget)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(vm.budgetFootnote(members: members, children: children))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("SELEZIONE RAPIDA")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(TravelWizardBudgetPreset.allCases) { preset in
                    let selected = vm.matchesBudgetPreset(preset)
                    Button {
                        vm.applyBudgetPreset(preset)
                    } label: {
                        Text(preset.label(currency: vm.currency))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selected ? wizardAccent : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    vm.enableCustomBudget()
                    customFieldFocused = true
                } label: {
                    Text("Personalizzato")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(vm.usesCustomBudget ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(vm.usesCustomBudget ? wizardAccent : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if vm.usesCustomBudget {
                HStack(spacing: 12) {
                    TextField(
                        "Importo personalizzato",
                        text: Binding(
                            get: { vm.customBudgetInput },
                            set: { vm.updateCustomBudget(from: $0) }
                        )
                    )
                        .keyboardType(.numberPad)
                        .focused($customFieldFocused)
                    Text(vm.currency == "EUR" ? "€" : "$")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(alignment: .top, spacing: 0) {
                Rectangle().fill(wizardAccent).frame(width: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suggerimento").font(.headline)
                    Text("Il budget include voli, alloggio, cibo, attività e trasporti locali.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
            .background(wizardAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var formattedBudget: String {
        let symbol = vm.currency == "EUR" ? "€" : "$"
        if vm.usesCustomBudget, vm.customBudgetInput.isEmpty {
            return "—"
        }
        let value = Int(vm.budgetTotal)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        return vm.currency == "EUR" ? "\(text) \(symbol)" : "\(symbol)\(text)"
    }
}

// MARK: - Step 6 Trip style

struct TravelWizardTripStyleStep: View {
    @ObservedObject var vm: TravelPlanningViewModel
    let destinationName: String

    private let gridStyles: [TravelStyle] = [.culture, .food, .nightlife, .adventure, .relaxation, .shopping]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WizardInfoTip(text: "Precompilato dal tuo profilo — modifica quando vuoi.")

            Text("STILE DEL VIAGGIO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(gridStyles) { style in
                    styleCard(style)
                }
            }
        }
    }

    private func styleCard(_ style: TravelStyle) -> some View {
        let selected = vm.tripStyles.contains(style)
        return Button {
            if selected { vm.tripStyles.remove(style) } else { vm.tripStyles.insert(style) }
        } label: {
            VStack(spacing: 8) {
                Text(style.emoji).font(.largeTitle)
                Text(style.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(style.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? wizardAccent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(wizardAccent)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 7 Build

struct TravelWizardBuildStep: View {
    @ObservedObject var vm: TravelPlanningViewModel
    let members: [KBFamilyMember]
    let children: [KBChild]
    let aiAvailable: Bool
    let onUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RIEPILOGO VIAGGIO")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            summaryRow("Destinazione", vm.destinationName)
            summaryRow("Date", "\(vm.startDate.formatted(date: .abbreviated, time: .omitted)) – \(vm.endDate.formatted(date: .abbreviated, time: .omitted))")
            summaryRow("Trasporto", vm.primaryTransport.title)
            summaryRow("Viaggiatori", vm.selectedParticipantSummary(members: members, children: children))
            summaryRow("Budget", formattedBudget)
            summaryRow("Stile", vm.tripStyles.map(\.title).sorted().joined(separator: ", "))

            if aiAvailable {
                ZStack(alignment: .topLeading) {
                    if vm.freeTextPrompt.isEmpty {
                        Text("Note aggiuntive per l'AI (opzionale)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.horizontal, 4)
                    }
                    TextEditor(text: $vm.freeTextPrompt)
                        .frame(minHeight: 100)
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Pianificazione AI: \(vm.tripDayCount) giorni · \(TravelPlanningCountdown.messageCost(plannedDayCount: vm.tripDayCount)) messaggi sul limite giornaliero della famiglia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("La pianificazione con AI richiede un piano Pro o Max.")
                    .foregroundStyle(.secondary)
                Button("Scopri Pro e Max", action: onUpgrade)
                    .buttonStyle(.borderedProminent)
            }

            if let err = vm.generationError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value).font(.subheadline.weight(.medium))
        }
    }

    private var formattedBudget: String {
        let symbol = vm.currency == "EUR" ? "€" : "$"
        return "\(Int(vm.budgetTotal)) \(symbol)"
    }
}
