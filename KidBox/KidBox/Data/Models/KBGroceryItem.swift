//
//  KBGroceryItem.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData

@Model
final class KBGroceryItem {
    
    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String
    
    // MARK: - Content
    var name: String
    var category: String?
    var notes: String?
    
    // MARK: - State
    var isPurchased: Bool
    var purchasedAt: Date?
    var purchasedBy: String?
    
    // MARK: - Soft delete
    var isDeleted: Bool
    
    // MARK: - Sync metadata
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String?
    var createdBy: String?
    var syncStateRaw: Int
    var lastSyncError: String?
    
    // MARK: - Computed sync state
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        category: String? = nil,
        notes: String? = nil,
        isPurchased: Bool = false,
        purchasedAt: Date? = nil,
        purchasedBy: String? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.category = category
        self.notes = notes
        self.isPurchased = isPurchased
        self.purchasedAt = purchasedAt
        self.purchasedBy = purchasedBy
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
        self.createdBy = createdBy
        self.syncStateRaw = KBSyncState.synced.rawValue
    }
}
