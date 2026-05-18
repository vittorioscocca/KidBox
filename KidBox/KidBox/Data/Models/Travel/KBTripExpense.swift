//
//  KBTripExpense.swift
//  KidBox
//

import Foundation
import SwiftData

enum TripExpenseCategory: String, CaseIterable {
    case transport
    case hotel
    case food
    case activity
    case other

    var label: String {
        switch self {
        case .transport: return "Trasporti"
        case .hotel: return "Alloggio"
        case .food: return "Cibo"
        case .activity: return "Attività"
        case .other: return "Altro"
        }
    }
}

@Model
final class KBTripExpense {
    @Attribute(.unique) var id: String
    var familyId: String
    var tripId: String
    var dateString: String
    var amount: Double
    var currency: String
    var categoryRaw: String
    var descriptionText: String?
    var paidBy: String
    var updatedAt: Date

    var category: TripExpenseCategory { TripExpenseCategory(rawValue: categoryRaw) ?? .other }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        tripId: String,
        dateString: String,
        amount: Double,
        currency: String = "EUR",
        categoryRaw: String,
        paidBy: String,
        descriptionText: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.tripId = tripId
        self.dateString = dateString
        self.amount = amount
        self.currency = currency
        self.categoryRaw = categoryRaw
        self.descriptionText = descriptionText
        self.paidBy = paidBy
        self.updatedAt = .now
    }
}
