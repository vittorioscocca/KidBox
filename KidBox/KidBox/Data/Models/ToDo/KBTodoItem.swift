//
//  KBTodoItem.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// A flexible shared task item.
///
/// Used for "mental load" items that should not be forgotten.
/// When `dueAt` is `nil`, the item belongs to the undated shared backlog ("Da fare").
///
/// - Note: This is not meant to replace full task managers; it focuses on child-related tasks.
@Model
final class KBTodoItem {
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    var title: String
    var notes: String?
    var dueAt: Date?
    var isDone: Bool
    var doneAt: Date?
    var doneBy: String?
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    var listId: String?
    
    var reminderEnabled: Bool = false
    var reminderId: String? = nil   // identifier UNUserNotificationCenter
    
    // ✅ M3 (make optional for migration safety)
    var syncStateRaw: Int?
    var lastSyncError: String?
    
    var assignedTo: String?        // uid membro famiglia
    var createdBy: String?         // separato da updatedBy
    var priorityRaw: Int?

    /// Opzionale per migrazione SwiftData: `nil` → equivalente a `family`.
    var visibilityScope: String?
    /// Opzionale per migrazione SwiftData: `nil` in store legacy → equivalente a `[]`.
    var visibilityMemberIds: [String]?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw ?? KBSyncState.synced.rawValue) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    var priority: Int {
        get { priorityRaw ?? 0 }
        set { priorityRaw = newValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        title: String,
        listId: String?,
        visibilityScope: String = KBVisibilityScope.family,
        visibilityMemberIds: [String] = [],
        notes: String? = nil,
        dueAt: Date? = nil,
        isDone: Bool = false,
        doneAt: Date? = nil,
        doneBy: String? = nil,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.title = title
        self.listId = listId
        self.visibilityScope = visibilityScope
        self.visibilityMemberIds = visibilityMemberIds
        self.notes = notes
        self.dueAt = dueAt
        self.isDone = isDone
        self.doneAt = doneAt
        self.doneBy = doneBy
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.assignedTo = nil
        self.createdBy = updatedBy
        self.priorityRaw = 0
        
        // default for new records
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }

    func isVisible(to currentUid: String?) -> Bool {
        KBVisibilityScope.isVisible(
            scope: visibilityScope,
            memberIds: visibilityMemberIds ?? [],
            createdBy: createdBy,
            currentUid: currentUid,
        )
    }
}

extension KBTodoItem: HasFamilyId {}
