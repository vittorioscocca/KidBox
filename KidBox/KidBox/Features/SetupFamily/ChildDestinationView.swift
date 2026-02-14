//
//  ChildDestinationView.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog

/// Displays the destination for editing a specific child.
///
/// This view resolves a `KBChild` from SwiftData by id and routes to `EditChildView`.
/// Logging strategy:
/// - Log only meaningful events (fetch success/failure).
/// - Avoid noisy logs for body recomputation.
struct ChildDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    let childId: String
    
    var body: some View {
        if let child = fetchChild(id: childId) {
            EditChildView(child: child)
        } else {
            Text("Figlio non trovato")
                .foregroundStyle(.secondary)
        }
    }
    
    private func fetchChild(id: String) -> KBChild? {
        do {
            let cid = id
            let desc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == cid })
            let child = try modelContext.fetch(desc).first
            
            if child == nil {
                KBLog.data.info("ChildDestinationView: child not found id=\(cid, privacy: .public)")
            } else {
                KBLog.data.debug("ChildDestinationView: child resolved id=\(cid, privacy: .public)")
            }
            return child
        } catch {
            KBLog.data.error("ChildDestinationView: fetch failed id=\(id, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// Allows editing a child and deleting it.
///
/// Persistence model:
/// - Save: updates local SwiftData immediately, then best-effort remote upsert.
/// - Delete: hard delete locally, then best-effort remote soft delete so other devices remove it via inbound.
///
/// Logging strategy:
/// - Log user actions and outcomes (save/delete start, local save OK/failed, remote sync OK/failed).
/// - No `print`.
struct EditChildView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @Bindable var child: KBChild
    @Environment(\.dismiss) private var dismiss
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirm = false
    
    var body: some View {
        Form {
            Section("Dati") {
                TextField("Nome", text: $child.name)
                
                DatePicker(
                    "Data di nascita",
                    selection: Binding(
                        get: { child.birthDate ?? Date() },
                        set: { child.birthDate = $0 }
                    ),
                    displayedComponents: .date
                )
            }
            
            Section {
                Button("Salva") {
                    save()
                }
            }
            
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash.fill")
                        Text("Elimina figlio")
                    }
                }
            } header: {
                Text("Zona Pericolosa")
            } footer: {
                Text("Questa azione non può essere annullata. Il figlio verrà eliminato da tutti i dispositivi della famiglia.")
            }
        }
        .navigationTitle("Figlio")
        .confirmationDialog(
            "Eliminare \(child.name)?",
            isPresented: $showDeleteConfirm,
            actions: {
                Button("Elimina", role: .destructive) { deleteChild() }
                Button("Annulla", role: .cancel) { }
            },
            message: {
                Text("Sei sicuro di voler eliminare \(child.name)? Questa azione non può essere annullata e il figlio verrà rimosso da tutti i dispositivi.")
            }
        )
        .alert("Errore", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    @MainActor private func save() {
        let childId = child.id
        let familyId = child.familyId ?? ""
        KBLog.data.info("EditChildView: save requested childId=\(childId, privacy: .public) familyId=\(familyId, privacy: .public)")
        
        // Minimal validation.
        let trimmed = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Inserisci un nome."
            showError = true
            KBLog.data.info("EditChildView: save blocked (empty name) childId=\(childId, privacy: .public)")
            return
        }
        child.name = trimmed
        
        // LWW metadata.
        child.updatedAt = Date()
        
        do {
            try modelContext.save()
            KBLog.data.info("EditChildView: local save OK childId=\(childId, privacy: .public)")
            
            // Remote best-effort.
            Task {
                do {
                    try await ChildSyncService().upsert(child: child)
                    KBLog.sync.info("EditChildView: remote upsert OK childId=\(childId, privacy: .public)")
                } catch {
                    KBLog.sync.error("EditChildView: remote upsert FAILED childId=\(childId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
                }
            }
            
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            KBLog.data.error("EditChildView: local save FAILED childId=\(childId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }
    
    @MainActor private func deleteChild() {
        let childId = child.id
        let familyId = child.familyId ?? ""
        let updatedBy = Auth.auth().currentUser?.uid
        KBLog.data.info("EditChildView: delete requested childId=\(childId, privacy: .public) familyId=\(familyId, privacy: .public)")
        
        do {
            // 1) Hard delete local.
            modelContext.delete(child)
            try modelContext.save()
            KBLog.data.info("EditChildView: local delete OK childId=\(childId, privacy: .public)")
            
            // 2) Remote soft delete best-effort.
            Task {
                do {
                    try await ChildSyncService().softDeleteChild(
                        familyId: familyId,
                        childId: childId,
                        updatedBy: updatedBy
                    )
                    KBLog.sync.info("EditChildView: remote softDelete OK childId=\(childId, privacy: .public)")
                } catch {
                    await MainActor.run {
                        errorMessage = "Eliminazione remota fallita: \(error.localizedDescription)"
                        showError = true
                    }
                    KBLog.sync.error("EditChildView: remote softDelete FAILED childId=\(childId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
                }
            }
            
            // 3) Navigate back.
            dismiss()
        } catch {
            errorMessage = "Errore locale: \(error.localizedDescription)"
            showError = true
            KBLog.data.error("EditChildView: local delete FAILED childId=\(childId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }
}
