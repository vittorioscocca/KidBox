//
//  SettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import Combine

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm = SettingsViewModel()
    
    var body: some View {
        List {
            Section("Family") {
                Button("Family settings") { coordinator.navigate(to: .familySettings) }
            }
            
            Section("Notifiche") {
                Toggle("Notifica nuovi documenti", isOn: Binding(
                    get: { vm.notifyOnNewDocs },
                    set: { newValue in
                        vm.notifyOnNewDocs = newValue
                        vm.toggleNotifyOnNewDocs(newValue)
                    }
                ))
                .disabled(vm.isLoading)
                
                if let t = vm.infoText {
                    Text(t).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .task { vm.load() }   // ✅ iOS 15+ (meglio di onAppear)
    }
}
