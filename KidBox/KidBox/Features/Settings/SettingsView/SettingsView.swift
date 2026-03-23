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
            
            Button {
                KBLog.navigation.debug("Settings -> Family settings tap")
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
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Impostazioni")
        .tint(.primary)
    }
}
