//
//  ExamAttachmentService.swift
//  KidBox
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
        url:          URL,
        examId:       String,
        familyId:     String,
        childId:      String,
        modelContext: ModelContext
    ) async -> KBDocument? {
        
        let okScope = url.startAccessingSecurityScopedResource()
        defer { if okScope { url.stopAccessingSecurityScopedResource() } }
        
        guard let rawData = try? Data(contentsOf: url), !rawData.isEmpty else {
            KBLog.storage.kbError("ExamAttachment: unable to read data file=\(url.lastPathComponent)")
            return nil
        }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let docId = UUID().uuidString
        let ext   = url.pathExtension.lowercased()
        
        // HEIC → JPEG: Vision OCR e preview funzionano meglio con JPEG.
        let (data, mime, fileName): (Data, String, String) = {
            if ext == "heic",
               let image = UIImage(data: rawData),
               let jpegData = image.jpegData(compressionQuality: 0.92) {
                let jpegName = url.deletingPathExtension().lastPathComponent + ".jpg"
                KBLog.storage.kbInfo("ExamAttachment: HEIC→JPEG file=\(jpegName)")
                return (jpegData, "image/jpeg", jpegName)
            }
            return (rawData, mimeType(for: ext), url.lastPathComponent)
        }()
        
        let title       = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
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
        doc.localPath = localRelPath
        doc.syncState = .pendingUpsert
        modelContext.insert(doc)
        try? modelContext.save()
        
        // Estrazione testo per AI (PDF nativo/OCR, immagini, DOCX, RTF, TXT)
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
            
            let ref  = Storage.storage().reference(withPath: storagePath)
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
    
    // MARK: - Re-extract (chiamato quando il documento arriva via sync senza testo estratto)
    
    /// Rienqueue l'estrazione testo per un documento già esistente che non ha ancora
    /// `extractedText` — tipicamente un allegato sincronizzato da un altro account.
    func enqueueReExtractionIfNeeded(
        doc: KBDocument,
        modelContext: ModelContext
    ) {
        guard ExamAttachmentTag.matches(doc, examId: doc.notes?.replacingOccurrences(of: "exam:", with: "") ?? "") else { return }
        guard doc.extractionStatus != .completed || !doc.hasExtractedText else {
            KBLog.storage.kbDebug("ExamAttachment: re-extraction skipped, already done docId=\(doc.id)")
            return
        }
        guard doc.localPath != nil else {
            KBLog.storage.kbDebug("ExamAttachment: re-extraction skipped, no local file yet docId=\(doc.id)")
            return
        }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        KBLog.storage.kbInfo("ExamAttachment: enqueue re-extraction docId=\(doc.id) status=\(doc.extractionStatus.rawValue)")
        DocumentTextExtractionCoordinator.shared.enqueueExtraction(
            for: doc, updatedBy: uid, modelContext: modelContext
        )
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
        // Se il file è stato aperto/decriptato e il testo non è ancora estratto, ri-enqueue.
        if doc.localPath != nil {
            enqueueReExtractionIfNeeded(doc: doc, modelContext: modelContext)
        }
        TreatmentAttachmentService.shared.open(
            doc: doc, modelContext: modelContext,
            onURL: onURL, onError: onError, onKeyMissing: onKeyMissing
        )
    }
    
    // MARK: - Mime helper
    
    private func mimeType(for ext: String) -> String {
        switch ext {
        case "pdf":              return "application/pdf"
        case "jpg", "jpeg":      return "image/jpeg"
        case "png":              return "image/png"
        case "heic":             return "image/heic"
        case "txt":              return "text/plain"
        case "rtf":              return "application/rtf"
        case "docx":             return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default:                 return "application/octet-stream"
        }
    }
}
