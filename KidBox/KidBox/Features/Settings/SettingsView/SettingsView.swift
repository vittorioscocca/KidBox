//
//  SettingsView.swift
//  KidBox
//

import SwiftUI
import Combine
internal import os

/// App settings screen.
struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm = SettingsViewModel()
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
    
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    
    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

#if DEBUG
    @State private var updateTestReport: String?
#endif
    
    var body: some View {
        List {
            NavigationLink {
                AppearanceSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: coordinator.appearanceMode.icon)
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tema")
                            .foregroundStyle(.primary)
                        Text(coordinator.appearanceMode.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(cardBackground)

            NavigationLink {
                LanguageSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lingua")
                            .foregroundStyle(.primary)
                        Text(LanguageManager.shared.current.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(cardBackground)

            Button {
                KBLog.navigation.kbDebug("Settings -> Family settings tap")
                coordinator.navigate(to: .familySettings)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Family settings")
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
            .accessibilityLabel("Apri impostazioni famiglia")
            .listRowBackground(cardBackground)
            
            NavigationLink {
                MessageSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "message.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Messaggi")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(cardBackground)
            
            NavigationLink {
                AISettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Assistente AI")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(cardBackground)
            
            NavigationLink {
                NotificationSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Notifiche")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(cardBackground)

            NavigationLink {
                PrivacySettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy")
                            .foregroundStyle(.primary)
                        Text("Report errori e log tecnici")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(cardBackground)

            NavigationLink {
                AutoFillSettingsView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Password")
                            .foregroundStyle(.primary)
                        Text("AutoFill e compilazione automatica")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(cardBackground)

            NavigationLink {
                StorageUsageView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Utilizzo spazio")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(cardBackground)

            NavigationLink {
                SupportChatView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lifepreserver.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assistente & Supporto")
                            .foregroundStyle(.primary)
                        Text("Domande, problemi e suggerimenti")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listRowBackground(cardBackground)

            NavigationLink {
                UserGuideWebView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Guida all'utilizzo")
                        .foregroundStyle(.primary)
                }
            }
            .listRowBackground(cardBackground)

            // Versione/build/test: dentro la List così scorrono con il resto della pagina.
            Section {
                VStack(spacing: 6) {
                    Text("Versione \(appVersion)")
                    Text("Build \(appBuild)")
#if DEBUG
                    Button("Test aggiornamento") {
                        Task { updateTestReport = await AppUpdateChecker.shared.runDebugCheck() }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                    if let updateTestReport {
                        Text(updateTestReport)
                            .font(.caption2)
                    }
#endif
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Versione \(appVersion), build \(appBuild)")
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Impostazioni")
        .tint(.primary)
    }
}
