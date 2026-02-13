//
//  InviteCodeView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//


import SwiftUI
import SwiftData

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
                        // ✅ QR CODE con la chiave crittografica
                        QRCodeView(payload: qrPayload)
                            .frame(maxWidth: .infinity)
                        
                        // Descrizione
                        VStack(spacing: 8) {
                            Text("Scansiona con l'altro genitore")
                                .font(.headline)
                            
                            Text("Condividi questo codice QR. L'altro genitore lo scannerà per unirsi alla famiglia e ricevere automaticamente la chiave di cifratura.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        
                        // Share button
                        ShareLink(item: qrPayload) {
                            Label("Condividi QR", systemImage: "square.and.arrow.up")
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
    }
    
    private func generateInvite() {
        Task { await vm.generateInviteCode() }
    }
}
