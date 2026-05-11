//
//  KBVehicleEvent.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import SwiftData

@Model
final class KBVehicleEvent {

    // MARK: - Identity
    @Attribute(.unique) var id: String
    var familyId: String
    var vehicleId: String

    // MARK: - Content
    var title: String
    /// `"service"` | `"repair"` | `"tire"` | `"revision"` | `"other"`
    var eventTypeRaw: String
    var date: Date
    var km: Int?
    var cost: Double?
    var garageName: String?
    var notes: String?

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
        vehicleId: String,
        title: String,
        eventTypeRaw: String,
        date: Date = Date(),
        km: Int? = nil,
        cost: Double? = nil,
        garageName: String? = nil,
        notes: String? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdBy: String,
        updatedBy: String
    ) {
        self.id = id
        self.familyId = familyId
        self.vehicleId = vehicleId
        self.title = title
        self.eventTypeRaw = eventTypeRaw
        self.date = date
        self.km = km
        self.cost = cost
        self.garageName = garageName
        self.notes = notes
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBVehicleEvent: HasFamilyId {}
