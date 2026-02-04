//
//  ContentView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator = AppCoordinator()
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.makeRootView()
                .navigationDestination(for: Route.self) { route in
                    coordinator.makeDestination(for: route)
                }
        }
        .onAppear {
            DebugSeeder.seedIfNeeded(context: modelContext)
        }
        .task {
        #if DEBUG
            FirestorePingService().ping { _ in }
        #endif
        }
    }
}

#Preview {
    RootView()
}
