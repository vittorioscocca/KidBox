//
//  CreateCategorySheet.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct CreateCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let familyId: String
    let onDone: () -> Void
    
    @State private var title: String = ""
    @State private var isBusy = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Nome categoria") {
                    TextField("Es. Identità, Salute, Scuola…", text: $title)
                        .textInputAutocapitalization(.words)
                }
                
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nuova categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismissAndDone() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isBusy ? "Salvo…" : "Salva") {
                        Task { await save() }
                    }
                    .disabled(isBusy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || familyId.isEmpty)
                }
            }
        }
    }
    
    @MainActor
    private func save() async {
        error = nil
        isBusy = true
        defer { isBusy = false }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            // sortOrder semplice: append in fondo
            let existing = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>())
                .filter { $0.familyId == familyId && !$0.isDeleted }
            let nextOrder = (existing.map { $0.sortOrder }.max() ?? -1) + 1
            
            let cat = KBDocumentCategory(
                id: UUID().uuidString,
                familyId: familyId,
                title: t,
                sortOrder: nextOrder,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now,
                isDeleted: false
            )
            
            // sync metadata
            cat.syncState = .pendingUpsert
            cat.lastSyncError = nil
            
            // 1) LOCAL
            modelContext.insert(cat)
            try modelContext.save()
            
            // 2) OUTBOX + FLUSH (sync su Firestore)
            SyncCenter.shared.enqueueDocumentCategoryUpsert(
                categoryId: cat.id,
                familyId: cat.familyId,
                modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            
            dismissAndDone()
            
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func dismissAndDone() {
        dismiss()
        onDone()
    }
}
