//
//  AutoFillSettingsBlock.swift
//  KidBox
//

import AuthenticationServices
import SwiftUI
import UIKit

/// Sezione Impostazioni per AutoFill / QuickType.
struct AutoFillSettingsBlock: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var providerEnabled = false
    @State private var requireBiometric = KidBoxAutoFillPreferences.requireBiometricForQuickType
    @State private var autofillCount = 0

    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }

    var body: some View {
        Section {
            HStack {
                Text("Stato")
                Spacer()
                Text(providerEnabled ? "Attivo" : "Da attivare in Impostazioni iOS")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .listRowBackground(cardBackground)

            Button {
                openIOSPasswordSettings()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gear")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Apri Impostazioni iOS")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(cardBackground)

            Toggle(isOn: $requireBiometric) {
                Text("Richiedi Face ID anche per AutoFill da QuickType")
            }
            .tint(KBTheme.bubbleTint)
            .onChange(of: requireBiometric) { _, newValue in
                KidBoxAutoFillPreferences.requireBiometricForQuickType = newValue
            }
            .listRowBackground(cardBackground)

            HStack {
                Text("Password disponibili per AutoFill")
                Spacer()
                Text("\(autofillCount)")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(cardBackground)
        } header: {
            Text("AutoFill")
        }
        .onAppear {
            refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshState()
        }
    }

    private func refreshState() {
        AutoFillSync.fetchProviderEnabled { enabled in
            providerEnabled = enabled
        }
        autofillCount = UserDefaults(suiteName: KidBoxAutoFillPaths.appGroupId)?.integer(forKey: "kidbox.autofill.lastSnapshotCount") ?? 0
        requireBiometric = KidBoxAutoFillPreferences.requireBiometricForQuickType
    }

    private func openIOSPasswordSettings() {
        if let url = URL(string: "App-Prefs:PASSWORDS"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
