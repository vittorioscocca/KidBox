//
//  SyncCenter+PediatricProfile.swift
//  KidBox
//
//  Created by vscocca on 09/03/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Listener var (aggiungi in SyncCenter.swift)
    // var pediatricProfileListener: ListenerRegistration?
    // let pediatricProfileRemote = PediatricProfileRemoteStore()
    
    // MARK: - Realtime Listener (Inbound)
    
    func startPediatricProfileRealtime(
        familyId: String,
        childId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startPediatricProfileRealtime familyId=\(familyId) childId=\(childId)")
        stopPediatricProfileRealtime()
        
        pediatricProfileListener = pediatricProfileRemote.listenProfile(
            familyId: familyId,
            childId: childId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyPediatricProfileInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "pediatricProfile", error: err)
                    }
                }
            }
        )
    }
    
    func stopPediatricProfileRealtime() {
        if pediatricProfileListener != nil {
            KBLog.sync.kbInfo("stopPediatricProfileRealtime")
        }
        pediatricProfileListener?.remove()
        pediatricProfileListener = nil
    }
    
    // MARK: - Apply inbound (LWW)
    
    private func applyPediatricProfileInbound(
        changes: [PediatricProfileRemoteChange],
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyPediatricProfileInbound changes=\(changes.count)")
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    let cid = dto.childId
                    let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
                    let local = try modelContext.fetch(desc).first
                    
                    let remoteStamp = dto.updatedAt ?? Date.distantPast
                    
                    if let local {
                        // 🛡️ Anti-resurrect: non sovrascrivere se c'è una write locale pendente
                        if local.syncState == .pendingUpsert && local.updatedAt > remoteStamp {
                            KBLog.sync.kbDebug("applyPediatricProfileInbound: skip anti-resurrect childId=\(cid)")
                            continue
                        }
                        
                        if remoteStamp >= local.updatedAt {
                            if dto.isDeleted {
                                modelContext.delete(local)
                                KBLog.sync.kbDebug("applyPediatricProfileInbound: deleted locally childId=\(cid)")
                            } else {
                                applyProfileFields(local, from: dto)
                                local.syncState     = .synced
                                local.lastSyncError = nil
                            }
                        }
                    } else {
                        guard !dto.isDeleted else { continue }
                        
                        let p = KBPediatricProfile(
                            childId:     dto.childId,
                            familyId:    dto.familyId,
                            bloodGroup:  dto.bloodGroup,
                            allergies:   dto.allergies,
                            medicalNotes: dto.medicalNotes,
                            doctorName:  dto.doctorName,
                            doctorPhone: dto.doctorPhone,
                            updatedAt:   remoteStamp,
                            updatedBy:   dto.updatedBy
                        )
                        // Decodifica contatti emergenza dal JSON remoto
                        if let json = dto.emergencyContactsJSON,
                           let data = json.data(using: .utf8) {
                            p.emergencyContactsData = data
                        }
                        p.syncState = .synced
                        modelContext.insert(p)
                        KBLog.sync.kbDebug("applyPediatricProfileInbound: created childId=\(cid)")
                    }
                    
                case .remove(let id):
                    let cid = id
                    let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
                    if let local = try modelContext.fetch(desc).first {
                        modelContext.delete(local)
                        KBLog.sync.kbDebug("applyPediatricProfileInbound: removed childId=\(id)")
                    }
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbInfo("applyPediatricProfileInbound saved")
            
        } catch {
            KBLog.sync.kbError("applyPediatricProfileInbound failed: \(error.localizedDescription)")
        }
    }
    
    private func applyProfileFields(_ local: KBPediatricProfile, from dto: RemotePediatricProfileDTO) {
        local.bloodGroup    = dto.bloodGroup
        local.allergies     = dto.allergies
        local.medicalNotes  = dto.medicalNotes
        local.doctorName    = dto.doctorName
        local.doctorPhone   = dto.doctorPhone
        local.updatedAt     = dto.updatedAt ?? local.updatedAt
        local.updatedBy     = dto.updatedBy
        
        if let json = dto.emergencyContactsJSON,
           let data = json.data(using: .utf8) {
            local.emergencyContactsData = data
        } else if dto.emergencyContactsJSON == nil {
            local.emergencyContactsData = nil
        }
    }
    
    // MARK: - Outbox enqueue
    
    func enqueuePediatricProfileUpsert(childId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueuePediatricProfileUpsert familyId=\(familyId) childId=\(childId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.pediatricProfile.rawValue,
            entityId: childId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process outbox op
    
    func processPediatricProfile(op: KBSyncOp, modelContext: ModelContext) async throws {
        let cid = op.entityId
        let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
        let profile = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let p = profile else {
                KBLog.sync.kbDebug("processPediatricProfile upsert skip: missing childId=\(cid)")
                return
            }
            
            p.syncState     = .pendingUpsert
            p.lastSyncError = nil
            try modelContext.save()
            
            // Serializza emergencyContacts in JSON string per Firestore
            let contactsJSON: String?
            if let data = p.emergencyContactsData {
                contactsJSON = String(data: data, encoding: .utf8)
            } else {
                contactsJSON = nil
            }
            
            let dto = RemotePediatricProfileDTO(
                id:                    p.id,
                familyId:              p.familyId,
                childId:               p.childId,
                bloodGroup:            p.bloodGroup,
                allergies:             p.allergies,
                medicalNotes:          p.medicalNotes,
                doctorName:            p.doctorName,
                doctorPhone:           p.doctorPhone,
                emergencyContactsJSON: contactsJSON,
                isDeleted:             false,
                updatedAt:             p.updatedAt,
                updatedBy:             p.updatedBy
            )
            
            try await pediatricProfileRemote.upsert(dto: dto)
            
            p.syncState     = .synced
            p.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processPediatricProfile upsert OK childId=\(cid)")
            
        default:
            KBLog.sync.kbDebug("processPediatricProfile unknown opType=\(op.opType)")
        }
    }
}
