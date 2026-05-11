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
import FirebaseAuth
import UIKit
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
        .task(id: resolvedActiveFamilyId) {
            guard let fid = resolvedActiveFamilyId else { return }
            let famName = families.first(where: { $0.id == fid })?.name ?? "Famiglia"
            await WeeklySummaryService.shared.scheduleWeeklyIfNeeded(
                input: PlanningContextInput(familyName: famName),
                familyName: famName,
                modelContext: modelContext,
                forcedFamilyId: fid
            )
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
            
            // Cold-start: se l'app è stata aperta proprio dal banner "Apri KidBox"
            // della Share Extension, scenePhase parte già .active e
            // willEnterForeground non scatta. Controlliamo qui.
            coordinator.handleIncomingShare(modelContext: modelContext)
            coordinator.consumePendingControlWidgetRouteIfNeeded(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            coordinator.consumePendingControlWidgetRouteIfNeeded(modelContext: modelContext)
        }
        // React to explicit family selection changes (join, switch).
        .onChange(of: coordinator.activeFamilyId) { oldValue, newValue in
            KBLog.sync.kbInfo("coordinator.activeFamilyId changed old=\(oldValue ?? "nil") new=\(newValue ?? "nil")")
            startFamilyRealtimeIfPossible()
        }
        // Dopo join: `resetToRoot()` mantiene lo stesso `activeFamilyId` ma azzera lo stack;
        // forza un nuovo ciclo listener così non restiamo agganciati a dati/sessione vecchi.
        .onChange(of: coordinator.rootDataRefreshToken) { _, _ in
            KBLog.sync.kbInfo("RootHostView: rootDataRefreshToken — forcing realtime rebind")
            startedFamilyId = nil
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
            VStack(spacing: 8) {
                if showRevokedAlert {
                    Text("Sei stato rimosso dalla famiglia \"\(revokedFamilyName ?? "")\".")
                        .padding()
                        .background(.red.opacity(0.9))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let message = coordinator.globalBannerMessage {
                    Text(message)
                        .padding()
                        .background(.black.opacity(0.85))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
        .animation(.spring(), value: showRevokedAlert)
        .animation(.spring(), value: coordinator.globalBannerMessage)
        .onChange(of: coordinator.globalBannerMessage) { _, newValue in
            guard newValue != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                coordinator.globalBannerMessage = nil
            }
        }
    }
    
    // MARK: - Realtime lifecycle
    
    /// Starts or restarts realtime listeners based on `resolvedActiveFamilyId`.
    ///
    /// Logic:
    /// - If there is no resolved active family, stop listeners (if any) and reset `startedFamilyId`.
    /// - If resolved family equals `startedFamilyId`, do nothing.
    /// - If resolved family differs, stop previous listeners, then start new ones.
    ///
    /// Includes `startChildrenRealtime` so SwiftData child fields (e.g. weight/height) stay in sync
    /// from Firestore without opening Family settings.
    private func startFamilyRealtimeIfPossible() {
        let familyId = resolvedActiveFamilyId
        
        guard let familyId, !familyId.isEmpty else {
            if startedFamilyId != nil {
                KBLog.sync.kbInfo("No active family. Stopping realtime listeners (previous=\(startedFamilyId ?? "nil"))")
                SyncCenter.shared.stopFamilyBundleRealtime()
                SyncCenter.shared.stopMembersRealtime()
                SyncCenter.shared.stopChildrenRealtime()
                SyncCenter.shared.stopDocumentsRealtime()
                SyncCenter.shared.stopTreatmentsRealtime()
                SyncCenter.shared.stopExpensesRealtime()
                SyncCenter.shared.stopWalletRealtime()
                SyncCenter.shared.stopPetsRealtime()
                SyncCenter.shared.stopPetEventsRealtime()
                SyncCenter.shared.stopHomeItemsRealtime()
                SyncCenter.shared.stopHousePaymentsRealtime()
                SyncCenter.shared.stopVehiclesRealtime()
                SyncCenter.shared.stopVehicleEventsRealtime()
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

        // Proactive key recovery: if Keychain entry is missing after reinstall/switch,
        // try Firestore escrow restore before document operations start failing.
        if let uid = Auth.auth().currentUser?.uid, !uid.isEmpty {
            Task {
                _ = await FamilyKeyEscrowService.ensureFamilyKeyAvailable(familyId: familyId, userId: uid)
            }
        }
        
        // Se stiamo usando il fallback families.first (activeFamilyId == nil),
        // salva il familyId nell'App Group per la Share Extension.
        if coordinator.activeFamilyId == nil {
            let sharedDefaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
            sharedDefaults?.set(familyId, forKey: "activeFamilyId")
            KBLog.sync.kbInfo("AppGroup: fallback activeFamilyId saved fid=\(familyId)")
        }
        
        // Switching to a different family → stop previous listeners first.
        if startedFamilyId != nil {
            KBLog.sync.kbInfo("Switching realtime listeners from=\(startedFamilyId ?? "nil") to=\(familyId)")
            SyncCenter.shared.stopFamilyBundleRealtime()
            SyncCenter.shared.stopMembersRealtime()
            SyncCenter.shared.stopChildrenRealtime()
            SyncCenter.shared.stopDocumentsRealtime()
            SyncCenter.shared.stopTreatmentsRealtime()
            SyncCenter.shared.stopExpensesRealtime()
            SyncCenter.shared.stopWalletRealtime()
            SyncCenter.shared.stopPetsRealtime()
            SyncCenter.shared.stopPetEventsRealtime()
            SyncCenter.shared.stopHomeItemsRealtime()
            SyncCenter.shared.stopHousePaymentsRealtime()
            SyncCenter.shared.stopVehiclesRealtime()
            SyncCenter.shared.stopVehicleEventsRealtime()
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

        KBLog.sync.kbDebug("startChildrenRealtime familyId=\(familyId)")
        SyncCenter.shared.startChildrenRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startDocumentsRealtime familyId=\(familyId)")
        SyncCenter.shared.startDocumentsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startTreatmentsRealtime familyId=\(familyId)")
        SyncCenter.shared.startTreatmentsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startVisitRealtime familyId=\(familyId)")
        SyncCenter.shared.startVisitsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startCalendarRealtime familyId=\(familyId)")
        SyncCenter.shared.startCalendarRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("startExpensesRealtime familyId=\(familyId)")
        SyncCenter.shared.startExpensesRealtime(
            familyId: familyId,
            modelContext: modelContext
        )

        KBLog.sync.kbDebug("startWalletRealtime familyId=\(familyId)")
        SyncCenter.shared.startWalletRealtime(
            familyId: familyId,
            modelContext: modelContext
        )

        KBLog.sync.kbDebug("startPetsRealtime familyId=\(familyId)")
        SyncCenter.shared.startPetsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        KBLog.sync.kbDebug("startPetEventsRealtime familyId=\(familyId)")
        SyncCenter.shared.startPetEventsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        KBLog.sync.kbDebug("startHomeItemsRealtime familyId=\(familyId)")
        SyncCenter.shared.startHomeItemsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        KBLog.sync.kbDebug("startHousePaymentsRealtime familyId=\(familyId)")
        SyncCenter.shared.startHousePaymentsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        KBLog.sync.kbDebug("startVehiclesRealtime familyId=\(familyId)")
        SyncCenter.shared.startVehiclesRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
        KBLog.sync.kbDebug("startVehicleEventsRealtime familyId=\(familyId)")
        SyncCenter.shared.startVehicleEventsRealtime(
            familyId: familyId,
            modelContext: modelContext
        )
    }
}
