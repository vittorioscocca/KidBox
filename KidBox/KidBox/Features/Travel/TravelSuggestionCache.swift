//
//  TravelSuggestionCache.swift
//  KidBox
//

import Foundation

/// Cache in-memory per aprire il dettaglio suggerimento via `Route` + `AppCoordinator`.
@MainActor
enum TravelSuggestionCache {

    private static var destinations: [String: TravelDestination] = [:]

    static func store(_ items: [TravelDestination], familyId: String) {
        for item in items {
            destinations[key(familyId: familyId, destinationId: item.id)] = item
        }
    }

    static func destination(familyId: String, destinationId: String) -> TravelDestination? {
        destinations[key(familyId: familyId, destinationId: destinationId)]
    }

    private static func key(familyId: String, destinationId: String) -> String {
        "\(familyId)|\(destinationId)"
    }
}
