//
//  SetupFamilyView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData

struct SetupFamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @State private var familyName: String = ""
    @State private var childName: String = ""
    @State private var birthDate: Date = Date()
    
    @State private var isBusy = false
    @State private var errorText: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Famiglia") {
                    TextField("Nome famiglia", text: $familyName)
                        .textInputAutocapitalization(.words)
                }
                
                Section("Bambino/a") {
                    TextField("Nome", text: $childName)
                        .textInputAutocapitalization(.words)
                    
                    DatePicker("Data di nascita", selection: $birthDate, displayedComponents: [.date])
                }
                
                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
                
                Button(isBusy ? "Creazione…" : "Crea famiglia") {
                    Task { await createFamily() }
                }
                .disabled(isBusy || familyName.isEmpty || childName.isEmpty)
            }
            .navigationTitle("Setup Family")
        }
    }
    
    private func createFamily() async {
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        
        do {
            let remote = FamilyRemoteStore()
            let service = FamilyCreationService(remote: remote, modelContext: modelContext)
            
            _ = try await service.createFamily(
                name: familyName,
                childName: childName,
                childBirthDate: birthDate
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}
