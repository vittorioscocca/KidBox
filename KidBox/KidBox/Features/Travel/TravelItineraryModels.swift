//
//  TravelItineraryModels.swift
//  KidBox
//

import Foundation
import SwiftUI

enum TravelItineraryPeriod: String, CaseIterable {
    case morning
    case afternoon
    case evening

    var title: String {
        switch self {
        case .morning: return "MATTINA"
        case .afternoon: return "POMERIGGIO"
        case .evening: return "SERA"
        }
    }

    var accentColor: Color {
        switch self {
        case .morning: return Color(red: 0.95, green: 0.75, blue: 0.1)
        case .afternoon: return Color(red: 0.95, green: 0.38, blue: 0.1)
        case .evening: return Color(red: 0.55, green: 0.35, blue: 0.85)
        }
    }
}

enum TravelItineraryStopCategory: String {
    case flight, transport, food, hotel, culture, beach, shopping, other

    var emoji: String {
        switch self {
        case .flight: return "✈️"
        case .transport: return "🚕"
        case .food: return "🍝"
        case .hotel: return "🏨"
        case .culture: return "🏛️"
        case .beach: return "🏖️"
        case .shopping: return "🛍️"
        case .other: return "📍"
        }
    }

    static func from(raw: String?) -> TravelItineraryStopCategory {
        guard let raw else { return .other }
        return TravelItineraryStopCategory(rawValue: raw.lowercased()) ?? .other
    }
}

struct TravelItineraryStop: Identifiable {
    let id = UUID()
    let time: String
    let title: String
    let detail: String
    let emoji: String
    let category: TravelItineraryStopCategory
}

struct TravelItineraryPeriodBlock: Identifiable {
    let id = UUID()
    let period: TravelItineraryPeriod
    let stops: [TravelItineraryStop]
    let durationSummary: String
    let costSummary: String
}

struct TravelItineraryBudgetBreakdown {
    let hotels: Double
    let flights: Double
    let restaurants: Double
    let activities: Double

    static let empty = TravelItineraryBudgetBreakdown(hotels: 0, flights: 0, restaurants: 0, activities: 0)
}

struct TravelItineraryDay: Identifiable {
    let id: String
    let dayIndex: Int
    let dateString: String
    let location: String
    let headline: String
    let dayCost: Double?
    let blocks: [TravelItineraryPeriodBlock]
}

struct TravelItineraryOverview {
    let destinationTitle: String
    let subtitle: String
    let dayCount: Int
    let estimatedTotal: Double
    let budgetLimit: Double
    let currency: String
    let budget: TravelItineraryBudgetBreakdown
    let days: [TravelItineraryDay]
}

struct TravelPlaceResult: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let meta: String
    /// Nome usato per la ricerca Google Places.
    let placeName: String
    /// Contesto geografico (località del giorno + destinazione viaggio).
    let locationContext: String

    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        meta: String = "",
        placeName: String? = nil,
        locationContext: String = ""
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.placeName = placeName ?? title
        self.locationContext = locationContext
    }

    /// Voce apribile su Google Places (nome luogo ragionevole).
    var isBrowsableOnMap: Bool {
        let query = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 3, query.count <= 80 else { return false }
        let lower = query.lowercased()
        if lower.hasPrefix("locale consigliato") { return false }
        let blocked = ["escursione in barca", "passeggiata ", "spiaggia ", "chiesa di ", "visita alla", "visita al "]
        return !blocked.contains(where: { lower.contains($0) })
    }
}
