//
//  SyncCenter+Calendar.swift
//  KidBox
//
//  Created by vscocca on 10/03/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Realtime Listener (Inbound)
    
    func startCalendarRealtime(
        familyId:     String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startCalendarRealtime familyId=\(familyId)")
        stopCalendarRealtime()
        
        calendarListener = calendarRemote.listen(
            familyId: familyId,
            onChange: { [weak self] dtos in
                guard let self else { return }
                Task { @MainActor in
                    self.applyCalendarInbound(dtos: dtos, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "calendar", error: err)
                    }
                }
            }
        )
    }
    
    func stopCalendarRealtime() {
        if calendarListener != nil {
            KBLog.sync.kbInfo("stopCalendarRealtime")
        }
        calendarListener?.remove()
        calendarListener = nil
    }
    
    // MARK: - Apply inbound (LWW)
    
    private func applyCalendarInbound(
        dtos:         [KBCalendarEventDTO],
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyCalendarInbound count=\(dtos.count)")
        
        do {
            for dto in dtos {
                let eid  = dto.id
                let desc = FetchDescriptor<KBCalendarEvent>(predicate: #Predicate { $0.id == eid })
                let local = try modelContext.fetch(desc).first
                
                let remoteStamp = dto.updatedAt
                
                if let local {
                    // 🛡️ Anti-resurrect: local pending-delete wins over remote upsert
                    if local.isDeleted && local.syncState == .pendingUpsert {
                        KBLog.sync.kbDebug("applyCalendarInbound: skip anti-resurrect id=\(eid)")
                        continue
                    }
                    
                    if remoteStamp >= local.updatedAt {
                        if dto.isDeleted {
                            modelContext.delete(local)
                            KBLog.sync.kbDebug("applyCalendarInbound: deleted locally id=\(eid)")
                        } else {
                            applyCalendarFields(local, from: dto)
                            local.syncState     = .synced
                            local.lastSyncError = nil
                        }
                    }
                } else {
                    guard !dto.isDeleted else { continue }
                    
                    let event = KBCalendarEvent(
                        id:              dto.id,
                        familyId:        dto.familyId,
                        childId:         dto.childId,
                        title:           dto.title,
                        notes:           dto.notes,
                        location:        dto.location,
                        startDate:       dto.startDate,
                        endDate:         dto.endDate,
                        isAllDay:        dto.isAllDay,
                        category:        KBEventCategory(rawValue: dto.categoryRaw) ?? .family,
                        recurrence:      KBEventRecurrence(rawValue: dto.recurrenceRaw) ?? .none,
                        reminderMinutes: dto.reminderMinutes,
                        isDeleted:       false,
                        createdAt:       dto.createdAt,
                        updatedAt:       remoteStamp,
                        updatedBy:       dto.updatedBy,
                        createdBy:       dto.createdBy
                    )
                    event.syncState = .synced
                    modelContext.insert(event)
                    KBLog.sync.kbDebug("applyCalendarInbound: created id=\(eid)")
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbInfo("applyCalendarInbound saved")
            
        } catch {
            KBLog.sync.kbError("applyCalendarInbound failed: \(error.localizedDescription)")
        }
    }
    
    private func applyCalendarFields(_ local: KBCalendarEvent, from dto: KBCalendarEventDTO) {
        local.childId          = dto.childId
        local.title            = dto.title
        local.notes            = dto.notes
        local.location         = dto.location
        local.startDate        = dto.startDate
        local.endDate          = dto.endDate
        local.isAllDay         = dto.isAllDay
        local.categoryRaw      = dto.categoryRaw
        local.recurrenceRaw    = dto.recurrenceRaw
        local.reminderMinutes  = dto.reminderMinutes
        local.isDeleted        = dto.isDeleted
        local.updatedAt        = dto.updatedAt
        local.updatedBy        = dto.updatedBy
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueCalendarUpsert(eventId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueCalendarUpsert familyId=\(familyId) eventId=\(eventId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.calendarEvent.rawValue,
                 entityId: eventId, opType: "upsert", modelContext: modelContext)
    }
    
    func enqueueCalendarDelete(eventId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueCalendarDelete familyId=\(familyId) eventId=\(eventId)")
        upsertOp(familyId: familyId, entityType: SyncEntityType.calendarEvent.rawValue,
                 entityId: eventId, opType: "delete", modelContext: modelContext)
    }
    
    // MARK: - Process outbox op
    
    func processCalendarEvent(op: KBSyncOp, modelContext: ModelContext) async throws {
        let eid  = op.entityId
        let desc = FetchDescriptor<KBCalendarEvent>(predicate: #Predicate { $0.id == eid })
        let event = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let e = event else {
                KBLog.sync.kbDebug("processCalendarEvent upsert skip: missing id=\(eid)")
                return
            }
            
            e.syncState     = .pendingUpsert
            e.lastSyncError = nil
            try modelContext.save()
            
            let dto = KBCalendarEventDTO(
                id:              e.id,
                familyId:        e.familyId,
                childId:         e.childId,
                title:           e.title,
                notes:           e.notes,
                location:        e.location,
                startDate:       e.startDate,
                endDate:         e.endDate,
                isAllDay:        e.isAllDay,
                categoryRaw:     e.categoryRaw,
                recurrenceRaw:   e.recurrenceRaw,
                reminderMinutes: e.reminderMinutes,
                isDeleted:       e.isDeleted,
                createdAt:       e.createdAt,
                updatedAt:       e.updatedAt,
                updatedBy:       e.updatedBy,
                createdBy:       e.createdBy
            )
            
            try await calendarRemote.upsert(dto: dto)
            
            e.syncState     = .synced
            e.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processCalendarEvent upsert OK id=\(eid)")
            
        case "delete":
            try await calendarRemote.softDelete(familyId: op.familyId, eventId: eid)
            if let e = event {
                modelContext.delete(e)
                try modelContext.save()
            }
            KBLog.sync.kbDebug("processCalendarEvent delete OK id=\(eid)")
            
        default:
            KBLog.sync.kbDebug("processCalendarEvent unknown opType=\(op.opType)")
        }
    }
}
