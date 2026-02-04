//
//  ContentView.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import SwiftUI

struct RootView: View {
    @State private var coordinator = AppCoordinator()
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.makeRootView()
                .navigationDestination(for: Route.self) { route in
                    coordinator.makeDestination(for: route)
                }
        }
    }
}

#Preview {
    RootView()
}
