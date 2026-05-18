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

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nessun risultato",
                    systemImage: "magnifyingglass",
                    description: Text("Non abbiamo trovato suggerimenti in questo itinerario. Prova a rigenerare il piano.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(items) { item in
                    row(for: item)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedPlace) { context in
            TravelPlaceDetailView(context: context, familyId: familyId)
        }
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
