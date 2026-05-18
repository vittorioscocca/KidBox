//
//  TravelPlacesService.swift
//  KidBox
//

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
