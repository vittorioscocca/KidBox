//
//  SyncCenter+DocumentCategories.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

extension SyncCenter {
    
    // MARK: - Outbox enqueue (Document Categories)
    
    /// Enqueues (or replaces) an outbox operation to upsert a document category.
    ///
    /// Behavior (unchanged):
    /// - Uses `upsertOp` to insert/update a `KBSyncOp` keyed by (familyId, entityType, entityId).
    func enqueueDocumentCategoryUpsert(categoryId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueDocumentCategoryUpsert familyId=\(familyId) categoryId=\(categoryId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.documentCategory.rawValue,
            entityId: categoryId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    /// Enqueues (or replaces) an outbox operation to hard-delete a document category remotely.
    ///
    /// Behavior (unchanged):
    /// - Uses `upsertOp` with opType "delete".
    func enqueueDocumentCategoryDelete(categoryId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueDocumentCategoryDelete familyId=\(familyId) categoryId=\(categoryId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.documentCategory.rawValue,
            entityId: categoryId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process
    
    /// Processes a single outbox operation for a document category.
    ///
    /// Behavior (unchanged):
    /// - For "upsert":
    ///   - marks local category as `.pendingUpsert`
    ///   - pushes DTO to Firestore (`remote.upsert`)
    ///   - marks local as `.synced`
    /// - For "delete":
    ///   - hard deletes remote doc (`remote.delete`)
    ///   - deletes local category if present
    ///
    /// - Throws: on unknown opType or remote failures.
    func processDocumentCategory(op: KBSyncOp, modelContext: ModelContext, remote: DocumentCategoryRemoteStore) async throws {
        let cid = op.entityId
        KBLog.sync.kbDebug("processDocumentCategory start familyId=\(op.familyId) categoryId=\(cid) opType=\(op.opType)")
        
        let desc = FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.id == cid })
        let cat = try modelContext.fetch(desc).first
        
        switch op.opType {
            
        case "upsert":
            guard let cat else {
                KBLog.sync.kbDebug("processDocumentCategory upsert skipped: local category missing categoryId=\(cid)")
                return
            }
            
            cat.syncState = .pendingUpsert
            cat.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteDocumentCategoryDTO(
                id: cat.id,
                familyId: cat.familyId,
                title: cat.title,
                sortOrder: cat.sortOrder,
                parentId: cat.parentId,
                isDeleted: cat.isDeleted,
                updatedAt: cat.updatedAt,
                updatedBy: cat.updatedBy
            )
            
            KBLog.sync.kbDebug("processDocumentCategory remote upsert categoryId=\(cid)")
            try await remote.upsert(dto: dto)
            
            cat.syncState = .synced
            cat.lastSyncError = nil
            try modelContext.save()
            
            KBLog.sync.kbDebug("processDocumentCategory upsert OK categoryId=\(cid)")
            
        case "delete":
            KBLog.sync.kbDebug("processDocumentCategory remote delete categoryId=\(cid)")
            try await remote.delete(
                familyId: op.familyId,
                categoryId: cid
            )
            
            if let cat {
                modelContext.delete(cat)
                try modelContext.save()
                KBLog.sync.kbDebug("processDocumentCategory delete OK (local deleted) categoryId=\(cid)")
            } else {
                KBLog.sync.kbDebug("processDocumentCategory delete OK (local missing) categoryId=\(cid)")
            }
            
        default:
            KBLog.sync.kbError("processDocumentCategory failed: unknown opType=\(op.opType)")
            throw NSError(
                domain: "KidBox.Sync",
                code: -2200,
                userInfo: [NSLocalizedDescriptionKey: "Unknown opType: \(op.opType)"]
            )
        }
    }
}
