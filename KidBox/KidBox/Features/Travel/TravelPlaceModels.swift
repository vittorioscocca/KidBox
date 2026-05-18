//
//  TravelPlaceModels.swift
//  KidBox
//

import Foundation

/// Contesto di navigazione da una tappa dell'itinerario verso il dettaglio luogo.
struct TravelItineraryStopContext: Identifiable, Hashable {
    let id: String
    let placeName: String
    let locationContext: String
    let scheduleBadge: String
    let time: String
    let staySummary: String
    let costSummary: String
    let nextStopTitle: String?
}

struct TravelPlaceReview: Identifiable, Hashable {
    let id: String
    let authorName: String
    let text: String
    let rating: Int
    let relativeTime: String
    let profilePhotoURL: URL?
}

struct TravelPlaceDetails: Hashable {
    let placeId: String
    let name: String
    let category: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double?
    let reviewCount: Int
    let about: String
    let photoURLs: [URL]
    let reviews: [TravelPlaceReview]
    let googleMapsURI: URL?

    var hasCoordinates: Bool {
        latitude != 0 || longitude != 0
    }
}

enum TravelPlacesServiceError: LocalizedError {
    case notConfigured
    case notFound
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Google Places non è configurato: abilita «Places API (New)» nel progetto Google Cloud, verifica la fatturazione e usa una chiave API senza restrizioni iOS per le Cloud Functions."
        case .notFound:
            return "Non abbiamo trovato questo luogo su Google."
        case .invalidResponse:
            return "Risposta non valida dal servizio luoghi."
        case .network(let msg):
            return msg
        }
    }
}
