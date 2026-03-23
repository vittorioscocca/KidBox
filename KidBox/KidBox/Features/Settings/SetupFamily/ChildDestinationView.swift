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
struct EditChildView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @Bindable var child: KBChild
    @Environment(\.dismiss) private var dismiss
    
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showDeleteConfirm = false
    
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
    
    var body: some View {
        Form {
            Section("Dati") {
                TextField("Nome", text: $child.name)
                    .listRowBackground(cardBackground)
                
                DatePicker(
                    "Data di nascita",
                    selection: Binding(
                        get: { child.birthDate ?? Date() },
                        set: { child.birthDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .listRowBackground(cardBackground)
            }
            
            Section {
                Button("Salva") {
                    save()
                }
                .listRowBackground(cardBackground)
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
                .listRowBackground(cardBackground)
            } header: {
                Text("Zona Pericolosa")
            } footer: {
                Text("Questa azione non può essere annullata. Il figlio verrà eliminato da tutti i dispositivi della famiglia.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
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
        
        let trimmed = child.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Inserisci un nome."
            showError = true
            KBLog.data.info("EditChildView: save blocked (empty name) childId=\(childId, privacy: .public)")
            return
        }
        child.name = trimmed
        child.updatedAt = Date()
        
        do {
            try modelContext.save()
            KBLog.data.info("EditChildView: local save OK childId=\(childId, privacy: .public)")
            
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
            modelContext.delete(child)
            try modelContext.save()
            KBLog.data.info("EditChildView: local delete OK childId=\(childId, privacy: .public)")
            
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
            
            dismiss()
        } catch {
            errorMessage = "Errore locale: \(error.localizedDescription)"
            showError = true
            KBLog.data.error("EditChildView: local delete FAILED childId=\(childId, privacy: .public) err=\(error.localizedDescription, privacy: .public)")
        }
    }
}
