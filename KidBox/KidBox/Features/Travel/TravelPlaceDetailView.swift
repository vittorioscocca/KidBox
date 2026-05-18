//
//  TravelPlaceDetailView.swift
//  KidBox
//

import MapKit
import SwiftUI
import UIKit

struct TravelPlaceDetailView: View {

    let context: TravelItineraryStopContext
    let familyId: String

    @State private var details: TravelPlaceDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Caricamento luogo…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let details {
                content(details)
            } else {
                fallbackContent
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(context.placeName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPlace() }
    }

    @ViewBuilder
    private func content(_ place: TravelPlaceDetails) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoHero(place)
                headerSection(place)
                scheduleCard
                directionsButton(place)
                if !place.about.isEmpty {
                    aboutSection(place.about)
                }
                if place.hasCoordinates {
                    mapSection(place)
                }
                if !place.reviews.isEmpty {
                    reviewsSection(place)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private var fallbackContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(nil)
                scheduleCard
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                directionsButton(nil)
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private func photoHero(_ place: TravelPlaceDetails) -> some View {
        if place.photoURLs.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [accent.opacity(0.35), accent.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(height: 220)
        } else {
            TabView {
                ForEach(Array(place.photoURLs.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color(.secondarySystemBackground)
                                .overlay { ProgressView() }
                        }
                    }
                    .frame(height: 260)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(index + 1) / \(place.photoURLs.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(12)
                    }
                }
            }
            .frame(height: 260)
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    // MARK: - Sections

    private func headerSection(_ place: TravelPlaceDetails?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(place?.category ?? "Tappa itinerario")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accent.opacity(0.12), in: Capsule())

            Text(place?.name ?? context.placeName)
                .font(.title.bold())

            if let place, let rating = place.rating, place.reviewCount > 0 {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: i < Int(rating.rounded()) ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundStyle(accent)
                        }
                    }
                    Text(String(format: "%.1f", rating))
                        .font(.subheadline.weight(.semibold))
                    Text("· \(place.reviewCount) recensioni")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("IN PROGRAMMA")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(context.scheduleBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            HStack(spacing: 0) {
                scheduleColumn(title: "ARRIVO", value: context.time.isEmpty ? "—" : context.time)
                Divider().frame(height: 36).background(.white.opacity(0.2))
                scheduleColumn(title: "PERMANENZA", value: context.staySummary.isEmpty ? "—" : context.staySummary)
                Divider().frame(height: 36).background(.white.opacity(0.2))
                scheduleColumn(title: "STIMA", value: context.costSummary.isEmpty ? "—" : context.costSummary)
            }

            if let next = context.nextStopTitle, !next.isEmpty {
                HStack(spacing: 6) {
                    if !context.time.isEmpty {
                        Text(context.time)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    Text("→ \(next)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.14, blue: 0.16), Color(red: 0.28, green: 0.16, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func scheduleColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private func directionsButton(_ place: TravelPlaceDetails?) -> some View {
        Button {
            openDirections(place)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "location.fill")
                Text("Indicazioni")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .disabled(place == nil && errorMessage != nil)
    }

    private func aboutSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INFO")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
    }

    private func mapSection(_ place: TravelPlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(position: $cameraPosition, interactionModes: [.zoom, .pan]) {
                Marker(place.name, coordinate: CLLocationCoordinate2D(
                    latitude: place.latitude,
                    longitude: place.longitude
                ))
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onAppear {
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
                cameraPosition = .region(region)
            }

            if !place.address.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text(place.address)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "figure.walk")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
    }

    private func reviewsSection(_ place: TravelPlaceDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENSIONI")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if place.reviewCount > place.reviews.count {
                    Text("Vedi tutte (\(place.reviewCount))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }

            ForEach(place.reviews) { review in
                reviewCard(review)
            }

            HStack {
                Spacer()
                Text("powered by Google")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func reviewCard(_ review: TravelPlaceReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(review.text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName)
                        .font(.caption.weight(.semibold))
                    if !review.relativeTime.isEmpty {
                        Text(review.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: i < review.rating ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private func loadPlace() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            details = try await TravelPlacesService.fetchDetails(
                placeName: context.placeName,
                locationContext: context.locationContext,
                familyId: familyId
            )
        } catch {
            errorMessage = error.localizedDescription
            details = nil
        }
    }

    private func openDirections(_ place: TravelPlaceDetails?) {
        if let place, place.hasCoordinates {
            let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            let placemark = MKPlacemark(coordinate: coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = place.name
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking,
            ])
            return
        }
        if let uri = place?.googleMapsURI {
            UIApplication.shared.open(uri)
            return
        }
        let query = "\(context.placeName), \(context.locationContext)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? context.placeName
        if let url = URL(string: "http://maps.apple.com/?q=\(query)") {
            UIApplication.shared.open(url)
        }
    }
}
