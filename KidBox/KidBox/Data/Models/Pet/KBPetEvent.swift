//
//  KBPetEvent.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData

@Model
final class KBPetEvent {

    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String
    var petId: String

    // MARK: - Content
    var title: String
    /// `"vaccine"` | `"vet_visit"` | `"medication"` | `"grooming"` | `"other"`
    var eventTypeRaw: String
    var date: Date
    var nextDueDate: Date?
    var notes: String?
    var vetName: String?
    var cost: Double?

    // MARK: - Soft delete
    var isDeleted: Bool

    // MARK: - Sync metadata
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var updatedBy: String

    var reminderEnabled: Bool
    var reminderId: String?

    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        petId: String,
        title: String,
        eventTypeRaw: String,
        date: Date = Date(),
        nextDueDate: Date? = nil,
        notes: String? = nil,
        vetName: String? = nil,
        cost: Double? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String,
        updatedBy: String,
        reminderEnabled: Bool = false,
        reminderId: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.petId = petId
        self.title = title
        self.eventTypeRaw = eventTypeRaw
        self.date = date
        self.nextDueDate = nextDueDate
        self.notes = notes
        self.vetName = vetName
        self.cost = cost
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.reminderEnabled = reminderEnabled
        self.reminderId = reminderId
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBPetEvent: HasFamilyId {}
