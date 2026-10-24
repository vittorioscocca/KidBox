//
//  HomeWeatherStrip.swift
//  KidBox
//
//  La barra del meteo in Home: ora, prossime ore e minima/massima di oggi.
//  Fonte WeatherKit (Android usa Open-Meteo: fonti diverse, valori che possono
//  differire di un grado). Serve la capability WeatherKit sull'App ID, e Apple
//  impone il marchio  Meteo col link alle fonti sotto i dati: senza, la
//  revisione respinge l'app. La posizione è una lettura
//  singola e approssimata, solo con l'app aperta; le coordinate restano sul
//  telefono (UserDefaults) e non vanno mai a KidBox. Senza permesso, o senza
//  rete, la barra non compare: una barra vuota in Home è peggio di nessuna barra.
//

import SwiftUI
import Combine
import WeatherKit
import CoreLocation

// MARK: - Preferenza

/// Spenta di default, come la Dashboard. Stessa chiave letta da Home e Tema.
enum KBHomeWeatherPreference {
    static let key = "kb_showHomeWeather"
}

// MARK: - Modello

struct KBWeatherHour: Identifiable, Equatable {
    let date: Date
    let temperature: Int
    let symbol: String
    var id: Date { date }
}

struct KBWeatherForecast: Equatable {
    let temperature: Int
    let symbol: String
    let min: Int
    let max: Int
    let hours: [KBWeatherHour]
    let city: String?
    let fetchedAt: Date
}

// MARK: - Posizione (una lettura, approssimata)

@MainActor
private final class WeatherLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    private static let latKey = "kb_weather_lat"
    private static let lonKey = "kb_weather_lon"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Ultima posizione nota, per mostrare subito qualcosa.
    static var cached: CLLocation? {
        let d = UserDefaults.standard
        guard d.object(forKey: latKey) != nil else { return nil }
        return CLLocation(latitude: d.double(forKey: latKey), longitude: d.double(forKey: lonKey))
    }

    func current() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        default:
            break
        }
        let loc: CLLocation? = await withCheckedContinuation { cont in
            continuation = cont
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
        if let loc {
            // Arrotondata a ~1 km: basta per il meteo e non è una traccia.
            let d = UserDefaults.standard
            d.set((loc.coordinate.latitude * 100).rounded() / 100, forKey: Self.latKey)
            d.set((loc.coordinate.longitude * 100).rounded() / 100, forKey: Self.lonKey)
        }
        return loc
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: self.finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in self.finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ loc: CLLocation?) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: loc)
    }
}

// MARK: - Servizio

@MainActor
final class HomeWeatherModel: ObservableObject {
    @Published private(set) var forecast: KBWeatherForecast?
    @Published private(set) var attribution: WeatherAttribution?

    private let location = WeatherLocationProvider()
    private var lastLoad: Date?
    private static let ttl: TimeInterval = 30 * 60

    func load() async {
        if let lastLoad, Date().timeIntervalSince(lastLoad) < Self.ttl, forecast != nil { return }
        let loc: CLLocation
        if let fresh = await location.current() {
            loc = fresh
        } else if let cached = WeatherLocationProvider.cached {
            loc = cached
        } else {
            forecast = nil
            return
        }
        do {
            let result = try await Self.fetch(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            if attribution == nil {
                attribution = try? await WeatherService.shared.attribution
            }
            forecast = result
            lastLoad = Date()
        } catch {
            KBLog.navigation.kbDebug("Home weather: fetch fallito \(error.localizedDescription)")
        }
    }

    private static func fetch(latitude: Double, longitude: Double) async throws -> KBWeatherForecast {
        let (current, hourly, daily) = try await WeatherService.shared.weather(
            for: CLLocation(latitude: latitude, longitude: longitude),
            including: .current, .hourly, .daily
        )
        let now = Date()
        let hours = hourly.forecast
            .filter { $0.date > now }
            .prefix(8)
            .map {
                KBWeatherHour(date: $0.date,
                              temperature: Int($0.temperature.converted(to: .celsius).value.rounded()),
                              symbol: $0.symbolName.kbFilled)
            }
        let today = daily.forecast.first
        return KBWeatherForecast(
            temperature: Int(current.temperature.converted(to: .celsius).value.rounded()),
            symbol: current.symbolName.kbFilled,
            min: Int((today?.lowTemperature.converted(to: .celsius).value ?? 0).rounded()),
            max: Int((today?.highTemperature.converted(to: .celsius).value ?? 0).rounded()),
            hours: Array(hours),
            city: nil,
            fetchedAt: now
        )
    }
}

private extension String {
    /// WeatherKit dà i simboli senza «.fill» (e alcuni già pieni): si preferisce la versione piena.
    var kbFilled: String { hasSuffix(".fill") ? self : self + ".fill" }
}

// MARK: - Vista

struct HomeWeatherStrip: View {
    @StateObject private var model = HomeWeatherModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let f = model.forecast {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: f.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 30))
                        Text("\(f.temperature)°")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(f.max)° / \(f.min)°")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 18) {
                            ForEach(f.hours) { h in
                                VStack(spacing: 4) {
                                    Text(h.date, format: .dateTime.hour())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: h.symbol)
                                        .symbolRenderingMode(.multicolor)
                                        .font(.title3)
                                    Text("\(h.temperature)°")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                        }
                    }
                    if let a = model.attribution {
                        attributionRow(a)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(.systemBackground))
                )
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .task { await model.load() }
    }

    /// Marchio  Meteo + link alle fonti: obbligatori per i dati WeatherKit.
    private func attributionRow(_ a: WeatherAttribution) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: colorScheme == .dark ? a.combinedMarkDarkURL : a.combinedMarkLightURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .frame(height: 12)
            Link(destination: a.legalPageURL) {
                Text("Fonti dei dati")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .underline()
            }
            Spacer()
        }
    }
}
