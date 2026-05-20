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
                        // Non sovrascrivere finché il push locale non è completato.
                        if local.syncState == .pendingUpsert {
                            KBLog.sync.kbDebug("applyPediatricProfileInbound: skip pending local childId=\(cid)")
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
                            doctorEmail: dto.doctorEmail,
                            doctorAddress: dto.doctorAddress,
                            doctorWebsite: dto.doctorWebsite,
                            updatedAt:   remoteStamp,
                            updatedBy:   dto.updatedBy
                        )
                        // Decodifica contatti emergenza dal JSON remoto
                        if let json = dto.emergencyContactsJSON,
                           let data = json.data(using: .utf8) {
                            p.emergencyContactsData = data
                        }
                        if let json = dto.doctorOfficeHoursJSON,
                           let data = json.data(using: .utf8) {
                            p.doctorOfficeHoursData = data
                        }
                        p.doctorAddress = dto.doctorAddress
                        p.doctorWebsite = dto.doctorWebsite
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
        local.doctorEmail   = dto.doctorEmail
        local.doctorAddress = dto.doctorAddress
        local.doctorWebsite = dto.doctorWebsite
        local.updatedAt     = dto.updatedAt ?? local.updatedAt
        local.updatedBy     = dto.updatedBy
        
        if let json = dto.emergencyContactsJSON,
           let data = json.data(using: .utf8) {
            local.emergencyContactsData = data
        }

        if let json = dto.doctorOfficeHoursJSON,
           let data = json.data(using: .utf8) {
            local.doctorOfficeHoursData = data
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
    
    // MARK: - Push immediato (scheda medica e outbox)

    /// Scrive la scheda su Firestore e marca il profilo come sincronizzato in locale.
    @MainActor
    func pushPediatricProfileToRemote(
        _ profile: KBPediatricProfile,
        modelContext: ModelContext
    ) async throws {
        let dto = remotePediatricProfileDTO(from: profile)
        try await pediatricProfileRemote.upsert(dto: dto)
        profile.syncState = .synced
        profile.lastSyncError = nil
        try modelContext.save()
        KBLog.sync.kbInfo("pushPediatricProfileToRemote OK childId=\(profile.childId)")
    }

    private func remotePediatricProfileDTO(from profile: KBPediatricProfile) -> RemotePediatricProfileDTO {
        let contactsJSON: String? = profile.emergencyContactsData.flatMap { String(data: $0, encoding: .utf8) }
        let officeHoursJSON: String? = profile.doctorOfficeHoursData.flatMap { String(data: $0, encoding: .utf8) }
        return RemotePediatricProfileDTO(
            id: profile.id,
            familyId: profile.familyId,
            childId: profile.childId,
            bloodGroup: profile.bloodGroup,
            allergies: profile.allergies,
            medicalNotes: profile.medicalNotes,
            doctorName: profile.doctorName,
            doctorPhone: profile.doctorPhone,
            doctorEmail: profile.doctorEmail,
            doctorAddress: profile.doctorAddress,
            doctorWebsite: profile.doctorWebsite,
            doctorOfficeHoursJSON: officeHoursJSON,
            emergencyContactsJSON: contactsJSON,
            isDeleted: false,
            updatedAt: profile.updatedAt,
            updatedBy: profile.updatedBy
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

            p.syncState = .pendingUpsert
            p.lastSyncError = nil
            try modelContext.save()

            try await pushPediatricProfileToRemote(p, modelContext: modelContext)
            KBLog.sync.kbDebug("processPediatricProfile upsert OK childId=\(cid)")

        default:
            KBLog.sync.kbDebug("processPediatricProfile unknown opType=\(op.opType)")
        }
    }
}
