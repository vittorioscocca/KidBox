//
//  GroceryEditView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct GroceryEditView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    private let familyId: String
    private let itemIdToEdit: String?
    
    @State private var name: String = ""
    @State private var category: String = ""
    @State private var notes: String = ""
    @State private var quantity: Int = 1
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    private let prefillName: String
    private var isEditing: Bool { itemIdToEdit != nil }
    
    /// Categorie fisse più, se serve, quella scritta a mano su Android/web,
    /// così il Picker non perde il valore di un prodotto esistente.
    private var categoryChoices: [String] {
        let current = category.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = KBGroceryCategory.suggested
        if !current.isEmpty, !list.contains(current) { list.append(current) }
        return list
    }
    
    init(familyId: String, itemIdToEdit: String? = nil, prefillName: String = "") {
        self.familyId = familyId
        self.itemIdToEdit = itemIdToEdit
        self.prefillName = prefillName
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Prodotto") {
                    TextField("Nome prodotto", text: $name)
                        .autocorrectionDisabled()
                }
                
                Section("Quantità") {
                    Stepper(value: $quantity, in: 1...99) {
                        HStack {
                            Text("Quantità")
                            Spacer()
                            Text("\(quantity)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                // Alla creazione la categoria la sceglie l'app dopo il salvataggio
                // (GroceryCategoryClassifier). Solo su un prodotto esistente si
                // può correggere a mano.
                if isEditing {
                    Section("Categoria") {
                        Picker("Categoria", selection: $category) {
                            Text("Automatica").tag("")
                            ForEach(categoryChoices, id: \.self) { cat in
                                Text(KBGroceryCategory.displayName(for: cat)).tag(cat)
                            }
                        }
                    }
                }
                
                Section("Note (opzionale)") {
                    TextField("Es. marca preferita, scadenza…", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isEditing ? "Modifica prodotto" : "Nuovo prodotto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                loadIfEditing()
                if itemIdToEdit == nil && !prefillName.isEmpty {
                    name = prefillName
                }
            }
        }
    }
    
    // MARK: - Load existing
    
    private func loadIfEditing() {
        guard let id = itemIdToEdit else { return }
        let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(desc).first else { return }
        name     = item.name
        category = item.category ?? ""
        notes    = item.notes ?? ""
        quantity = max(1, item.quantity ?? 1)
    }
    
    // MARK: - Save
    
    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        let uid = KBUid.current ?? "local"
        let now = Date()
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes    = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let _ = GroceryRemoteStore()
        
        if let id = itemIdToEdit {
            // Update existing
            let desc = FetchDescriptor<KBGroceryItem>(predicate: #Predicate { $0.id == id })
            guard let item = try? modelContext.fetch(desc).first else {
                errorMessage = "Prodotto non trovato."
                return
            }
            item.name      = trimmedName
            item.category  = trimmedCategory.isEmpty ? nil : trimmedCategory
            item.notes     = trimmedNotes.isEmpty ? nil : trimmedNotes
            // 1 si salva come `nil`: è il valore implicito di ogni riga, e
            // tenerlo fuori dal dato evita di doverlo filtrare a ogni lettura.
            item.quantity  = quantity > 1 ? quantity : nil
            item.updatedBy = uid
            item.updatedAt = now
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
            if trimmedCategory.isEmpty { autoCategorize(itemId: item.id, name: trimmedName) }
        } else {
            // Create new
            let isFirstGroceryItem = ((try? modelContext.fetchCount(FetchDescriptor<KBGroceryItem>(predicate: #Predicate<KBGroceryItem> {
                $0.familyId == familyId && $0.isDeleted == false
            }))) ?? 0) == 0
            let item = KBGroceryItem(
                familyId: familyId,
                name: trimmedName,
                category: trimmedCategory.isEmpty ? nil : trimmedCategory,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                quantity: quantity > 1 ? quantity : nil,
                createdAt: now,
                updatedAt: now,
                updatedBy: uid,
                createdBy: uid
            )
            item.syncState = .pendingUpsert
            modelContext.insert(item)
            try? modelContext.save()
            SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
            autoCategorize(itemId: item.id, name: trimmedName)
            AppAnalytics.contentCreated(type: "grocery")
            if isFirstGroceryItem {
                AppAnalytics.featureFirstUse(feature: "grocery")
            }
        }
        
        await SyncCenter.shared.flushGrocery(modelContext: modelContext)
        dismiss()
    }
    
    // MARK: - Categoria automatica
    
    /// Parte dopo il salvataggio e non blocca la chiusura della scheda.
    private func autoCategorize(itemId: String, name: String) {
        GroceryCategoryClassifier.assignMissing(
            to: [(id: itemId, name: name)], familyId: familyId, modelContext: modelContext)
    }
}
