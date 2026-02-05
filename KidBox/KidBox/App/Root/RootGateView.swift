//
//  RootGateView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI
import SwiftData

struct RootGateView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var families: [KBFamily]
    
    var body: some View {
        Group {
            if !coordinator.isAuthenticated {
                LoginView()
            } else if families.isEmpty {
                SetupFamilyView()
            } else {
                HomeView()
            }
        }
        .task {
            coordinator.startSessionListener(modelContext: modelContext)
        }
    }
}
