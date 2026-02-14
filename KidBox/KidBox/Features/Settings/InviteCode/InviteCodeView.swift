//
//  InviteCodeView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Screen that generates and shows an invite QR code for the current family.
///
/// Logging policy (SwiftUI-safe):
/// - ✅ Log only on user actions (tap) and lifecycle edges (first appear).
/// - ❌ Avoid logs in `body` rendering paths that may re-run often.
struct InviteCodeView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        InviteCodeViewBody(modelContext: modelContext)
            .navigationTitle("Invita genitore")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InviteCodeViewBody: View {
    let modelContext: ModelContext
    @StateObject private var vm: InviteCodeViewModel
    
    @State private var didLogAppear = false
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        _vm = StateObject(wrappedValue: InviteCodeViewModel(
            remote: InviteRemoteStore(),
            modelContext: modelContext
        ))
    }
    
    var body: some View {
        Form {
            Section {
                if let qrPayload = vm.qrPayload {
                    VStack(spacing: 16) {
                        // ✅ QR code payload includes the crypto key material (as designed).
                        // The QR rendering is handled by `QRCodeView`.
                        QRCodeView(payload: qrPayload)
                            .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 8) {
                            Text("Scansiona con l'altro genitore")
                                .font(.headline)
                            
                            Text("Condividi questo codice QR. L'altro genitore lo scannerà per unirsi alla famiglia e ricevere automaticamente la chiave di cifratura.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        
                        // Share button (shares the payload string)
                        ShareLink(item: qrPayload) {
                            Label("Condividi QR", systemImage: "square.and.arrow.up")
                        }
                        .onTapGesture {
                            // Note: ShareLink doesn't expose completion; we only log the user intent.
                            KBLog.navigation.debug("InviteCode: tap ShareLink")
                        }
                    }
                    .padding(.vertical, 12)
                    
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        
                        Text("Genera il codice QR")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            }
            
            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
            }
            
            Section {
                Button(action: generateInvite) {
                    if vm.isBusy {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Generazione in corso...")
                        }
                    } else {
                        HStack {
                            Image(systemName: "qrcode")
                            Text("Genera codice QR")
                        }
                    }
                }
                .disabled(vm.isBusy)
            }
        }
        .onAppear {
            // SwiftUI can call onAppear multiple times (navigation stack, state changes).
            // We log only once per view lifetime.
            guard !didLogAppear else { return }
            didLogAppear = true
            KBLog.navigation.debug("InviteCode: appeared")
        }
    }
    
    /// Starts the async generation flow in the ViewModel.
    ///
    /// - Note: The ViewModel is responsible for validating family state,
    ///   contacting the server, and producing `qrPayload` or an error message.
    private func generateInvite() {
        KBLog.navigation.debug("InviteCode: tap Generate QR (busy=\(vm.isBusy, privacy: .public))")
        Task { await vm.generateInviteCode() }
    }
}
