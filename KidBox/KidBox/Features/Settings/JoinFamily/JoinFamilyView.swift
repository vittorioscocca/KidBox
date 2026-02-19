//
//  JoinFamilyView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData
import OSLog

struct JoinFamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        JoinFamilyViewBody(modelContext: modelContext, coordinator: coordinator)
            .environmentObject(coordinator)
            .navigationTitle("Entra con codice")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                KBLog.ui.debug("JoinFamilyView appeared")
            }
    }
}

private struct JoinFamilyViewBody: View {
    private var coordinator: AppCoordinator
    @State private var showScanner = false
    let modelContext: ModelContext
    @StateObject private var vm: JoinFamilyViewModel
    
    init(modelContext: ModelContext,  coordinator: AppCoordinator) {
        self.modelContext = modelContext
        _vm = StateObject(wrappedValue: JoinFamilyViewModel(
            service: FamilyJoinService(
                inviteRemote: InviteRemoteStore(),
                readRemote: FamilyReadRemoteStore(),
                modelContext: modelContext
            ), coordinator: coordinator
        ))
        self.coordinator = coordinator
    }
    
    var body: some View {
        Form {
            Section("Codice invito") {
                TextField("Es. K7P4D2", text: $vm.code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: vm.code) { _, newValue in
                        // Logga solo metadati (lunghezza), non il contenuto del codice.
                        KBLog.ui.debug("JoinFamilyView code changed len=\(newValue.count, privacy: .public)")
                    }
            }
            
            Button {
                showScanner = true
                KBLog.ui.info("JoinFamilyView: open QR scanner")
            } label: {
                Label("Scansiona QR code", systemImage: "qrcode.viewfinder")
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet(
                    onDetected: { raw in
                        Task {
                            do {
                                KBLog.ui.info("JoinFamilyView: QR scanned (processing)")
                                
                                // 1️⃣ Decifra la chiave dal QR (non loggare raw: contiene segreti)
                                KBLog.sync.info("JoinFamilyView: unwrap master key from encrypted invite (start)")
                                try await JoinWrapService().join(usingQRPayload: raw)
                                KBLog.sync.info("JoinFamilyView: master key saved to Keychain (ok)")
                                
                                // 2️⃣ Estrai il codice membership dal QR
                                KBLog.sync.debug("JoinFamilyView: extract membership code from QR payload")
                                guard let code = JoinPayloadParser.extractCode(from: raw) else {
                                    showScanner = false
                                    vm.errorMessage = "QR valido ma senza codice invito."
                                    KBLog.sync.error("JoinFamilyView: QR missing membership code")
                                    return
                                }
                                
                                // Non loggare il codice; al massimo la lunghezza.
                                KBLog.sync.info("JoinFamilyView: membership code extracted len=\(code.count, privacy: .public)")
                                
                                // 3️⃣ Join membership
                                vm.code = code
                                showScanner = false
                                
                                // Give UI time to update (as in original)
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                
                                KBLog.sync.info("JoinFamilyView: starting membership join")
                                await vm.join()
                                KBLog.sync.info("JoinFamilyView: join completed")
                                
                            } catch {
                                showScanner = false
                                vm.errorMessage = error.localizedDescription
                                KBLog.sync.error("JoinFamilyView: join failed \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    },
                    onClose: {
                        showScanner = false
                        KBLog.ui.debug("JoinFamilyView: QR scanner closed")
                    }
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
                    .accessibilityLabel("Errore: \(err)")
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
                        KBLog.navigation.info("JoinFamilyView: continue -> resetToRoot")
                        coordinator.resetToRoot()
                    }
                }
            } else {
                Button(vm.isBusy ? "Ingresso…" : "Entra") {
                    KBLog.sync.info("JoinFamilyView: join button tapped")
                    Task { await vm.join() }
                }
                .disabled(vm.isBusy || vm.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            KBLog.ui.debug("JoinFamilyViewBody appeared")
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
                    
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                        .frame(width: 260, height: 260)
                }
                .navigationTitle("Scansiona QR")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { onClose() }
                    }
                }
                .onAppear {
                    KBLog.ui.debug("QRScannerSheet appeared")
                }
            }
        }
    }
}
