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

    /// `String` (non `LocalizedStringKey`): usato con `.sorted()`/`.joined()`, quindi
    /// passa da NSLocalizedString.
    var title: String {
        switch self {
        case .culture: return NSLocalizedString("Cultura e storia", comment: "Travel style")
        case .food: return NSLocalizedString("Cibo e gastronomia", comment: "Travel style")
        case .nightlife: return NSLocalizedString("Vita notturna", comment: "Travel style")
        case .adventure: return NSLocalizedString("Avventura e outdoor", comment: "Travel style")
        case .relaxation: return NSLocalizedString("Relax e spiaggia", comment: "Travel style")
        case .shopping: return NSLocalizedString("Shopping", comment: "Travel style")
        }
    }

    var subtitle: String {
        switch self {
        case .culture: return NSLocalizedString("Musei, monumenti, storie", comment: "Travel style detail")
        case .food: return NSLocalizedString("Ristoranti, mercati, cucina locale", comment: "Travel style detail")
        case .nightlife: return NSLocalizedString("Bar, locali, serate", comment: "Travel style detail")
        case .adventure: return NSLocalizedString("Trekking, sport, natura", comment: "Travel style detail")
        case .relaxation: return NSLocalizedString("Spa, resort, giornate lente", comment: "Travel style detail")
        case .shopping: return NSLocalizedString("Boutique, mercati, design", comment: "Travel style detail")
        }
    }
}

enum TravelPace: String, CaseIterable, Codable, Identifiable {
    case chill
    case balanced
    case packed

    var id: String { rawValue }

    /// `String` (non `LocalizedStringKey`): usato con `.lowercased()` in frasi
    /// composte (es. `TravelHubView`), quindi passa da NSLocalizedString.
    var title: String {
        switch self {
        case .chill: return NSLocalizedString("Rilassato", comment: "Travel pace")
        case .balanced: return NSLocalizedString("Equilibrato", comment: "Travel pace")
        case .packed: return NSLocalizedString("Intenso", comment: "Travel pace")
        }
    }

    var line1: String {
        switch self {
        case .chill: return NSLocalizedString("1–2 attività al giorno", comment: "Travel pace detail")
        case .balanced: return NSLocalizedString("3–4 attività al giorno", comment: "Travel pace detail")
        case .packed: return NSLocalizedString("5–6 attività al giorno", comment: "Travel pace detail")
        }
    }

    var line2: String {
        switch self {
        case .chill: return NSLocalizedString("Mattine lente, pasti lunghi", comment: "Travel pace detail")
        case .balanced: return NSLocalizedString("Mix di visite e riposo", comment: "Travel pace detail")
        case .packed: return NSLocalizedString("Vedi tutto, senza perdere tempo", comment: "Travel pace detail")
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
        case .young: return NSLocalizedString("Giovane esploratore", comment: "Travel age group detail")
        case .modern: return NSLocalizedString("Viaggiatore moderno", comment: "Travel age group detail")
        case .seasoned: return NSLocalizedString("Esperto", comment: "Travel age group detail")
        case .comfort: return NSLocalizedString("In cerca di comfort", comment: "Travel age group detail")
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
        let format = NSLocalizedString("In base al tuo stile%@, ritmo %@, fascia %@", comment: "Discover subtitle built from travel profile")
        let stylesSuffix = stylesPart.isEmpty ? "" : " (\(stylesPart))"
        return String(format: format, stylesSuffix, pace.title.lowercased(), ageGroup.rawValue)
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
