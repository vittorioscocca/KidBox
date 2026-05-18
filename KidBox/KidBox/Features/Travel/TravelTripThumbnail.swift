//
//  TravelTripThumbnail.swift
//  KidBox
//

import SwiftUI

struct TravelTripThumbnailSpec: Equatable {
    let systemImage: String
    let colors: [Color]
}

enum TravelTripThumbnailResolver {

    static func resolve(tripName: String, legs: [KBTripLeg]) -> TravelTripThumbnailSpec {
        let sortedLegs = legs.sorted { $0.order < $1.order }
        let destination = primaryDestination(tripName: tripName, legs: sortedLegs)
        let haystack = normalized(
            [tripName, destination]
                + sortedLegs.flatMap { [$0.fromLocation, $0.toLocation] }
        )

        if let themed = theme(from: haystack) {
            return themed
        }
        if let leg = sortedLegs.last ?? sortedLegs.first {
            return spec(for: leg.transportMode, seed: destination.isEmpty ? tripName : destination)
        }
        return defaultSpec(seed: destination.isEmpty ? tripName : destination)
    }

    static func primaryDestination(tripName: String, legs: [KBTripLeg]) -> String {
        if let last = legs.last?.toLocation.trimmingCharacters(in: .whitespacesAndNewlines), !last.isEmpty {
            return last
        }
        let name = tripName.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = [" – ", " - ", " — ", " a ", " in ", " per ", " verso ", ", "]
        for separator in separators {
            if let range = name.range(of: separator, options: [.caseInsensitive, .backwards]) {
                let tail = String(name[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if tail.count >= 2 { return tail }
            }
        }
        return name
    }

    private static func normalized(_ parts: [String]) -> String {
        parts
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    private static func theme(from haystack: String) -> TravelTripThumbnailSpec? {
        let rules: [(keywords: [String], image: String, colors: [Color])] = [
            (
                ["mare", "spiaggia", "costa", "isola", "lido", "baia", "cala", "beach", "sea", "coast", "island"],
                "beach.umbrella.fill",
                [Color(red: 0.12, green: 0.55, blue: 0.82), Color(red: 0.20, green: 0.78, blue: 0.90)]
            ),
            (
                ["montagna", "alpi", "dolomiti", "trekking", "rifugio", "mountain", "hike", "trail"],
                "mountain.2.fill",
                [Color(red: 0.22, green: 0.48, blue: 0.34), Color(red: 0.45, green: 0.62, blue: 0.42)]
            ),
            (
                ["neve", "sci", "snow", "ski"],
                "snowflake",
                [Color(red: 0.45, green: 0.62, blue: 0.86), Color(red: 0.78, green: 0.88, blue: 0.98)]
            ),
            (
                ["parco", "natura", "foresta", "camping", "lake", "lago"],
                "leaf.fill",
                [Color(red: 0.18, green: 0.52, blue: 0.28), Color(red: 0.42, green: 0.72, blue: 0.38)]
            ),
            (
                ["roma", "milano", "napoli", "paris", "london", "barcelona", "city", "città", "centro"],
                "building.2.fill",
                [Color(red: 0.36, green: 0.28, blue: 0.72), Color(red: 0.52, green: 0.42, blue: 0.88)]
            ),
        ]
        for rule in rules where rule.keywords.contains(where: { haystack.contains($0) }) {
            return TravelTripThumbnailSpec(systemImage: rule.image, colors: rule.colors)
        }
        return nil
    }

    private static func spec(for mode: TransportMode, seed: String) -> TravelTripThumbnailSpec {
        let palette = gradientPalette(seed: seed)
        return TravelTripThumbnailSpec(systemImage: mode.icon, colors: palette)
    }

    private static func defaultSpec(seed: String) -> TravelTripThumbnailSpec {
        TravelTripThumbnailSpec(systemImage: "map.fill", colors: gradientPalette(seed: seed))
    }

    private static func gradientPalette(seed: String) -> [Color] {
        let hash = stableHash(seed.isEmpty ? "trip" : seed)
        let hue = Double(hash % 360) / 360.0
        let start = Color(hue: hue, saturation: 0.55, brightness: 0.72)
        let end = Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.48, brightness: 0.88)
        return [start, end]
    }

    private static func stableHash(_ string: String) -> Int {
        string.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7FFF_FFFF
        }
    }
}

struct TravelTripThumbnailView: View {
    let tripName: String
    let legs: [KBTripLeg]

    private var spec: TravelTripThumbnailSpec {
        TravelTripThumbnailResolver.resolve(tripName: tripName, legs: legs)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: spec.colors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: spec.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 48, height: 48)
        .accessibilityHidden(true)
    }
}
