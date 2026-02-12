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
    private static var _familyListener: ListenerRegistration?
    
    // Usa il tuo RemoteStore
    private var familyRemote: FamilyRemoteStore { FamilyRemoteStore() }
    
    func startFamilyBundleRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        stopFamilyBundleRealtime()
        
        // 1) family doc listener
        Self._familyListener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.error("Family listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap, let data = snap.data() else { return }
                
                let remoteName = data["name"] as? String ?? ""
                
                let remoteUpdatedAt =
                (data["updatedAt"] as? Timestamp)?.dateValue()
                ?? .distantPast
                
                let remoteUpdatedBy = data["updatedBy"] as? String
                
                // ✅ Hero fields (URL + crop)
                let remoteHeroURL = data["heroPhotoURL"] as? String
                let remoteHeroUpdatedAt = (data["heroPhotoUpdatedAt"] as? Timestamp)?.dateValue()
                
                let remoteHeroScale = data["heroPhotoScale"] as? Double
                let remoteHeroOffsetX = data["heroPhotoOffsetX"] as? Double
                let remoteHeroOffsetY = data["heroPhotoOffsetY"] as? Double
                
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
                                updatedBy: remoteUpdatedBy ?? "remote", createdAt: now,
                                updatedAt: remoteUpdatedAt
                            )
                            modelContext.insert(created)
                            return created
                        }()
                        
                        // ✅ LWW: name/metadata
                        if remoteUpdatedAt >= fam.updatedAt {
                            fam.name = remoteName
                            fam.updatedAt = remoteUpdatedAt
                            fam.updatedBy = remoteUpdatedBy ?? fam.updatedBy
                        }
                        
                        // ✅ LWW: hero (se manca heroPhotoUpdatedAt, fallback su updatedAt)
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
                    } catch {
                        KBLog.sync.error("Family inbound apply failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
    }
    
    func stopFamilyBundleRealtime() {
        Self._familyListener?.remove()
        Self._familyListener = nil
    }
    
    // MARK: - Enqueue (one op for family+child)
    
    func enqueueFamilyBundleUpsert(familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.familyBundle.rawValue,
            entityId: familyId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process (called inside process(op:...))
    
    func processFamilyBundle(op: KBSyncOp, modelContext: ModelContext) async throws {
        // Bundle = family + first child (coerente con come usi TodoListView: family?.children.first)
        let fid = op.familyId
        
        let fdesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        guard let fam = try modelContext.fetch(fdesc).first else { return }
        guard let child = fam.children.first else { return }
        
        // payload
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
        
        try await familyRemote.updateFamilyAndChild(family: familyPayload, child: childPayload)
    }
}
