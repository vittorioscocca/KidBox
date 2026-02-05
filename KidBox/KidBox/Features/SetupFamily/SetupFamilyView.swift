//
//  SetupFamilyView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct SetupFamilyView: View {
    enum Mode {
        case create
        case edit(family: KBFamily, child: KBChild)
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @EnvironmentObject private var coordinator: AppCoordinator
    
    private let mode: Mode
    
    @State private var familyName: String = ""
    @State private var childName: String = ""
    @State private var hasBirthDate: Bool = false
    @State private var birthDate: Date = Date()
    
    @State private var isBusy = false
    @State private var errorText: String?
    
    init(mode: Mode = .create) {
        self.mode = mode
    }
    
    var body: some View {
        Form {
            Section("Famiglia") {
                TextField("Nome famiglia", text: $familyName)
                    .textInputAutocapitalization(.words)
            }
            
            Section("Bimbo/a") {
                TextField("Nome", text: $childName)
                    .textInputAutocapitalization(.words)
                
                Toggle("Imposta data di nascita", isOn: $hasBirthDate)
                
                if hasBirthDate {
                    DatePicker("Data di nascita", selection: $birthDate, displayedComponents: [.date])
                }
            }
            
            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red)
                }
            }
            
            Section {
                Button(isBusy ? buttonBusyTitle : buttonTitle) {
                    Task { await primaryAction() }
                }
                .disabled(isBusy || familyName.trimmed.isEmpty || childName.trimmed.isEmpty)
            }
        }
        .navigationTitle(navTitle)
        .onAppear { hydrateIfNeeded() }
    }
    
    // MARK: - Titles
    
    private var navTitle: String {
        switch mode {
        case .create: return "Crea famiglia"
        case .edit:   return "Modifica famiglia"
        }
    }
    
    private var buttonTitle: String {
        switch mode {
        case .create: return "Crea famiglia"
        case .edit:   return "Salva modifiche"
        }
    }
    
    private var buttonBusyTitle: String {
        switch mode {
        case .create: return "Creazione…"
        case .edit:   return "Salvataggio…"
        }
    }
    
    // MARK: - Hydrate
    
    private func hydrateIfNeeded() {
        guard case let .edit(family, child) = mode else { return }
        
        familyName = family.name
        childName = child.name
        
        if let d = child.birthDate {
            hasBirthDate = true
            birthDate = d
        } else {
            hasBirthDate = false
            birthDate = Date()
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func primaryAction() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        
        switch mode {
        case .create:
            await createFamily()
        case let .edit(family, child):
            await updateFamily(family: family, child: child)
        }
    }
    
    @MainActor
    private func createFamily() async {
        do {
            let service = FamilyCreationService(remote: FamilyRemoteStore(), modelContext: modelContext)
            
            _ = try await service.createFamily(
                name: familyName.trimmed,
                childName: childName.trimmed,
                childBirthDate: hasBirthDate ? birthDate : nil
            )
            
            // dopo create, torna indietro dove vuoi (io farei dismiss)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    @MainActor
    private func updateFamily(family: KBFamily, child: KBChild) async {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        // 1) LOCAL
        family.name = familyName.trimmed
        family.updatedBy = uid
        family.updatedAt = now
        
        child.name = childName.trimmed
        child.birthDate = hasBirthDate ? birthDate : nil
        
        do {
            try modelContext.save()
        } catch {
            errorText = "SwiftData save failed: \(error.localizedDescription)"
            return
        }
        
        // 2) REMOTE (best-effort)
        do {
            try await FamilyRemoteStore().updateFamilyAndChild(
                family: .init(familyId: family.id, name: family.name),
                child: .init(
                    familyId: family.id,
                    childId: child.id,
                    name: child.name,
                    birthDate: child.birthDate
                )
            )
            dismiss()
        } catch {
            errorText = "Firestore update failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Small helper

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
