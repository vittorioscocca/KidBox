//
//  KBPet.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData

@Model
final class KBPet {

    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String

    // MARK: - Content
    var name: String
    /// `"cane"` | `"gatto"` | `"coniglio"` | `"criceto"` | `"uccello"` | `"altro"`
    var species: String
    var breed: String?
    var birthDate: Date?
    var color: String?
    var chipCode: String?
    var notes: String?
    var photoURL: String?

    // MARK: - Soft delete
    var isDeleted: Bool

    // MARK: - Sync metadata
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var updatedBy: String
    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        species: String,
        breed: String? = nil,
        birthDate: Date? = nil,
        color: String? = nil,
        chipCode: String? = nil,
        notes: String? = nil,
        photoURL: String? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String,
        updatedBy: String
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.species = species
        self.breed = breed
        self.birthDate = birthDate
        self.color = color
        self.chipCode = chipCode
        self.notes = notes
        self.photoURL = photoURL
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBPet: HasFamilyId {}
