//
//  KBHomeItem.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData

@Model
final class KBHomeItem {

    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String

    // MARK: - Content
    var name: String
    /// `"appliance"` | `"system"` | `"contract"` | `"other"`
    var categoryRaw: String
    var brand: String?
    var model: String?
    var serialNumber: String?
    var purchaseDate: Date?
    var warrantyExpiryDate: Date?
    var nextServiceDate: Date?
    var servicePeriodMonths: Int?
    var notes: String?

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
        categoryRaw: String,
        brand: String? = nil,
        model: String? = nil,
        serialNumber: String? = nil,
        purchaseDate: Date? = nil,
        warrantyExpiryDate: Date? = nil,
        nextServiceDate: Date? = nil,
        servicePeriodMonths: Int? = nil,
        notes: String? = nil,
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
        self.categoryRaw = categoryRaw
        self.brand = brand
        self.model = model
        self.serialNumber = serialNumber
        self.purchaseDate = purchaseDate
        self.warrantyExpiryDate = warrantyExpiryDate
        self.nextServiceDate = nextServiceDate
        self.servicePeriodMonths = servicePeriodMonths
        self.notes = notes
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

extension KBHomeItem: HasFamilyId {}
