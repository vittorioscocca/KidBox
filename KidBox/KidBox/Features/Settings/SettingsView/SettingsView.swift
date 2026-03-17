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
    
    var body: some View {
        List {
            Picker(selection: Binding(
                get: { vm.appearanceMode },
                set: { vm.setAppearanceMode($0, coordinator: coordinator) }
            )) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: coordinator.appearanceMode.icon)
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text("Tema")
                        .foregroundStyle(.primary)
                }
            }
            .pickerStyle(.navigationLink)
            
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
        }
        .navigationTitle("Impostazioni")
        .tint(.primary)
    }
}
