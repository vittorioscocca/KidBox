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
            // ✅ Migra master key per famiglie esistenti (idempotent - safe to call multiple times)
            Task {
                do {
                    try await MasterKeyMigration.migrateAllFamilies(modelContext: modelContext)
                } catch {
                    print("⚠️ Master key migration failed:", error.localizedDescription)
                }
            }
            
            // Avvia realtime sync
            startFamilyRealtimeIfPossible()
        }
        .onChange(of: families.first?.id) { _, _ in
            startFamilyRealtimeIfPossible()
        }
    }
    
    private func startFamilyRealtimeIfPossible() {
        guard let familyId = families.first?.id, !familyId.isEmpty else {
            // se perdi la family, stop listeners
            if startedFamilyId != nil {
                SyncCenter.shared.stopFamilyBundleRealtime()
                SyncCenter.shared.stopMembersRealtime()
                SyncCenter.shared.stopDocumentsRealtime()
                startedFamilyId = nil
            }
            return
        }
        
        // evita restart inutili
        guard startedFamilyId != familyId else { return }
        
        // se stavi ascoltando un'altra famiglia, stop prima
        if startedFamilyId != nil {
            SyncCenter.shared.stopFamilyBundleRealtime()
            SyncCenter.shared.stopMembersRealtime()
            SyncCenter.shared.stopDocumentsRealtime()
        }
        
        startedFamilyId = familyId
        
        SyncCenter.shared.startFamilyBundleRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        SyncCenter.shared.startMembersRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        SyncCenter.shared.startDocumentsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
    }
}
