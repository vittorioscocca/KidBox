//
//  TravelPlacesMapView.swift
//  KidBox
//

import MapKit
import SwiftUI

/// Un luogo disegnato sulla mappa della categoria.
struct TravelMapPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let address: String
    let rating: Double?
    let reviewCount: Int
    let coordinate: CLLocationCoordinate2D
    let mapsURL: URL?
    /// Vero per le voci che vengono dall'itinerario e non da Google: la
    /// posizione è ricavata da una ricerca locale, quindi va distinta.
    let isFromItinerary: Bool

    static func == (lhs: TravelMapPlace, rhs: TravelMapPlace) -> Bool {
        lhs.id == rhs.id
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Mappa di tutti i luoghi elencati in una sezione (Ristoranti / Hotel / Attività).
///
/// I locali di Google arrivano già con le coordinate: si disegnano subito.
/// Le voci dell'itinerario invece sono solo testo, quindi la posizione si
/// cerca con MapKit — gratis e senza chiamare Places una volta per riga.
struct TravelPlacesMapView: View {

    let title: String
    let kind: TravelPlaceSearchKind?
    let destinationTitle: String
    let familyId: String
    let places: [TravelPlaceSummary]
    let itineraryItems: [TravelPlaceResult]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var annotations: [TravelMapPlace] = []
    @State private var selectedID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isResolvingItinerary = false
    @State private var placeDetailContext: TravelItineraryStopContext?

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    private var selectedPlace: TravelMapPlace? {
        annotations.first { $0.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                map

                if let selectedPlace {
                    selectedCard(selectedPlace)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if annotations.isEmpty {
                    emptyState
                }
            }
            .animation(.snappy, value: selectedID)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isResolvingItinerary {
                        ProgressView()
                    } else {
                        Text("\(annotations.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(item: $placeDetailContext) { context in
                TravelPlaceDetailView(context: context, familyId: familyId)
            }
            .task { await loadAnnotations() }
        }
    }

    private var map: some View {
        Map(position: $cameraPosition, selection: $selectedID) {
            ForEach(annotations) { place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    marker(for: place)
                }
                .tag(place.id)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Segnaposto dedicato: pallino colorato col simbolo della categoria e
    /// punta verso il basso, così si distingue dai POI di sistema.
    private func marker(for place: TravelMapPlace) -> some View {
        let isSelected = place.id == selectedID
        let tint = place.isFromItinerary ? Color.blue : accent
        return VStack(spacing: -3) {
            ZStack {
                Circle()
                    .fill(tint)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                Image(systemName: kind?.mapSymbol ?? "mappin")
                    .font(.system(size: isSelected ? 15 : 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: isSelected ? 42 : 34, height: isSelected ? 42 : 34)

            Triangle()
                .fill(tint)
                .frame(width: 12, height: 8)
        }
        .scaleEffect(isSelected ? 1.05 : 1)
        .animation(.snappy, value: isSelected)
    }

    private func selectedCard(_ place: TravelMapPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)
                    if let rating = place.rating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption.weight(.semibold))
                            if place.reviewCount > 0 {
                                Text("(\(place.reviewCount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !place.subtitle.isEmpty {
                                Text("· \(place.subtitle)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } else if !place.subtitle.isEmpty {
                        Text(place.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !place.address.isEmpty {
                        Text(place.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    selectedID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    placeDetailContext = TravelItineraryStopContext(
                        id: place.id,
                        placeName: place.name,
                        locationContext: destinationTitle,
                        scheduleBadge: "",
                        time: "",
                        staySummary: place.subtitle,
                        costSummary: place.address,
                        nextStopTitle: nil
                    )
                } label: {
                    Label("Dettagli", systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accent.opacity(0.15))
                        .foregroundStyle(accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    openInMaps(place)
                } label: {
                    Label("Indicazioni", systemImage: "arrow.triangle.turn.up.right.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.08))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(KBTheme.cardBackground(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isResolvingItinerary {
            ProgressView("Cerco i luoghi sulla mappa…")
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 40)
        } else {
            ContentUnavailableView(
                "Nessun luogo da mostrare",
                systemImage: "mappin.slash",
                description: Text("Non abbiamo la posizione dei luoghi di questa lista.")
            )
            .background(.regularMaterial)
        }
    }

    private func openInMaps(_ place: TravelMapPlace) {
        if let mapsURL = place.mapsURL {
            UIApplication.shared.open(mapsURL)
            return
        }
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        mapItem.name = place.name
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    // MARK: - Caricamento

    private func loadAnnotations() async {
        guard annotations.isEmpty else { return }

        let fromGoogle = places.compactMap { place -> TravelMapPlace? in
            guard let coordinate = place.coordinate else { return nil }
            return TravelMapPlace(
                id: place.placeId,
                name: place.name,
                subtitle: place.category,
                address: place.address,
                rating: place.rating,
                reviewCount: place.reviewCount,
                coordinate: coordinate,
                mapsURL: place.googleMapsURI,
                isFromItinerary: false
            )
        }
        annotations = fromGoogle
        focusOnAnnotations()

        // Le voci dell'itinerario si risolvono una a una: sono poche e la
        // ricerca MapKit non ha un modo per chiederne un blocco.
        let resolvable = itineraryItems.filter(\.isBrowsableOnMap).prefix(12)
        guard !resolvable.isEmpty else { return }

        isResolvingItinerary = true
        defer { isResolvingItinerary = false }

        let hint = fromGoogle.first?.coordinate
        for item in resolvable {
            // Un luogo già trovato su Google non va cercato di nuovo.
            let alreadyThere = annotations.contains {
                $0.name.localizedCaseInsensitiveCompare(item.placeName) == .orderedSame
            }
            guard !alreadyThere else { continue }

            let location = item.locationContext.isEmpty ? destinationTitle : item.locationContext
            guard let placemark = await searchPlacemark(
                for: item.placeName,
                near: location,
                hint: hint
            ) else { continue }

            annotations.append(
                TravelMapPlace(
                    id: item.id,
                    name: item.title,
                    subtitle: item.subtitle,
                    address: placemark.title ?? "",
                    rating: nil,
                    reviewCount: 0,
                    coordinate: placemark.coordinate,
                    mapsURL: nil,
                    isFromItinerary: true
                )
            )
        }
        focusOnAnnotations()
    }

    private func searchPlacemark(
        for name: String,
        near location: String,
        hint: CLLocationCoordinate2D?
    ) async -> MKPlacemark? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location.isEmpty ? name : "\(name), \(location)"
        if let hint {
            request.region = MKCoordinateRegion(
                center: hint,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        let search = MKLocalSearch(request: request)
        guard let response = try? await search.start() else { return nil }
        return response.mapItems.first?.placemark
    }

    /// Inquadratura che contiene tutti i segnaposti.
    private func focusOnAnnotations() {
        let coordinates = annotations.map(\.coordinate)
        guard let first = coordinates.first else { return }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        // Margine del 40% e minimo di 0.01°: con un solo pin, o con pin quasi
        // sovrapposti, altrimenti la mappa entrerebbe a zoom massimo.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
            longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)
        )
        withAnimation(.easeInOut) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

/// Punta del segnaposto.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
