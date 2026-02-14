//
//  SyncCenter+DocumentsEvents.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData
import FirebaseFirestore

extension SyncCenter {
    
    // MARK: - Realtime (Inbound) Documents + Categories
    
    /// Shared listener for remote documents.
    private static var _docListener: ListenerRegistration?
    
    /// Shared listener for remote document categories.
    private static var _docCategoryListener: ListenerRegistration?
    
    /// Starts realtime listeners for:
    /// - `families/{familyId}/documentCategories`
    /// - `families/{familyId}/documents`
    ///
    /// Behavior (unchanged):
    /// - Stops existing listeners before starting new ones.
    /// - Categories are applied directly from snapshot `documentChanges`.
    /// - Documents are applied via `DocumentRemoteStore.listenDocuments(...)`.
    /// - Emits `docsChanged` after applying inbound changes.
    func startDocumentsRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("startDocumentsRealtime familyId=\(familyId)")
        stopDocumentsRealtime()
        
        // 1) Categories listener
        Self._docCategoryListener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("documentCategories")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("DocCategories listener error: \(err.localizedDescription)")
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("DocCategories snapshot nil familyId=\(familyId)")
                    return
                }
                
                KBLog.sync.kbDebug("DocCategories snapshot size=\(snap.documents.count) changes=\(snap.documentChanges.count) familyId=\(familyId)")
                
                Task { @MainActor in
                    do {
                        for diff in snap.documentChanges {
                            let doc = diff.document
                            let id = doc.documentID
                            
                            // HARD delete: Firestore removed => delete local category
                            if diff.type == .removed {
                                let cid = id
                                let desc = FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.id == cid })
                                if let local = try modelContext.fetch(desc).first {
                                    modelContext.delete(local)
                                    KBLog.sync.kbDebug("DocCategory removed locally categoryId=\(cid)")
                                }
                                continue
                            }
                            
                            // added/modified
                            let data = doc.data()
                            
                            let title = data["title"] as? String ?? "Categoria"
                            let sortOrder = data["sortOrder"] as? Int ?? 0
                            let parentId = data["parentId"] as? String
                            let isDeleted = data["isDeleted"] as? Bool ?? false
                            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                            let updatedBy = data["updatedBy"] as? String ?? "remote"
                            
                            let cid = id
                            let desc = FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.id == cid })
                            let local = try modelContext.fetch(desc).first
                            
                            if let local {
                                if updatedAt >= local.updatedAt {
                                    local.familyId = familyId
                                    local.title = title
                                    local.sortOrder = sortOrder
                                    local.parentId = parentId
                                    local.isDeleted = isDeleted
                                    local.updatedAt = updatedAt
                                    local.updatedBy = updatedBy
                                    local.syncState = .synced
                                    local.lastSyncError = nil
                                    
                                    KBLog.sync.kbDebug("DocCategory updated locally categoryId=\(cid)")
                                }
                            } else {
                                if isDeleted { continue }
                                
                                let created = KBDocumentCategory(
                                    id: id,
                                    familyId: familyId,
                                    title: title,
                                    sortOrder: sortOrder,
                                    parentId: parentId,
                                    updatedBy: updatedBy,
                                    createdAt: updatedAt == .distantPast ? Date() : updatedAt,
                                    updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                                    isDeleted: isDeleted
                                )
                                created.syncState = .synced
                                created.lastSyncError = nil
                                modelContext.insert(created)
                                
                                KBLog.sync.kbDebug("DocCategory inserted locally categoryId=\(cid)")
                            }
                        }
                        
                        try modelContext.save()
                        KBLog.sync.kbInfo("DocCategories inbound applied + saved familyId=\(familyId)")
                        
                        SyncCenter.shared.emitDocsChanged(familyId: familyId)
                        
                    } catch {
                        KBLog.sync.kbError("DocCategories inbound apply failed: \(error.localizedDescription)")
                    }
                }
            }
        
        // 2) Documents listener
        Self._docListener = documentRemote.listenDocuments(familyId: familyId) { [weak self] changes in
            guard let self else {
                KBLog.sync.kbError("Documents listener callback lost self (unexpected)")
                return
            }
            
            KBLog.sync.kbDebug("Documents onChange changes=\(changes.count) familyId=\(familyId)")
            
            Task { @MainActor in
                self.applyDocumentInbound(changes: changes, modelContext: modelContext)
                SyncCenter.shared.emitDocsChanged(familyId: familyId)
            }
        }
        
        KBLog.sync.kbInfo("Documents listeners attached familyId=\(familyId)")
    }
    
    /// Stops documents + documentCategories listeners if active.
    func stopDocumentsRealtime() {
        if Self._docListener != nil || Self._docCategoryListener != nil {
            KBLog.sync.kbInfo("stopDocumentsRealtime")
        }
        Self._docListener?.remove()
        Self._docListener = nil
        Self._docCategoryListener?.remove()
        Self._docCategoryListener = nil
    }
    
    // MARK: - Apply inbound (Documents)
    
    /// Applies inbound changes for documents to local SwiftData.
    ///
    /// Behavior (unchanged):
    /// - Upsert uses LWW based on `updatedAt` with a special placeholder rule:
    ///   if local doc is a placeholder (missing familyId or categoryId), remote always wins.
    /// - Remove deletes local record.
    /// - After apply, computes "broken" docs for debugging (familyId empty or categoryId missing/empty).
    private func applyDocumentInbound(changes: [DocumentRemoteChange], modelContext: ModelContext) {
        KBLog.sync.kbDebug("applyDocumentInbound changes=\(changes.count)")
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    let local = try fetchOrCreateDocument(id: dto.id, modelContext: modelContext)
                    
                    let remoteStamp = dto.updatedAt ?? Date.distantPast
                    let localStamp = local.updatedAt
                    
                    // placeholder: family empty OR categoryId nil/empty
                    let isPlaceholder =
                    local.familyId.isEmpty ||
                    local.categoryId == nil ||
                    local.categoryId?.isEmpty == true
                    
                    if isPlaceholder || dto.updatedAt == nil || remoteStamp >= localStamp {
                        local.familyId = dto.familyId
                        local.childId = dto.childId
                        local.categoryId = dto.categoryId
                        local.title = dto.title
                        local.fileName = dto.fileName
                        local.mimeType = dto.mimeType
                        local.fileSize = Int64(dto.fileSize)
                        local.storagePath = dto.storagePath
                        local.downloadURL = dto.downloadURL
                        local.isDeleted = dto.isDeleted
                        
                        local.updatedAt = remoteStamp
                        local.updatedBy = dto.updatedBy ?? local.updatedBy
                        
                        local.syncState = .synced
                        local.lastSyncError = nil
                    }
                    
                case .remove(let id):
                    if let existing = try fetchDocument(id: id, modelContext: modelContext) {
                        modelContext.delete(existing)
                    }
                }
            }
            
            // Debug counts: total + broken (no content)
            let all = try modelContext.fetch(FetchDescriptor<KBDocument>())
            let broken = all.filter {
                $0.familyId.isEmpty || ($0.categoryId?.isEmpty ?? true)
            }
            KBLog.sync.kbDebug("Documents local total=\(all.count) broken=\(broken.count)")
            
            try modelContext.save()
            KBLog.sync.kbInfo("Documents inbound applied + saved")
            
        } catch {
            KBLog.sync.kbError("Documents inbound apply failed: \(error.localizedDescription)")
        }
    }
    
    private func fetchDocument(id: String, modelContext: ModelContext) throws -> KBDocument? {
        let pid = id
        let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == pid })
        return try modelContext.fetch(desc).first
    }
    
    /// Fetches a local document by id or creates a placeholder row.
    ///
    /// Behavior (unchanged):
    /// - Placeholder has empty familyId and nil categoryId.
    /// - Timestamps are `.distantPast`.
    private func fetchOrCreateDocument(id: String, modelContext: ModelContext) throws -> KBDocument {
        if let existing = try fetchDocument(id: id, modelContext: modelContext) {
            return existing
        }
        
        let created = KBDocument(
            id: id,
            familyId: "",
            childId: nil,
            categoryId: nil,
            title: "",
            fileName: "",
            mimeType: "application/octet-stream",
            fileSize: 0,
            storagePath: "",
            downloadURL: nil,
            updatedBy: "remote",
            createdAt: .distantPast,
            updatedAt: .distantPast,
            isDeleted: false
        )
        created.syncState = .synced
        created.lastSyncError = nil
        modelContext.insert(created)
        return created
    }
    
    // MARK: - Outbox enqueue (Documents)
    
    /// Enqueues an outbox operation to upsert a document.
    func enqueueDocumentUpsert(documentId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueDocumentUpsert familyId=\(familyId) docId=\(documentId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.document.rawValue,
            entityId: documentId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    /// Enqueues an outbox operation to hard-delete a document.
    func enqueueDocumentDelete(documentId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueDocumentDelete familyId=\(familyId) docId=\(documentId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.document.rawValue,
            entityId: documentId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process (hook inside process(op:...))
    
    /// Processes a single outbox operation for documents.
    ///
    /// Behavior (unchanged):
    /// - For "upsert":
    ///   - mark local `.pendingUpsert`
    ///   - remote upsert
    ///   - mark local `.synced`
    /// - For "delete":
    ///   - remote hard delete
    ///   - local hard delete
    /// - For unknown opType: does nothing (kept as in original: `default: break`)
    func processDocument(op: KBSyncOp, modelContext: ModelContext, remote: DocumentRemoteStore) async throws {
        let did = op.entityId
        KBLog.sync.kbDebug("processDocument start familyId=\(op.familyId) docId=\(did) opType=\(op.opType)")
        
        let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
        let doc = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let doc else {
                KBLog.sync.kbDebug("processDocument upsert skipped: local doc missing docId=\(did)")
                return
            }
            
            doc.syncState = .pendingUpsert
            doc.lastSyncError = nil
            try modelContext.save()
            
            let dto = RemoteDocumentDTO(
                id: doc.id,
                familyId: doc.familyId,
                childId: doc.childId,
                categoryId: doc.categoryId,
                title: doc.title,
                fileName: doc.fileName,
                mimeType: doc.mimeType,
                fileSize: Int(doc.fileSize),
                storagePath: doc.storagePath,
                downloadURL: doc.downloadURL,
                isDeleted: doc.isDeleted,
                updatedAt: doc.updatedAt,
                updatedBy: doc.updatedBy
            )
            
            try await remote.upsert(dto: dto)
            
            doc.syncState = .synced
            doc.lastSyncError = nil
            try modelContext.save()
            
            KBLog.sync.kbDebug("processDocument upsert OK docId=\(did)")
            
        case "delete":
            try await remote.delete(
                familyId: op.familyId,
                docId: did
            )
            
            if let doc {
                modelContext.delete(doc)
                try modelContext.save()
                KBLog.sync.kbDebug("processDocument delete OK (local deleted) docId=\(did)")
            } else {
                KBLog.sync.kbDebug("processDocument delete OK (local missing) docId=\(did)")
            }
            
        default:
            // Keep original behavior (no throw)
            KBLog.sync.kbDebug("processDocument ignored unknown opType=\(op.opType) docId=\(did)")
            break
        }
    }
}
