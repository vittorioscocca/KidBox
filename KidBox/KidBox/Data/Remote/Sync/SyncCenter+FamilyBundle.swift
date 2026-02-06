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
    private static var _childListener: ListenerRegistration?
    
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
                        
                        guard let fam = try modelContext.fetch(desc).first else { return }
                        
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
                            // URL può essere nil se non impostata ancora
                            fam.heroPhotoURL = remoteHeroURL
                            fam.heroPhotoUpdatedAt = remoteHeroStamp
                            
                            // crop: se non ci sono valori, lascio i locali (non li azzero)
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
        
        // 2) children collection listener (single child for now: first child)
        Self._childListener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("children")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.error("Children listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap else { return }
                
                Task { @MainActor in
                    do {
                        // fetch family locale
                        let fid = familyId
                        let fdesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
                        guard let fam = try modelContext.fetch(fdesc).first else { return }
                        
                        for diff in snap.documentChanges {
                            let doc = diff.document
                            let data = doc.data()
                            let cid = doc.documentID
                            
                            let remoteName = data["name"] as? String ?? ""
                            let remoteBirthDate = (data["birthDate"] as? Timestamp)?.dateValue()
                            let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                            let remoteUpdatedBy = data["updatedBy"] as? String
                            let remoteIsDeleted = data["isDeleted"] as? Bool ?? false
                            
                            // ✅ fetch child by id (non dipendere da family.children materializzata)
                            let childId = cid
                            let cdesc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
                            let localChild = try modelContext.fetch(cdesc).first
                            
                            if let localChild {
                                // ✅ LWW robusto: se updatedAt manca, usa createdAt
                                let localStamp = (localChild.updatedAt ?? localChild.createdAt)
                                let remoteStamp = (remoteUpdatedAt ?? Date.distantPast)
                                
                                // Se remote non ha timestamp (non dovrebbe più dopo Patch 1),
                                // lo applichiamo comunque, perché è meglio che non vedere nulla.
                                if remoteUpdatedAt == nil || remoteStamp >= localStamp {
                                    localChild.name = remoteName
                                    localChild.birthDate = remoteBirthDate
                                    localChild.updatedAt = remoteUpdatedAt ?? Date()
                                    localChild.updatedBy = remoteUpdatedBy ?? localChild.updatedBy ?? "remote"
                                    
                                    // se hai isDeleted su KBChild, qui lo setti (tu non ce l’hai)
                                    // localChild.isDeleted = remoteIsDeleted
                                }
                                
                                // assicurati che sia legato alla family
                                if localChild.family == nil {
                                    localChild.family = fam
                                }
                                if !fam.children.contains(where: { $0.id == localChild.id }) {
                                    fam.children.append(localChild)
                                }
                                
                            } else {
                                // crea child e attacca alla family (se non deleted)
                                if remoteIsDeleted { continue }
                                
                                let now = Date()
                                let created = KBChild(
                                    id: cid,
                                    name: remoteName,
                                    birthDate: remoteBirthDate,
                                    createdBy: remoteUpdatedBy ?? "remote",
                                    createdAt: now,
                                    updatedBy: remoteUpdatedBy ?? "remote",
                                    updatedAt: remoteUpdatedAt ?? now
                                )
                                created.family = fam
                                created.updatedAt = remoteUpdatedAt ?? now
                                created.updatedBy = remoteUpdatedBy ?? "remote"
                                
                                fam.children.append(created)
                                modelContext.insert(created)
                            }
                        }
                        
                        try modelContext.save()
                    } catch {
                        KBLog.sync.error("Children inbound apply failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
    }
    
    func stopFamilyBundleRealtime() {
        Self._familyListener?.remove()
        Self._familyListener = nil
        Self._childListener?.remove()
        Self._childListener = nil
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
