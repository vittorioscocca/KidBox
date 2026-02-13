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
            .navigationTitle("Codice invito")
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
                if let code = vm.code {
                    let payload = "kidbox://join?code=\(code)"
                    
                    HStack {
                        Text(code)
                            .font(.system(.title2, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Button("Copia") { vm.copyToClipboard() }
                    }
                    
                    // ✅ QR CODE
                    VStack(spacing: 12) {
                        QRCodeView(payload: payload)
                        
                        Text("Scansiona questo QR con l’altro genitore.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    
                    ShareLink(item: vm.shareText) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text("Genera un codice da condividere con l’altro genitore o con un altro membro della famiglia.")
                        .foregroundStyle(.secondary)
                }
            }
            
            if let err = vm.errorMessage {
                Section { Text(err).foregroundStyle(.red) }
            }
            
            Button(vm.isBusy ? "Generazione…" : "Genera codice") {
                Task { await vm.generateInviteCode() }
            }
            .disabled(vm.isBusy)
        }
    }
}
