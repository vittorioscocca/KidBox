//
//  NewsModels.swift
//  KidBox
//
//  Notizie per la famiglia (Pro e Max): i dati che arrivano da `getFamilyNews`
//  e `getNewsOffers` (functions/news) e le scelte dell'utente.
//  Disegno in `internal/notizie.md`; Android ha gli stessi modelli in
//  `ui/screens/news/NewsModels.kt`.
//

import SwiftUI

// MARK: - Categorie

/// Gli argomenti fra cui l'utente sceglie nelle impostazioni. Gli id sono
/// quelli del server (`CATEGORIES` in `functions/news/prompts.js`) e di Android:
/// non si traducono e non si rinominano.
enum NewsCategory: String, CaseIterable, Identifiable, Codable {
    case economy, bonus, school, health, growth, leisure, society

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .economy: return "Economia"
        case .bonus:   return "Bonus"
        case .school:  return "Scuola"
        case .health:  return "Salute"
        case .growth:  return "Crescita"
        case .leisure: return "Tempo libero"
        case .society: return "Società"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .economy: return "Bollette, prezzi, mutui e tasse di casa"
        case .bonus:   return "Agevolazioni, contributi e scadenze per le famiglie"
        case .school:  return "Calendario, iscrizioni, mense e trasporti"
        case .health:  return "Vaccinazioni, prevenzione e prodotti richiamati"
        case .growth:  return "Crescita ed educazione dei figli"
        case .leisure: return "Eventi vicino a te e iniziative per famiglie"
        case .society: return "Leggi e cambiamenti che toccano le famiglie"
        }
    }

    var symbol: String {
        switch self {
        case .economy: return "eurosign.circle.fill"
        case .bonus:   return "gift.fill"
        case .school:  return "graduationcap.fill"
        case .health:  return "cross.case.fill"
        case .growth:  return "figure.and.child.holdinghands"
        case .leisure: return "ticket.fill"
        case .society: return "person.3.fill"
        }
    }

    var tint: Color {
        switch self {
        case .economy: return Color(red: 0.20, green: 0.55, blue: 0.40)
        case .bonus:   return Color(red: 0.95, green: 0.45, blue: 0.15)
        case .school:  return Color(red: 0.25, green: 0.45, blue: 0.85)
        case .health:  return Color(red: 0.85, green: 0.30, blue: 0.35)
        case .growth:  return Color(red: 0.55, green: 0.40, blue: 0.85)
        case .leisure: return Color(red: 0.10, green: 0.60, blue: 0.70)
        case .society: return Color(red: 0.45, green: 0.45, blue: 0.55)
        }
    }
}

// MARK: - Luogo e preferenze

/// Dove vive l'utente, come lo scrivono le edizioni: paese, regione, città.
/// La città è facoltativa: senza, arriva solo l'edizione nazionale.
struct NewsPlace: Codable, Hashable {
    var countryCode: String
    var country: String
    var region: String = ""
    var province: String = ""
    var city: String = ""

    var hasCity: Bool { !city.trimmingCharacters(in: .whitespaces).isEmpty }

    /// «Benevento · Campania · Italia», dal più vicino al più lontano.
    var label: String {
        [city, region == city ? "" : region, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var dictionary: [String: Any] {
        ["countryCode": countryCode, "country": country, "region": region, "province": province, "city": city]
    }

    init(countryCode: String, country: String, region: String = "", province: String = "", city: String = "") {
        self.countryCode = countryCode
        self.country = country
        self.region = region
        self.province = province
        self.city = city
    }

    init?(dictionary d: [String: Any]?) {
        guard let d, let cc = d["countryCode"] as? String, cc.count == 2 else { return nil }
        countryCode = cc
        country = d["country"] as? String ?? cc
        region = d["region"] as? String ?? ""
        province = d["province"] as? String ?? ""
        city = d["city"] as? String ?? ""
    }

    /// Il paese del telefono, finché l'utente non sceglie la sua città.
    static var deviceDefault: NewsPlace {
        let code = Locale.autoupdatingCurrent.region?.identifier ?? "IT"
        let name = kbDeviceLocale().localizedString(forRegionCode: code) ?? code
        return NewsPlace(countryCode: code, country: name)
    }
}

/// Le scelte della famiglia, uguali per tutti i membri su
/// `families/{familyId}/news/settings`: le notizie che un membro accende le
/// vedono tutti, con lo stesso luogo e la stessa lingua, e la famiglia le paga
/// una volta (richiesta dell'utente del 03/10/2026). Il server le legge e,
/// quando ci sono, le preferisce a quello che manda il telefono.
struct NewsFamilySettings: Equatable {
    /// Qualcuno della famiglia ha letto la presentazione e acceso le Notizie:
    /// prima di allora non parte nessuna ricerca e non si scala nessun messaggio.
    var enabled: Bool = false
    var place: NewsPlace? = nil
    /// Lingua delle edizioni: quella di chi le ha accese. Un'edizione in
    /// un'altra lingua sarebbe un'altra ricerca, pagata di nuovo.
    var lang: String? = nil
    var updatedAt: Date = .distantPast
    var updatedBy: String? = nil

    var effectivePlace: NewsPlace { place ?? .deviceDefault }
    var effectiveLang: String { lang ?? LanguageManager.shared.currentLanguageCode }
}

/// Le scelte di ciascuno, sincronizzate fra i suoi dispositivi su
/// `users/{uid}.newsPrefs` (vince la modifica più recente): cosa leggere delle
/// stesse edizioni della famiglia. Non cambiano le notizie degli altri e non
/// costano niente.
struct NewsPrefs: Equatable {
    var categories: [NewsCategory] = NewsCategory.allCases
    /// Mostrare le offerte su misura della famiglia (si cercano solo su richiesta).
    var personalOffers: Bool = true
    var updatedAt: Date = .distantPast
}

// MARK: - Risposte del server

struct NewsItem: Identifiable, Hashable, Decodable {
    var id: String { url }
    let category: String
    let level: String
    let title: String
    let summary: String
    let action: String?
    let keyDate: String?
    let keyDateKind: String?
    let publishedAt: String?
    let source: String
    let url: String

    var newsCategory: NewsCategory? { NewsCategory(rawValue: category) }
}

struct NewsEvent: Identifiable, Hashable, Decodable {
    var id: String { "\(url)|\(startDate)|\(title)" }
    let title: String
    let summary: String?
    let place: String?
    let distanceKm: Int?
    let startDate: String
    let endDate: String?
    let free: Bool?
    let source: String
    let url: String
}

struct NewsOffer: Identifiable, Hashable, Decodable {
    var id: String { url + title }
    let kind: String
    let title: String
    let summary: String
    let saving: String?
    let source: String
    let url: String

    var symbol: String {
        switch kind {
        case "electricity": return "bolt.fill"
        case "gas":         return "flame.fill"
        case "water":       return "drop.fill"
        case "internet":    return "wifi"
        case "phone":       return "iphone"
        default:            return "cart.fill"
        }
    }
}

struct NewsOffersPayload: Decodable, Equatable {
    let offers: [NewsOffer]
    /// Millisecondi epoch della generazione.
    let generatedAt: Double?
    let units: Int?
    let estimateUnits: Int?
    let status: String?
}

struct NewsFeed: Decodable {
    struct Place: Decodable { let city: String?; let region: String?; let country: String? }
    struct Charge: Decodable { let units: Int; let totalUnits: Int }
    struct EditionInfo: Decodable { let status: String; let generatedAt: Double?; let stale: Bool; let reason: String? }
    struct Editions: Decodable { let country: EditionInfo?; let local: EditionInfo? }

    let status: String
    let pending: [String]
    let dateKey: String
    let place: Place
    let items: [NewsItem]
    let events: [NewsEvent]
    let offers: NewsOffersPayload?
    let editions: Editions
    let charge: Charge
    let maxUnitsPerEdition: Int?

    var isPreparing: Bool { status == "preparing" }
}

// MARK: - Date

enum NewsDates {
    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ key: String?) -> Date? {
        guard let key, !key.isEmpty else { return nil }
        return parser.date(from: key)
    }

    static func key(_ date: Date) -> String { parser.string(from: date) }

    /// «sab 3 ott», nella lingua dell'app.
    static func short(_ key: String?) -> String? {
        guard let d = date(key) else { return nil }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(kbDeviceLocale()))
    }

    static func dayMonth(_ key: String?) -> String? {
        guard let d = date(key) else { return nil }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(kbDeviceLocale()))
    }
}
