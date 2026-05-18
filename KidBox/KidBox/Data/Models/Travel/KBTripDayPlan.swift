//
//  KBTripDayPlan.swift
//  KidBox
//

import Foundation
import SwiftData

@Model
final class KBTripDayPlan {
    @Attribute(.unique) var id: String
    var familyId: String
    var tripId: String
    var dateString: String
    var location: String
    var morningPlan: String
    var afternoonPlan: String
    var eveningPlan: String
    var accommodationName: String?
    var accommodationType: String?
    var accommodationCostPerNight: Double?
    var weatherBackupPlan: String?
    var estimatedDailyCost: Double?
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        familyId: String,
        tripId: String,
        dateString: String,
        location: String,
        morningPlan: String,
        afternoonPlan: String,
        eveningPlan: String
    ) {
        self.id = id
        self.familyId = familyId
        self.tripId = tripId
        self.dateString = dateString
        self.location = location
        self.morningPlan = morningPlan
        self.afternoonPlan = afternoonPlan
        self.eveningPlan = eveningPlan
        self.updatedAt = .now
    }
}
