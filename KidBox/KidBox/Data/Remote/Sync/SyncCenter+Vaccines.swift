//
//  SyncCenter+Vaccines.swift
//  KidBox
//
//  Created by vscocca on 09/03/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Realtime Listener (Inbound)
    
    func startVaccinesRealtime(
        familyId: String,
        childId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startVaccinesRealtime familyId=\(familyId) childId=\(childId)")
        stopVaccinesRealtime()
        
        vaccineListener = vaccineRemote.listenVaccines(
            familyId: familyId,
            childId: childId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyVaccinesInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "vaccines", error: err)
                    }
                }
            }
        )
    }
    
    func stopVaccinesRealtime() {
        if vaccineListener != nil {
            KBLog.sync.kbInfo("stopVaccinesRealtime")
        }
        vaccineListener?.remove()
        vaccineListener = nil
    }
    
    // MARK: - Apply inbound (LWW)
    
    private func applyVaccinesInbound(
        changes: [VaccineRemoteChange],
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyVaccinesInbound changes=\(changes.count)")
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    let vid  = dto.id
                    let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
                    let local = try modelContext.fetch(desc).first
                    
                    let remoteStamp = dto.updatedAt ?? Date.distantPast
                    
                    if let local {
                        // 🛡️ Anti-resurrect
                        if local.isDeleted && local.syncState == .pendingUpsert {
                            KBLog.sync.kbDebug("applyVaccinesInbound: skip anti-resurrect id=\(vid)")
                            continue
                        }
                        
                        if remoteStamp >= local.updatedAt {
                            if dto.isDeleted {
                                modelContext.delete(local)
                                KBLog.sync.kbDebug("applyVaccinesInbound: deleted locally id=\(vid)")
                            } else {
                                applyVaccineFields(local, from: dto)
                                local.syncState     = .synced
                                local.lastSyncError = nil
                            }
                        }
                    } else {
                        guard !dto.isDeleted else { continue }
                        
                        let v = KBVaccine(
                            id:                    dto.id,
                            familyId:              dto.familyId,
                            childId:               dto.childId,
                            vaccineType:           VaccineType(rawValue: dto.vaccineTypeRaw) ?? .altro,
                            status:                VaccineStatus(rawValue: dto.statusRaw) ?? .administered,
                            commercialName:        dto.commercialName,
                            doseNumber:            dto.doseNumber,
                            totalDoses:            dto.totalDoses,
                            administeredDate:      dto.administeredDate,
                            scheduledDate:         dto.scheduledDate,
                            lotNumber:             dto.lotNumber,
                            administeredBy:        dto.administeredBy,
                            administrationSiteRaw: dto.administrationSiteRaw,
                            notes:                 dto.notes,
                            isDeleted:             false,
                            createdAt:             dto.createdAt ?? Date(),
                            updatedAt:             remoteStamp,
                            updatedBy:             dto.updatedBy,
                            createdBy:             dto.createdBy
                        )
                        v.syncState = .synced
                        modelContext.insert(v)
                        KBLog.sync.kbDebug("applyVaccinesInbound: created id=\(vid)")
                    }
                    
                case .remove(let id):
                    let vid  = id
                    let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
                    if let local = try modelContext.fetch(desc).first {
                        modelContext.delete(local)
                        KBLog.sync.kbDebug("applyVaccinesInbound: removed id=\(id)")
                    }
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbInfo("applyVaccinesInbound saved")
            
        } catch {
            KBLog.sync.kbError("applyVaccinesInbound failed: \(error.localizedDescription)")
        }
    }
    
    private func applyVaccineFields(_ local: KBVaccine, from dto: RemoteVaccineDTO) {
        local.vaccineTypeRaw        = dto.vaccineTypeRaw
        local.statusRaw             = dto.statusRaw
        local.commercialName        = dto.commercialName
        local.doseNumber            = dto.doseNumber
        local.totalDoses            = dto.totalDoses
        local.administeredDate      = dto.administeredDate
        local.scheduledDate         = dto.scheduledDate
        local.lotNumber             = dto.lotNumber
        local.administeredBy        = dto.administeredBy
        local.administrationSiteRaw = dto.administrationSiteRaw
        local.notes                 = dto.notes
        local.isDeleted             = dto.isDeleted
        local.updatedAt             = dto.updatedAt ?? local.updatedAt
        local.updatedBy             = dto.updatedBy
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueVaccineUpsert(vaccineId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVaccineUpsert familyId=\(familyId) vaccineId=\(vaccineId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.vaccine.rawValue,
                 entityId: vaccineId, opType: "upsert", modelContext: modelContext)
    }
    
    func enqueueVaccineDelete(vaccineId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueVaccineDelete familyId=\(familyId) vaccineId=\(vaccineId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.vaccine.rawValue,
                 entityId: vaccineId, opType: "delete", modelContext: modelContext)
    }
    
    // MARK: - Process outbox op
    
    func processVaccine(op: KBSyncOp, modelContext: ModelContext) async throws {
        let vid  = op.entityId
        let desc = FetchDescriptor<KBVaccine>(predicate: #Predicate { $0.id == vid })
        let vaccine = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let v = vaccine else {
                KBLog.sync.kbDebug("processVaccine upsert skip: missing id=\(vid)")
                return
            }
            
            v.syncState     = .pendingUpsert
            v.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteVaccineDTO(
                id:                    v.id,
                familyId:              v.familyId,
                childId:               v.childId,
                vaccineTypeRaw:        v.vaccineTypeRaw,
                statusRaw:             v.statusRaw,
                commercialName:        v.commercialName,
                doseNumber:            v.doseNumber,
                totalDoses:            v.totalDoses,
                administeredDate:      v.administeredDate,
                scheduledDate:         v.scheduledDate,
                lotNumber:             v.lotNumber,
                administeredBy:        v.administeredBy,
                administrationSiteRaw: v.administrationSiteRaw,
                notes:                 v.notes,
                isDeleted:             v.isDeleted,
                createdAt:             v.createdAt,
                updatedAt:             v.updatedAt,
                updatedBy:             v.updatedBy,
                createdBy:             v.createdBy
            )
            
            try await vaccineRemote.upsert(dto: dto)
            
            v.syncState     = .synced
            v.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processVaccine upsert OK id=\(vid)")
            
        case "delete":
            try await vaccineRemote.softDelete(familyId: op.familyId, vaccineId: vid)
            if let v = vaccine {
                modelContext.delete(v)
                try modelContext.save()
            }
            KBLog.sync.kbDebug("processVaccine delete OK id=\(vid)")
            
        default:
            KBLog.sync.kbDebug("processVaccine unknown opType=\(op.opType)")
        }
    }
}
