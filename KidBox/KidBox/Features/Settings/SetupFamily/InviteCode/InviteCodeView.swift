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
    @State private var showRevokeConfirm = false
    
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

                            Label("È il modo più sicuro: la chiave viene letta dalla fotocamera e non passa da chat, email o backup.", systemImage: "lock.shield.fill")
                                .font(.footnote)
                                .foregroundStyle(.green)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        
                        // Il link è la via principale: funziona a distanza e
                        // trasporta anche la chiave. Il QR resta per quando si è
                        // vicini. Si condivide `shareText`, non `qrPayload`.
                        if vm.shareLink != nil {
                            Divider()

                            Text("Se non siete vicini, invia il link.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ShareLink(
                                item: vm.shareText,
                                subject: Text(InviteCodeViewModel.shareSubject)
                            ) {
                                Label("Invia link d'invito", systemImage: "square.and.arrow.up")
                            }

                            Button {
                                vm.copyToClipboard()
                            } label: {
                                Label("Copia link", systemImage: "doc.on.doc")
                            }

                            // Il segreto viaggia dentro il link: va detto, perché
                            // resta nella conversazione anche dopo l'invio.
                            Label("Il link contiene la chiave: chi lo riceve può entrare. Resta nella chat o nella posta finché non viene usato. Vale 24 ore, una volta sola, e puoi annullarlo qui sotto.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
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

            // Revoca: il segreto viaggia dentro il link, quindi finché l'invito
            // è valido chi lo possiede può entrare. Poterlo annullare è la
            // difesa vera se finisce nella chat sbagliata — più del TTL.
            if vm.currentInviteId != nil {
                Section {
                    Button(role: .destructive) {
                        showRevokeConfirm = true
                    } label: {
                        Label("Revoca invito", systemImage: "xmark.circle")
                    }
                    .disabled(vm.isBusy)
                } footer: {
                    Text("Il link già inviato smetterà di funzionare. Potrai generarne uno nuovo.")
                }
                .listRowBackground(cardBackground)
            }
        }
        .confirmationDialog(
            "Revocare l'invito?",
            isPresented: $showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoca", role: .destructive) {
                Task { await vm.revokeInvite() }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Chi ha ricevuto il link non potrà più usarlo per entrare nella famiglia.")
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
