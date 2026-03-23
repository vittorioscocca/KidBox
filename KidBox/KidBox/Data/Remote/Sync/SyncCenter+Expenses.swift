//
//  SyncCenter+Expenses.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth

extension SyncCenter {
    
    // MARK: - Realtime Listener (Inbound)
    
    func startExpensesRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startExpensesRealtime familyId=\(familyId)")
        stopExpensesRealtime()
        
        expenseListener = expenseRemote.listen(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                // FIX 1: Salta batch vuoti (allineato a SyncCenter+Visits che fa
                // `if !changes.isEmpty { onChange(changes) }` nel remote store).
                guard !changes.isEmpty else { return }
                Task { @MainActor in
                    self.applyExpensesInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "expenses", error: err)
                    }
                }
            }
        )
        KBLog.sync.kbInfo("Expenses listener attached familyId=\(familyId)")
    }
    
    func stopExpensesRealtime() {
        if expenseListener != nil { KBLog.sync.kbInfo("stopExpensesRealtime") }
        expenseListener?.remove()
        expenseListener = nil
    }
    
    // MARK: - Apply inbound (LWW)
    
    private func applyExpensesInbound(changes: [ExpenseRemoteChange], modelContext: ModelContext) {
        KBLog.sync.kbDebug("applyExpensesInbound changes=\(changes.count)")
        guard !isWipingLocalData else {
            KBLog.sync.kbDebug("applyExpensesInbound skipped: wipe in progress")
            return
        }
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    let eid = dto.id
                    let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == eid })
                    let local = try modelContext.fetch(desc).first
                    let remoteStamp = dto.updatedAt
                    
                    if let local {
                        // Anti-resurrect: pendingUpsert locale vince sul remoto
                        if local.isDeleted && local.syncState == .pendingUpsert {
                            KBLog.sync.kbDebug("applyExpensesInbound skip anti-resurrect id=\(eid)")
                            continue
                        }
                        if remoteStamp >= local.updatedAt {
                            if dto.isDeleted {
                                modelContext.delete(local)
                                KBLog.sync.kbDebug("applyExpensesInbound: deleted locally id=\(eid)")
                            } else {
                                let previousDocId = local.attachedDocumentId
                                applyExpenseFields(local, from: dto)
                                local.syncState     = .synced
                                local.lastSyncError = nil
                                
                                if let newDocId = dto.attachedDocumentId,
                                   !newDocId.isEmpty,
                                   newDocId != previousDocId {
                                    KBLog.sync.kbDebug("applyExpensesInbound: new attachedDocumentId on update id=\(eid) docId=\(newDocId)")
                                    Task { [weak self] in
                                        guard let self else { return }
                                        await self.downloadExpenseAttachmentIfNeeded(
                                            docId: newDocId,
                                            familyId: dto.familyId,
                                            modelContext: modelContext
                                        )
                                    }
                                }
                            }
                        }
                    } else {
                        if dto.isDeleted { continue }
                        let exp = KBExpense(
                            familyId:           dto.familyId,
                            title:              dto.title,
                            amount:             dto.amount,
                            date:               dto.date,
                            categoryId:         dto.categoryId,
                            notes:              dto.notes,
                            attachedDocumentId: dto.attachedDocumentId,
                            createdByUid:       dto.createdByUid
                        )
                        exp.id            = dto.id
                        exp.createdAt     = dto.createdAt
                        exp.updatedAt     = dto.updatedAt
                        exp.updatedBy     = dto.updatedBy
                        exp.isDeleted     = false
                        exp.syncState     = .synced
                        exp.lastSyncError = nil
                        modelContext.insert(exp)
                        KBLog.sync.kbDebug("applyExpensesInbound: created expenseId=\(eid)")
                        
                        if let attachedDocId = dto.attachedDocumentId, !attachedDocId.isEmpty {
                            KBLog.sync.kbDebug("applyExpensesInbound: kicking off attachment download for new expense id=\(eid) docId=\(attachedDocId)")
                            Task { [weak self] in
                                guard let self else { return }
                                await self.downloadExpenseAttachmentIfNeeded(
                                    docId: attachedDocId,
                                    familyId: dto.familyId,
                                    modelContext: modelContext
                                )
                            }
                        }
                    }
                    
                case .remove(let id):
                    let eid = id
                    let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == eid })
                    if let local = try modelContext.fetch(desc).first {
                        modelContext.delete(local)
                        KBLog.sync.kbDebug("applyExpensesInbound: removed id=\(id)")
                    }
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbInfo("applyExpensesInbound saved")
            
        } catch {
            KBLog.sync.kbError("applyExpensesInbound failed: \(error.localizedDescription)")
        }
    }
    
    private func applyExpenseFields(_ local: KBExpense, from dto: RemoteExpenseDTO) {
        local.title              = dto.title
        local.amount             = dto.amount
        local.date               = dto.date
        local.categoryId         = dto.categoryId
        local.notes              = dto.notes
        local.attachedDocumentId = dto.attachedDocumentId
        local.isDeleted          = dto.isDeleted
        local.updatedAt          = dto.updatedAt
        local.updatedBy          = dto.updatedBy
    }
    
    // MARK: - Auto-download allegato spesa (inbound)
    
    private func downloadExpenseAttachmentIfNeeded(
        docId: String,
        familyId: String,
        modelContext: ModelContext
    ) async {
        let did = docId
        let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
        guard let doc = (try? modelContext.fetch(desc))?.first,
              !doc.isDeleted,
              let dlURL = doc.downloadURL, !dlURL.isEmpty,
              doc.localPath == nil || doc.localPath!.isEmpty
        else {
            KBLog.sync.kbDebug("downloadExpenseAttachmentIfNeeded: skip (not ready or already cached) docId=\(docId)")
            return
        }
        
        KBLog.sync.kbInfo("downloadExpenseAttachmentIfNeeded: starting download docId=\(docId)")
        await ExpenseAttachmentService.shared.downloadRemoteAttachment(
            docId:        doc.id,
            familyId:     familyId,
            storagePath:  doc.storagePath,
            fileName:     doc.fileName,
            modelContext: modelContext
        )
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueExpenseUpsert(expenseId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueExpenseUpsert familyId=\(familyId) id=\(expenseId)")
        upsertOp(
            familyId:     familyId,
            entityType:   SyncEntityType.expense.rawValue,
            entityId:     expenseId,
            opType:       "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueExpenseDelete(expenseId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueExpenseDelete familyId=\(familyId) id=\(expenseId)")
        upsertOp(
            familyId:     familyId,
            entityType:   SyncEntityType.expense.rawValue,
            entityId:     expenseId,
            opType:       "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process outbox op
    
    func processExpense(op: KBSyncOp, modelContext: ModelContext) async throws {
        let eid = op.entityId
        let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == eid })
        let expense = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let exp = expense else {
                KBLog.sync.kbDebug("processExpense upsert skip: missing id=\(eid)")
                return
            }
            exp.syncState     = .pendingUpsert
            exp.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteExpenseDTO(
                id:                 exp.id,
                familyId:           exp.familyId,
                title:              exp.title,
                amount:             exp.amount,
                date:               exp.date,
                categoryId:         exp.categoryId,
                notes:              exp.notes,
                attachedDocumentId: exp.attachedDocumentId,
                isDeleted:          exp.isDeleted,
                createdByUid:       exp.createdByUid,
                updatedBy:          exp.updatedBy ?? Auth.auth().currentUser?.uid ?? "local",
                createdAt:          exp.createdAt,
                updatedAt:          exp.updatedAt
            )
            try await expenseRemote.upsert(dto: dto)
            
            exp.syncState     = .synced
            exp.lastSyncError = nil
            try modelContext.save()
            KBLog.sync.kbDebug("processExpense upsert OK id=\(eid)")
            
        case "delete":
            try await expenseRemote.softDelete(familyId: op.familyId, expenseId: eid)
            // FIX 2: Elimina il record locale dopo il soft-delete remoto,
            // esattamente come fa processVisit. Senza questo, la spesa rimane
            // in SwiftData con isDeleted=true e syncState=pendingUpsert,
            // bloccando l'anti-resurrect per tutti i successivi inbound.
            if let exp = expense {
                modelContext.delete(exp)
                try modelContext.save()
            }
            KBLog.sync.kbDebug("processExpense delete OK id=\(eid)")
            
        default:
            KBLog.sync.kbDebug("processExpense unknown opType=\(op.opType)")
        }
    }
}
