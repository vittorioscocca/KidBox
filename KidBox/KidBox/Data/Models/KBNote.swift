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
    /// Opzionale per migrazione SwiftData: `nil` → comportamento come tutta la famiglia.
    var visibilityScope: String?
    /// Opzionale per migrazione SwiftData: ai record precedenti può mancare nel DB (`nil` = nessun membro aggiunto).
    var visibilityMemberIds: [String]?
    
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
        visibilityScope: String = KBVisibilityScope.family,
        visibilityMemberIds: [String] = [],
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
        self.visibilityScope = visibilityScope
        self.visibilityMemberIds = visibilityMemberIds
        self.createdBy = createdBy
        self.createdByName = createdByName
        self.updatedBy = updatedBy
        self.updatedByName = updatedByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.synced.rawValue
    }

    func isVisible(to currentUid: String?) -> Bool {
        KBVisibilityScope.isVisible(
            scope: visibilityScope,
            memberIds: visibilityMemberIds ?? [],
            createdBy: createdBy.isEmpty ? nil : createdBy,
            currentUid: currentUid,
        )
    }
}
