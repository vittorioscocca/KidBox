//
//  TravelTripCardView.swift
//  KidBox
//

import SwiftUI

enum TravelTripDateRangeFormatter {
    private static let locale = Locale(identifier: "it_IT")

    static func format(start: Date, end: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(start, inSameDayAs: end) {
            return start.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        }

        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)

        if startYear == endYear, startMonth == endMonth {
            let startDay = calendar.component(.day, from: start)
            let endDay = calendar.component(.day, from: end)
            let monthYear = start.formatted(.dateTime.month(.abbreviated).year().locale(locale))
            return "\(startDay) – \(endDay) \(monthYear)"
        }

        if startYear == endYear {
            let startPart = start.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            let endPart = end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
            return "\(startPart) – \(endPart)"
        }

        let startPart = start.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        let endPart = end.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
        return "\(startPart) – \(endPart)"
    }
}

struct TravelTripCardBackgroundView: View {
    let tripName: String
    let legs: [KBTripLeg]

    @State private var imageURL: URL?

    private var destination: String {
        TravelTripThumbnailResolver.primaryDestination(tripName: tripName, legs: legs)
    }

    private var spec: TravelTripThumbnailSpec {
        TravelTripThumbnailResolver.resolve(tripName: tripName, legs: legs)
    }

    var body: some View {
        ZStack {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure, .empty:
                            placeholderBackground
                        @unknown default:
                            placeholderBackground
                        }
                    }
                } else {
                    placeholderBackground
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.35), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .task(id: destination) {
            imageURL = await TravelTripPlaceImageLoader.shared.imageURL(for: destination)
        }
    }

    private var placeholderBackground: some View {
        ZStack {
            LinearGradient(
                colors: spec.colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: spec.systemImage)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
                .symbolRenderingMode(.hierarchical)
        }
    }
}

struct TravelTripCardView: View {
    let trip: KBTrip
    let legs: [KBTripLeg]
    var isSelected: Bool = false
    var showsSelectionBadge: Bool = false

    private let cornerRadius: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TravelTripCardBackgroundView(tripName: trip.name, legs: legs)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(trip.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)

                Text(TravelTripDateRangeFormatter.format(start: trip.startDate, end: trip.endDate))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsSelectionBadge {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    }
                    Spacer()
                }
                .padding(.top, 20)
                .padding(.trailing, 16)
            }
        }
        .frame(height: 212)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
