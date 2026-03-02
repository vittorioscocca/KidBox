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
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    private var isEditing: Bool { itemIdToEdit != nil }
    
    // Categorie suggerite
    private let suggestedCategories = [
        "Frutta e Verdura", "Carne e Pesce", "Latticini", "Pane e Cereali",
        "Surgelati", "Bevande", "Dolci e Snack", "Pulizia", "Cura Personale", "Altro"
    ]
    
    init(familyId: String, itemIdToEdit: String? = nil) {
        self.familyId = familyId
        self.itemIdToEdit = itemIdToEdit
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Prodotto") {
                    TextField("Nome prodotto", text: $name)
                        .autocorrectionDisabled()
                }
                
                Section("Categoria") {
                    TextField("Es. Frutta e Verdura", text: $category)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestedCategories, id: \.self) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    Text(cat)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(category == cat
                                                      ? Color.accentColor
                                                      : Color.secondary.opacity(0.15))
                                        )
                                        .foregroundStyle(category == cat ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                
                Section("Note (opzionale)") {
                    TextField("Es. marca preferita, quantità…", text: $notes, axis: .vertical)
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
            .onAppear { loadIfEditing() }
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
    }
    
    // MARK: - Save
    
    @MainActor
    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes    = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let remote = GroceryRemoteStore()
        
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
            item.updatedBy = uid
            item.updatedAt = now
            item.syncState = .pendingUpsert
            item.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
        } else {
            // Create new
            let item = KBGroceryItem(
                familyId: familyId,
                name: trimmedName,
                category: trimmedCategory.isEmpty ? nil : trimmedCategory,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                createdAt: now,
                updatedAt: now,
                updatedBy: uid,
                createdBy: uid
            )
            item.syncState = .pendingUpsert
            modelContext.insert(item)
            try? modelContext.save()
            SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
        }
        
        await SyncCenter.shared.flushGrocery(modelContext: modelContext)
        dismiss()
    }
}
