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
    
    var body: some View {
        List {
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
        }
        .navigationTitle("Impostazioni")
        .tint(.primary)
    }
}
