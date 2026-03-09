//
//  SyncCenter+Visits.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//


import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Realtime Listener (Inbound)
    
    func startVisitsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startVisitsRealtime familyId=\(familyId)")
        stopVisitsRealtime()
        
        visitListener = visitRemote.listenAllVisits(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyVisitsInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "visits", error: err)
                    }
                }
            }
        )
        KBLog.sync.kbInfo("Visits listener attached familyId=\(familyId)")
    }
    
    func stopVisitsRealtime() {
        if visitListener != nil { KBLog.sync.kbInfo("stopVisitsRealtime") }
        visitListener?.remove()
        visitListener = nil
    }
    
    // MARK: - Apply inbound
    
    private func applyVisitsInbound(changes: [VisitRemoteChange], modelContext: ModelContext) {
        KBLog.sync.kbDebug("applyVisitsInbound changes=\(changes.count)")
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    let vid = dto.id
                    let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
                    let local = try modelContext.fetch(desc).first
                    let remoteStamp = dto.updatedAt ?? Date.distantPast
                    
                    if let local {
                        // Anti-resurrect
                        if local.isDeleted && local.syncState == .pendingUpsert {
                            KBLog.sync.kbDebug("applyVisitsInbound skip anti-resurrect id=\(vid)")
                            continue
                        }
                        if remoteStamp >= local.updatedAt {
                            if dto.isDeleted {
                                modelContext.delete(local)
                                KBLog.sync.kbDebug("applyVisitsInbound: deleted locally id=\(vid)")
                            } else {
                                applyVisitFields(local, from: dto)
                                local.syncState     = .synced
                                local.lastSyncError = nil
                            }
                        }
                    } else {
                        if dto.isDeleted { continue }
                        let v = KBMedicalVisit(
                            familyId:          dto.familyId,
                            childId:           dto.childId,
                            date:              dto.date,
                            doctorName:        dto.doctorName,
                            reason:            dto.reason,
                            diagnosis:         dto.diagnosis,
                            recommendations:   dto.recommendations,
                            photoURLs:         dto.photoURLs,
                            notes:             dto.notes,
                            nextVisitDate:     dto.nextVisitDate,
                            nextVisitReason:   dto.nextVisitReason,
                            createdAt:         dto.createdAt ?? Date(),
                            updatedAt:         remoteStamp,
                            updatedBy:         dto.updatedBy,
                            createdBy:         dto.createdBy ?? dto.updatedBy
                        )
                        v.id                      = dto.id
                        v.doctorSpecializationRaw = dto.doctorSpecializationRaw
                        v.linkedTreatmentIds      = dto.linkedTreatmentIds
                        v.therapyTypesRaw         = dto.therapyTypesRaw
                        v.travelDetailsData       = dto.travelDetailsData
                        v.asNeededDrugsData       = dto.asNeededDrugsData
                        v.prescribedExamsData     = dto.prescribedExamsData
                        v.isDeleted               = false
                        v.syncState               = .synced
                        modelContext.insert(v)
                        KBLog.sync.kbDebug("applyVisitsInbound: created visitId=\(vid)")
                    }
                    
                case .remove(let id):
                    let vid = id
                    let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
                    if let local = try modelContext.fetch(desc).first {
                        modelContext.delete(local)
                        KBLog.sync.kbDebug("applyVisitsInbound: removed visitId=\(id)")
                    }
                }
            }
            try modelContext.save()
            KBLog.sync.kbInfo("applyVisitsInbound saved")
        } catch {
            KBLog.sync.kbError("applyVisitsInbound failed: \(error.localizedDescription)")
        }
    }
    
    private func applyVisitFields(_ local: KBMedicalVisit, from dto: RemoteVisitDTO) {
        local.date                    = dto.date
        local.doctorName              = dto.doctorName
        local.doctorSpecializationRaw = dto.doctorSpecializationRaw
        local.travelDetailsData       = dto.travelDetailsData
        local.reason                  = dto.reason
        local.diagnosis               = dto.diagnosis
        local.recommendations         = dto.recommendations
        local.linkedTreatmentIds      = dto.linkedTreatmentIds
        local.asNeededDrugsData       = dto.asNeededDrugsData
        local.therapyTypesRaw         = dto.therapyTypesRaw
        local.prescribedExamsData     = dto.prescribedExamsData
        local.photoURLs               = dto.photoURLs
        local.notes                   = dto.notes
        local.nextVisitDate           = dto.nextVisitDate
        local.nextVisitReason         = dto.nextVisitReason
        local.isDeleted               = dto.isDeleted
        local.updatedAt               = dto.updatedAt ?? local.updatedAt
        local.updatedBy               = dto.updatedBy
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueVisitUpsert(visitId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVisitUpsert familyId=\(familyId) id=\(visitId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.visit.rawValue,
                 entityId: visitId, opType: "upsert", modelContext: modelContext)
    }
    
    func enqueueVisitDelete(visitId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVisitDelete familyId=\(familyId) id=\(visitId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.visit.rawValue,
                 entityId: visitId, opType: "delete", modelContext: modelContext)
    }
    
    // MARK: - Process outbox op
    
    func processVisit(op: KBSyncOp, modelContext: ModelContext) async throws {
        let vid = op.entityId
        let desc = FetchDescriptor<KBMedicalVisit>(predicate: #Predicate { $0.id == vid })
        let visit = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let v = visit else {
                KBLog.sync.kbDebug("processVisit upsert skip: missing id=\(vid)")
                return
            }
            v.syncState = .pendingUpsert; v.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteVisitDTO(
                id:                      v.id,
                familyId:                v.familyId,
                childId:                 v.childId,
                date:                    v.date,
                doctorName:              v.doctorName,
                doctorSpecializationRaw: v.doctorSpecializationRaw,
                travelDetailsData:       v.travelDetailsData,
                reason:                  v.reason,
                diagnosis:               v.diagnosis,
                recommendations:         v.recommendations,
                linkedTreatmentIds:      v.linkedTreatmentIds,
                linkedExamIds:           v.linkedExamIds ,
                asNeededDrugsData:       v.asNeededDrugsData,
                therapyTypesRaw:         v.therapyTypesRaw,
                prescribedExamsData:     v.prescribedExamsData,
                photoURLs:               v.photoURLs,
                notes:                   v.notes,
                nextVisitDate:           v.nextVisitDate,
                nextVisitReason:         v.nextVisitReason,
                isDeleted:               v.isDeleted,
                createdBy:               v.createdBy,
                updatedBy:               v.updatedBy ?? "local",
                createdAt:               v.createdAt,
                updatedAt:               v.updatedAt
            )
            try await visitRemote.upsertVisit(dto)
            v.syncState = .synced; v.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processVisit upsert OK id=\(vid)")
            
        case "delete":
            try await visitRemote.deleteVisit(familyId: op.familyId, visitId: vid)
            if let v = visit { modelContext.delete(v); try modelContext.save() }
            KBLog.sync.kbDebug("processVisit delete OK id=\(vid)")
            
        default:
            KBLog.sync.kbDebug("processVisit unknown opType=\(op.opType)")
        }
    }
}
