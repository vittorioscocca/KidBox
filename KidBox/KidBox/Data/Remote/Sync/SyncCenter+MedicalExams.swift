//
//  SyncCenter+MedicalExams.swift
//  KidBox
//

// MARK: - Integrazioni manuali in SyncCenter.swift
// 1. Aggiungi a SyncEntityType:     case medicalExam = "medicalExam"
// 2. Aggiungi come property:        var medicalExamListener: ListenerRegistration?
//                                   let medicalExamRemote = MedicalExamRemoteStore()
// 3. In stopFamilyBundleRealtime()  stopMedicalExamsRealtime()
// 4. In process(op:) switch:        case SyncEntityType.medicalExam.rawValue:
//                                       try await processMedicalExam(op: op, modelContext: modelContext)

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Realtime listener
    
    func startMedicalExamsRealtime(familyId: String, childId: String, modelContext: ModelContext) {
        guard medicalExamListener == nil else { return }
        stopMedicalExamsRealtime()
        
        medicalExamListener = medicalExamRemote.listen(
            familyId: familyId,
            childId:  childId,
            onChange: { [weak self] dtos in
                guard let self else { return }
                Task { @MainActor in
                    self.applyMedicalExamsInbound(dtos: dtos, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "medicalExams", error: err)
                    }
                }
                KBLog.sync.kbError("MedicalExam listener error: \(err.localizedDescription)")
            }
        )
        KBLog.sync.kbInfo("MedicalExam realtime started familyId=\(familyId) childId=\(childId)")
    }
    
    func stopMedicalExamsRealtime() {
        medicalExamListener?.remove()
        medicalExamListener = nil
        KBLog.sync.kbInfo("MedicalExam realtime stopped")
    }
    
    // MARK: - Inbound (Firestore → SwiftData)  LWW + anti-resurrect
    
    func applyMedicalExamsInbound(dtos: [KBMedicalExamDTO], modelContext: ModelContext) {
        KBLog.sync.kbDebug("applyMedicalExamsInbound dtos=\(dtos.count)")
        
        do {
            for dto in dtos {
                let id   = dto.id
                let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == id })
                let local = try modelContext.fetch(desc).first
                
                let remoteStamp = dto.updatedAt
                
                if let local {
                    // Anti-resurrect: non sovrascrivere delete locale pendente
                    if local.isDeleted && local.syncState == .pendingUpsert {
                        KBLog.sync.kbDebug("applyMedicalExamsInbound skip anti-resurrect id=\(id)")
                        continue
                    }
                    
                    if remoteStamp >= local.updatedAt {
                        if dto.isDeleted {
                            modelContext.delete(local)
                            KBLog.sync.kbDebug("applyMedicalExamsInbound: deleted locally id=\(id)")
                        } else {
                            local.name               = dto.name
                            local.isUrgent           = dto.isUrgent
                            local.deadline           = dto.deadline
                            local.preparation        = dto.preparation
                            local.notes              = dto.notes
                            local.location           = dto.location   // ← NUOVO
                            local.statusRaw          = dto.statusRaw
                            local.resultText         = dto.resultText
                            local.resultDate         = dto.resultDate
                            local.prescribingVisitId = dto.prescribingVisitId
                            local.isDeleted          = dto.isDeleted
                            local.updatedAt          = remoteStamp
                            local.updatedBy          = dto.updatedBy
                            local.syncState          = .synced
                            local.lastSyncError      = nil
                        }
                    }
                } else {
                    if dto.isDeleted { continue }
                    let exam = KBMedicalExam(
                        id:                 dto.id,
                        familyId:           dto.familyId,
                        childId:            dto.childId,
                        name:               dto.name,
                        isUrgent:           dto.isUrgent,
                        deadline:           dto.deadline,
                        preparation:        dto.preparation,
                        notes:              dto.notes,
                        location:           dto.location,   // ← NUOVO
                        status:             KBExamStatus(rawValue: dto.statusRaw) ?? .pending,
                        resultText:         dto.resultText,
                        resultDate:         dto.resultDate,
                        prescribingVisitId: dto.prescribingVisitId,
                        createdAt:          dto.createdAt,
                        updatedAt:          remoteStamp,
                        updatedBy:          dto.updatedBy,
                        createdBy:          dto.createdBy
                    )
                    exam.id         = dto.id
                    exam.isDeleted  = false
                    exam.syncState  = .synced
                    modelContext.insert(exam)
                    KBLog.sync.kbDebug("applyMedicalExamsInbound: created examId=\(id)")
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbInfo("applyMedicalExamsInbound saved")
            
        } catch {
            KBLog.sync.kbError("applyMedicalExamsInbound failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueMedicalExamUpsert(examId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueMedicalExamUpsert familyId=\(familyId) id=\(examId)")
        upsertOp(
            familyId:   familyId,
            entityType: SyncEntityType.medicalExam.rawValue,
            entityId:   examId,
            opType:     "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueMedicalExamDelete(examId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueMedicalExamDelete familyId=\(familyId) id=\(examId)")
        upsertOp(
            familyId:   familyId,
            entityType: SyncEntityType.medicalExam.rawValue,
            entityId:   examId,
            opType:     "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process outbox op
    
    func processMedicalExam(op: KBSyncOp, modelContext: ModelContext) async throws {
        let eid  = op.entityId
        let desc = FetchDescriptor<KBMedicalExam>(predicate: #Predicate { $0.id == eid })
        let exam = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let e = exam else {
                KBLog.sync.kbDebug("processMedicalExam upsert skip: missing id=\(eid)")
                return
            }
            e.syncState     = .pendingUpsert
            e.lastSyncError = nil
            try modelContext.save()
            
            let dto = KBMedicalExamDTO(
                id:                 e.id,
                familyId:           e.familyId,
                childId:            e.childId,
                name:               e.name,
                isUrgent:           e.isUrgent,
                deadline:           e.deadline,
                preparation:        e.preparation,
                notes:              e.notes,
                location:           e.location,   // ← NUOVO
                statusRaw:          e.statusRaw,
                resultText:         e.resultText,
                resultDate:         e.resultDate,
                prescribingVisitId: e.prescribingVisitId,
                isDeleted:          e.isDeleted,
                createdAt:          e.createdAt,
                updatedAt:          e.updatedAt,
                updatedBy:          e.updatedBy,
                createdBy:          e.createdBy
            )
            try await medicalExamRemote.upsert(dto: dto)
            
            e.syncState     = .synced
            e.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processMedicalExam upsert OK id=\(eid)")
            
        case "delete":
            try await medicalExamRemote.softDelete(familyId: op.familyId, examId: eid)
            if let e = exam {
                modelContext.delete(e)
                try modelContext.save()
            }
            KBLog.sync.kbDebug("processMedicalExam delete OK id=\(eid)")
            
        default:
            KBLog.sync.kbDebug("processMedicalExam unknown opType=\(op.opType)")
        }
    }
}
