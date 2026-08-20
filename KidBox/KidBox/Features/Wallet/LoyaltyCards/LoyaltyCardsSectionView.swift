//
//  LoyaltyCardsSectionView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Home della sezione "Carte" del Wallet: griglia 2 colonne di carte fedeltà,
//  ricerca, ordinamento, pulsante "+ Aggiungi una carta".
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct LoyaltyCardsSectionView: View {
    let familyId: String

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var cards: [KBLoyaltyCard]

    @State private var searchText = ""
    @State private var sortOption: SortOption = .recent
    @State private var showBrandPicker = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showBulkDeleteConfirm = false

    private enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Più recenti"
        case alphabetical = "Nome A-Z"
        var id: String { rawValue }

        /// `Text(rawValue)` non viene localizzato automaticamente da SwiftUI
        /// (a differenza di un literal passato direttamente a `Text`/`Label`),
        /// quindi qui serve un lookup esplicito nello String Catalog.
        var localizedTitle: String {
            switch self {
            case .recent:
                return NSLocalizedString("Più recenti", comment: "Loyalty cards sort option: most recent")
            case .alphabetical:
                return NSLocalizedString("Nome A-Z", comment: "Loyalty cards sort option: alphabetical")
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init(familyId: String) {
        self.familyId = familyId
        _cards = Query(
            filter: #Predicate<KBLoyaltyCard> { $0.familyId == familyId && $0.isDeleted == false },
            sort: [SortDescriptor(\KBLoyaltyCard.updatedAt, order: .reverse)]
        )
    }

    private var visibleCards: [KBLoyaltyCard] {
        let uid = Auth.auth().currentUser?.uid
        var result = cards.filter { $0.isVisible(to: uid) }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.brandName.localizedStandardContains(query) }
        }

        switch sortOption {
        case .recent:
            break // già ordinato dalla @Query
        case .alphabetical:
            result.sort { $0.brandName.localizedCaseInsensitiveCompare($1.brandName) == .orderedAscending }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            searchAndSortBar

            if cards.isEmpty {
                emptyState
            } else if visibleCards.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(visibleCards) { card in
                            Button {
                                if isSelecting {
                                    if selectedIds.contains(card.id) {
                                        selectedIds.remove(card.id)
                                    } else {
                                        selectedIds.insert(card.id)
                                    }
                                } else {
                                    coordinator.navigate(to: .loyaltyCardDetail(familyId: familyId, cardId: card.id))
                                }
                            } label: {
                                LoyaltyCardTileView(card: card)
                                    .overlay(alignment: .topLeading) {
                                        if isSelecting {
                                            Image(systemName: selectedIds.contains(card.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(
                                                    selectedIds.contains(card.id) ? Color.white : Color.white.opacity(0.9),
                                                    selectedIds.contains(card.id) ? KBTheme.tint : Color.black.opacity(0.25)
                                                )
                                                .padding(10)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        // Stessa toolbar della sezione Documenti del Wallet (`WalletDocumentsSectionView`):
        // Seleziona + "+" in alto a destra, e in modalità selezione "Elimina (N)" +
        // "Annulla" al loro posto. `WalletHomeView` limita i propri item al tab
        // Biglietti, quindi non si sovrappongono.
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Button(role: .destructive) {
                        showBulkDeleteConfirm = true
                    } label: {
                        Text("Elimina (\(selectedIds.count))")
                    }
                    .disabled(selectedIds.isEmpty)

                    Button("Annulla") {
                        isSelecting = false
                        selectedIds = []
                    }
                } else {
                    if !visibleCards.isEmpty {
                        Button("Seleziona") {
                            isSelecting = true
                            selectedIds = []
                        }
                    }
                    Button {
                        showBrandPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            selectedIds = []
        }
        .onChange(of: sortOption) { _, _ in
            selectedIds = []
        }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) carte fedeltà?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                deleteSelectedCards()
            }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showBrandPicker) {
            AddLoyaltyCardBrandPickerView(familyId: familyId) { cardId in
                showBrandPicker = false
                coordinator.navigate(to: .loyaltyCardDetail(familyId: familyId, cardId: cardId))
            }
        }
    }

    // MARK: - Bars

    private var searchAndSortBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Cerca una carta", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(KBTheme.inputBackground(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Menu {
                    Picker("Ordina", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.localizedTitle).tag(option)
                        }
                    }
                } label: {
                    Label("Ordina", systemImage: "arrow.up.arrow.down")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(KBTheme.inputBackground(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Eliminazione multipla

    private func deleteSelectedCards() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let card = cards.first(where: { $0.id == id }) else { continue }
            card.isDeleted = true
            card.updatedAt = .now
            card.syncState = .pendingDelete
            SyncCenter.shared.enqueueLoyaltyCardDelete(
                cardId: card.id,
                familyId: familyId,
                modelContext: modelContext
            )
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        selectedIds = []
        isSelecting = false
        coordinator.globalBannerMessage = ids.count == 1
            ? NSLocalizedString("Carta fedeltà eliminata.", comment: "Banner after deleting one loyalty card")
            : String(format: NSLocalizedString("%lld carte fedeltà eliminate.", comment: "Banner after deleting several loyalty cards"), ids.count)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nessuna carta fedeltà", systemImage: "creditcard")
        } description: {
            // Nessun bottone qui: si aggiunge dal "+" in toolbar, come nella
            // sezione Documenti del Wallet.
            Text("Aggiungi le carte fedeltà del supermercato, dell'elettronica o del negozio preferito: saranno visibili a tutta la famiglia.")
        }
    }
}
