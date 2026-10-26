//
//  DocumentIntelligenceSheet.swift
//  KidBox
//
//  Sheet di conferma: mostra cosa l'AI ha capito del documento e le azioni
//  proposte nelle rispettive sezioni. L'utente sceglie quali eseguire e può
//  correggere titolo, importo, data e persona prima di salvare.
//

import SwiftUI
import SwiftData

struct DocumentIntelligenceSheet: View {
    let payload: DocIntelPayload
    let familyId: String
    let modelContext: ModelContext
    /// Riepilogo di quanto creato (nil se annullato o nulla di creato).
    var onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var actions: [DocIntelAction]
    @State private var selected: Set<UUID>
    @State private var expanded: UUID?
    @State private var isExecuting = false
    @State private var resultText: String?
    @State private var createdSummary: String?

    init(payload: DocIntelPayload,
         familyId: String,
         modelContext: ModelContext,
         onDone: @escaping (String?) -> Void) {
        self.payload = payload
        self.familyId = familyId
        self.modelContext = modelContext
        self.onDone = onDone
        _actions = State(initialValue: payload.result.actions)
        _selected = State(initialValue: Set(payload.result.actions.map { $0.id }))
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(.systemBackground)
    }

    /// Azioni selezionate a cui manca la persona: senza, la scheda non si salva.
    private var missingPerson: Bool {
        actions.contains { selected.contains($0.id) && $0.needsPerson && personName($0.childId) == nil }
    }

    /// Prima scheda selezionata che riceverà il file (stesso ordine dell'executor).
    private var attachLabel: String? {
        guard payload.sourceFile != nil else { return nil }
        let order = ["house_payment", "medical_visit", "exam_add", "treatment_add"]
        let chosen = actions.filter { selected.contains($0.id) && $0.takesAttachment }
        return order.compactMap { t in chosen.first { $0.type == t } }.first?.humanTypeLabel
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(KBTheme.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payload.result.documentType ?? String(localized: "Documento analizzato"))
                                .font(.headline)
                            if let t = payload.result.suggestedTitle {
                                Text(t).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(cardBackground)
                }

                if let resultText {
                    Section("Fatto") {
                        Text(resultText)
                            .font(.callout)
                            .listRowBackground(cardBackground)
                    }
                } else {
                    Section("Azioni proposte") {
                        ForEach($actions) { $action in
                            VStack(alignment: .leading, spacing: 10) {
                                actionRow(action)
                                if expanded == action.id {
                                    DocIntelActionEditor(action: $action, persons: payload.children)
                                }
                            }
                            .listRowBackground(cardBackground)
                        }
                    }

                    Section {
                        Group {
                            if payload.sourceFile != nil {
                                if let attachLabel {
                                    Text("Il file verrà allegato a: \(attachLabel).")
                                } else {
                                    Text("Il file verrà salvato in Documenti.")
                                }
                            } else {
                                Text("Le azioni selezionate verranno create nelle rispettive sezioni dell'app. Il documento resta allegato dove pertinente.")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Smista documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { finish() } label: {
                        if resultText == nil { Text("Annulla") } else { Text("Chiudi") }
                    }
                }
                if resultText == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Conferma") { Task { await confirm() } }
                            .disabled((selected.isEmpty && payload.sourceFile == nil) || missingPerson || isExecuting)
                    }
                }
            }
            .overlay {
                if isExecuting {
                    ProgressView("Creazione…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .interactiveDismissDisabled(isExecuting)
        .onAppear { AppAnalytics.screenView(name: "document_intelligence") }
    }

    @ViewBuilder
    private func actionRow(_ action: DocIntelAction) -> some View {
        HStack(spacing: 12) {
            Button {
                toggle(action.id)
            } label: {
                Image(systemName: selected.contains(action.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected.contains(action.id) ? KBTheme.tint : Color.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: action.iconName)
                .frame(width: 24)
                .foregroundStyle(KBTheme.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.humanTypeLabel)
                    .font(.subheadline.weight(.semibold))
                Text(action.summary ?? action.title ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if action.needsPerson {
                    if let name = personName(action.childId) {
                        Label(name, systemImage: "person")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Scegli la persona", systemImage: "person.fill.questionmark")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            if action.type != "rename_document" {
                Button {
                    withAnimation { expanded = expanded == action.id ? nil : action.id }
                } label: {
                    Image(systemName: expanded == action.id ? "chevron.up" : "pencil")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Modifica"))
            }
        }
        .contentShape(Rectangle())
    }

    private func personName(_ id: String?) -> String? {
        guard let id else { return nil }
        return payload.children.first { $0.id == id }?.name
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func confirm() async {
        isExecuting = true
        let chosen = actions.filter { selected.contains($0.id) }
        let executor = DocumentIntelligenceExecutor(
            modelContext: modelContext,
            familyId: familyId,
            documentId: payload.documentId,
            sourceFile: payload.sourceFile,
            children: payload.children,
            vehicles: payload.vehicles
        )
        let summary = await executor.execute(chosen)
        isExecuting = false
        resultText = summary ?? String(localized: "Nessuna azione creata.")
        createdSummary = summary
    }

    private func finish() {
        onDone(createdSummary)
        dismiss()
    }
}

/// Campi correggibili di un'azione: titolo, importo, data, persona.
private struct DocIntelActionEditor: View {
    @Binding var action: DocIntelAction
    let persons: [DocumentIntelligenceService.ChildRef]

    private var showsAmount: Bool {
        ["expense_add", "house_payment", "vehicle_event"].contains(action.type)
    }

    private var dateLabel: LocalizedStringKey {
        switch action.type {
        case "house_payment": return "Scadenza"
        case "treatment_add": return "Inizio"
        default:              return "Data"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Titolo", text: Binding(
                get: { action.title ?? "" },
                set: { action.title = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            if showsAmount {
                HStack {
                    Text("Importo")
                    Spacer()
                    TextField("0,00", value: Binding(
                        get: { action.amount },
                        set: { action.amount = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
                    Text(verbatim: "€").foregroundStyle(.secondary)
                }
            }

            if action.type != "note_add" {
                DatePicker(dateLabel, selection: Binding(
                    get: { DocIntelDate.parse(action.date) ?? Date() },
                    set: { action.date = DocIntelDate.format($0) }
                ), displayedComponents: action.type == "event_add" ? [.date, .hourAndMinute] : [.date])
            }

            if action.needsPerson {
                Picker("Persona", selection: Binding(
                    get: { action.childId ?? "" },
                    set: { action.childId = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Scegli…").tag("")
                    ForEach(persons.filter { action.type != "vaccine_add" || !$0.isAdult }, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(.leading, 36)
    }
}

/// Date ISO8601 dell'AI, lette e riscritte dalla scheda.
enum DocIntelDate {
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = f.date(from: raw) { return d }
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: raw)
    }

    static func format(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
