//
//  KBDocument.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

enum KBTextExtractionStatus: Int, Codable {
    case none = 0
    case pending = 1
    case processing = 2
    case completed = 3
    case failed = 4
}

@Model
final class KBDocument {
    @Attribute(.unique) var id: String
    
    // Ownership
    var familyId: String
    var childId: String?        // nil = documento famiglia
    
    // Category
    var categoryId: String?
    
    // Storage (locale)
    var localPath: String?
    
    // Metadata
    var title: String
    var fileName: String
    var mimeType: String
    var fileSize: Int64
    
    // Storage remoto
    var storagePath: String
    var downloadURL: String?
    var notes: String?          // tag libero, es. "treatment:{id}"
    
    // OCR / text extraction
    var extractedText: String?
    var extractedTextUpdatedAt: Date?
    var extractionStatusRaw: Int
    var extractionError: String?
    
    // Dates
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    // Sync
    var syncStateRaw: Int
    var lastSyncError: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    var extractionStatus: KBTextExtractionStatus {
        get { KBTextExtractionStatus(rawValue: extractionStatusRaw) ?? .none }
        set { extractionStatusRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String?,
        categoryId: String?,
        title: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64,
        localPath: String? = nil,
        storagePath: String,
        downloadURL: String?,
        notes: String? = nil,
        extractedText: String? = nil,
        extractedTextUpdatedAt: Date? = nil,
        extractionStatus: KBTextExtractionStatus = .none,
        extractionError: String? = nil,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.categoryId = categoryId
        self.title = title
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.localPath = localPath
        self.storagePath = storagePath
        self.downloadURL = downloadURL
        self.notes = notes
        
        self.extractedText = extractedText
        self.extractedTextUpdatedAt = extractedTextUpdatedAt
        self.extractionStatusRaw = extractionStatus.rawValue
        self.extractionError = extractionError
        
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBDocument {
    var localFileURL: URL? {
        guard let localPath, !localPath.isEmpty else {
            KBLog.persistence.kbDebug("KBDocument.localFileURL missing localPath docId=\(id)")
            return nil
        }
        
        do {
            let url = try DocumentLocalCache.resolve(localPath: localPath)
            KBLog.persistence.kbDebug("KBDocument.localFileURL resolved docId=\(id) localPath=\(localPath) -> \(url.path)")
            return url
        } catch {
            KBLog.persistence.kbError("KBDocument.localFileURL resolve failed docId=\(id) localPath=\(localPath): \(error.localizedDescription)")
            return nil
        }
    }
    
    var isImageDocument: Bool {
        mimeType.hasPrefix("image/")
    }
    
    var isPDFDocument: Bool {
        mimeType == "application/pdf"
    }
    
    var hasExtractedText: Bool {
        guard let extractedText else { return false }
        return !extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func markExtractionPending(updatedBy: String) {
        extractionStatus = .pending
        extractionError = nil
        updatedAt = Date()
        self.updatedBy = updatedBy
        syncState = .pendingUpsert
    }
    
    func markExtractionProcessing(updatedBy: String) {
        extractionStatus = .processing
        extractionError = nil
        updatedAt = Date()
        self.updatedBy = updatedBy
        syncState = .pendingUpsert
    }
    
    func markExtractionCompleted(text: String, updatedBy: String) {
        extractedText = text
        extractedTextUpdatedAt = Date()
        extractionStatus = .completed
        extractionError = nil
        updatedAt = Date()
        self.updatedBy = updatedBy
        syncState = .pendingUpsert
    }
    
    func markExtractionFailed(_ error: String, updatedBy: String) {
        extractionStatus = .failed
        extractionError = error
        updatedAt = Date()
        self.updatedBy = updatedBy
        syncState = .pendingUpsert
    }
    
    func clearExtractedText(updatedBy: String) {
        extractedText = nil
        extractedTextUpdatedAt = nil
        extractionStatus = .none
        extractionError = nil
        updatedAt = Date()
        self.updatedBy = updatedBy
        syncState = .pendingUpsert
    }
}

extension KBDocument: HasFamilyId {}
