//
//  KBVehicle.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData

@Model
final class KBVehicle {

    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String

    // MARK: - Content
    var name: String
    var licensePlate: String?
    var brand: String?
    var model: String?
    var year: Int?
    /// `"benzina"` | `"diesel"` | `"elettrica"` | `"ibrida"` | `"gpl"`
    var fuelTypeRaw: String?
    var color: String?
    var vin: String?
    var insuranceExpiryDate: Date?
    var revisionExpiryDate: Date?
    var taxExpiryDate: Date?
    var lastServiceDate: Date?
    var nextServiceDate: Date?
    var currentKm: Int?
    var notes: String?
    var photoURL: String?

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
        name: String,
        licensePlate: String? = nil,
        brand: String? = nil,
        model: String? = nil,
        year: Int? = nil,
        fuelTypeRaw: String? = nil,
        color: String? = nil,
        vin: String? = nil,
        insuranceExpiryDate: Date? = nil,
        revisionExpiryDate: Date? = nil,
        taxExpiryDate: Date? = nil,
        lastServiceDate: Date? = nil,
        nextServiceDate: Date? = nil,
        currentKm: Int? = nil,
        notes: String? = nil,
        photoURL: String? = nil,
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
        self.name = name
        self.licensePlate = licensePlate
        self.brand = brand
        self.model = model
        self.year = year
        self.fuelTypeRaw = fuelTypeRaw
        self.color = color
        self.vin = vin
        self.insuranceExpiryDate = insuranceExpiryDate
        self.revisionExpiryDate = revisionExpiryDate
        self.taxExpiryDate = taxExpiryDate
        self.lastServiceDate = lastServiceDate
        self.nextServiceDate = nextServiceDate
        self.currentKm = currentKm
        self.notes = notes
        self.photoURL = photoURL
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

extension KBVehicle: HasFamilyId {}
