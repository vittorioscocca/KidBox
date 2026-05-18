//
//  KBTripLeg.swift
//  KidBox
//

import Foundation
import SwiftData

enum TransportMode: String, CaseIterable, Codable {
    case flight
    case train
    case ship
    case car
    case walk
    case bike

    var label: String {
        switch self {
        case .flight: return "Aereo"
        case .train: return "Treno"
        case .ship: return "Nave"
        case .car: return "Auto"
        case .walk: return "A piedi"
        case .bike: return "Bici"
        }
    }

    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .train: return "tram.fill"
        case .ship: return "ferry.fill"
        case .car: return "car.fill"
        case .walk: return "figure.walk"
        case .bike: return "bicycle"
        }
    }
}

@Model
final class KBTripLeg {
    @Attribute(.unique) var id: String
    var familyId: String
    var tripId: String
    var order: Int
    var fromLocation: String
    var toLocation: String
    var transportModeRaw: String
    var departureAt: Date?
    var arrivalAt: Date?
    var notes: String?
    var updatedAt: Date

    var transportMode: TransportMode { TransportMode(rawValue: transportModeRaw) ?? .car }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        tripId: String,
        order: Int,
        fromLocation: String,
        toLocation: String,
        transportModeRaw: String,
        notes: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.tripId = tripId
        self.order = order
        self.fromLocation = fromLocation
        self.toLocation = toLocation
        self.transportModeRaw = transportModeRaw
        self.notes = notes
        self.updatedAt = .now
    }
}
