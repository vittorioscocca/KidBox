//
//  VehicleReminderOffsets.swift
//  KidBox
//

import Foundation

/// Offset di preavviso (in giorni) configurabili per ciascuna scadenza veicolo.
/// Valori ammessi: 0 (giorno stesso), 2 (2 giorni prima), 7 (1 settimana prima) — fino a 3 attivi per scadenza.
struct VehicleReminderOffsets: Codable, Equatable {
    var insurance: [Int]
    var revision: [Int]
    var tax: [Int]
    var service: [Int]

    static let allowedOffsets = [0, 2, 7]
    static let defaultOffsets = [0, 7]

    static let `default` = VehicleReminderOffsets(
        insurance: defaultOffsets,
        revision: defaultOffsets,
        tax: defaultOffsets,
        service: defaultOffsets
    )

    func offsets(forKind kind: String) -> [Int] {
        switch kind {
        case "insurance": return insurance
        case "revision": return revision
        case "tax": return tax
        case "service": return service
        default: return []
        }
    }

    static func decode(json: String?) -> VehicleReminderOffsets {
        guard let json, let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(VehicleReminderOffsets.self, from: data)
        else { return .default }
        return decoded
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Firestore mapping (mappa nativa `reminderOffsets`, non JSON string)

extension VehicleReminderOffsets {
    init(firestoreMap: [String: [Int]]?) {
        guard let firestoreMap else { self = .default; return }
        self.init(
            insurance: firestoreMap["insurance"] ?? Self.defaultOffsets,
            revision: firestoreMap["revision"] ?? Self.defaultOffsets,
            tax: firestoreMap["tax"] ?? Self.defaultOffsets,
            service: firestoreMap["service"] ?? Self.defaultOffsets
        )
    }

    var firestoreMap: [String: [Int]] {
        ["insurance": insurance, "revision": revision, "tax": tax, "service": service]
    }
}
