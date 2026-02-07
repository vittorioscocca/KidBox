//
//  SyncCenter+DocumentsEvents.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData
import FirebaseFirestore
import OSLog

extension SyncCenter {
    
    // MARK: - Realtime (Inbound) Documents + Categories
    
    private static var _docListener: ListenerRegistration?
    private static var _docCategoryListener: ListenerRegistration?
    
    func startDocumentsRealtime(
        familyId: String,
        modelContext: ModelContext
    ) {
        stopDocumentsRealtime()
        
        // 1) Categories listener
        Self._docCategoryListener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("documentCategories")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.error("DocCategories listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap else { return }
                
                Task { @MainActor in
                    do {
                        for diff in snap.documentChanges {
                            let doc = diff.document
                            let id = doc.documentID
                            
                            // ✅ HARD delete: se la categoria è stata cancellata su Firestore,
                            // Firestore manda diff.type == .removed -> noi cancelliamo la categoria locale
                            if diff.type == .removed {
                                let cid = id
                                let desc = FetchDescriptor<KBDocumentCategory>(predicate: #Predicate { $0.id == cid })
                                if let local = try modelContext.fetch(desc).first {
                                    modelContext.delete(local)
                                }
                                continue
                            }
                            
                            // ---- qui sotto è il tuo codice attuale (added/modified) ----
                            let data = doc.data()
                            
                            let title = data["title"] as? String ?? "Categoria"
                            let sortOrder = data["sortOrder"] as? Int ?? 0
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
                                    local.isDeleted = isDeleted
                                    local.updatedAt = updatedAt
                                    local.updatedBy = updatedBy
                                    local.syncState = .synced
                                    local.lastSyncError = nil
                                }
                            } else {
                                if isDeleted { continue }
                                let created = KBDocumentCategory(
                                    id: id,
                                    familyId: familyId,
                                    title: title,
                                    sortOrder: sortOrder,
                                    updatedBy: updatedBy,
                                    createdAt: updatedAt == .distantPast ? Date() : updatedAt,
                                    updatedAt: updatedAt == .distantPast ? Date() : updatedAt,
                                    isDeleted: isDeleted
                                )
                                created.syncState = .synced
                                created.lastSyncError = nil
                                modelContext.insert(created)
                            }
                        }
                        
                        try modelContext.save()
                    } catch {
                        KBLog.sync.error("DocCategories inbound apply failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        
        // 2) Documents listener
        Self._docListener = documentRemote.listenDocuments(familyId: familyId) { [weak self] changes in
            print("➡️ DOC onChange fired, changes =", changes.count)
            guard let self else {
                print("❌ self nil inside doc listener (should NOT happen)")
                return
            }
            Task { @MainActor in
                print("➡️ calling applyDocumentInbound")
                self.applyDocumentInbound(changes: changes, modelContext: modelContext)
            }
        }
    }
    
    func stopDocumentsRealtime() {
        Self._docListener?.remove()
        Self._docListener = nil
        Self._docCategoryListener?.remove()
        Self._docCategoryListener = nil
    }
    
    // MARK: - Apply inbound (Documents)
    
    private func applyDocumentInbound(changes: [DocumentRemoteChange], modelContext: ModelContext) {
        print("🧩 applyDocumentInbound changes =", changes.count)
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    let local = try fetchOrCreateDocument(id: dto.id, modelContext: modelContext)
                    
                    print("DOC DTO id=\(dto.id) family=\(dto.familyId) cat=\(dto.categoryId) deleted=\(dto.isDeleted)")
                    
                    let remoteStamp = dto.updatedAt ?? Date.distantPast
                    let localStamp = local.updatedAt
                    
                    // ✅ Se è placeholder (family/category vuoti) applica SEMPRE,
                    // altrimenti fai LWW normale.
                    let isPlaceholder = local.familyId.isEmpty || local.categoryId.isEmpty
                    
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
            
            print("🧩 inbound changes =", changes.count)
            for c in changes {
                if case let .upsert(dto) = c {
                    print("📄 dto id=\(dto.id) family=\(dto.familyId) cat=\(dto.categoryId) deleted=\(dto.isDeleted)")
                }
            }
            
            // ✅ Debug: quanti documenti sono “rotti” (non agganciati a family/category)
            let all = try modelContext.fetch(FetchDescriptor<KBDocument>())
            let broken = all.filter { $0.familyId.isEmpty || $0.categoryId.isEmpty }
            print("💾 LOCAL total docs =", all.count)
            print("🧪 docs broken =", broken.count)
            
            try modelContext.save()
            
        } catch {
            KBLog.sync.error("Documents inbound apply failed: \(error.localizedDescription, privacy: .public)")
            print("❌ applyDocumentInbound FAILED:", error.localizedDescription)
        }
    }
    
    private func fetchDocument(id: String, modelContext: ModelContext) throws -> KBDocument? {
        let pid = id
        let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == pid })
        return try modelContext.fetch(desc).first
    }
    
    private func fetchOrCreateDocument(id: String, modelContext: ModelContext) throws -> KBDocument {
        if let existing = try fetchDocument(id: id, modelContext: modelContext) {
            return existing
        }
        
        let created = KBDocument(
            id: id,
            familyId: "",
            childId: nil,
            categoryId: "",
            title: "",
            fileName: "",
            mimeType: "application/octet-stream",
            fileSize: 0,
            storagePath: "",
            downloadURL: nil,
            updatedBy: "remote",
            createdAt: .distantPast,     // ✅
            updatedAt: .distantPast,     // ✅
            isDeleted: false
        )
        created.syncState = .synced
        created.lastSyncError = nil
        modelContext.insert(created)
        return created
    }
    
    // MARK: - Outbox enqueue (Documents)
    
    func enqueueDocumentUpsert(documentId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.document.rawValue,
            entityId: documentId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueDocumentDelete(documentId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.document.rawValue,
            entityId: documentId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    // MARK: - Process (hook inside process(op:...))
    
    func processDocument(op: KBSyncOp, modelContext: ModelContext, remote: DocumentRemoteStore) async throws {
        let did = op.entityId
        let desc = FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })
        let doc = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let doc else { return }
            
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
            
        case "delete":
            try await remote.delete(
                familyId: op.familyId,
                docId: did
            )
            
            // locale: elimina davvero
            if let doc {
                modelContext.delete(doc)
                try modelContext.save()
            }
            
        default:
            break
        }
    }
}
