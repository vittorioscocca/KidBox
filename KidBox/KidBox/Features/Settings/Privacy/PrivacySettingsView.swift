//
//  PrivacySettingsView.swift
//  KidBox
//

import SwiftUI

/// Impostazioni privacy: report errori automatici dai log locali.
struct PrivacySettingsView: View {
    @AppStorage("kb_log_reporting_enabled") private var automaticErrorReports = false
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        List {
            Section {
                Text(
                    "KidBox salva log tecnici sul dispositivo (avvio app, sincronizzazione, crash). "
                    + "Se attivi l’invio automatico, analizziamo questi log e possiamo inviare un report "
                    + "anonimo per correggere bug e migliorare l’app."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(cardBackground)

            Section {
                Toggle(isOn: $automaticErrorReports) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Invia report errori automatici")
                            .font(.body.weight(.medium))
                        Text(
                            "Nessun nome, messaggio di chat, documento o dato sanitario. "
                            + "Solo log tecnici e informazioni sul dispositivo."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: automaticErrorReports) { _, enabled in
                    CrashAnalyzer.isAutomaticReportingEnabled = enabled
                    if enabled {
                        CrashAnalyzer.hasBeenAskedForReporting = true
                        CrashAnalyzer.clearAnalysisThrottle()
                        Task { await CrashAnalyzer.analyzeIfNeeded(force: true) }
                    }
                }
            } footer: {
                Text(
                    "Su iPhone l’analisi usa Apple Intelligence sul dispositivo quando disponibile. "
                    + "Puoi disattivare l’invio in qualsiasi momento."
                )
            }
            .listRowBackground(cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            automaticErrorReports = CrashAnalyzer.isAutomaticReportingEnabled
        }
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
}
