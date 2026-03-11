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
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @Query private var allItems: [KBGroceryItem]
    
    private let familyId: String
    private let remote = GroceryRemoteStore()
    
    @State private var didStartRealtime = false
    @State private var showAddSheet = false
    @State private var editingItemId: String? = nil
    @State private var showDeletePurchasedAlert = false
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
    
    private var groupedToBuy: [(category: String, items: [KBGroceryItem])] {
        let uncategorized = "Altro"
        var dict: [String: [KBGroceryItem]] = [:]
        for item in toBuy {
            let key = item.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? item.category!
            : uncategorized
            dict[key, default: []].append(item)
        }
        return dict.keys.sorted().map { key in
            (category: key, items: dict[key]!)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        List {
            // ── Da acquistare ──
            if toBuy.isEmpty && purchased.isEmpty {
                Text("Lista vuota")
                    .foregroundStyle(.secondary)
            }
            
            if !toBuy.isEmpty {
                ForEach(groupedToBuy, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.items) { item in
                            row(item)
                        }
                        .onDelete { offsets in
                            deleteItems(offsets: offsets, from: group.items)
                        }
                    }
                }
            }
            
            // ── Acquistati ──
            if !purchased.isEmpty {
                Section {
                    ForEach(purchased) { item in
                        row(item)
                    }
                    .onDelete { offsets in
                        deleteItems(offsets: offsets, from: purchased)
                    }
                } header: {
                    HStack {
                        Text("Acquistati (\(purchased.count))")
                        Spacer()
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
            }
        }
        .navigationTitle("Spesa")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingItemId = nil
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            GroceryEditView(
                familyId: familyId,
                itemIdToEdit: editingItemId,
                prefillName: sharePrefillName
            )
        }
        .alert("Elimina acquistati", isPresented: $showDeletePurchasedAlert) {
            Button("Elimina", role: .destructive) { deleteAllPurchased() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Vuoi eliminare tutti i prodotti già acquistati?")
        }
        .onAppear {
            BadgeManager.shared.activeSections.insert("shopping")
            // Realtime: avvia una sola volta
            guard !didStartRealtime else { return }
            didStartRealtime = true
            SyncCenter.shared.startGroceryRealtime(familyId: familyId, modelContext: modelContext)
            Task { await SyncCenter.shared.flushGrocery(modelContext: modelContext) }
            // Fallback: se onReceive non ha ancora scattato (cold start)
            consumePendingShare()
        }
        // onReceive: scatta anche se GroceryListView era già montata
        .onReceive(coordinator.$pendingShareText.compactMap { $0 }) { text in
            consumePendingShare()
        }
        .onDisappear {
            SyncCenter.shared.stopGroceryRealtime()
            BadgeManager.shared.activeSections.remove("shopping")
        }
    }
    
    // MARK: - Row
    
    @ViewBuilder
    private func row(_ item: KBGroceryItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await togglePurchased(item) }
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(item.isPurchased ? .green : .primary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .strikethrough(item.isPurchased)
                    .foregroundStyle(item.isPurchased ? .secondary : .primary)
                
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editingItemId = item.id
            showAddSheet = true
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
            // Lista multi-riga → crea tutti gli articoli direttamente,
            // senza aprire lo sheet (stessa UX del todo multi-item)
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
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
        } else {
            // Singolo elemento → apri lo sheet con prefill
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
