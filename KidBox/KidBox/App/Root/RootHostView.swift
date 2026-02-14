//
//  RootHostView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

//
//  RootHostView.swift
//  KidBox
//
//  Hosts the app root NavigationStack and manages the lifecycle of the
//  active family realtime listeners (family bundle, members, documents).
//
//  Notes:
//  - Uses the most recently updated family as "active" (families.first).
//  - Starts/stops listeners when active family changes.
//  - Performs a master-key migration on appear (best effort with logging).
//

import SwiftUI
import SwiftData

struct RootHostView: View {
    
    // MARK: - Dependencies
    
    /// App navigation / routing coordinator.
    @EnvironmentObject private var coordinator: AppCoordinator
    
    /// SwiftData model context (used by realtime sync + migration).
    @Environment(\.modelContext) private var modelContext
    
    /// Families ordered by latest update, first is considered the "active" family.
    @Query(sort: \KBFamily.updatedAt, order: .reverse)
    private var families: [KBFamily]
    
    // MARK: - State
    
    /// The familyId for which realtime listeners are currently active.
    ///
    /// We keep this local state so we can:
    /// - avoid re-starting listeners for the same familyId
    /// - stop listeners when there is no active family
    /// - switch listeners when the active family changes
    @State private var startedFamilyId: String?
    
    // MARK: - View
    
    var body: some View {
        NavigationStack(path: $coordinator.path) {
            coordinator.makeRootView()
                .navigationDestination(for: Route.self) {
                    coordinator.makeDestination(for: $0)
                }
        }
        .onAppear {
            KBLog.navigation.kbDebug("RootHostView appeared")
            
            // Keep the migration inside a Task to avoid blocking UI.
            KBLog.sync.kbInfo("Starting master key migration (best effort)")
            Task {
                do {
                    try await MasterKeyMigration.migrateAllFamilies(modelContext: modelContext)
                    KBLog.sync.kbInfo("Master key migration completed")
                } catch {
                    KBLog.sync.kbError("Master key migration failed: \(error.localizedDescription)")
                }
            }
            
            startFamilyRealtimeIfPossible()
        }
        .onChange(of: families.first?.id) { oldValue, newValue in
            // Same trigger as before, but now with useful context.
            KBLog.sync.kbInfo("Active family changed old=\(oldValue ?? "nil") new=\(newValue ?? "nil")")
            startFamilyRealtimeIfPossible()
        }
    }
    
    // MARK: - Realtime lifecycle
    
    /// Starts or restarts realtime listeners if needed.
    ///
    /// Logic (unchanged):
    /// - If there is no active family, stop listeners (if any were started) and reset `startedFamilyId`.
    /// - If active family is the same as `startedFamilyId`, do nothing.
    /// - If active family differs, stop previous listeners (if any), then start new ones.
    private func startFamilyRealtimeIfPossible() {
        let activeId = families.first?.id
        
        guard let familyId = activeId, !familyId.isEmpty else {
            // No active family → stop listeners if they were active.
            if startedFamilyId != nil {
                KBLog.sync.kbInfo("No active family. Stopping realtime listeners (previous=\(startedFamilyId ?? "nil"))")
                
                SyncCenter.shared.stopFamilyBundleRealtime()
                SyncCenter.shared.stopMembersRealtime()
                SyncCenter.shared.stopDocumentsRealtime()
                
                startedFamilyId = nil
                KBLog.sync.kbDebug("Realtime listeners stopped and startedFamilyId cleared")
            } else {
                KBLog.sync.kbDebug("No active family and no realtime to stop")
            }
            return
        }
        
        // Same family already started → nothing to do.
        guard startedFamilyId != familyId else {
            KBLog.sync.kbDebug("Realtime already active for familyId=\(familyId)")
            return
        }
        
        // Switching to a different family → stop previous listeners first.
        if startedFamilyId != nil {
            KBLog.sync.kbInfo("Switching realtime listeners from=\(startedFamilyId ?? "nil") to=\(familyId)")
            
            SyncCenter.shared.stopFamilyBundleRealtime()
            SyncCenter.shared.stopMembersRealtime()
            SyncCenter.shared.stopDocumentsRealtime()
        } else {
            KBLog.sync.kbInfo("Starting realtime listeners for familyId=\(familyId)")
        }
        
        startedFamilyId = familyId
        
        // Start listeners (unchanged).
        KBLog.sync.kbDebug("startFamilyBundleRealtime familyId=\(familyId)")
        SyncCenter.shared.startFamilyBundleRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startMembersRealtime familyId=\(familyId)")
        SyncCenter.shared.startMembersRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startDocumentsRealtime familyId=\(familyId)")
        SyncCenter.shared.startDocumentsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
    }
}
