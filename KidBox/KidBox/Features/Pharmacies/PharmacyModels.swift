//
//  PharmacyModels.swift
//  KidBox
//
//  Le risposte di `getPharmacies` (functions/pharmacies). Il disegno è in
//  internal/farmacie-di-turno.md: la fonte è ufficiale e letta dal codice,
//  oppure indicata dall'utente; qui non si inventa mai un turno.
//

import Foundation
import SwiftUI

struct PharmacyShift: Codable, Identifiable, Hashable {
    var date: String
    var name: String
    var comune: String = ""
    var address: String = ""
    var phone: String = ""
    var lat: Double? = nil
    var lng: Double? = nil
    /// night, afternoon, holiday, afternoon_holiday, h24: opzionale, non tutte le fonti lo dicono.
    var service: String? = nil

    var id: String { "\(date)|\(name)|\(comune)|\(address)" }

    /// Solo cifre e «+»: quello che `tel:` accetta.
    var dialNumber: String {
        phone.filter { $0.isNumber || $0 == "+" }
    }

    /// Il tipo di servizio, quando la fonte lo indica.
    var serviceLabel: LocalizedStringKey? {
        switch service {
        case "night": return "Servizio notturno"
        case "afternoon": return "Servizio pomeridiano"
        case "holiday": return "Servizio festivo"
        case "afternoon_holiday": return "Servizio pomeridiano e festivo"
        case "h24": return "Aperta 24 ore"
        default: return nil
        }
    }

    /// Indirizzo e comune per la ricerca su Mappe.
    var mapQuery: String {
        [name, address, comune].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct PharmacyDay: Codable, Identifiable, Hashable {
    var date: String
    var items: [PharmacyShift]
    var id: String { date }
}

/// Da dove vengono i turni. `confidence`: verified (scritta da noi), ai
/// (ente ufficiale trovato dall'AI), uncertain (da verificare), manual (scelta
/// dall'utente).
struct PharmacySource: Codable, Hashable {
    var kind: String = ""
    var label: String = ""
    var url: String = ""
    var confidence: String = ""
    var fetchedAtMs: Double? = nil
    var readable: Bool = false
    var manual: Bool = false
    var lastError: String? = nil
    var hasManual: Bool = false

    var fetchedAt: Date? { fetchedAtMs.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var link: URL? { URL(string: url) }
}

struct PharmacyEstimate: Codable, Hashable {
    var find: Int = 0
    var manual: Int = 0
}

struct PharmacyFeed: Decodable {
    /// ready, stale, unreadable, none, no-place, unsupported
    var status: String
    var source: PharmacySource?
    var estimate: PharmacyEstimate?
    var dateKey: String?
    var today: [PharmacyShift]?
    var upcoming: [PharmacyDay]?
    var others: [PharmacyShift]?
}
