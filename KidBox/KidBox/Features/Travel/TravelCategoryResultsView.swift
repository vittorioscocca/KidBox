//
//  TravelCategoryResultsView.swift
//  KidBox
//

import SwiftUI

struct TravelCategoryResultsPresentation: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let emoji: String
    let items: [TravelPlaceResult]
    let destinationTitle: String
}

struct TravelCategoryResultsView: View {

    let title: String
    let emoji: String
    let items: [TravelPlaceResult]
    let familyId: String
    let destinationTitle: String

    @State private var selectedPlace: TravelItineraryStopContext?
    @State private var isShowingMap = false

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    /// Luoghi reali dalla ricerca Google, quando disponibili.
    @State private var placesResults: [TravelPlaceSummary] = []
    @State private var isLoadingPlaces = true

    /// Categoria Places corrispondente a questa lista. `nil` per le liste che
    /// non hanno un equivalente cercabile: lì resta l'itinerario.
    private var searchKind: TravelPlaceSearchKind? {
        switch title {
        case "Ristoranti": return .restaurant
        case "Hotel": return .hotel
        case "Attività": return .attraction
        default: return nil
        }
    }

    /// L'itinerario si mostra ovunque tranne che sugli Hotel.
    ///
    /// Lì le voci sono estratte dal testo del piano e sono descrizioni, non
    /// nomi di strutture ("Pernottamento in un hotel vicino al centro"):
    /// niente da prenotare né da cercare, quindi Google resta la sola fonte.
    private var showsItinerarySection: Bool {
        searchKind != .hotel
    }

    /// Voci dell'itinerario che la mappa può provare a posizionare.
    ///
    /// Solo dove la sezione itinerario è visibile: mostrare sulla mappa righe
    /// che nella lista non ci sono sarebbe la mappa di un'altra lista.
    private var mappableItineraryItems: [TravelPlaceResult] {
        showsItinerarySection ? items.filter(\.isBrowsableOnMap) : []
    }

    /// Il tasto Mappa compare solo se c'è davvero qualcosa da disegnare.
    private var canShowMap: Bool {
        placesResults.contains { $0.coordinate != nil } || !mappableItineraryItems.isEmpty
    }

    var body: some View {
        List {
            if !placesResults.isEmpty {
                Section {
                    ForEach(placesResults) { place in
                        placeRow(for: place)
                    }
                } header: {
                    Text("A \(destinationTitle) · da Google")
                } footer: {
                    Text("Locali reali con le valutazioni di Google, ordinati per voto.")
                }
            }

            if isLoadingPlaces, placesResults.isEmpty, searchKind != nil {
                HStack {
                    ProgressView()
                    Text("Cerco luoghi a \(destinationTitle)…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // L'itinerario accettato resta la fonte più vicina al viaggio
            // dell'utente: i locali di Google si affiancano, non lo sostituiscono.
            if showsItinerarySection, !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        row(for: item)
                    }
                } header: {
                    Text("Dal tuo itinerario")
                }
            }

            if placesResults.isEmpty, !isLoadingPlaces,
               !(showsItinerarySection && !items.isEmpty) {
                ContentUnavailableView(
                    "Nessun risultato",
                    systemImage: "magnifyingglass",
                    // Sugli Hotel dire "rigenera il piano" non aiuterebbe: la
                    // lista non dipende più dall'itinerario.
                    description: Text(
                        showsItinerarySection
                        ? "Non abbiamo trovato suggerimenti in questo itinerario. Prova a rigenerare il piano."
                        : "Nessun hotel trovato su Google per \(destinationTitle)."
                    )
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canShowMap {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingMap = true
                    } label: {
                        Label("Mappa", systemImage: "map")
                    }
                    .labelStyle(.titleAndIcon)
                    .tint(accent)
                }
            }
        }
        .navigationDestination(item: $selectedPlace) { context in
            TravelPlaceDetailView(context: context, familyId: familyId)
        }
        .sheet(isPresented: $isShowingMap) {
            TravelPlacesMapView(
                title: title,
                kind: searchKind,
                destinationTitle: destinationTitle,
                familyId: familyId,
                places: placesResults,
                itineraryItems: mappableItineraryItems
            )
        }
        .task(id: destinationTitle) {
            guard let kind = searchKind, !destinationTitle.isEmpty else {
                isLoadingPlaces = false
                return
            }
            defer { isLoadingPlaces = false }
            placesResults = (try? await TravelPlacesService.searchPlaces(
                locationContext: destinationTitle,
                kind: kind,
                familyId: familyId
            )) ?? []
        }
    }

    /// Riga di un luogo reale: nome, categoria, indirizzo e stelle Google.
    @ViewBuilder
    private func placeRow(for place: TravelPlaceSummary) -> some View {
        Button {
            selectedPlace = TravelItineraryStopContext(
                id: place.placeId,
                placeName: place.name,
                locationContext: destinationTitle,
                scheduleBadge: "",
                time: "",
                staySummary: place.category,
                costSummary: place.address,
                nextStopTitle: nil
            )
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(emoji).font(.title3)
                    Text(place.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
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
                        if !place.category.isEmpty {
                            Text("· \(place.category)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !place.address.isEmpty {
                    Text(place.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func row(for item: TravelPlaceResult) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(emoji).font(.title3)
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if item.isBrowsableOnMap {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                }
            }
            if !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !item.meta.isEmpty {
                Text(item.meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TravelPlaceRatingBadge(item: item, familyId: familyId)
        }
        .padding(.vertical, 4)

        if item.isBrowsableOnMap {
            Button {
                selectedPlace = placeContext(for: item)
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func placeContext(for item: TravelPlaceResult) -> TravelItineraryStopContext {
        let location = item.locationContext.isEmpty
            ? destinationTitle
            : item.locationContext
        return TravelItineraryStopContext(
            id: item.id,
            placeName: item.placeName,
            locationContext: location,
            scheduleBadge: title.uppercased(),
            time: "",
            staySummary: item.subtitle,
            costSummary: item.meta,
            nextStopTitle: nil
        )
    }
}


/// Stelle Google di una riga, caricate quando la riga compare.
///
/// Il caricamento è per riga e non in blocco all'apertura della lista: la List
/// è pigra, quindi partono solo le richieste delle righe effettivamente viste.
/// Su un itinerario con decine di locali, chiedere tutti i voti in anticipo
/// significherebbe pagare Places anche per righe che l'utente non guarda mai.
private struct TravelPlaceRatingBadge: View {
    let item: TravelPlaceResult
    let familyId: String

    @State private var rating: TravelPlaceRating?

    var body: some View {
        Group {
            if let rating {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", rating.value))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    if rating.reviewCount > 0 {
                        Text("(\(rating.reviewCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: item.placeName) {
            // Senza un nome utilizzabile non ha senso interrogare Places.
            guard !item.placeName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            rating = await TravelPlaceRatingStore.shared.rating(
                placeName: item.placeName,
                locationContext: item.locationContext,
                familyId: familyId
            )
        }
    }
}
