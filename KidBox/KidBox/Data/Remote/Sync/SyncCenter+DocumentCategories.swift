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
    
    func enqueueDocumentCategoryUpsert(categoryId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.documentCategory.rawValue,
            entityId: categoryId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueDocumentCategoryDelete(categoryId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.documentCategory.rawValue,
            entityId: categoryId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process
    
    func processDocumentCategory(op: KBSyncOp, modelContext: ModelContext, remote: DocumentCategoryRemoteStore) async throws {
        let cid = op.entityId
        let desc = FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.id == cid })
        let cat = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let cat else { return }
            
            cat.syncState = .pendingUpsert
            cat.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteDocumentCategoryDTO(
                id: cat.id,
                familyId: cat.familyId,
                title: cat.title,
                sortOrder: cat.sortOrder,
                isDeleted: cat.isDeleted,
                updatedAt: cat.updatedAt,
                updatedBy: cat.updatedBy
            )
            
            try await remote.upsert(dto: dto)
            
            cat.syncState = .synced
            cat.lastSyncError = nil
            try modelContext.save()
            
        case "delete":
            try await remote.delete(
                familyId: op.familyId,
                categoryId: cid
            )
            
            if let cat {
                modelContext.delete(cat)
                try modelContext.save()
            }
            
        default:
            throw NSError(domain: "KidBox.Sync", code: -2200,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType: \(op.opType)"])
        }
    }
}
