//
//  AIConsentSheet.swift
//  KidBox
//

import SwiftUI

/// One-time consent sheet shown before the first message to the AI assistant.
///
/// Must be presented before the first use of the AI chat feature.
/// Records consent via `AIProviderSettings.recordConsent()`.
struct AIConsentSheet: View {
    
    @ObservedObject private var settings = AISettings.shared
    @Environment(\.dismiss) private var dismiss
    
    /// Called when the user accepts. The caller should then open the AI chat.
    var onAccept: () -> Void
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Icon + title
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 52))
                                .foregroundStyle(.blue)
                            Text("Assistente AI")
                                .font(.title2.bold())
                            Text("Prima di continuare, leggi come funziona.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    
                    Divider()
                    
                    // Cosa parte a ogni domanda: dal 02/10/2026 la memoria di tutta
                    // l'app (internal/assistente-unico.md), non più il solo contesto sanitario.
                    infoBlock(
                        icon: "arrow.up.doc.fill",
                        color: .orange,
                        title: "Cosa viene inviato",
                        body: "A ogni domanda, insieme a quello che scrivi, parte la memoria dell'assistente: quello che la famiglia tiene in KidBox. Calendario, to-do, spesa, note, spese, salute con i referti, testo letto dai documenti, wallet, casa, veicoli, animali, viaggi, ultimi messaggi della chat. Non partono mai password, numeri dei documenti d'identità e delle carte fedeltà, posizione, né le voci che un altro membro tiene solo per sé."
                    )
                    
                    infoBlock(
                        icon: "building.2.fill",
                        color: .blue,
                        title: "Fornitore AI: Anthropic",
                        body: "Le risposte le genera Claude di Anthropic (Stati Uniti), passando dai server KidBox. Anthropic non usa questi dati per addestrare i suoi modelli e li tratta secondo la sua Privacy Policy."
                    )
                    
                    infoBlock(
                        icon: "tray.full.fill",
                        color: .teal,
                        title: "Cosa resta salvato",
                        body: "Le conversazioni restano nel tuo account per ritrovarle sugli altri dispositivi, e qualche fatto utile emerso parlando resta nella memoria della famiglia. Puoi cancellare la conversazione dall'assistente."
                    )
                    
                    infoBlock(
                        icon: "exclamationmark.triangle.fill",
                        color: .red,
                        title: "Non è un parere medico",
                        body: "L'AI fornisce spiegazioni e informazioni generali. Non sostituisce il tuo medico. Per qualsiasi decisione clinica, consulta sempre un professionista."
                    )
                    
                    infoBlock(
                        icon: "hand.raised.fill",
                        color: .purple,
                        title: "Il tuo controllo",
                        body: "L'assistente risponde quando gli scrivi. Briefing, recap e analisi mensile partono da soli solo se li attivi nelle impostazioni. Puoi revocare il consenso in qualsiasi momento da Impostazioni → Assistente AI."
                    )
                    
                    // Provider info link
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Informativa privacy")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        Link("Anthropic — Privacy Policy",
                             destination: URL(string: "https://www.anthropic.com/privacy")!)
                        .font(.caption)
                        
                        Link("KidBox — Privacy Policy",
                             destination: URL(string: "https://kidboxapp.com/privacy.html")!)
                        .font(.caption)
                    }
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button {
                        settings.recordConsent()
                        onAccept()
                        dismiss()
                    } label: {
                        Label("Ho capito, procedi", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    
                    Button("Annulla", role: .cancel) { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                .background(.regularMaterial)
            }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func infoBlock(
        icon: String,
        color: Color,
        title: LocalizedStringKey,
        body: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    
}

#Preview {
    AIConsentSheet(onAccept: {})
}
