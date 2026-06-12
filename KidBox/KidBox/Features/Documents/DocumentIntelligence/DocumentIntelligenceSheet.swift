//
//  DocumentIntelligenceSheet.swift
//  KidBox
//
//  Sheet di conferma: mostra le azioni proposte dall'AI per il documento
//  importato. L'utente sceglie quali eseguire.
//

import SwiftUI
import SwiftData

struct DocumentIntelligenceSheet: View {
    let payload: DocumentFolderViewModel.DocIntelPayload
    let familyId: String
    let modelContext: ModelContext
    var onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selected: Set<UUID>
    @State private var isExecuting = false
    @State private var resultText: String?

    init(payload: DocumentFolderViewModel.DocIntelPayload,
         familyId: String,
         modelContext: ModelContext,
         onDone: @escaping () -> Void) {
        self.payload = payload
        self.familyId = familyId
        self.modelContext = modelContext
        self.onDone = onDone
        _selected = State(initialValue: Set(payload.result.actions.map { $0.id }))
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(.systemBackground)
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
                            Text(payload.result.documentType ?? "Documento analizzato")
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
                        ForEach(payload.result.actions) { action in
                            Button {
                                toggle(action.id)
                            } label: {
                                actionRow(action)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(cardBackground)
                        }
                    }

                    Section {
                        Text("Le azioni selezionate verranno create nelle rispettive sezioni dell'app. Il documento resta allegato dove pertinente.")
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
                    Button(resultText == nil ? "Annulla" : "Chiudi") { finish() }
                }
                if resultText == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Conferma") { Task { await confirm() } }
                            .disabled(selected.isEmpty || isExecuting)
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
    }

    @ViewBuilder
    private func actionRow(_ action: DocIntelAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.iconName)
                .frame(width: 28)
                .foregroundStyle(KBTheme.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.humanTypeLabel)
                    .font(.subheadline.weight(.semibold))
                Text(action.summary ?? action.title ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected.contains(action.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected.contains(action.id) ? KBTheme.tint : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func confirm() async {
        isExecuting = true
        let chosen = payload.result.actions.filter { selected.contains($0.id) }
        let executor = DocumentIntelligenceExecutor(
            modelContext: modelContext,
            familyId: familyId,
            documentId: payload.documentId,
            children: payload.children,
            vehicles: payload.vehicles
        )
        let summary = await executor.execute(chosen)
        isExecuting = false
        resultText = summary ?? "Nessuna azione creata."
    }

    private func finish() {
        onDone()
        dismiss()
    }
}
