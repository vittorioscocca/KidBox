//
//  AISettingsView.swift
//  KidBox
//

import SwiftUI

struct AISettingsView: View {
    
    @StateObject private var viewModel = AISettingsViewModel()
    @State private var showConsent = false
    
    var body: some View {
        List {
            
            // MARK: - Intro
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .padding(10)
                            .background(.blue.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Assistente AI")
                                .font(.headline)
                            Text("Incluso nel tuo piano KidBox")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Collega il tuo assistente AI e trasforma KidBox nel punto di riferimento intelligente della tua famiglia. Salute, routine, documenti, agenda: tutto il contesto che già tieni in app, a disposizione di un assistente che conosce davvero i tuoi figli.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Toggle
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.aiEnabled },
                    set: { newValue in
                        if newValue && !viewModel.consentGiven {
                            // Mostra consent sheet prima di attivare
                            showConsent = true
                        } else {
                            viewModel.toggleAIEnabled(newValue)
                        }
                    }
                )) {
                    Label("Attiva assistente AI", systemImage: "brain.head.profile")
                }
                
                if let info = viewModel.infoText {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
            } footer: {
                Text("Puoi disattivarlo in qualsiasi momento. I dati inviati all'AI sono quelli che scegli di condividere, visita per visita.")
                    .font(.caption)
            }
            
            // MARK: - Utilizzo
            if viewModel.aiEnabled {
                Section("Utilizzo oggi") {
                    if viewModel.loadingUsage {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Caricamento…").foregroundStyle(.secondary)
                        }
                    } else if let usage = viewModel.usage {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(usage.usageToday) di \(usage.dailyLimit) messaggi usati oggi")
                                    .font(.subheadline)
                                Spacer()
                                if usage.isNearLimit {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                }
                            }
                            ProgressView(value: Double(usage.usageToday), total: Double(usage.dailyLimit))
                                .tint(usage.isNearLimit ? .orange : .blue)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Text("—").foregroundStyle(.secondary)
                    }
                }
                .task { await viewModel.loadUsage() }
            }
            
            // MARK: - Privacy / Consenso
            if viewModel.consentGiven, let date = viewModel.consentDate {
                Section("Privacy") {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Consenso fornito").font(.subheadline)
                            Text(date.formatted(date: .long, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) {
                        viewModel.revokeConsent()
                    } label: {
                        Label("Revoca consenso e disattiva", systemImage: "hand.raised")
                    }
                }
            }
            
            // MARK: - Come funziona
            Section("Come funziona") {
                infoRow(icon: "lock.shield.fill", color: .green,
                        title: "Dati al sicuro",
                        body: "Nessuna API key sul tuo dispositivo. Tutto passa per i server KidBox.")
                infoRow(icon: "gauge.with.dots.needle.bottom.50percent", color: .blue,
                        title: "Limite giornaliero",
                        body: "Ogni piano include un numero di messaggi AI al giorno. Piani superiori sbloccano limiti più alti.")
                infoRow(icon: "exclamationmark.triangle", color: .orange,
                        title: "Non è un parere medico",
                        body: "L'AI spiega e informa. Per decisioni cliniche consulta sempre il tuo medico.")
            }
        }
        .navigationTitle("Assistente AI")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load() }
        .sheet(isPresented: $showConsent) {
            AIConsentSheet {
                viewModel.recordConsent()
            }
        }
    }
    
    @ViewBuilder
    private func infoRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { AISettingsView() }
}
