//
//  KBNote.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData

@Model
final class KBNote {
    @Attribute(.unique) var id: String
    
    var familyId: String
    
    var title: String
    var body: String
    
    // Autore / ultimo editor (no email!)
    var createdBy: String
    var createdByName: String
    var updatedBy: String
    var updatedByName: String
    
    var createdAt: Date
    var updatedAt: Date
    
    // Tombstone per delete sync-friendly
    var isDeleted: Bool
    var syncStateRaw: Int
    var lastSyncError: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        title: String = "",
        body: String = "",
        createdBy: String,
        createdByName: String,
        updatedBy: String,
        updatedByName: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.title = title
        self.body = body
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.updatedBy = updatedBy
        self.updatedByName = updatedByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.synced.rawValue
    }
}
