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
    
    private static var _childrenListener: ListenerRegistration?
    
    func startChildrenRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        stopChildrenRealtime()
        
        Self._childrenListener = Firestore.firestore()
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
                    self.applyChildrenInbound(
                        familyId: familyId,
                        documentChanges: snap.documentChanges,
                        modelContext: modelContext
                    )
                }
            }
    }
    
    func stopChildrenRealtime() {
        Self._childrenListener?.remove()
        Self._childrenListener = nil
    }
    
    // MARK: - Apply inbound
    
    @MainActor
    private func applyChildrenInbound(
        familyId: String,
        documentChanges: [DocumentChange],
        modelContext: ModelContext
    ) {
        do {
            // 1) fetch family locale
            let fid = familyId
            let fdesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
            guard let fam = try modelContext.fetch(fdesc).first else { return }
            
            var didMutateAny = false
            
            for diff in documentChanges {
                let doc = diff.document
                let data = doc.data()
                let cid = doc.documentID
                
                // Se Firestore segnala removed, cancelliamo locale (hard delete)
                if diff.type == .removed {
                    let childId = cid
                    let cdesc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
                    if let local = try modelContext.fetch(cdesc).first {
                        modelContext.delete(local)
                        didMutateAny = true
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
                
                // 2) fetch child by id (non dipendere da fam.children materializzata)
                let childId = cid
                let cdesc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
                let localChild = try modelContext.fetch(cdesc).first
                
                // DELETE remoto (soft) => hard delete locale
                if remoteIsDeleted {
                    if let localChild {
                        modelContext.delete(localChild)
                        didMutateAny = true
                    }
                    continue
                }
                
                if let localChild {
                    var didMutate = false
                    
                    // LWW: confronto robusto (MA non inventiamo Date() se manca updatedAt remoto)
                    let localStamp = (localChild.updatedAt ?? localChild.createdAt)
                    let remoteStamp = (remoteUpdatedAt ?? remoteCreatedAt ?? .distantPast)
                    
                    // Applica solo se remoto è più recente
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
                        
                        // ✅ NON mettere Date() se remoteUpdatedAt è nil
                        if let rua = remoteUpdatedAt, localChild.updatedAt != rua {
                            localChild.updatedAt = rua
                            didMutate = true
                        }
                        
                        if let rub = remoteUpdatedBy, localChild.updatedBy != rub {
                            localChild.updatedBy = rub
                            didMutate = true
                        }
                    }
                    
                    // assicurati relazione (solo puntatore; NON toccare fam.children)
                    if localChild.family == nil {
                        localChild.family = fam
                        didMutate = true
                    }
                    
                    if didMutate { didMutateAny = true }
                    
                } else {
                    // create locale
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
                }
            }
            
            // ✅ salva solo se ci sono state mutazioni
            if didMutateAny {
                try modelContext.save()
            }
            
        } catch {
            KBLog.sync.error("Children inbound apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
