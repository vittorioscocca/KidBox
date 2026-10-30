//
//  WorkAttachmentService.swift
//  KidBox
//
//  Il file originale di una busta paga o di un contratto: un `KBDocument`
//  cifrato (cartella «Lavoro» in Documenti) con visibilità **privata**, e tag
//  `work:{uid}`. Stesso flusso di `VehicleAttachmentService`.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseStorage

enum WorkAttachmentTag {
    static func make(_ ownerUid: String) -> String { "work:\(ownerUid)" }
}

@MainActor
final class WorkAttachmentService {

    static let shared = WorkAttachmentService()
    private init() {}

    private static func rootId(familyId: String) -> String { "work-root-\(familyId)" }

    private func ensureFolder(familyId: String, modelContext: ModelContext) -> KBDocumentCategory {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let rid = Self.rootId(familyId: familyId)
        let desc = FetchDescriptor<KBDocumentCategory>(
            predicate: #Predicate<KBDocumentCategory> { $0.id == rid && $0.isDeleted == false }
        )
        if let existing = try? modelContext.fetch(desc).first { return existing }

        let folder = KBDocumentCategory(
            id: rid, familyId: familyId, title: "Lavoro", sortOrder: 89, parentId: nil,
            updatedBy: uid, createdAt: Date(), updatedAt: Date(), isDeleted: false
        )
        modelContext.insert(folder)
        try? modelContext.save()
        SyncCenter.shared.enqueueDocumentCategoryUpsert(categoryId: folder.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        return folder
    }

    /// Carica il file e ritorna l'id del `KBDocument` (privato).
    func upload(data: Data, fileName: String, mimeType: String, title: String,
                ownerUid: String, familyId: String, modelContext: ModelContext) -> String? {
        let uid = Auth.auth().currentUser?.uid ?? ownerUid
        let now = Date()
        let docId = UUID().uuidString
        let storagePath = "families/\(familyId)/documents/\(docId)/\(fileName).kbenc"
        let folder = ensureFolder(familyId: familyId, modelContext: modelContext)

        guard let encrypted = try? DocumentCryptoService.encrypt(data, familyId: familyId, userId: uid),
              let localRelPath = try? DocumentLocalCache.write(familyId: familyId, docId: docId, fileName: fileName, data: encrypted)
        else {
            KBLog.storage.kbError("Work attachment encrypt/cache failed docId=\(docId)")
            return nil
        }

        let doc = KBDocument(
            id: docId, familyId: familyId, childId: nil, categoryId: folder.id,
            title: title, fileName: fileName, mimeType: mimeType, fileSize: Int64(data.count),
            storagePath: storagePath, downloadURL: nil,
            notes: WorkAttachmentTag.make(ownerUid),
            visibilityScope: KBVisibilityScope.onlyCreator, visibilityMemberIds: [],
            createdBy: uid, updatedBy: uid, createdAt: now, updatedAt: now, isDeleted: false
        )
        doc.localPath = localRelPath
        doc.syncState = .pendingUpsert
        modelContext.insert(doc)
        try? modelContext.save()

        SyncCenter.shared.enqueueDocumentUpsert(documentId: doc.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        Task.detached {
            do {
                let ref = Storage.storage().reference(withPath: storagePath)
                let metadata = StorageMetadata()
                metadata.contentType = "application/octet-stream"
                metadata.customMetadata = [
                    "kb_encrypted": "1", "kb_alg": "AES-GCM",
                    "kb_orig_mime": mimeType, "kb_orig_name": fileName,
                ]
                _ = try await ref.putDataAsync(encrypted, metadata: metadata)
                let downloadURL = try await ref.downloadURL().absoluteString
                await MainActor.run {
                    doc.downloadURL = downloadURL
                    doc.syncState = .synced
                    doc.updatedAt = Date()
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    doc.syncState = .error
                    doc.lastSyncError = error.localizedDescription
                    try? modelContext.save()
                }
            }
        }
        return docId
    }

    func delete(documentId: String, familyId: String, modelContext: ModelContext) {
        let did = documentId
        guard let doc = try? modelContext.fetch(FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })).first else { return }
        let path = doc.storagePath
        if let lp = doc.localPath, !lp.isEmpty { DocumentLocalCache.deleteFile(localPath: lp) }
        doc.localPath = nil
        SyncCenter.shared.enqueueDocumentDelete(documentId: doc.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        if !path.isEmpty {
            Task.detached { try? await Storage.storage().reference(withPath: path).delete() }
        }
    }

    func open(documentId: String, modelContext: ModelContext,
              onURL: @escaping (URL) -> Void, onError: @escaping (String) -> Void) {
        let did = documentId
        guard let doc = try? modelContext.fetch(FetchDescriptor<KBDocument>(predicate: #Predicate { $0.id == did })).first else {
            onError(String(localized: "File non disponibile."))
            return
        }
        TreatmentAttachmentService.shared.open(
            doc: doc, modelContext: modelContext, onURL: onURL, onError: onError,
            onKeyMissing: { onError(String(localized: "Chiave di famiglia non disponibile.")) }
        )
    }
}
