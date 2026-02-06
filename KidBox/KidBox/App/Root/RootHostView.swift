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
    
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    @State private var startedFamilyId: String?
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.makeRootView()
                .navigationDestination(for: Route.self) { coordinator.makeDestination(for: $0) }
        }
        .onAppear {
            startFamilyRealtimeIfPossible()
        }
        .onChange(of: families.first?.id) { _, _ in
            startFamilyRealtimeIfPossible()
        }
    }
    
    private func startFamilyRealtimeIfPossible() {
        guard let familyId = families.first?.id, !familyId.isEmpty else {
            // opzionale: se perdi la family, stop listeners
            if startedFamilyId != nil {
                SyncCenter.shared.stopFamilyBundleRealtime()
                SyncCenter.shared.stopMembersRealtime()
                startedFamilyId = nil
            }
            return
        }
        
        // evita restart inutili
        guard startedFamilyId != familyId else { return }
        startedFamilyId = familyId
        
        SyncCenter.shared.startFamilyBundleRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        SyncCenter.shared.startMembersRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
    }
}
