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
//  - Uses coordinator.activeFamilyId as the source of truth for the active family.
//    This is an explicit value set by join/switch actions, not derived from DB ordering.
//  - Falls back to families.first only if activeFamilyId is not set (e.g. first run).
//  - Starts/stops listeners when active family changes.
//  - Performs a master-key migration on appear (best effort with logging).
//

import SwiftUI
import SwiftData
import Combine
internal import os

struct RootHostView: View {
    
    // MARK: - Dependencies
    
    /// App navigation / routing coordinator.
    @EnvironmentObject private var coordinator: AppCoordinator
    
    /// SwiftData model context (used by realtime sync + migration).
    @Environment(\.modelContext) private var modelContext
    
    /// All families, used as fallback when no activeFamilyId is pinned.
    /// Ordered by latest update so families.first is a reasonable default.
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
    
    // MARK: - Computed
    
    /// The resolved active family ID.
    ///
    /// Priority:
    /// 1. `coordinator.activeFamilyId` — explicit selection (join, switch).
    /// 2. `families.first?.id` — implicit fallback for first-run / fresh install.
    ///
    /// This means a family join or switch will always take precedence over
    /// whatever ordering SwiftData returns.
    private var resolvedActiveFamilyId: String? {
        if let pinned = coordinator.activeFamilyId {
            return pinned
        }
        return families.first?.id
    }
    
    @State private var revokedFamilyName: String?
    @State private var showRevokedAlert = false
    
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
        // React to explicit family selection changes (join, switch).
        .onChange(of: coordinator.activeFamilyId) { oldValue, newValue in
            KBLog.sync.kbInfo("coordinator.activeFamilyId changed old=\(oldValue ?? "nil") new=\(newValue ?? "nil")")
            startFamilyRealtimeIfPossible()
        }
        // React to SwiftData families list changes (covers first-run fallback).
        .onChange(of: families.first?.id) { oldValue, newValue in
            // Only relevant when no explicit active family is pinned.
            guard coordinator.activeFamilyId == nil else {
                KBLog.sync.kbDebug("families.first changed but activeFamilyId is pinned — ignoring")
                return
            }
            KBLog.sync.kbInfo("families.first changed (fallback) old=\(oldValue ?? "nil") new=\(newValue ?? "nil")")
            startFamilyRealtimeIfPossible()
        }
        // Espulsione: wipa i dati locali e torna al root da qualsiasi view.
        .onReceive(SyncCenter.shared.currentUserRevoked) { revokedFamilyId in
            KBLog.sync.info("RootHostView: currentUserRevoked familyId=\(revokedFamilyId, privacy: .public)")
            
            
            // Recupera nome famiglia prima del wipe
            if let fam = try? modelContext.fetch(
                FetchDescriptor<KBFamily>(
                    predicate: #Predicate { $0.id == revokedFamilyId }
                )
            ).first {
                revokedFamilyName = fam.name
            } else {
                revokedFamilyName = nil
            }
            
            showRevokedAlert = true
            
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    showRevokedAlert = false
                }
            }
            
            startedFamilyId = nil
            Task { @MainActor in
                do {
                    let service = FamilyLeaveService(modelContext: modelContext)
                    try await service.leaveFamily(familyId: revokedFamilyId)
                    KBLog.sync.info("RootHostView: post-revoke wipe OK")
                } catch {
                    KBLog.sync.error("RootHostView: post-revoke leaveFamily failed: \(error.localizedDescription, privacy: .public)")
                    do {
                        let service = FamilyLeaveService(modelContext: modelContext)
                        try service.wipeFamilyLocalOnly(familyId: revokedFamilyId)
                        KBLog.sync.info("RootHostView: fallback local wipe OK")
                    } catch {
                        KBLog.sync.error("RootHostView: fallback local wipe failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                coordinator.setActiveFamily(nil)
                coordinator.resetToRoot()
            }
        }
        .overlay(alignment: .top) {
            if showRevokedAlert {
                Text("Sei stato rimosso dalla famiglia \"\(revokedFamilyName ?? "")\".")
                    .padding()
                    .background(.red.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: showRevokedAlert)
    }
    
    // MARK: - Realtime lifecycle
    
    /// Starts or restarts realtime listeners based on `resolvedActiveFamilyId`.
    ///
    /// Logic:
    /// - If there is no resolved active family, stop listeners (if any) and reset `startedFamilyId`.
    /// - If resolved family equals `startedFamilyId`, do nothing.
    /// - If resolved family differs, stop previous listeners, then start new ones.
    private func startFamilyRealtimeIfPossible() {
        let familyId = resolvedActiveFamilyId
        
        guard let familyId, !familyId.isEmpty else {
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
