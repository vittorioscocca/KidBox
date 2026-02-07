//
//  KBDocumentItem.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

@Model
final class KBDocumentItem {
    @Attribute(.unique) var id: String
    
    var familyId: String
    var childId: String?          // ✅ nil = documento di famiglia, non-nil = documento del bimbo/a
    var categoryId: String
    
    var title: String
    var fileName: String
    var mimeType: String
    var fileSize: Int
    
    var storagePath: String       // families/{familyId}/docs/{docId}/{fileName}
    var downloadURL: String?      // opzionale, comodo per AsyncImage/preview
    var isDeleted: Bool
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    
    // ✅ M3 sync metadata
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
        fileSize: Int,
        storagePath: String,
        downloadURL: String? = nil,
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
