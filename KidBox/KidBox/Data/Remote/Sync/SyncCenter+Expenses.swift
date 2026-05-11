//
//  SyncCenter+Expenses.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseFirestore
import FirebaseAuth
import Combine

extension SyncCenter {
    
    // MARK: - Change Publisher
    //
    // Emesso da applyExpensesInbound dopo ogni save riuscito con cambiamenti effettivi.
    // ExpensesHomeView si subscribe e chiama vm.reload() per aggiornare
    // la UI (incluso MonthlyBarChartView) senza usare @Query.
    
    private static var _expensesChanged = PassthroughSubject<String, Never>()
    
    var expensesChanged: AnyPublisher<String, Never> {
        Self._expensesChanged.eraseToAnyPublisher()
    }
    
    func emitExpensesChanged(familyId: String) {
        KBLog.sync.kbDebug("📣 [expenses][publisher] emitExpensesChanged familyId=\(familyId)")
        Self._expensesChanged.send(familyId)
    }
    
    // MARK: - Realtime Listener (Inbound)
    
    func startExpensesRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("▶️ [expenses][listener] startExpensesRealtime familyId=\(familyId)")
        stopExpensesRealtime()
        
        // ── Seed categorie con ID deterministici ─────────────────────────────
        // Eseguito qui (oltre che nel VM) così le categorie sono pronte
        // prima che arrivi il primo batch inbound dal listener.
        // Gli ID deterministici (expcat-{familyId}-{slug}) garantiscono che
        // il categoryId di una spesa sincronizzata trovi sempre la categoria
        // locale → grafico a torta visibile su tutti i dispositivi.
        KBLog.sync.kbDebug("🌱 [expenses][listener] seeding categories familyId=\(familyId)")
        KBExpenseCategory.seedDefaults(familyId: familyId, context: modelContext)
        try? modelContext.save()
        
        // ── Seed cartella Documenti/Spese ─────────────────────────────────────
        // Crea la gerarchia root "Spese" in Documents in modo che esista
        // sul dispositivo ricevente PRIMA che arrivino allegati inbound.
        // Senza questo, ensureExpensesFolder veniva chiamato solo durante
        // upload() sul dispositivo mittente, mai sul ricevente.
        KBLog.sync.kbDebug("📁 [expenses][listener] ensuring Spese folder familyId=\(familyId)")
        _ = ExpenseAttachmentService.shared.ensureExpensesFolder(
            familyId:      familyId,
            expenseId:     "",       // stringa vuota = crea solo la root "Spese", non la subfolder
            expenseTitle:  "",
            modelContext:  modelContext
        )
        try? modelContext.save()
        // ─────────────────────────────────────────────────────────────────────
        
        expenseListener = expenseRemote.listen(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                guard !changes.isEmpty else {
                    KBLog.sync.kbDebug("⚠️ [expenses][listener] onChange: empty batch skipped familyId=\(familyId)")
                    return
                }
                KBLog.sync.kbInfo("📥 [expenses][listener] onChange: received changes=\(changes.count) familyId=\(familyId)")
                Task { @MainActor in
                    self.applyExpensesInbound(changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                KBLog.sync.kbError("❌ [expenses][listener] onError: \(err.localizedDescription) familyId=\(familyId)")
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "expenses", error: err)
                    }
                }
            }
        )
        KBLog.sync.kbInfo("✅ [expenses][listener] Listener attached familyId=\(familyId)")
    }
    
    func stopExpensesRealtime() {
        if expenseListener != nil {
            KBLog.sync.kbInfo("⏹️ [expenses][listener] stopExpensesRealtime")
        }
        expenseListener?.remove()
        expenseListener = nil
    }
    
    // MARK: - Apply inbound (LWW)
    
    func applyExpensesInbound(changes: [ExpenseRemoteChange], modelContext: ModelContext) {
        KBLog.sync.kbDebug("🔄 [expenses][inbound] applyExpensesInbound START changes=\(changes.count)")
        
        guard !isWipingLocalData else {
            KBLog.sync.kbDebug("⚠️ [expenses][inbound] skipped: wipe in progress")
            return
        }
        
        var resolvedFamilyId: String? = nil
        var appliedCount  = 0
        var skippedCount  = 0
        var deletedCount  = 0
        var createdCount  = 0
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    resolvedFamilyId = dto.familyId
                    let eid = dto.id
                    let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == eid })
                    let local = try modelContext.fetch(desc).first
                    let remoteStamp = dto.updatedAt
                    
                    if let local {
                        // Anti-resurrect
                        if local.syncStateRaw == KBSyncState.pendingDelete.rawValue {
                            KBLog.sync.kbDebug("🛡️ [expenses][inbound] anti-resurrect SKIP id=\(eid)")
                            skippedCount += 1
                            continue
                        }
                        
                        if remoteStamp >= local.updatedAt {
                            if dto.isDeleted {
                                KBLog.sync.kbDebug("🗑️ [expenses][inbound] remote isDeleted=true -> delete local id=\(eid)")
                                modelContext.delete(local)
                                deletedCount += 1
                            } else {
                                let previousDocId = local.attachedDocumentId
                                applyExpenseFields(local, from: dto)
                                local.syncState     = .synced
                                local.lastSyncError = nil
                                appliedCount += 1
                                KBLog.sync.kbDebug("✏️ [expenses][inbound] updated local id=\(eid) remoteStamp=\(remoteStamp)")
                                
                                if let newDocId = dto.attachedDocumentId,
                                   !newDocId.isEmpty,
                                   newDocId != previousDocId {
                                    KBLog.sync.kbDebug("📎 [expenses][inbound] new attachedDocumentId on update id=\(eid) docId=\(newDocId)")
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
                        } else {
                            KBLog.sync.kbDebug("⏩ [expenses][inbound] SKIP local is newer id=\(eid) localStamp=\(local.updatedAt) remoteStamp=\(remoteStamp)")
                            skippedCount += 1
                        }
                    } else {
                        if dto.isDeleted {
                            KBLog.sync.kbDebug("⏩ [expenses][inbound] SKIP remote isDeleted + local missing id=\(eid)")
                            skippedCount += 1
                            continue
                        }
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
                        createdCount += 1
                        KBLog.sync.kbDebug("➕ [expenses][inbound] created new expense id=\(eid) title='\(dto.title)' amount=\(dto.amount) categoryId=\(dto.categoryId ?? "nil")")
                        
                        if let attachedDocId = dto.attachedDocumentId, !attachedDocId.isEmpty {
                            KBLog.sync.kbDebug("📎 [expenses][inbound] kicking off attachment download for new expense id=\(eid) docId=\(attachedDocId)")
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
                        deletedCount += 1
                        KBLog.sync.kbDebug("🗑️ [expenses][inbound] .remove -> deleted local id=\(id)")
                    } else {
                        KBLog.sync.kbDebug("⏩ [expenses][inbound] .remove -> local not found id=\(id)")
                        skippedCount += 1
                    }
                }
            }
            
            try modelContext.save()
            
            KBLog.sync.kbInfo("""
            ✅ [expenses][inbound] SAVED \
            created=\(createdCount) \
            updated=\(appliedCount) \
            deleted=\(deletedCount) \
            skipped=\(skippedCount) \
            familyId=\(resolvedFamilyId ?? "unknown")
            """)
            
            // Notifica la UI solo se c'è stato almeno un cambiamento effettivo
            let hasChanges = (createdCount + appliedCount + deletedCount) > 0
            if hasChanges, let fid = resolvedFamilyId {
                KBLog.sync.kbInfo("📣 [expenses][inbound] emitting expensesChanged familyId=\(fid) (created=\(createdCount) updated=\(appliedCount) deleted=\(deletedCount))")
                emitExpensesChanged(familyId: fid)
            } else {
                KBLog.sync.kbDebug("⏩ [expenses][inbound] no effective changes, publisher NOT emitted")
            }
            
        } catch {
            KBLog.sync.kbError("❌ [expenses][inbound] FAILED: \(error.localizedDescription)")
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
            KBLog.sync.kbDebug("📎 [expenses][attachment] skip download (not ready or already cached) docId=\(docId)")
            return
        }
        
        KBLog.sync.kbInfo("📎 [expenses][attachment] starting download docId=\(docId) familyId=\(familyId)")
        await ExpenseAttachmentService.shared.downloadRemoteAttachment(
            docId:        doc.id,
            familyId:     familyId,
            storagePath:  doc.storagePath,
            fileName:     doc.fileName,
            notes:        doc.notes,
            modelContext: modelContext
        )
    }
    
    // MARK: - Outbox enqueue
    
    func enqueueExpenseUpsert(expenseId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("📤 [expenses][outbox] enqueueExpenseUpsert familyId=\(familyId) id=\(expenseId)")
        upsertOp(
            familyId:     familyId,
            entityType:   SyncEntityType.expense.rawValue,
            entityId:     expenseId,
            opType:       "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueExpenseDelete(expenseId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("📤 [expenses][outbox] enqueueExpenseDelete familyId=\(familyId) id=\(expenseId)")
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
        KBLog.sync.kbDebug("⚙️ [expenses][outbox] processExpense opType=\(op.opType) id=\(eid)")
        
        let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == eid })
        let expense = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let exp = expense else {
                KBLog.sync.kbDebug("⚠️ [expenses][outbox] upsert skip: expense missing id=\(eid)")
                return
            }
            exp.syncState     = .pendingUpsert
            exp.lastSyncError = nil
            try modelContext.save()
            
            KBLog.sync.kbDebug("📤 [expenses][outbox] upsert sending id=\(eid) title='\(exp.title)' amount=\(exp.amount) categoryId=\(exp.categoryId ?? "nil")")
            
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
            KBLog.sync.kbInfo("✅ [expenses][outbox] upsert OK id=\(eid)")
            
        case "delete":
            KBLog.sync.kbDebug("🗑️ [expenses][outbox] soft-delete remote id=\(eid)")
            try await expenseRemote.softDelete(familyId: op.familyId, expenseId: eid)
            
            if let exp = expense {
                modelContext.delete(exp)
                try modelContext.save()
                KBLog.sync.kbInfo("✅ [expenses][outbox] delete OK + hard-deleted local id=\(eid)")
            } else {
                KBLog.sync.kbDebug("⚠️ [expenses][outbox] delete OK but local expense already missing id=\(eid)")
            }
            
        default:
            KBLog.sync.kbDebug("⚠️ [expenses][outbox] unknown opType=\(op.opType) id=\(eid)")
        }
    }
}
