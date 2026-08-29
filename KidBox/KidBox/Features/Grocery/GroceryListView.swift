//
//  GroceryListView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Combine

struct GroceryListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // MARK: - Dynamic theme (same as LoginView)
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    @Query private var allItems: [KBGroceryItem]
    
    private let familyId: String
    private let remote = GroceryRemoteStore()
    
    /// I tre filtri della testata. Sostituiscono le sezioni fisse
    /// "da acquistare / acquistati": con la lista lunga, scorrere fino in fondo
    /// per vedere cosa è già stato preso era il gesto più frequente.
    private enum GroceryFilter: CaseIterable {
        case all, toBuy, purchased

        var label: LocalizedStringKey {
            switch self {
            case .all:       return "Tutti"
            case .toBuy:     return "Da prendere"
            case .purchased: return "Presi"
            }
        }
    }

    @State private var filter: GroceryFilter = .toBuy
    @State private var didStartRealtime = false
    @State private var showAddSheet = false
    @State private var editingItemId: String? = nil
    @State private var showDeletePurchasedAlert = false
    @State private var showSaveTripSheet = false
    @State private var showTripsHistory = false
    @State private var sharePrefillName = ""
    
    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _allItems = Query(
            filter: #Predicate<KBGroceryItem> { i in
                i.familyId == fid && i.isDeleted == false
            },
            sort: [SortDescriptor(\KBGroceryItem.createdAt, order: .reverse)]
        )
    }
    
    // MARK: - Computed
    
    private var toBuy: [KBGroceryItem] {
        allItems.filter { !$0.isPurchased }
    }
    
    private var purchased: [KBGroceryItem] {
        allItems.filter { $0.isPurchased }
    }
    
    /// Quello che il filtro attivo lascia passare.
    private var visibleItems: [KBGroceryItem] {
        switch filter {
        case .all:       return allItems
        case .toBuy:     return toBuy
        case .purchased: return purchased
        }
    }

    /// Raggruppa per categoria: è l'ordine in cui si gira il supermercato, e
    /// resta il motivo per cui la categoria esiste nel modello.
    private var groupedVisible: [(category: String, items: [KBGroceryItem])] {
        var dict: [String: [KBGroceryItem]] = [:]
        for item in visibleItems {
            let key = item.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.category!
            : KBGroceryCategory.uncategorized
            dict[key, default: []].append(item)
        }
        return dict.keys.sorted().map { key in
            (category: key, items: dict[key]!)
        }
    }

    private var countsLine: String {
        let left = String(localized: "\(toBuy.count) da prendere")
        let right = String(localized: "\(purchased.count) presi")
        return "\(left) · \(right)"
    }

    // MARK: - Body
    
    var body: some View {
        List {
            header
            filterChips

            if filter == .purchased && !purchased.isEmpty {
                Button {
                    showSaveTripSheet = true
                } label: {
                    Label("Salva spesa", systemImage: "receipt.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }

            if allItems.isEmpty {
                KBEmptyStateView(
                    systemImage: "cart",
                    title: "Lista vuota",
                    message: "Aggiungi quello che manca e spuntalo mentre sei al supermercato. La lista è condivisa: se qualcuno prende il latte, lo vedi sparire dal tuo telefono.",
                    actionTitle: "Aggiungi articolo",
                    actionSystemImage: "plus.circle.fill",
                    action: { showAddSheet = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if visibleItems.isEmpty {
                // La lista non è vuota: è vuoto questo filtro. Dirlo evita di
                // far credere che la spesa sia sparita.
                Text(filter == .purchased ? "Niente di già preso" : "Niente da prendere")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            // Niente `Section`: in `.plain` l'intestazione resta incollata in
            // alto e prende il colore spento di sistema. Qui il titolo di
            // categoria è una riga come le altre, che scorre con la lista.
            ForEach(groupedVisible, id: \.category) { group in
                sectionHeader(for: group.category)

                ForEach(group.items) { item in
                    row(item)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)   // ← nasconde il grigio di sistema
        .background(backgroundColor)
        .trackSectionPresence(.shoppingList, familyId: familyId)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddSheet) {
            GroceryEditView(
                familyId: familyId,
                itemIdToEdit: editingItemId,
                prefillName: sharePrefillName
            )
        }
        .sheet(isPresented: $showSaveTripSheet) {
            SaveShoppingTripView(
                familyId: familyId,
                purchasedItems: purchased,
                onSaved: {
                    // Archiviato lo scontrino la lista resta senza "presi":
                    // si torna dove si stava guardando prima.
                    filter = .toBuy
                }
            )
        }
        .sheet(isPresented: $showTripsHistory) {
            ShoppingTripsListView(familyId: familyId)
        }
        .alert("Elimina acquistati", isPresented: $showDeletePurchasedAlert) {
            Button("Elimina", role: .destructive) { deleteAllPurchased() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Vuoi eliminare tutti i prodotti già acquistati?")
        }
        .onAppear {
            BadgeManager.shared.activeSections.insert("shopping")
            guard !didStartRealtime else { return }
            didStartRealtime = true
            SyncCenter.shared.startGroceryRealtime(familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.startShoppingTripsRealtime(familyId: familyId, modelContext: modelContext)
            Task { await SyncCenter.shared.flushGrocery(modelContext: modelContext) }
            consumePendingShare()
        }
        .onReceive(coordinator.$pendingShareText.compactMap { $0 }) { text in
            consumePendingShare()
        }
        .onDisappear {
            SyncCenter.shared.stopGroceryRealtime()
            SyncCenter.shared.stopShoppingTripsRealtime()
            BadgeManager.shared.activeSections.remove("shopping")
        }
    }
    
    // MARK: - Testata

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Indietro")

            VStack(alignment: .leading, spacing: 2) {
                Text("Spesa")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.primary)
                Text(countsLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                showTripsHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 44, height: 44)
                    .background(Color(.secondarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Spese salvate")

            Button {
                editingItemId = nil
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 44)
                    .background(Color.green, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Aggiungi articolo")
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    private var filterChips: some View {
        HStack(spacing: 10) {
            ForEach(GroceryFilter.allCases, id: \.self) { option in
                let isSelected = option == filter
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { filter = option }
                } label: {
                    Text(option.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            isSelected ? Color.green : Color(.secondarySystemFill),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    /// Titolo di categoria. Sui "presi" porta anche la scorciatoia per svuotarli:
    /// è lì che serve, e non ha senso mostrarla mentre si guarda cosa manca.
    @ViewBuilder
    private func sectionHeader(for category: String) -> some View {
        HStack {
            Text(KBGroceryCategory.displayName(for: category))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if filter == .purchased {
                Button(role: .destructive) {
                    showDeletePurchasedAlert = true
                } label: {
                    Label("Elimina tutti", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 2)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Row
    
    @ViewBuilder
    private func row(_ item: KBGroceryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: KBGroceryCategory.symbol(for: item.category))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KBGroceryCategory.tint(for: item.category))
                .frame(width: 44, height: 44)
                .background(KBGroceryCategory.tint(for: item.category).opacity(0.16), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .strikethrough(item.isPurchased)
                    .foregroundStyle(item.isPurchased ? .secondary : .primary)

                // Quantità e note nella stessa riga: sono entrambe dettagli del
                // prodotto, e due righe separate spezzerebbero la scheda.
                if let detail = detailLine(for: item) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 8)

            // Il cerchio è l'unico punto che spunta: il resto della scheda apre
            // la modifica, così spuntare mentre si cammina non apre un foglio.
            Button {
                Task { await togglePurchased(item) }
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26))
                    .foregroundStyle(item.isPurchased ? Color.green : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            editingItemId = item.id
            showAddSheet = true
        }
    }

    /// "x 3", "x 3 · senza glutine", "senza glutine" o niente.
    private func detailLine(for item: KBGroceryItem) -> String? {
        var parts: [String] = []
        if let quantity = item.quantity, quantity > 1 {
            parts.append(String(localized: "x \(quantity)"))
        }
        if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            parts.append(notes)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func delete(_ item: KBGroceryItem) {
        Task { @MainActor in
            let uid = Auth.auth().currentUser?.uid ?? "local"
            item.isDeleted = true
            item.updatedBy = uid
            item.updatedAt = Date()
            item.syncState = .pendingDelete
            item.lastSyncError = nil
            SyncCenter.shared.enqueueGroceryDelete(itemId: item.id, familyId: familyId, modelContext: modelContext)
            try? modelContext.save()
            await SyncCenter.shared.flushGrocery(modelContext: modelContext)
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func togglePurchased(_ item: KBGroceryItem) async {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        item.isPurchased.toggle()
        item.updatedBy = uid
        item.updatedAt = now
        item.purchasedAt = item.isPurchased ? now : nil
        item.purchasedBy = item.isPurchased ? uid : nil
        item.syncState = .pendingUpsert
        item.lastSyncError = nil
        
        try? modelContext.save()
        
        SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
        await SyncCenter.shared.flushGrocery(modelContext: modelContext)
    }
    
    private func deleteItems(offsets: IndexSet, from list: [KBGroceryItem]) {
        Task { @MainActor in
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            
            for i in offsets {
                guard list.indices.contains(i) else { continue }
                let item = list[i]
                item.isDeleted = true
                item.updatedBy = uid
                item.updatedAt = now
                item.syncState = .pendingDelete
                item.lastSyncError = nil
                SyncCenter.shared.enqueueGroceryDelete(itemId: item.id, familyId: familyId, modelContext: modelContext)
            }
            
            try? modelContext.save()
            await SyncCenter.shared.flushGrocery(modelContext: modelContext)
        }
    }
    
    private func consumePendingShare() {
        guard let text = coordinator.pendingShareText else { return }
        coordinator.pendingShareText = nil
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count > 1 {
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            let isFirstGroceryItem = ((try? modelContext.fetchCount(FetchDescriptor<KBGroceryItem>(predicate: #Predicate<KBGroceryItem> {
                $0.familyId == familyId && $0.isDeleted == false
            }))) ?? 0) == 0
            for line in lines {
                let item = KBGroceryItem(
                    familyId: familyId,
                    name: line,
                    category: nil,
                    notes: nil,
                    createdAt: now,
                    updatedAt: now,
                    updatedBy: uid,
                    createdBy: uid
                )
                item.syncState = .pendingUpsert
                modelContext.insert(item)
                SyncCenter.shared.enqueueGroceryUpsert(
                    itemId: item.id,
                    familyId: familyId,
                    modelContext: modelContext
                )
            }
            try? modelContext.save()
            Task { await SyncCenter.shared.flushGrocery(modelContext: modelContext) }
            AppAnalytics.contentCreated(type: "grocery")
            if isFirstGroceryItem {
                AppAnalytics.featureFirstUse(feature: "grocery")
            }
        } else {
            sharePrefillName = lines.first ?? text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAddSheet = true
            }
        }
    }
    
    private func deleteAllPurchased() {
        Task { @MainActor in
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            
            for item in purchased {
                item.isDeleted = true
                item.updatedBy = uid
                item.updatedAt = now
                item.syncState = .pendingDelete
                item.lastSyncError = nil
                SyncCenter.shared.enqueueGroceryDelete(itemId: item.id, familyId: familyId, modelContext: modelContext)
            }
            
            try? modelContext.save()
            await SyncCenter.shared.flushGrocery(modelContext: modelContext)
        }
    }
}
