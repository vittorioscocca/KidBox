//
//  TravelProfile.swift
//  KidBox
//

import Foundation

enum TravelStyle: String, CaseIterable, Codable, Identifiable {
    case culture
    case food
    case nightlife
    case adventure
    case relaxation
    case shopping

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .culture: return "🏛️"
        case .food: return "🍝"
        case .nightlife: return "🍸"
        case .adventure: return "🏔️"
        case .relaxation: return "🏖️"
        case .shopping: return "🛍️"
        }
    }

    var title: String {
        switch self {
        case .culture: return "Cultura e storia"
        case .food: return "Cibo e gastronomia"
        case .nightlife: return "Vita notturna"
        case .adventure: return "Avventura e outdoor"
        case .relaxation: return "Relax e spiaggia"
        case .shopping: return "Shopping"
        }
    }

    var subtitle: String {
        switch self {
        case .culture: return "Musei, monumenti, storie"
        case .food: return "Ristoranti, mercati, cucina locale"
        case .nightlife: return "Bar, locali, serate"
        case .adventure: return "Trekking, sport, natura"
        case .relaxation: return "Spa, resort, giornate lente"
        case .shopping: return "Boutique, mercati, design"
        }
    }
}

enum TravelPace: String, CaseIterable, Codable, Identifiable {
    case chill
    case balanced
    case packed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chill: return "Rilassato"
        case .balanced: return "Equilibrato"
        case .packed: return "Intenso"
        }
    }

    var line1: String {
        switch self {
        case .chill: return "1–2 attività al giorno"
        case .balanced: return "3–4 attività al giorno"
        case .packed: return "5–6 attività al giorno"
        }
    }

    var line2: String {
        switch self {
        case .chill: return "Mattine lente, pasti lunghi"
        case .balanced: return "Mix di visite e riposo"
        case .packed: return "Vedi tutto, senza perdere tempo"
        }
    }

    var systemImage: String {
        switch self {
        case .chill: return "leaf.fill"
        case .balanced: return "scalemass.fill"
        case .packed: return "bolt.fill"
        }
    }

    var tint: (red: Double, green: Double, blue: Double) {
        switch self {
        case .chill: return (0.30, 0.65, 0.45)
        case .balanced: return (0.45, 0.48, 0.52)
        case .packed: return (0.95, 0.38, 0.10)
        }
    }
}

enum TravelAgeGroup: String, CaseIterable, Codable, Identifiable {
    case young = "18-25"
    case modern = "26-35"
    case seasoned = "36-50"
    case comfort = "50+"

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .young: return "🎒"
        case .modern: return "✈️"
        case .seasoned: return "🧭"
        case .comfort: return "☕"
        }
    }

    var title: String { rawValue }

    var subtitle: String {
        switch self {
        case .young: return "Giovane esploratore"
        case .modern: return "Viaggiatore moderno"
        case .seasoned: return "Esperto"
        case .comfort: return "In cerca di comfort"
        }
    }
}

struct TravelProfile: Codable, Equatable {
    var styles: [TravelStyle]
    var pace: TravelPace
    var ageGroup: TravelAgeGroup

    func familyContextValue() -> [String: Any] {
        [
            "styles": styles.map(\.rawValue),
            "pace": pace.rawValue,
            "ageGroup": ageGroup.rawValue,
        ]
    }

    var discoverSubtitle: String {
        let stylesPart = styles.prefix(2).map(\.title).joined(separator: ", ")
        return "In base al tuo stile\(stylesPart.isEmpty ? "" : " (\(stylesPart))"), ritmo \(pace.title.lowercased()), fascia \(ageGroup.rawValue)"
    }
}

enum TravelProfileStore {
    private static let completedPrefix = "travelOnboardingCompleted."
    private static let profilePrefix = "travelProfile."

    static func hasCompletedOnboarding(userId: String) -> Bool {
        guard !userId.isEmpty else { return true }
        return UserDefaults.standard.bool(forKey: completedPrefix + userId)
    }

    static func loadProfile(userId: String) -> TravelProfile? {
        guard !userId.isEmpty,
              let data = UserDefaults.standard.data(forKey: profilePrefix + userId) else { return nil }
        return try? JSONDecoder().decode(TravelProfile.self, from: data)
    }

    static func save(profile: TravelProfile, userId: String) {
        guard !userId.isEmpty else { return }
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profilePrefix + userId)
        }
        UserDefaults.standard.set(true, forKey: completedPrefix + userId)
    }
}
