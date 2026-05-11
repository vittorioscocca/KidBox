//
//  SyncCenter+Treatments.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Realtime Listener (Inbound)
    
    func startTreatmentsRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startTreatmentsRealtime familyId=\(familyId)")
        stopTreatmentsRealtime()
        
        // Listener Treatments — tutti i child della famiglia
        treatmentListener = treatmentRemote.listenAllTreatments(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyTreatmentsInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "treatments", error: err)
                    }
                }
            }
        )
        
        // Listener DoseLogs — tutti i child della famiglia
        doseLogListener = treatmentRemote.listenAllDoseLogs(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyDoseLogsInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "doseLogs", error: err)
                    }
                }
            }
        )
        
        KBLog.sync.kbInfo("Treatments + DoseLogs listeners attached familyId=\(familyId)")
    }
    
    func stopTreatmentsRealtime() {
        if treatmentListener != nil || doseLogListener != nil {
            KBLog.sync.kbInfo("stopTreatmentsRealtime")
        }
        treatmentListener?.remove()
        treatmentListener = nil
        doseLogListener?.remove()
        doseLogListener = nil
    }
    
    /// `childId` della cura coincide con l'id di un `KBChild` in famiglia (profilo bambino). Per gli adulti è il `userId` del membro — nessun `KBChild` con quell'id.
    private func isPediatricHealthSubject(childId: String, familyId: String, modelContext: ModelContext) -> Bool {
        let cid = childId
        let fid = familyId
        let desc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == cid && $0.familyId == fid })
        return (try? modelContext.fetch(desc).first) != nil
    }
    
    // MARK: - Apply inbound (Treatments)

    private func applyTreatmentsInbound(
        changes: [TreatmentRemoteChange],
        modelContext: ModelContext
    ) {
        guard !changes.isEmpty else { return }
        KBLog.sync.kbDebug("applyTreatmentsInbound changes=\(changes.count)")

        do {
            // Bulk fetch: 2 queries total instead of O(n) queries.
            let familyId = changes.lazy.compactMap {
                if case .upsert(let dto) = $0 { return dto.familyId } else { return nil }
            }.first ?? ""

            var byId: [String: KBTreatment] = [:]
            var pediatricChildIds: Set<String> = []
            if !familyId.isEmpty {
                let fid = familyId
                let allT = try modelContext.fetch(
                    FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.familyId == fid })
                )
                for t in allT { byId[t.id] = t }

                let allC = try modelContext.fetch(
                    FetchDescriptor<KBChild>(predicate: #Predicate { $0.familyId == fid })
                )
                pediatricChildIds = Set(allC.map(\.id))
            }

            for change in changes {
                switch change {

                case .upsert(let dto):
                    let remoteStamp = dto.updatedAt ?? Date.distantPast

                    if let local = byId[dto.id] {
                        if local.isDeleted && local.syncState == .pendingUpsert {
                            KBLog.sync.kbDebug("applyTreatmentsInbound skip anti-resurrect id=\(dto.id)")
                            continue
                        }
                        if remoteStamp >= local.updatedAt {
                            if dto.isDeleted {
                                modelContext.delete(local)
                                byId.removeValue(forKey: dto.id)
                                KBLog.sync.kbDebug("applyTreatmentsInbound: deleted locally id=\(dto.id)")
                            } else {
                                applyTreatmentFields(local, from: dto,
                                                     isPediatric: pediatricChildIds.contains(dto.childId))
                                local.syncState     = .synced
                                local.lastSyncError = nil
                            }
                        }
                    } else {
                        if dto.isDeleted { continue }
                        let isPediatric = pediatricChildIds.contains(dto.childId)
                        let t = KBTreatment(
                            familyId:           dto.familyId,
                            childId:            dto.childId,
                            drugName:           dto.drugName,
                            activeIngredient:   dto.activeIngredient,
                            dosageValue:        dto.dosageValue,
                            dosageUnit:         dto.dosageUnit,
                            isLongTerm:         dto.isLongTerm,
                            durationDays:       dto.durationDays,
                            startDate:          dto.startDate,
                            endDate:            dto.endDate,
                            dailyFrequency:     dto.dailyFrequency,
                            scheduleTimes:      dto.scheduleTimes,
                            isActive:           dto.isActive,
                            notes:              dto.notes,
                            reminderEnabled:    isPediatric ? dto.reminderEnabled : false,
                            createdAt:          dto.createdAt ?? Date(),
                            updatedAt:          remoteStamp,
                            updatedBy:          dto.updatedBy,
                            createdBy:          dto.createdBy ?? dto.updatedBy,
                            prescribingVisitId: dto.prescribingVisitId
                        )
                        t.id        = dto.id
                        t.isDeleted = false
                        t.syncState = .synced
                        modelContext.insert(t)
                        byId[t.id] = t
                        KBLog.sync.kbDebug("applyTreatmentsInbound: created treatmentId=\(dto.id)")
                    }

                case .remove(let id):
                    if let local = byId[id] {
                        modelContext.delete(local)
                        byId.removeValue(forKey: id)
                        KBLog.sync.kbDebug("applyTreatmentsInbound: removed treatmentId=\(id)")
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbInfo("applyTreatmentsInbound saved")

        } catch {
            KBLog.sync.kbError("applyTreatmentsInbound failed: \(error.localizedDescription)")
        }
    }

    private func applyTreatmentFields(_ local: KBTreatment, from dto: RemoteTreatmentDTO, isPediatric: Bool) {
        local.drugName           = dto.drugName
        local.activeIngredient   = dto.activeIngredient
        local.dosageValue        = dto.dosageValue
        local.dosageUnit         = dto.dosageUnit
        local.isLongTerm         = dto.isLongTerm
        local.durationDays       = dto.durationDays
        local.startDate          = dto.startDate
        local.endDate            = dto.endDate
        local.dailyFrequency     = dto.dailyFrequency
        local.scheduleTimes      = dto.scheduleTimes
        local.isActive           = dto.isActive
        local.isDeleted          = dto.isDeleted
        local.notes              = dto.notes
        local.prescribingVisitId = dto.prescribingVisitId
        if isPediatric { local.reminderEnabled = dto.reminderEnabled }
        local.updatedAt          = dto.updatedAt ?? local.updatedAt
        local.updatedBy          = dto.updatedBy
    }
    
    // MARK: - Apply inbound (DoseLogs)
    
    private func applyDoseLogsInbound(
        changes: [DoseLogRemoteChange],
        modelContext: ModelContext
    ) {
        guard !changes.isEmpty else { return }
        KBLog.sync.kbDebug("applyDoseLogsInbound changes=\(changes.count)")

        do {
            // Bulk fetch: 1 query instead of O(n) queries (was ~304 queries for 152 items).
            let familyId = changes.lazy.compactMap {
                if case .upsert(let dto) = $0 { return dto.familyId } else { return nil }
            }.first ?? ""

            var byId: [String: KBDoseLog] = [:]
            // key = "treatmentId_dayNumber_slotIndex" for compound-key lookups
            var bySlot: [String: [KBDoseLog]] = [:]
            if !familyId.isEmpty {
                let fid = familyId
                let all = try modelContext.fetch(
                    FetchDescriptor<KBDoseLog>(predicate: #Predicate { $0.familyId == fid })
                )
                for item in all {
                    byId[item.id] = item
                    let key = "\(item.treatmentId)_\(item.dayNumber)_\(item.slotIndex)"
                    bySlot[key, default: []].append(item)
                }
            }

            for change in changes {
                switch change {

                case .upsert(let dto):
                    if dto.isDeleted {
                        let key = "\(dto.treatmentId)_\(dto.dayNumber)_\(dto.slotIndex)"
                        for r in bySlot[key, default: []] {
                            modelContext.delete(r)
                            byId.removeValue(forKey: r.id)
                        }
                        bySlot.removeValue(forKey: key)
                        continue
                    }

                    let remoteStamp = dto.updatedAt ?? Date.distantPast

                    if let local = byId[dto.id] {
                        if local.isDeleted && local.syncState == .pendingUpsert { continue }
                        let localIsRecent = local.updatedAt.timeIntervalSince(remoteStamp) > -30
                        if localIsRecent && local.taken && !dto.taken {
                            KBLog.sync.kbDebug("applyDoseLogsInbound skip anti-overwrite id=\(dto.id)")
                            continue
                        }
                        if remoteStamp >= local.updatedAt {
                            local.taken         = dto.taken
                            local.takenAt       = dto.takenAt
                            local.isDeleted     = false
                            local.updatedAt     = remoteStamp
                            local.updatedBy     = dto.updatedBy ?? local.updatedBy
                            local.syncState     = .synced
                            local.lastSyncError = nil
                        }
                    } else {
                        // Remove any duplicates occupying the same slot (in-memory)
                        let key = "\(dto.treatmentId)_\(dto.dayNumber)_\(dto.slotIndex)"
                        for dup in bySlot[key, default: []] where dup.id != dto.id {
                            modelContext.delete(dup)
                            byId.removeValue(forKey: dup.id)
                        }
                        bySlot[key] = []

                        let log = KBDoseLog(
                            id:            dto.id,
                            familyId:      dto.familyId,
                            childId:       dto.childId,
                            treatmentId:   dto.treatmentId,
                            dayNumber:     dto.dayNumber,
                            slotIndex:     dto.slotIndex,
                            scheduledTime: dto.scheduledTime,
                            takenAt:       dto.takenAt,
                            taken:         dto.taken,
                            createdAt:     dto.createdAt ?? Date(),
                            updatedAt:     remoteStamp,
                            updatedBy:     dto.updatedBy
                        )
                        log.isDeleted = false
                        log.syncState = .synced
                        modelContext.insert(log)
                        byId[log.id] = log
                        bySlot[key] = [log]
                    }

                case .remove(let id):
                    if let local = byId[id] {
                        modelContext.delete(local)
                        byId.removeValue(forKey: id)
                    }
                }
            }

            try modelContext.save()
            KBLog.sync.kbInfo("applyDoseLogsInbound saved")

        } catch {
            KBLog.sync.kbError("applyDoseLogsInbound failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueTreatmentUpsert(treatmentId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueTreatmentUpsert familyId=\(familyId) id=\(treatmentId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.treatment.rawValue,
                 entityId: treatmentId, opType: "upsert", modelContext: modelContext)
    }
    
    func enqueueTreatmentDelete(treatmentId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueTreatmentDelete familyId=\(familyId) id=\(treatmentId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.treatment.rawValue,
                 entityId: treatmentId, opType: "delete", modelContext: modelContext)
    }
    
    func enqueueDoseLogUpsert(logId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueDoseLogUpsert familyId=\(familyId) id=\(logId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.doseLog.rawValue,
                 entityId: logId, opType: "upsert", modelContext: modelContext)
    }
    
    func enqueueDoseLogDelete(logId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueDoseLogDelete familyId=\(familyId) id=\(logId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.doseLog.rawValue,
                 entityId: logId, opType: "delete", modelContext: modelContext)
    }
    
    // MARK: - Process outbox ops
    
    func processTreatment(op: KBSyncOp, modelContext: ModelContext) async throws {
        let tid = op.entityId
        let desc = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.id == tid })
        let treatment = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let t = treatment else {
                KBLog.sync.kbDebug("processTreatment upsert skip: missing id=\(tid)")
                return
            }
            t.syncState = .pendingUpsert
            t.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteTreatmentDTO(
                id:               t.id,
                familyId:         t.familyId,
                childId:          t.childId,
                prescribingVisitId: t.prescribingVisitId,
                drugName:         t.drugName,
                activeIngredient: t.activeIngredient,
                dosageValue:      t.dosageValue,
                dosageUnit:       t.dosageUnit,
                isLongTerm:       t.isLongTerm,
                durationDays:     t.durationDays,
                startDate:        t.startDate,
                endDate:          t.endDate,
                dailyFrequency:   t.dailyFrequency,
                scheduleTimes:    t.scheduleTimes,
                isActive:         t.isActive,
                isDeleted:        t.isDeleted,
                notes:            t.notes,
                reminderEnabled:  t.reminderEnabled,
                createdBy:        t.createdBy,
                updatedBy:        t.updatedBy ?? "local",
                createdAt:        t.createdAt,
                updatedAt:        t.updatedAt
            )
            let syncReminder = isPediatricHealthSubject(
                childId: t.childId, familyId: t.familyId, modelContext: modelContext
            )
            try await treatmentRemote.upsertTreatment(dto, syncReminderEnabledToRemote: syncReminder)
            
            t.syncState = .synced
            t.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processTreatment upsert OK id=\(tid)")
            
        case "delete":
            try await treatmentRemote.deleteTreatment(familyId: op.familyId, treatmentId: tid)
            if let t = treatment {
                modelContext.delete(t)
                try modelContext.save()
            }
            KBLog.sync.kbDebug("processTreatment delete OK id=\(tid)")
            
        default:
            KBLog.sync.kbDebug("processTreatment unknown opType=\(op.opType)")
        }
    }
    
    func processDoseLog(op: KBSyncOp, modelContext: ModelContext) async throws {
        let lid = op.entityId
        let desc = FetchDescriptor<KBDoseLog>(predicate: #Predicate { $0.id == lid })
        let log = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let l = log else {
                KBLog.sync.kbDebug("processDoseLog upsert skip: missing id=\(lid)")
                return
            }
            l.syncState = .pendingUpsert
            try modelContext.save()
            
            let dto = RemoteDoseLogDTO(
                id:            l.id,
                familyId:      l.familyId,
                childId:       l.childId,
                treatmentId:   l.treatmentId,
                dayNumber:     l.dayNumber,
                slotIndex:     l.slotIndex,
                scheduledTime: l.scheduledTime,
                takenAt:       l.takenAt,
                taken:         l.taken,
                isDeleted:     l.isDeleted,
                updatedBy:     l.updatedBy,
                createdAt:     l.createdAt,
                updatedAt:     l.updatedAt
            )
            try await treatmentRemote.upsertDoseLog(dto)
            
            l.syncState = .synced
            l.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processDoseLog upsert OK id=\(lid)")
            
        case "delete":
            try await treatmentRemote.deleteDoseLog(familyId: op.familyId, logId: lid)
            if let l = log {
                modelContext.delete(l)
                try modelContext.save()
            }
            KBLog.sync.kbDebug("processDoseLog delete OK id=\(lid)")
            
        default:
            KBLog.sync.kbDebug("processDoseLog unknown opType=\(op.opType)")
        }
    }
}
