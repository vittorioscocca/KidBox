//
//  KBSearchView.swift
//  KidBox
//
//  «Cerca in KidBox»: il foglio della lente accanto alla lampadina in Home.
//  Capsule per restringere a una o più sezioni (nessuna = tutto), risultati
//  per sezione mentre si scrive; un tocco chiude il foglio e apre la voce, e
//  in fondo «Chiedi all'assistente» con la frase già scritta, per le domande
//  che una ricerca non risolve («quanto abbiamo speso di scuola?»).
//

import SwiftUI
import SwiftData

struct KBSearchView: View {

    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var index: KBSearchIndex?
    @State private var sections: [KBSearchIndex.Section] = []
    /// Capsule scelte: nessuna = tutte le sezioni.
    @State private var kinds: Set<AgentLinks.Kind> = []
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 10)
            filterCapsules
                .padding(.vertical, 10)
            List {
                if index == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if trimmed.count < 2 && kinds.isEmpty {
                    Text("Cerca fra spese, documenti (anche nel testo letto), note, calendario, to-do, salute, wallet, casa, veicoli, animali e viaggi.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    if sections.isEmpty {
                        Text(trimmed.isEmpty ? String(localized: "Niente in questa sezione.") : String(localized: "Nessun risultato per «\(trimmed)»."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.hits) { hit in
                                Button { open(hit) } label: { row(hit) }
                                    .buttonStyle(.plain)
                            }
                        } header: {
                            Label(section.kind.searchTitle, systemImage: section.kind.searchIcon)
                        }
                    }
                    if !trimmed.isEmpty {
                    Section {
                        Button { askAssistant() } label: {
                            Label {
                                Text("Chiedi all'assistente: «\(trimmed)»")
                                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                            } icon: {
                                Image(systemName: "sparkles").foregroundStyle(KBTheme.tint)
                            }
                        }
                    } footer: {
                        Text("Per le domande sui dati, come «quanto abbiamo speso di scuola?». Usa un messaggio AI.")
                    }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Cerca")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
            }
        }
        .onChange(of: kinds) { _, _ in refresh() }
        .task {
            // Si legge una volta all'apertura: poi la ricerca è in memoria.
            guard index == nil else { return }
            let name = (try? modelContext.fetch(FetchDescriptor<KBFamily>()))?.first { $0.id == familyId }?.name ?? ""
            index = KBSearchIndex(snapshot: AgentMemorySnapshot.load(familyId: familyId, familyName: name, modelContext: modelContext))
            refresh()
        }
        .task(id: query) {
            // Mezzo secondo di quiete fra un tasto e l'altro: i testi letti
            // possono essere lunghi e non serve rifare la ricerca a ogni lettera.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            refresh()
        }
        .onAppear { focused = true }
        .onAppear { AppAnalytics.screenView(name: "cerca") }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Cerca in KidBox", text: $query)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Cancella"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemFill)))
    }

    /// Una capsula per sezione; si possono sceglierne più d'una, «Tutto» le toglie.
    private var filterCapsules: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                capsule(title: String(localized: "Tutto"), icon: nil, selected: kinds.isEmpty) { kinds.removeAll() }
                ForEach(KBSearchIndex.order, id: \.self) { kind in
                    capsule(title: kind.searchTitle, icon: kind.searchIcon, selected: kinds.contains(kind)) {
                        if kinds.contains(kind) { kinds.remove(kind) } else { kinds.insert(kind) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func capsule(title: String, icon: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : KBTheme.primaryText(colorScheme))
            .background(Capsule().fill(selected ? KBTheme.tint : Color(.secondarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func row(_ hit: KBSearchIndex.Hit) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.entry.title)
                .font(.body.weight(.medium))
                .foregroundStyle(KBTheme.primaryText(colorScheme))
                .lineLimit(2)
            if !hit.entry.subtitle.isEmpty {
                Text(hit.entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let snippet = hit.snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func refresh() {
        sections = index?.search(trimmed, kinds: kinds) ?? []
    }

    private func open(_ hit: KBSearchIndex.Hit) {
        guard let index else { return }
        focused = false
        AppAnalytics.searchResultOpened(kind: hit.entry.kind.rawValue, inText: hit.snippet != nil)
        let dest = AgentLinks.destination(of: hit.entry.item, in: index.snapshot)
        leave {
            for route in dest.routes { coordinator.navigate(to: route) }
            if let docId = dest.documentId { coordinator.pendingOpenDocumentId = docId }
        }
    }

    /// Il foglio si chiude prima di navigare, o la navigazione resterebbe sotto.
    private func leave(then go: @escaping () -> Void) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            go()
        }
    }

    /// La frase va nel campo dell'assistente, non parte da sola: mandarla
    /// costa un messaggio, e la decisione resta a chi scrive.
    private func askAssistant() {
        focused = false
        AppAnalytics.searchAskedAssistant()
        let draft = trimmed
        leave {
            coordinator.pendingAssistantDraft = draft
            coordinator.navigate(to: .askExpert)
        }
    }
}
