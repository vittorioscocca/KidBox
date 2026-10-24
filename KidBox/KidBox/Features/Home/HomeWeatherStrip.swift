//
//  HomeWeatherStrip.swift
//  KidBox
//
//  La barra del meteo in Home: ora, prossime ore e minima/massima di oggi.
//  Fonte Open-Meteo (senza chiave, la stessa su iOS e Android, così i due
//  client non possono dare previsioni diverse). La posizione è una lettura
//  singola e approssimata, solo con l'app aperta; le coordinate restano sul
//  telefono (UserDefaults) e non vanno mai a KidBox. Senza permesso, o senza
//  rete, la barra non compare: una barra vuota in Home è peggio di nessuna barra.
//

import SwiftUI
import Combine
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
    let code: Int
    let isDay: Bool
    var id: Date { date }
}

struct KBWeatherForecast: Equatable {
    let temperature: Int
    let code: Int
    let isDay: Bool
    let min: Int
    let max: Int
    let hours: [KBWeatherHour]
    let city: String?
    let fetchedAt: Date
}

/// Codici WMO di Open-Meteo → simbolo SF.
func kbWeatherSymbol(code: Int, isDay: Bool) -> String {
    switch code {
    case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
    case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
    case 3: return "cloud.fill"
    case 45, 48: return "cloud.fog.fill"
    case 51...57: return "cloud.drizzle.fill"
    case 61...67, 80...82: return "cloud.rain.fill"
    case 71...77, 85, 86: return "cloud.snow.fill"
    case 95...99: return "cloud.bolt.rain.fill"
    default: return "cloud.fill"
    }
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
            forecast = result
            lastLoad = Date()
        } catch {
            KBLog.navigation.kbDebug("Home weather: fetch fallito \(error.localizedDescription)")
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let timezone: String
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    private static func fetch(latitude: Double, longitude: Double) async throws -> KBWeatherForecast {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", latitude)),
            .init(name: "longitude", value: String(format: "%.2f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "2"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let r = try JSONDecoder().decode(Response.self, from: data)

        // Gli orari sono locali al luogo, senza fuso: si leggono nel suo fuso.
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let tz = TimeZone(identifier: r.timezone) { fmt.timeZone = tz }
        let now = Date()
        var hours: [KBWeatherHour] = []
        for i in r.hourly.time.indices {
            guard let d = fmt.date(from: r.hourly.time[i]), d > now.addingTimeInterval(-3600) else { continue }
            hours.append(KBWeatherHour(date: d,
                                       temperature: Int(r.hourly.temperature_2m[i].rounded()),
                                       code: r.hourly.weather_code[i],
                                       isDay: r.hourly.is_day[i] == 1))
            if hours.count == 8 { break }
        }
        return KBWeatherForecast(
            temperature: Int(r.current.temperature_2m.rounded()),
            code: r.current.weather_code,
            isDay: r.current.is_day == 1,
            min: Int((r.daily.temperature_2m_min.first ?? 0).rounded()),
            max: Int((r.daily.temperature_2m_max.first ?? 0).rounded()),
            hours: Array(hours.dropFirst()),
            city: nil,
            fetchedAt: now
        )
    }
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
                        Image(systemName: kbWeatherSymbol(code: f.code, isDay: f.isDay))
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
                                    Image(systemName: kbWeatherSymbol(code: h.code, isDay: h.isDay))
                                        .symbolRenderingMode(.multicolor)
                                        .font(.title3)
                                    Text("\(h.temperature)°")
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                        }
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
}
