//
//  CreateCategorySheet.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
internal import os


/// Sheet to create a new top-level document category for a given family.
///
/// Flow:
/// 1) Validate input
/// 2) Create the category locally (SwiftData) as `.pendingUpsert`
/// 3) Enqueue an outbox op + flush to sync to Firestore
///
/// - Note: This view avoids noisy logs in `body`. Logging is done only in actions.
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
                    .disabled(
                        isBusy ||
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        familyId.isEmpty
                    )
                }
            }
        }
    }
    
    @MainActor
    private func save() async {
        error = nil
        isBusy = true
        defer { isBusy = false }
        
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            KBLog.data.kbDebug("CreateCategorySheet save blocked: empty title")
            return
        }
        guard !familyId.isEmpty else {
            KBLog.data.kbError("CreateCategorySheet save blocked: empty familyId")
            return
        }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        KBLog.data.kbInfo("CreateCategorySheet save started familyId=\(familyId) title=\(t)")
        
        do {
            // sortOrder semplice: append in fondo
            let all = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>())
            let existing = all.filter { $0.familyId == familyId && !$0.isDeleted }
            let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
            
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
            KBLog.data.kbInfo("CreateCategorySheet local saved categoryId=\(cat.id) sortOrder=\(nextOrder)")
            
            // 2) OUTBOX + FLUSH (sync su Firestore)
            SyncCenter.shared.enqueueDocumentCategoryUpsert(
                categoryId: cat.id,
                familyId: cat.familyId,
                modelContext: modelContext
            )
            KBLog.sync.kbDebug("CreateCategorySheet enqueued category upsert categoryId=\(cat.id)")
            
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            KBLog.sync.kbDebug("CreateCategorySheet flushGlobal requested familyId=\(familyId)")
            
            dismissAndDone()
            
        } catch {
            self.error = error.localizedDescription
            KBLog.data.kbError("CreateCategorySheet save failed: \(error.localizedDescription)")
        }
    }
    
    private func dismissAndDone() {
        KBLog.ui.kbDebug("CreateCategorySheet dismissAndDone")
        dismiss()
        onDone()
    }
}
