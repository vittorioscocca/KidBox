//
//  KBPhotoAlbum.swift
//  KidBox
//
//  Created by vscocca on 12/03/26.
//

import Foundation
import SwiftData


// MARK: - KBPhotoAlbum

@Model
final class KBPhotoAlbum {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var title: String
    var coverPhotoId: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var updatedBy: String
    var isDeleted: Bool
    var syncStateRaw: Int
    var lastSyncError: String?
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        title: String,
        coverPhotoId: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String,
        updatedBy: String,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.title = title
        self.coverPhotoId = coverPhotoId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
    }
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .pendingUpsert }
        set { syncStateRaw = newValue.rawValue }
    }
}
