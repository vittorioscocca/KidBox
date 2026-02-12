//
//  ChildDestinationView.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

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
            return try modelContext.fetch(desc).first
        } catch {
            return nil
        }
    }
}

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
            
            // ✅ Sezione Pericolo - Elimina figlio
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
                Button("Elimina", role: .destructive) {
                    deleteChild()
                }
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
        // Validazione minima (opzionale ma utile)
        let trimmed = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Inserisci un nome."
            showError = true
            return
        }
        child.name = trimmed
        
        // Audit LWW
        child.updatedAt = Date()
        
        do {
            try modelContext.save()
            Task {
                try? await ChildSyncService().upsert(child: child)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    // ✅ NEW: Eliminazione con sync remoto
    @MainActor private func deleteChild() {
        do {
            let childId = child.id
            let familyId = child.familyId ?? ""
            let updatedBy = Auth.auth().currentUser?.uid
            
            // 1) Hard delete locale
            modelContext.delete(child)
            try modelContext.save()
            
            // 2) Soft delete remoto (async, non blocca UI)
            Task {
                do {
                    try await ChildSyncService().softDeleteChild(
                        familyId: familyId,
                        childId: childId,
                        updatedBy: updatedBy
                    )
                } catch {
                    await MainActor.run {
                        errorMessage = "Eliminazione remota fallita: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
            
            // 3) Torna indietro
            dismiss()
            
        } catch {
            errorMessage = "Errore locale: \(error.localizedDescription)"
            showError = true
        }
    }
}
