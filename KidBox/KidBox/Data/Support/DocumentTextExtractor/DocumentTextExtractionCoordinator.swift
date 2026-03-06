//
//  DocumentTextExtractionCoordinator.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import Foundation
import SwiftData

@MainActor
final class DocumentTextExtractionCoordinator {
    
    static let shared = DocumentTextExtractionCoordinator()
    
    private let extractor: MedicalDocumentTextExtracting = MedicalDocumentTextExtractor()
    
    private init() {}
    
    // MARK: - Public
    
    func enqueueExtraction(
        for document: KBDocument,
        updatedBy: String,
        modelContext: ModelContext
    ) {
        KBLog.data.kbInfo("Queue extraction for document id=\(document.id) fileName=\(document.fileName)")
        
        document.markExtractionPending(updatedBy: updatedBy)
        
        do {
            try modelContext.save()
            KBLog.persistence.kbDebug("Saved extraction pending state for document id=\(document.id)")
        } catch {
            KBLog.persistence.kbError("Failed saving pending state for document id=\(document.id): \(error.localizedDescription)")
        }
        
        let documentId = document.id
        
        Task { @MainActor in
            KBLog.data.kbDebug("Starting extraction task for document id=\(documentId)")
            await self.process(
                documentId: documentId,
                updatedBy: updatedBy,
                modelContext: modelContext
            )
        }
    }
    
    // MARK: - Processing
    
    private func process(
        documentId: String,
        updatedBy: String,
        modelContext: ModelContext
    ) async {
        KBLog.data.kbDebug("Processing extraction for document id=\(documentId)")
        
        guard let document = fetchDocument(documentId: documentId, modelContext: modelContext) else {
            KBLog.data.kbError("Document not found for extraction id=\(documentId)")
            return
        }
        
        KBLog.storage.kbDebug("Fetched document for extraction: name=\(document.fileName), mime=\(document.mimeType)")
        
        document.markExtractionProcessing(updatedBy: updatedBy)
        save(modelContext)
        
        guard let localFileURL = document.localFileURL else {
            KBLog.storage.kbError("Extraction failed: localFileURL missing for document id=\(document.id)")
            document.markExtractionFailed("File locale non trovato.", updatedBy: updatedBy)
            save(modelContext)
            syncExtractedDocument(document, modelContext: modelContext)
            return
        }
        
        let input = MedicalDocumentExtractionInput(
            documentId: document.id,
            fileName: document.fileName,
            mimeType: document.mimeType,
            localFileURL: localFileURL
        )
        
        do {
            KBLog.storage.kbInfo("Starting text extraction for fileName=\(document.fileName)")
            
            let text = try await extractor.extractText(from: input)
            
            KBLog.storage.kbDebug("Extraction finished for fileName=\(document.fileName), chars=\(text.count)")
            
            document.markExtractionCompleted(text: text, updatedBy: updatedBy)
            KBLog.storage.kbInfo("Extraction completed for fileName=\(document.fileName)")
            
        } catch {
            KBLog.storage.kbError("Extraction failed for fileName=\(document.fileName): \(error.localizedDescription)")
            document.markExtractionFailed(error.localizedDescription, updatedBy: updatedBy)
        }
        
        save(modelContext)
        syncExtractedDocument(document, modelContext: modelContext)
    }
    
    // MARK: - Sync
    
    private func syncExtractedDocument(
        _ document: KBDocument,
        modelContext: ModelContext
    ) {
        KBLog.sync.kbInfo("Enqueue document upsert after extraction docId=\(document.id) status=\(document.extractionStatus.rawValue)")
        
        SyncCenter.shared.enqueueDocumentUpsert(
            documentId: document.id,
            familyId: document.familyId,
            modelContext: modelContext
        )
        
        KBLog.sync.kbDebug("Flush global requested after extraction docId=\(document.id)")
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
    
    // MARK: - Helpers
    
    private func fetchDocument(
        documentId: String,
        modelContext: ModelContext
    ) -> KBDocument? {
        KBLog.persistence.kbDebug("Fetching document id=\(documentId)")
        
        let descriptor = FetchDescriptor<KBDocument>(
            predicate: #Predicate { $0.id == documentId }
        )
        
        do {
            let result = try modelContext.fetch(descriptor).first
            
            if result == nil {
                KBLog.persistence.kbError("Fetch returned nil for document id=\(documentId)")
            }
            
            return result
        } catch {
            KBLog.persistence.kbError("Fetch failed for document id=\(documentId): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func save(_ modelContext: ModelContext) {
        do {
            try modelContext.save()
            KBLog.persistence.kbDebug("ModelContext save OK")
        } catch {
            KBLog.persistence.kbError("ModelContext save failed: \(error.localizedDescription)")
        }
    }
}
