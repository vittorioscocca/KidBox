//
//  SyncCenter+FamilyBundle.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth
import OSLog

extension SyncCenter {
    
    // MARK: - Family realtime
    
    /// Shared listener for the family root document (`families/{familyId}`).
    private static var _familyListener: ListenerRegistration?
    
    /// Remote store used for outbound updates (family + child bundle).
    ///
    /// Note: kept as a computed property exactly as before (creates a new instance).
    private var familyRemote: FamilyRemoteStore { FamilyRemoteStore() }
    
    /// Starts realtime listener for the "family bundle" root document.
    ///
    /// Inbound behavior (unchanged):
    /// - Listens to `families/{familyId}`.
    /// - Applies LWW updates for family name/metadata using `updatedAt`.
    /// - Applies LWW updates for hero photo using `heroPhotoUpdatedAt` (fallback to `updatedAt`).
    /// - Creates a local `KBFamily` if missing.
    func startFamilyBundleRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startFamilyBundleRealtime familyId=\(familyId)")
        stopFamilyBundleRealtime()
        
        Self._familyListener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .addSnapshotListener { [weak self] snap, err in
                if let err {
                    KBLog.sync.kbError("Family listener error: \(err.localizedDescription)")
                    if let self, Self.isPermissionDenied(err) {
                        Task { @MainActor in
                            self.handleFamilyAccessLost(familyId: familyId, source: "family", error: err)
                        }
                    }
                    return
                }
                guard let snap, let data = snap.data() else {
                    KBLog.sync.kbDebug("Family listener snapshot/data nil familyId=\(familyId)")
                    return
                }
                
                let remoteName = data["name"] as? String ?? ""
                
                let remoteUpdatedAt =
                (data["updatedAt"] as? Timestamp)?.dateValue()
                ?? .distantPast
                
                let remoteUpdatedBy = data["updatedBy"] as? String
                
                // Hero fields (URL + crop)
                let remoteHeroURL = data["heroPhotoURL"] as? String
                let remoteHeroUpdatedAt = (data["heroPhotoUpdatedAt"] as? Timestamp)?.dateValue()
                
                let remoteHeroScale = data["heroPhotoScale"] as? Double
                let remoteHeroOffsetX = data["heroPhotoOffsetX"] as? Double
                let remoteHeroOffsetY = data["heroPhotoOffsetY"] as? Double
                
                KBLog.sync.kbDebug("Family snapshot received familyId=\(familyId)")
                
                Task { @MainActor in
                    do {
                        let fid = familyId
                        let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
                        
                        let fam = try modelContext.fetch(desc).first ?? {
                            let now = Date()
                            let created = KBFamily(
                                id: fid,
                                name: remoteName,
                                createdBy: remoteUpdatedBy ?? "remote",
                                updatedBy: remoteUpdatedBy ?? "remote",
                                createdAt: now,
                                updatedAt: remoteUpdatedAt
                            )
                            modelContext.insert(created)
                            KBLog.sync.kbDebug("Local family inserted familyId=\(fid)")
                            return created
                        }()
                        
                        // LWW: name/metadata
                        if remoteUpdatedAt >= fam.updatedAt {
                            fam.name = remoteName
                            fam.updatedAt = remoteUpdatedAt
                            fam.updatedBy = remoteUpdatedBy ?? fam.updatedBy
                        }
                        
                        // LWW: hero (fallback on updatedAt if heroPhotoUpdatedAt is missing)
                        let remoteHeroStamp = remoteHeroUpdatedAt ?? remoteUpdatedAt
                        let localHeroStamp = fam.heroPhotoUpdatedAt ?? .distantPast
                        
                        if remoteHeroStamp >= localHeroStamp {
                            fam.heroPhotoURL = remoteHeroURL
                            fam.heroPhotoUpdatedAt = remoteHeroStamp
                            
                            if let s = remoteHeroScale { fam.heroPhotoScale = s }
                            if let x = remoteHeroOffsetX { fam.heroPhotoOffsetX = x }
                            if let y = remoteHeroOffsetY { fam.heroPhotoOffsetY = y }
                        }
                        
                        try modelContext.save()
                        KBLog.sync.kbDebug("Family inbound applied + saved familyId=\(familyId)")
                        
                    } catch {
                        KBLog.sync.kbError("Family inbound apply failed: \(error.localizedDescription)")
                    }
                }
            }
        
        KBLog.sync.kbInfo("Family listener attached familyId=\(familyId)")
    }
    
    /// Stops the family root document listener if active.
    func stopFamilyBundleRealtime() {
        if Self._familyListener != nil {
            KBLog.sync.kbInfo("stopFamilyBundleRealtime")
        }
        Self._familyListener?.remove()
        Self._familyListener = nil
    }
    
    // MARK: - Enqueue (one op for family+child)
    
    /// Enqueues a single "bundle" upsert operation for family + first child.
    ///
    /// Behavior unchanged: stores an outbox op with entityType `.familyBundle`.
    func enqueueFamilyBundleUpsert(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueFamilyBundleUpsert familyId=\(familyId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.familyBundle.rawValue,
            entityId: familyId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process (called inside process(op:...))
    
    /// Processes the family bundle outbox operation.
    ///
    /// Behavior unchanged:
    /// - Bundle = family + first child (as used by UI assumptions).
    /// - If local family or first child missing => return.
    /// - Calls `FamilyRemoteStore.updateFamilyAndChild(...)`.
    func processFamilyBundle(op: KBSyncOp, modelContext: ModelContext) async throws {
        let fid = op.familyId
        KBLog.sync.kbDebug("processFamilyBundle start familyId=\(fid) opType=\(op.opType)")
        
        let fdesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        guard let fam = try modelContext.fetch(fdesc).first else {
            KBLog.sync.kbDebug("processFamilyBundle skipped: local family missing familyId=\(fid)")
            return
        }
        guard let child = fam.children.first else {
            KBLog.sync.kbDebug("processFamilyBundle skipped: local child missing familyId=\(fid)")
            return
        }
        
        let familyPayload = RemoteFamilyUpdatePayload(
            familyId: fam.id,
            name: fam.name
        )
        
        let childPayload = RemoteChildUpdatePayload(
            familyId: fam.id,
            childId: child.id,
            name: child.name,
            birthDate: child.birthDate
        )
        
        try await familyRemote.updateFamilyAndChild(
            family: familyPayload,
            child: childPayload
        )
        
        KBLog.sync.kbDebug("processFamilyBundle completed familyId=\(fid)")
    }
}
