//
//  KBTrip.swift
//  KidBox
//

import Foundation
import SwiftData

enum TripStatus: String, Codable {
    case planning
    case active
    case completed
}

@Model
final class KBTrip {
    @Attribute(.unique) var id: String
    var familyId: String
    var name: String
    var startDate: Date
    var endDate: Date
    var participantIdsJson: String
    var budgetTotal: Double
    var currency: String
    var statusRaw: String
    var aiProposalJson: String?
    /// Album KidBox dedicato alle foto del viaggio (`KBPhotoAlbum.id`).
    var photoAlbumId: String?
    /// Nota KidBox dedicata alle annotazioni del viaggio (`KBNote.id`).
    var notesNoteId: String?
    /// Lista Todo KidBox dedicata al viaggio (`KBTodoList.id`).
    var todoListId: String?
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var updatedBy: String
    var syncStateRaw: Int
    var lastSyncError: String?

    @Relationship(deleteRule: .cascade) var legs: [KBTripLeg] = []
    @Relationship(deleteRule: .cascade) var dayPlans: [KBTripDayPlan] = []
    @Relationship(deleteRule: .cascade) var expenses: [KBTripExpense] = []
    @Relationship(deleteRule: .cascade) var packingItems: [KBPackingItem] = []

    var status: TripStatus { TripStatus(rawValue: statusRaw) ?? .planning }

    /// Giorni di soggiorno inclusivi (es. 30 mag → 1 giu = 3 giorni).
    var plannedDayCount: Int {
        endDate.kbDayCount(from: startDate)
    }

    /// Alias storico: stesso conteggio inclusivo usato nel wizard.
    var durationDays: Int {
        plannedDayCount
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        startDate: Date,
        endDate: Date,
        participantIdsJson: String = "[]",
        budgetTotal: Double = 0,
        currency: String = "EUR",
        createdBy: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.participantIdsJson = participantIdsJson
        self.budgetTotal = budgetTotal
        self.currency = currency
        self.statusRaw = TripStatus.planning.rawValue
        self.createdBy = createdBy
        self.updatedBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.syncStateRaw = 0
    }
}
