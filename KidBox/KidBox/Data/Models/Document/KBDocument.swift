//
//  KBDocument.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

@Model
final class KBDocument {
    @Attribute(.unique) var id: String
    
    // Ownership
    var familyId: String
    var childId: String?        // nil = documento famiglia
    
    // Category
    var categoryId: String
    
    // Metadata
    var title: String
    var fileName: String
    var mimeType: String
    var fileSize: Int64
    
    // Storage
    var storagePath: String     // es: families/{familyId}/documents/{docId}.pdf
    var downloadURL: String?
    
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
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String?,
        categoryId: String,
        title: String,
        fileName: String,
        mimeType: String,
        fileSize: Int64,
        storagePath: String,
        downloadURL: String?,
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
        self.storagePath = storagePath
        self.downloadURL = downloadURL
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}
