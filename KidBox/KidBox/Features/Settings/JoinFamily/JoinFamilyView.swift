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
    @State private var showScanner = false
    
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
            
            Button {
                showScanner = true
            } label: {
                Label("Scansiona QR code", systemImage: "qrcode.viewfinder")
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet(
                    onDetected: { raw in
                        let extracted = JoinPayloadParser.extractCode(from: raw)
                        if let extracted {
                            vm.code = extracted
                            showScanner = false
                            
                            // ✅ auto-join: stessa logica del bottone "Entra"
                            Task { await vm.join() }
                        }
                    },
                    onClose: { showScanner = false }
                )
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
    
    struct QRScannerSheet: View {
        var onDetected: (String) -> Void
        var onClose: () -> Void
        
        var body: some View {
            NavigationStack {
                ZStack {
                    QRCodeScannerView(onCode: onDetected)
                        .ignoresSafeArea()
                    
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 260, height: 260)
                }
                .navigationTitle("Scansiona QR")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { onClose() }
                    }
                }
            }
        }
    }
}
