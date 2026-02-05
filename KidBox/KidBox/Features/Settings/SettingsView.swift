//
//  SettingsView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    
    var body: some View {
        List {
            Section("Family") {
                Button("Family settings") { coordinator.navigate(to: .familySettings) }
            }
        }
        .navigationTitle("Settings")
    }
}
