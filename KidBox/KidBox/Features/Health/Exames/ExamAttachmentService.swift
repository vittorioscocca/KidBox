//
//  ExamAttachmentService.swift
//  KidBox
//
//  Created by vscocca on 09/03/26.
//

import Combine
import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseStorage

// MARK: - Tag

enum ExamAttachmentTag {
    static func make(_ examId: String) -> String { "exam:\(examId)" }
    static func matches(_ doc: KBDocument, examId: String) -> Bool {
        doc.notes == make(examId) && !doc.isDeleted
    }
}

// MARK: - Service

@MainActor
final class ExamAttachmentService {
    
    static let shared = ExamAttachmentService()
    private init() {}
    
    // MARK: - Upload
    
    func upload(
        url:         URL,
        examId:      String,
        familyId:    String,
        childId:     String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        
        let okScope = url.startAccessingSecurityScopedResource()
        defer { if okScope { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            KBLog.storage.kbError("ExamAttachment: unable to read data file=\(url.lastPathComponent)")
            return nil
        }
        
        let uid        = Auth.auth().currentUser?.uid ?? "local"
        let now        = Date()
        let docId      = UUID().uuidString
        let fileName   = url.lastPathComponent
        let ext        = url.pathExtension.lowercased()
        let mime       = mimeType(for: ext)
        let title      = url.deletingPathExtension().lastPathComponent
        let storagePath = "families/\(familyId)/exam-attachments/\(examId)/\(docId)/\(fileName).kbenc"
        
        let (_, referti) = TreatmentAttachmentService.shared.ensureHealthFolders(
            familyId: familyId, modelContext: modelContext
        )
        
        guard let localRelPath = try? DocumentLocalCache.write(
            familyId: familyId, docId: docId, fileName: fileName, data: data
        ) else {
            KBLog.storage.kbError("ExamAttachment: local cache write failed docId=\(docId)")
            return nil
        }
        
        let doc = KBDocument(
            id:          docId,
            familyId:    familyId,
            childId:     childId,
            categoryId:  referti.id,
            title:       title,
            fileName:    fileName,
            mimeType:    mime,
            fileSize:    Int64(data.count),
            storagePath: storagePath,
            downloadURL: nil,
            notes:       ExamAttachmentTag.make(examId),
            updatedBy:   uid,
            createdAt:   now,
            updatedAt:   now,
            isDeleted:   false
        )
        doc.localPath  = localRelPath
        doc.syncState  = .pendingUpsert
        modelContext.insert(doc)
        try? modelContext.save()
        
        DocumentTextExtractionCoordinator.shared.enqueueExtraction(
            for: doc, updatedBy: uid, modelContext: modelContext
        )
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: doc.id, familyId: familyId, modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        // Upload remoto cifrato in background
        Task.detached {
            guard let encrypted = try? await DocumentCryptoService.encrypt(
                data, familyId: familyId, userId: uid
            ) else { return }
            
            let ref = Storage.storage().reference(withPath: storagePath)
            let meta = StorageMetadata()
            meta.contentType = "application/octet-stream"
            meta.customMetadata = [
                "kb_encrypted": "1", "kb_alg": "AES-GCM",
                "kb_orig_mime": mime, "kb_orig_name": fileName
            ]
            guard (try? await ref.putDataAsync(encrypted, metadata: meta)) != nil,
                  let dlURL = try? await ref.downloadURL().absoluteString else { return }
            
            await MainActor.run {
                doc.downloadURL = dlURL
                doc.syncState   = .synced
                doc.updatedAt   = Date()
                try? modelContext.save()
            }
        }
        
        return doc
    }
    
    // MARK: - Delete
    
    func delete(_ doc: KBDocument, modelContext: ModelContext) {
        if let lp = doc.localPath, !lp.isEmpty {
            DocumentLocalCache.deleteFile(localPath: lp)
        }
        doc.localPath = nil
        SyncCenter.shared.enqueueDocumentDelete(
            documentId: doc.id, familyId: doc.familyId, modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        let path = doc.storagePath
        if !path.isEmpty {
            Task.detached {
                try? await Storage.storage().reference(withPath: path).delete()
            }
        }
    }
    
    // MARK: - Open
    
    func open(
        doc:          KBDocument,
        modelContext: ModelContext,
        onURL:        @escaping (URL) -> Void,
        onError:      @escaping (String) -> Void,
        onKeyMissing: @escaping () -> Void
    ) {
        // Se il file è già in cache locale, apri direttamente
        if let lp = doc.localPath, !lp.isEmpty {
            TreatmentAttachmentService.shared.open(
                doc: doc, modelContext: modelContext,
                onURL: onURL, onError: onError, onKeyMissing: onKeyMissing
            )
            return
        }
        
        // File non in cache (arrivato via sync da altro device) — scarica prima
        guard !doc.storagePath.isEmpty else {
            onError("Percorso remoto mancante")
            return
        }
        
        Task {
            await downloadAndOpen(
                doc: doc, modelContext: modelContext,
                onURL: onURL, onError: onError, onKeyMissing: onKeyMissing
            )
        }
    }
    
    private func downloadAndOpen(
        doc:          KBDocument,
        modelContext: ModelContext,
        onURL:        @escaping (URL) -> Void,
        onError:      @escaping (String) -> Void,
        onKeyMissing: @escaping () -> Void
    ) async {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        
        do {
            // 1. Scarica il file cifrato da Firebase Storage
            let ref = Storage.storage().reference(withPath: doc.storagePath)
            let encryptedData = try await ref.data(maxSize: 50 * 1024 * 1024) // 50 MB max
            
            // 2. Decifra
            guard let clearData = try? DocumentCryptoService.decrypt(
                encryptedData, familyId: doc.familyId, userId: uid
            ) else {
                await MainActor.run { onKeyMissing() }
                return
            }
            
            // 3. Salva in cache locale
            guard let localRelPath = try? DocumentLocalCache.write(
                familyId: doc.familyId,
                docId:    doc.id,
                fileName: doc.fileName,
                data:     clearData
            ) else {
                await MainActor.run { onError("Impossibile salvare il file in cache") }
                return
            }
            
            // 4. Aggiorna il KBDocument con localPath e ri-enqueue l'estrazione testo
            await MainActor.run {
                doc.localPath = localRelPath
                try? modelContext.save()
                DocumentTextExtractionCoordinator.shared.enqueueExtraction(
                    for: doc, updatedBy: uid, modelContext: modelContext
                )
            }
            
            // 5. Apri tramite il service standard (ora ha localPath)
            await MainActor.run {
                TreatmentAttachmentService.shared.open(
                    doc: doc, modelContext: modelContext,
                    onURL: onURL, onError: onError, onKeyMissing: onKeyMissing
                )
            }
            
        } catch {
            await MainActor.run {
                onError("Download fallito: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Mime helper
    
    private func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf":         return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "heic":        return "image/heic"
        default:            return "application/octet-stream"
        }
    }
}
