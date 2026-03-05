//
//  AIConsentSheet.swift
//  KidBox
//

import SwiftUI

/// One-time consent sheet shown before sending medical data to an AI provider.
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
                            Text("Assistente AI Medico")
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
                    
                    // What will be sent
                    infoBlock(
                        icon: "arrow.up.doc.fill",
                        color: .orange,
                        title: "Cosa viene inviato",
                        body: "I dati della visita medica (diagnosi, farmaci, terapie, esami) vengono elaborati dall'assistente AI di KidBox per generare la risposta."
                    )
                    
                    infoBlock(
                        icon: "key.fill",
                        color: .green,
                        title: "La tua API key",
                        body: "La chiave API è salvata in modo sicuro sul tuo dispositivo (Keychain). KidBox non ha mai accesso alla tua chiave."
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
                        body: "Puoi revocare il consenso in qualsiasi momento da Impostazioni → Assistente AI. Ogni richiesta richiede un'azione esplicita da parte tua."
                    )
                    
                    // Provider info link
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Informativa privacy")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        
                        Link("Anthropic — Privacy Policy",
                             destination: URL(string: "https://www.anthropic.com/privacy")!)
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
        title: String,
        body: String
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
