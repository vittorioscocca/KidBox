//
//  KBDocumentCategory.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

@Model
final class KBDocumentCategory {
    @Attribute(.unique) var id: String
    var familyId: String
    
    var title: String
    var sortOrder: Int
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
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
        title: String,
        sortOrder: Int,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.title = title
        self.sortOrder = sortOrder
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}
