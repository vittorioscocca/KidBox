//
//  RootGateView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

//
//  RootGateView.swift
//  KidBox
//
//  Root authentication gate.
//  Decides whether to show LoginView or HomeView.
//

import SwiftUI
import SwiftData

struct RootGateView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if !coordinator.isAuthenticated {
                LoginView()
            } else {
                HomeView()
            }
        }
        .onAppear {
            KBLog.navigation.kbDebug("RootGateView appeared")
        }
        .onChange(of: coordinator.isAuthenticated) { _, newValue in
            KBLog.navigation.kbInfo("Auth state changed: \(newValue)")
        }
        .task {
            KBLog.navigation.kbDebug("Starting session listener")
            coordinator.startSessionListener(modelContext: modelContext)
        }
    }
}
