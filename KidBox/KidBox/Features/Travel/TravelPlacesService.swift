//
//  TravelPlacesService.swift
//  KidBox
//

import CoreLocation
import FirebaseFunctions
import Foundation

enum TravelPlacesService {

    /// Lingua richiesta a Google Places (Cloud Function).
    static let placesLanguageCode = "it"

    private static let functions = Functions.functions(region: "europe-west1")

    static func fetchDetails(
        placeName: String,
        locationContext: String,
        familyId: String
    ) async throws -> TravelPlaceDetails {
        let callable = functions.httpsCallable("getTravelPlaceDetails")
        callable.timeoutInterval = 30

        let payload: [String: Any] = [
            "familyId": familyId,
            "placeName": placeName,
            "locationContext": locationContext,
            "languageCode": placesLanguageCode,
        ]

        do {
            let result = try await callable.call(payload)
            guard let data = result.data as? [String: Any] else {
                throw TravelPlacesServiceError.invalidResponse
            }
            if data["found"] as? Bool == false {
                throw TravelPlacesServiceError.notFound
            }
            guard let place = data["place"] as? [String: Any] else {
                throw TravelPlacesServiceError.invalidResponse
            }
            return try parsePlace(place)
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain,
               error.code == FunctionsErrorCode.failedPrecondition.rawValue {
                throw TravelPlacesServiceError.notConfigured
            }
            throw TravelPlacesServiceError.network(error.localizedDescription)
        }
    }


    /// Luoghi reali di una categoria nella località (Places Text Search).
    ///
    /// Sostituisce l'estrazione dal testo dell'itinerario: quei "nomi" erano
    /// frasi o spezzoni, e per definizione non erano cercabili su Google —
    /// quindi niente voti. Qui i risultati sono locali esistenti e il voto
    /// arriva nella stessa risposta, senza una chiamata per riga.
    static func searchPlaces(
        locationContext: String,
        kind: TravelPlaceSearchKind,
        familyId: String
    ) async throws -> [TravelPlaceSummary] {
        let callable = functions.httpsCallable("searchTravelPlaces")
        callable.timeoutInterval = 30

        let payload: [String: Any] = [
            "locationContext": locationContext,
            "kind": kind.rawValue,
            "languageCode": placesLanguageCode,
        ]

        let result = try await callable.call(payload)
        guard let data = result.data as? [String: Any],
              let raw = data["places"] as? [[String: Any]] else {
            throw TravelPlacesServiceError.invalidResponse
        }
        return raw.compactMap { dict in
            let name = dict["name"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            return TravelPlaceSummary(
                placeId: dict["placeId"] as? String ?? UUID().uuidString,
                name: name,
                address: dict["address"] as? String ?? "",
                category: dict["category"] as? String ?? "",
                rating: dict["rating"] as? Double,
                reviewCount: dict["reviewCount"] as? Int ?? 0,
                latitude: dict["latitude"] as? Double,
                longitude: dict["longitude"] as? Double,
                googleMapsURI: (dict["googleMapsUri"] as? String).flatMap(URL.init(string:))
            )
        }
    }

    private static func parsePlace(_ dict: [String: Any]) throws -> TravelPlaceDetails {
        let name = dict["name"] as? String ?? ""
        guard !name.isEmpty else { throw TravelPlacesServiceError.invalidResponse }

        let photoStrings = dict["photoUrls"] as? [String] ?? []
        let photoURLs = photoStrings.compactMap { URL(string: $0) }

        let reviewDicts = dict["reviews"] as? [[String: Any]] ?? []
        let reviews = reviewDicts.compactMap { review -> TravelPlaceReview? in
            let text = review["text"] as? String ?? ""
            guard !text.isEmpty else { return nil }
            let profile = review["profilePhotoUrl"] as? String
            return TravelPlaceReview(
                id: review["id"] as? String ?? UUID().uuidString,
                authorName: review["authorName"] as? String ?? "Recensione",
                text: text,
                rating: review["rating"] as? Int ?? 0,
                relativeTime: review["relativeTime"] as? String ?? "",
                profilePhotoURL: profile.flatMap { URL(string: $0) }
            )
        }

        let mapsURI = (dict["googleMapsUri"] as? String).flatMap { URL(string: $0) }

        return TravelPlaceDetails(
            placeId: dict["placeId"] as? String ?? "",
            name: name,
            category: dict["category"] as? String ?? "Luogo di interesse",
            address: dict["address"] as? String ?? "",
            latitude: dict["latitude"] as? Double ?? 0,
            longitude: dict["longitude"] as? Double ?? 0,
            rating: dict["rating"] as? Double,
            reviewCount: dict["reviewCount"] as? Int ?? 0,
            about: dict["about"] as? String ?? "",
            photoURLs: photoURLs,
            reviews: reviews,
            googleMapsURI: mapsURI
        )
    }
}

enum TravelPlaceSearchKind: String {
    case restaurant, hotel, attraction

    /// Simbolo del segnaposto: distingue a colpo d'occhio cosa si sta guardando
    /// quando la mappa è piena di pin.
    var mapSymbol: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .hotel: return "bed.double.fill"
        case .attraction: return "star.fill"
        }
    }
}

struct TravelPlaceSummary: Identifiable, Equatable {
    let placeId: String
    let name: String
    let address: String
    let category: String
    let rating: Double?
    let reviewCount: Int
    let latitude: Double?
    let longitude: Double?
    let googleMapsURI: URL?

    var id: String { placeId }

    /// Coordinata utilizzabile sulla mappa, quando Google l'ha restituita.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        // (0,0) è in mezzo all'oceano: è un dato mancante, non un luogo.
        guard latitude != 0 || longitude != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
