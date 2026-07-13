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
struct InviteCodeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        InviteCodeViewBody(modelContext: modelContext, coordinator: coordinator)
            .navigationTitle("Invita genitore")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InviteCodeViewBody: View {
    let modelContext: ModelContext
    let coordinator: AppCoordinator
    @StateObject private var vm: InviteCodeViewModel
    @Environment(\.colorScheme) private var colorScheme
    
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
    
    @State private var didLogAppear = false
    
    init(modelContext: ModelContext, coordinator: AppCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        _vm = StateObject(wrappedValue: InviteCodeViewModel(
            remote: InviteRemoteStore(),
            modelContext: modelContext,
            coordinator: coordinator
        ))
    }
    
    var body: some View {
        Form {
            Section {
                if let qrPayload = vm.qrPayload {
                    VStack(spacing: 16) {
                        QRCodeView(payload: qrPayload)
                            .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 8) {
                            Text("Scansiona con l'altro genitore")
                                .font(.headline)
                            
                            Text("Condividi questo codice QR. L'altro genitore lo scannerizzerà per unirsi alla famiglia e ricevere automaticamente la chiave di cifratura.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        
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
            .listRowBackground(cardBackground)
            
            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .listRowBackground(cardBackground)
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
            .listRowBackground(cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .onAppear {
            guard !didLogAppear else { return }
            didLogAppear = true
            KBLog.navigation.kbDebug("InviteCode: appeared")
        }
    }
    
    private func generateInvite() {
        KBLog.navigation.kbDebug("InviteCode: tap Generate QR (busy=\(vm.isBusy))")
        Task { await vm.generateInviteCode() }
    }
}
