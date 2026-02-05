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
    
    var body: some View {
        Group {
            if !coordinator.isAuthenticated {
                LoginView()
            } else {
                HomeView()
            }
        }
        .task {
            coordinator.startSessionListener(modelContext: modelContext)
        }
    }
}
