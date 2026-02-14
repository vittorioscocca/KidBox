//
//  SettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import Combine
internal import os

/// App settings screen.
///
/// - Note:
///   Uses `.task` to load settings once per view lifecycle (better than `onAppear` for async work).
/// - Important:
///   In SwiftUI, avoid logging in `body` (it can be recomputed many times).
///   Prefer `.task` / `.onAppear` with lightweight logs.
struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm = SettingsViewModel()
    
    var body: some View {
        List {
            Section("Family") {
                Button("Family settings") {
                    KBLog.navigation.debug("Settings -> Family settings tap")
                    coordinator.navigate(to: .familySettings)
                }
                .accessibilityLabel("Apri impostazioni famiglia")
            }
            
            Section("Notifiche") {
                Toggle(
                    "Notifica nuovi documenti",
                    isOn: Binding(
                        get: { vm.notifyOnNewDocs },
                        set: { newValue in
                            // Log the user intent, not every render.
                            KBLog.settings.info("Toggle notifyOnNewDocs set=\(newValue, privacy: .public)")
                            vm.notifyOnNewDocs = newValue
                            vm.toggleNotifyOnNewDocs(newValue)
                        }
                    )
                )
                .disabled(vm.isLoading)
                .accessibilityHint("Abilita o disabilita le notifiche quando arrivano nuovi documenti.")
                
                if let t = vm.infoText {
                    Text(t)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            KBLog.settings.debug("SettingsView task start")
            vm.load()
            KBLog.settings.debug("SettingsView task end")
        }
    }
}
