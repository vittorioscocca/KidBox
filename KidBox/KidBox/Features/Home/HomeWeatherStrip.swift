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
import MapKit

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
    /// Chi ha acceso la barra deve vedere perché è vuota: sparire in silenzio
    /// rendeva indistinguibili posizione negata, WeatherKit non attivo e rete giù.
    enum Status: Equatable {
        case loading
        case ready
        case noLocation
        case failed(String)
    }

    @Published private(set) var forecast: KBWeatherForecast?
    @Published private(set) var attribution: WeatherAttribution?
    @Published private(set) var status: Status = .loading

    private let location = WeatherLocationProvider()
    private var lastLoad: Date?
    private static let ttl: TimeInterval = 30 * 60

    func load(force: Bool = false) async {
        if !force, let lastLoad, Date().timeIntervalSince(lastLoad) < Self.ttl, forecast != nil { return }
        if forecast == nil { status = .loading }
        let loc: CLLocation
        if let fresh = await location.current() {
            loc = fresh
        } else if let cached = WeatherLocationProvider.cached {
            loc = cached
        } else {
            KBLog.navigation.kbError("Home weather: nessuna posizione (permesso negato o lettura fallita)")
            if forecast == nil { status = .noLocation }
            return
        }
        do {
            let city = await Self.cityName(for: loc)
            let result = try await Self.fetch(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, city: city)
            forecast = result
            status = .ready
            lastLoad = Date()
        } catch {
            // WeatherKit non attivo sull'App ID, profilo senza entitlement o
            // rete giù: finisce tutto qui, e il dettaglio serve a capire quale.
            KBLog.navigation.kbError("Home weather: WeatherKit fallito \(String(describing: error))")
            if forecast == nil { status = .failed(error.localizedDescription) }
        }
    }

    /// Il marchio  Meteo è obbligatorio: se la prima lettura fallisce (capita
    /// subito dopo l'accensione) si riprova invece di restare senza fino al
    /// prossimo avvio.
    func loadAttribution() async {
        guard attribution == nil else { return }
        if let cached = Self.cachedAttribution { attribution = cached; return }
        for attempt in 0..<3 {
            if let a = try? await WeatherService.shared.attribution {
                Self.cachedAttribution = a
                attribution = a
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 2_000_000_000)
        }
        KBLog.navigation.kbError("Home weather: attribuzione WeatherKit non disponibile")
    }

    private static var cachedAttribution: WeatherAttribution?

    private static let cityKey = "kb_weather_city"

    /// Nome della località per l'intestazione. Se il geocoding fallisce resta
    /// l'ultimo noto: le coordinate in cache sono le stesse a cui si riferisce.
    private static func cityName(for location: CLLocation) async -> String? {
        let d = UserDefaults.standard
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            let name = item.addressRepresentations?.cityName ?? item.placemark.locality ?? item.placemark.subAdministrativeArea
            if let name, !name.isEmpty {
                d.set(name, forKey: cityKey)
                return name
            }
        }
        return d.string(forKey: cityKey)
    }

    private static func fetch(latitude: Double, longitude: Double, city: String?) async throws -> KBWeatherForecast {
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
        let today = daily.forecast.first { Calendar.current.isDateInToday($0.date) } ?? daily.forecast.first
        return KBWeatherForecast(
            temperature: Int(current.temperature.converted(to: .celsius).value.rounded()),
            symbol: current.symbolName.kbFilled,
            min: Int((today?.lowTemperature.converted(to: .celsius).value ?? 0).rounded()),
            max: Int((today?.highTemperature.converted(to: .celsius).value ?? 0).rounded()),
            hours: Array(hours),
            city: city,
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
                    VStack(alignment: .leading, spacing: 12) {
                        if let city = f.city {
                            Label(city, systemImage: "location.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .labelStyle(.titleAndIcon)
                        }
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
                    }
                    // Tutta la parte con i dati apre Meteo di Apple, che è la
                    // fonte; il link alle fonti sotto resta un tocco a parte.
                    .contentShape(Rectangle())
                    .onTapGesture { openWeatherApp() }
                    .accessibilityAddTraits(.isButton)
                    if let a = model.attribution {
                        attributionRow(a)
                    } else {
                        // Finché il marchio non arriva, almeno il testo e il link.
                        HStack(spacing: 8) {
                            Text(" Meteo")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let legal = URL(string: "https://weatherkit.apple.com/legal-attribution.html") {
                                Link("Fonti dei dati", destination: legal)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(cardFill)
                )
                .overlay(cardBorder)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                placeholder
            }
        }
        .task { await model.load() }
        .task { await model.loadAttribution() }
    }

    /// In chiaro la scheda è crema come lo sfondo dell'app, non bianca: le nuvole multicolor di
    /// WeatherKit sono bianche e su un fondo bianco sparivano.
    private var cardFill: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    /// Contorno sottile in chiaro: la scheda è dello stesso colore dello sfondo.
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(colorScheme == .dark ? Color.clear : Color(red: 0.847, green: 0.839, blue: 0.816), lineWidth: 0.5)
    }

    /// Barra vuota ma presente: dice perché e offre l'unica azione utile.
    @ViewBuilder
    private var placeholder: some View {
        HStack(spacing: 12) {
            switch model.status {
            case .loading, .ready:
                ProgressView()
                Text("Meteo")
                    .foregroundStyle(.secondary)
                Spacer()
            case .noLocation:
                Image(systemName: "location.slash")
                    .foregroundStyle(.secondary)
                Text("Consenti la posizione per vedere il meteo")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline.weight(.semibold))
            case .failed(let message):
                Image(systemName: "cloud.slash")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meteo non disponibile")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    #if DEBUG
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                    #endif
                }
                Spacer()
                Button("Riprova") {
                    Task { await model.load(force: true) }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .tint(KBTheme.bubbleTint)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(cardFill))
        .overlay(cardBorder)
    }

    /// Meteo di Apple non ha uno schema documentato: `weather://` lo apre su
    /// iPhone e iPad; dove non risponde (Mac) si ripiega sulla pagina delle
    /// fonti di Apple Meteo.
    private func openWeatherApp() {
        guard let url = URL(string: "weather://") else { return }
        UIApplication.shared.open(url) { ok in
            guard !ok, let legal = model.attribution?.legalPageURL else { return }
            UIApplication.shared.open(legal)
        }
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
