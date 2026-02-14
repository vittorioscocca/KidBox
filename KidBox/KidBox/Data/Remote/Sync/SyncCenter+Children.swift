//
//  SyncCenter+Children.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth
import OSLog

extension SyncCenter {
    
    // MARK: - Realtime (Inbound) Children
    
    /// Shared listener for children realtime updates.
    ///
    /// Note:
    /// - Kept as `static` to ensure a single active listener even if `SyncCenter`
    ///   is referenced in multiple places.
    private static var _childrenListener: ListenerRegistration?
    
    /// Starts a realtime listener on `families/{familyId}/children`.
    ///
    /// Behavior (unchanged):
    /// - Stops any existing children listener.
    /// - Attaches a Firestore snapshot listener.
    /// - On each snapshot, dispatches inbound apply on MainActor.
    func startChildrenRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startChildrenRealtime familyId=\(familyId)")
        stopChildrenRealtime()
        
        Self._childrenListener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("children")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("Children listener error: \(err.localizedDescription)")
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("Children listener snapshot nil familyId=\(familyId)")
                    return
                }
                
                KBLog.sync.kbDebug("Children snapshot size=\(snap.documents.count) changes=\(snap.documentChanges.count) familyId=\(familyId)")
                
                Task { @MainActor in
                    self.applyChildrenInbound(
                        familyId: familyId,
                        documentChanges: snap.documentChanges,
                        modelContext: modelContext
                    )
                }
            }
        
        KBLog.sync.kbInfo("Children listener attached familyId=\(familyId)")
    }
    
    /// Stops the children realtime listener if active.
    func stopChildrenRealtime() {
        if Self._childrenListener != nil {
            KBLog.sync.kbInfo("stopChildrenRealtime")
        }
        Self._childrenListener?.remove()
        Self._childrenListener = nil
    }
    
    // MARK: - Apply inbound
    
    /// Applies inbound Firestore document changes for children into local SwiftData.
    ///
    /// Behavior (unchanged):
    /// - Loads local `KBFamily` for `familyId` (returns if missing).
    /// - For each change:
    ///   - `.removed` => hard delete local child
    ///   - `isDeleted == true` => hard delete local child
    ///   - otherwise upsert with LWW (remoteUpdatedAt/remoteCreatedAt vs local updated/created)
    /// - Ensures `child.family` relationship is set (does not mutate `fam.children` array).
    /// - Saves only if any mutation occurred.
    @MainActor
    private func applyChildrenInbound(
        familyId: String,
        documentChanges: [DocumentChange],
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyChildrenInbound start familyId=\(familyId) changes=\(documentChanges.count)")
        
        do {
            // 1) fetch local family
            let fid = familyId
            let fdesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
            guard let fam = try modelContext.fetch(fdesc).first else {
                KBLog.sync.kbDebug("applyChildrenInbound skipped: local family missing familyId=\(familyId)")
                return
            }
            
            var didMutateAny = false
            
            for diff in documentChanges {
                let doc = diff.document
                let data = doc.data()
                let cid = doc.documentID
                
                // Firestore removed => hard delete local
                if diff.type == .removed {
                    let childId = cid
                    let cdesc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
                    if let local = try modelContext.fetch(cdesc).first {
                        modelContext.delete(local)
                        didMutateAny = true
                        KBLog.sync.kbDebug("Child removed locally childId=\(childId)")
                    }
                    continue
                }
                
                let remoteName = data["name"] as? String ?? ""
                let remoteBirthDate = (data["birthDate"] as? Timestamp)?.dateValue()
                let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                let remoteUpdatedBy = data["updatedBy"] as? String
                let remoteCreatedAt = (data["createdAt"] as? Timestamp)?.dateValue()
                let remoteCreatedBy = data["createdBy"] as? String
                let remoteIsDeleted = data["isDeleted"] as? Bool ?? false
                
                // 2) fetch child by id (do not rely on fam.children)
                let childId = cid
                let cdesc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
                let localChild = try modelContext.fetch(cdesc).first
                
                // remote soft delete => hard delete local
                if remoteIsDeleted {
                    if let localChild {
                        modelContext.delete(localChild)
                        didMutateAny = true
                        KBLog.sync.kbDebug("Child soft-deleted remotely -> deleted locally childId=\(childId)")
                    }
                    continue
                }
                
                if let localChild {
                    var didMutate = false
                    
                    // LWW
                    let localStamp = (localChild.updatedAt ?? localChild.createdAt)
                    let remoteStamp = (remoteUpdatedAt ?? remoteCreatedAt ?? .distantPast)
                    
                    if remoteStamp >= localStamp {
                        if localChild.familyId != familyId {
                            localChild.familyId = familyId
                            didMutate = true
                        }
                        
                        if localChild.name != remoteName {
                            localChild.name = remoteName
                            didMutate = true
                        }
                        
                        if localChild.birthDate != remoteBirthDate {
                            localChild.birthDate = remoteBirthDate
                            didMutate = true
                        }
                        
                        if let ca = remoteCreatedAt, localChild.createdAt != ca {
                            localChild.createdAt = ca
                            didMutate = true
                        }
                        
                        if let cb = remoteCreatedBy, localChild.createdBy != cb {
                            localChild.createdBy = cb
                            didMutate = true
                        }
                        
                        // do not invent Date() if remoteUpdatedAt is nil
                        if let rua = remoteUpdatedAt, localChild.updatedAt != rua {
                            localChild.updatedAt = rua
                            didMutate = true
                        }
                        
                        if let rub = remoteUpdatedBy, localChild.updatedBy != rub {
                            localChild.updatedBy = rub
                            didMutate = true
                        }
                    }
                    
                    // ensure relationship pointer only (do not touch fam.children)
                    if localChild.family == nil {
                        localChild.family = fam
                        didMutate = true
                    }
                    
                    if didMutate {
                        didMutateAny = true
                        KBLog.sync.kbDebug("Child updated locally childId=\(childId)")
                    }
                    
                } else {
                    // create local
                    let now = Date()
                    let createdAt = remoteCreatedAt ?? now
                    
                    let created = KBChild(
                        id: cid,
                        familyId: familyId,
                        name: remoteName,
                        birthDate: remoteBirthDate,
                        createdBy: remoteCreatedBy ?? remoteUpdatedBy ?? "remote",
                        createdAt: createdAt,
                        updatedBy: remoteUpdatedBy,
                        updatedAt: remoteUpdatedAt
                    )
                    
                    created.family = fam
                    modelContext.insert(created)
                    didMutateAny = true
                    KBLog.sync.kbDebug("Child inserted locally childId=\(cid)")
                }
            }
            
            // Save only if any mutation occurred
            if didMutateAny {
                try modelContext.save()
                KBLog.sync.kbInfo("applyChildrenInbound saved familyId=\(familyId)")
            } else {
                KBLog.sync.kbDebug("applyChildrenInbound no changes to save familyId=\(familyId)")
            }
            
        } catch {
            KBLog.sync.kbError("Children inbound apply failed: \(error.localizedDescription)")
        }
    }
}
