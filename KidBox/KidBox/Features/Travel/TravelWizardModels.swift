//
//  TravelWizardModels.swift
//  KidBox
//

import Foundation

enum WizardPrimaryTransport: String, CaseIterable, Identifiable {
    case flight
    case car
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: return "Volo"
        case .car: return "In auto"
        case .other: return "Altro"
        }
    }

    var subtitle: String {
        switch self {
        case .flight: return "Prezzi voli in tempo reale"
        case .car: return "Viaggio su strada flessibile"
        case .other: return "Treno, autobus, traghetto…"
        }
    }

    var emoji: String {
        switch self {
        case .flight: return "✈️"
        case .car: return "🚗"
        case .other: return "🚆"
        }
    }

    var transportMode: TransportMode {
        switch self {
        case .flight: return .flight
        case .car: return .car
        case .other: return .train
        }
    }
}

struct TravelWizardParticipantLine: Identifiable {
    let id: String
    let name: String
    let ageLabel: String
    let emoji: String
    let isChild: Bool
}

enum TravelWizardBudgetPreset: Int, CaseIterable, Identifiable {
    case twoThousand = 2000
    case threeThousand = 3000
    case fourThousand = 4000
    case sixThousand = 6000
    case tenThousand = 10000

    var id: Int { rawValue }

    var labelUSD: String { label(currency: "USD") }

    func label(currency: String) -> String {
        let amount = currency == "EUR" ? Int(Double(rawValue) * 0.92) : rawValue
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: amount), number: .decimal)
        let symbol = currency == "EUR" ? "€" : "$"
        return currency == "EUR" ? "\(formatted) \(symbol)" : "\(formatted) \(symbol)"
    }

    func amount(in currency: String) -> Double {
        currency == "EUR" ? Double(rawValue) * 0.92 : Double(rawValue)
    }
}
