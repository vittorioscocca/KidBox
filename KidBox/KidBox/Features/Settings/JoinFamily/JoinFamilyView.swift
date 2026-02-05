//
//  JoinFamilyView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData

import SwiftUI
import SwiftData

struct JoinFamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        JoinFamilyViewBody(modelContext: modelContext)
            .environmentObject(coordinator)
            .navigationTitle("Entra con codice")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct JoinFamilyViewBody: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    let modelContext: ModelContext
    @StateObject private var vm: JoinFamilyViewModel
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _vm = StateObject(wrappedValue: JoinFamilyViewModel(
            service: FamilyJoinService(
                inviteRemote: InviteRemoteStore(),
                readRemote: FamilyReadRemoteStore(),
                modelContext: modelContext
            )
        ))
    }
    
    var body: some View {
        Form {
            Section("Codice invito") {
                TextField("Es. K7P4D2", text: $vm.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            
            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.red) }
            }
            
            if vm.didJoin {
                Section {
                    Text("✅ Sei entrato nella family!")
                    Button("Continua") {
                        coordinator.resetToRoot()
                        // RootGateView vedrà families non vuoto e mostrerà HomeView
                    }
                }
            } else {
                Button(vm.isBusy ? "Ingresso…" : "Entra") {
                    Task { await vm.join() }
                }
                .disabled(vm.isBusy || vm.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
