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
            .navigationTitle("Entra in famiglia")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                KBLog.ui.kbDebug("JoinFamilyView appeared")
            }
    }
}

private struct JoinFamilyViewBody: View {
    private var coordinator: AppCoordinator
    @State private var showScanner = false
    let modelContext: ModelContext
    @StateObject private var vm: JoinFamilyViewModel
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
    
    init(modelContext: ModelContext, coordinator: AppCoordinator) {
        self.modelContext = modelContext
        _vm = StateObject(wrappedValue: JoinFamilyViewModel(
            modelContext: modelContext,
            coordinator: coordinator
        ))
        self.coordinator = coordinator
    }
    
    var body: some View {
        Form {
            // Il codice testuale non esiste più: entrava in famiglia senza
            // trasportare la chiave di cifratura. Restano due strade complete —
            // il link d'invito (che apre l'app da solo) e il QR qui sotto.
            Section {
                Text("Chiedi a chi ti invita di mandarti il link d'invito, oppure inquadra il suo codice QR.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(cardBackground)

            Button {
                showScanner = true
                KBLog.ui.kbInfo("JoinFamilyView: open QR scanner")
            } label: {
                Label("Scansiona QR code", systemImage: "qrcode.viewfinder")
            }
            .listRowBackground(cardBackground)
            .sheet(isPresented: $showScanner) {
                QRScannerSheet(
                    onDetected: { raw in
                        showScanner = false
                        Task { await vm.joinFromQR(payload: raw) }
                    },
                    onClose: {
                        showScanner = false
                        KBLog.ui.kbDebug("JoinFamilyView: QR scanner closed")
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
                .listRowBackground(cardBackground)
            }
            
            if vm.didJoin {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Sei entrato nella famiglia!")
                    }
                    .listRowBackground(cardBackground)

                    Button("Continua") {
                        KBLog.navigation.kbInfo("JoinFamilyView: continue -> resetToRoot")
                        coordinator.resetToRoot()
                    }
                    .listRowBackground(cardBackground)
                }
            }

            if vm.isBusy {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ingresso in corso…")
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(cardBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .onAppear {
            KBLog.ui.kbDebug("JoinFamilyViewBody appeared")
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
                    KBLog.ui.kbDebug("QRScannerSheet appeared")
                }
            }
        }
    }
}
