//
//  RootHostView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData

struct RootHostView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    // family “attiva” deterministica
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.makeRootView()
                .navigationDestination(for: Route.self) { coordinator.makeDestination(for: $0) }
        }
        .onAppear {
            startFamilyRealtimeIfPossible()
        }
        .onChange(of: families.first?.id) { _, _ in
            // se dopo create family l’id arriva “dopo”, riproviamo
            startFamilyRealtimeIfPossible()
        }
    }
    
    private func startFamilyRealtimeIfPossible() {
        guard let familyId = families.first?.id, !familyId.isEmpty else { return }
        SyncCenter.shared.startFamilyBundleRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
    }
}
