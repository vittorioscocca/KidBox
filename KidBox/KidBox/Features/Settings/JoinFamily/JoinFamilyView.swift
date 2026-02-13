//
//  JoinFamilyView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

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
                        Task {
                            do {
                                print("📱 QR scanned, processing...")
                                
                                // 1️⃣ Decifra la chiave dal QR
                                print("🔑 Step 1: Unwrap master key from encrypted invite...")
                                try await JoinWrapService().join(usingQRPayload: raw)
                                print("✅ Master key saved to Keychain")
                                
                                // 2️⃣ Estrai il codice membership dal QR
                                print("📋 Step 2: Extract membership code...")
                                guard let code = JoinPayloadParser.extractCode(from: raw) else {
                                    showScanner = false
                                    vm.errorMessage = "QR valido ma senza codice invito."
                                    print("❌ No membership code found in QR")
                                    return
                                }
                                
                                print("✅ Membership code extracted: \(code)")
                                
                                // 3️⃣ Fai il join membership con il codice
                                print("👥 Step 3: Join membership...")
                                vm.code = code
                                showScanner = false
                                
                                // Aspetta un attimo prima del join (give UI time to update)
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                
                                await vm.join()
                                print("✅ Join completed")
                                
                            } catch {
                                showScanner = false
                                vm.errorMessage = error.localizedDescription
                                print("❌ Join error: \(error.localizedDescription)")
                            }
                        }
                    },
                    onClose: { showScanner = false }
                )
            }
            
            if let err = vm.errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .foregroundStyle(.red)
                    }
                }
            }
            
            if vm.didJoin {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Sei entrato nella famiglia!")
                    }
                    Button("Continua") {
                        coordinator.resetToRoot()
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

