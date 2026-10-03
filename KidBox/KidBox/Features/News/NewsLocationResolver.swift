//
//  NewsLocationResolver.swift
//  KidBox
//
//  La città per le Notizie: dalla posizione attuale (una sola lettura, solo su
//  richiesta, poi il GPS si spegne) o da un nome scritto a mano. Si salvano
//  paese, regione, provincia e città — mai le coordinate.
//
//  MapKit non espone la regione amministrativa (Campania, Île-de-France) nei
//  campi nuovi di iOS 26: si legge da `placemark`, deprecato ma ancora
//  valorizzato. Se un giorno sparisse, la regione resterebbe vuota e il server
//  userebbe la provincia (vedi `parsePlace` in functions/news).
//

import Foundation
import CoreLocation
import MapKit

@MainActor
final class NewsLocationResolver: NSObject, CLLocationManagerDelegate {

    enum ResolveError: LocalizedError {
        case denied, notFound, failed(String)
        var errorDescription: String? {
            switch self {
            case .denied:
                return NSLocalizedString("Posizione non consentita. Scrivi la tua città qui sotto, oppure abilita la posizione in Impostazioni.", comment: "News: location denied")
            case .notFound:
                return NSLocalizedString("Non trovo questa città. Prova a scriverla con la provincia.", comment: "News: city not found")
            case .failed(let m):
                return m
            }
        }
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    // MARK: - Dalla posizione

    func resolveCurrentPlace() async throws -> NewsPlace {
        let location = try await currentLocation()
        guard let request = MKReverseGeocodingRequest(location: location) else { throw ResolveError.notFound }
        let items = try await request.mapItems
        guard let item = items.first, let place = Self.place(from: item) else { throw ResolveError.notFound }
        return place
    }

    private func currentLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw ResolveError.denied
        default:
            break
        }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.requestLocation()
            case .denied, .restricted:
                self.finish(.failure(ResolveError.denied))
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.failure(ResolveError.failed(error.localizedDescription))) }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    // MARK: - Da un nome

    func resolve(cityName: String) async throws -> NewsPlace {
        let query = cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let request = MKGeocodingRequest(addressString: query) else { throw ResolveError.notFound }
        let items = try await request.mapItems
        guard let item = items.first, let place = Self.place(from: item) else { throw ResolveError.notFound }
        return place
    }

    // MARK: - MKMapItem → NewsPlace

    private static func place(from item: MKMapItem) -> NewsPlace? {
        let reps = item.addressRepresentations
        let legacy = item.placemark
        guard let code = reps?.region?.identifier ?? legacy.isoCountryCode, code.count == 2 else { return nil }
        let country = reps?.regionName ?? legacy.country ?? kbDeviceLocale().localizedString(forRegionCode: code) ?? code
        let city = reps?.cityName ?? legacy.locality ?? legacy.subAdministrativeArea ?? ""
        return NewsPlace(
            countryCode: code.uppercased(),
            country: country,
            region: legacy.administrativeArea ?? "",
            province: legacy.subAdministrativeArea ?? "",
            city: city
        )
    }
}
