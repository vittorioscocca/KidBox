//
//  TravelPlaceRatingStore.swift
//  KidBox
//
//  Voti Google per le righe delle liste luoghi (ristoranti, hotel, attività).
//

import Foundation

struct TravelPlaceRating: Equatable {
    let value: Double
    let reviewCount: Int
}

/// Cache dei voti Google, condivisa fra le liste.
///
/// Ogni voto è una chiamata a Places, che si paga: la cache serve a non
/// ripagare la stessa riga a ogni scroll o rientro nella lista. Si memorizza
/// anche l'ESITO NEGATIVO (`nil`), altrimenti un locale che Places non trova —
/// il caso frequente quando il nome viene da un itinerario generato — verrebbe
/// richiesto daccapo ogni volta che la riga ricompare.
actor TravelPlaceRatingStore {
    static let shared = TravelPlaceRatingStore()

    private var cache: [String: TravelPlaceRating?] = [:]
    /// Richieste in volo, per non partire due volte sulla stessa riga quando
    /// la List ricicla le celle durante lo scroll.
    private var inFlight: [String: Task<TravelPlaceRating?, Never>] = [:]

    func rating(
        placeName: String,
        locationContext: String,
        familyId: String
    ) async -> TravelPlaceRating? {
        let key = "\(placeName.lowercased())|\(locationContext.lowercased())"
        if let cached = cache[key] { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task<TravelPlaceRating?, Never> {
            do {
                let details = try await TravelPlacesService.fetchDetails(
                    placeName: placeName,
                    locationContext: locationContext,
                    familyId: familyId
                )
                guard let value = details.rating, value > 0 else { return nil }
                return TravelPlaceRating(value: value, reviewCount: details.reviewCount)
            } catch {
                // Locale non trovato o rete assente: si registra come "nessun
                // voto" e non si riprova. Riprovare a ogni comparsa della riga
                // moltiplicherebbe le chiamate a pagamento senza guadagno.
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = result
        return result
    }
}
