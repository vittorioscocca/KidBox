//
//  TravelAllTripsView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct TravelAllTripsView: View {

    let familyId: String

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query private var trips: [KBTrip]
    @Query private var tripLegs: [KBTripLeg]

    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showDeleteConfirm = false

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _trips = Query(
            filter: #Predicate<KBTrip> { $0.familyId == fid },
            sort: [SortDescriptor(\KBTrip.startDate, order: .reverse)]
        )
        _tripLegs = Query(
            filter: #Predicate<KBTripLeg> { $0.familyId == fid },
            sort: [SortDescriptor(\KBTripLeg.order)]
        )
    }

    private var legsByTripId: [String: [KBTripLeg]] {
        Dictionary(grouping: tripLegs, by: \.tripId)
            .mapValues { $0.sorted { $0.order < $1.order } }
    }

    private var filteredTrips: [KBTrip] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return trips }
        return trips.filter { trip in
            if trip.name.lowercased().contains(q) { return true }
            let range = TravelTripDateRangeFormatter.format(start: trip.startDate, end: trip.endDate)
            if range.lowercased().contains(q) { return true }
            let legs = legsByTripId[trip.id] ?? []
            for leg in legs {
                if leg.fromLocation.lowercased().contains(q) { return true }
                if leg.toLocation.lowercased().contains(q) { return true }
            }
            return false
        }
    }

    var body: some View {
        Group {
            if trips.isEmpty {
                ContentUnavailableView(
                    "Nessun viaggio",
                    systemImage: "airplane",
                    description: Text("I viaggi che crei compariranno qui.")
                )
            } else if filteredTrips.isEmpty {
                ContentUnavailableView(
                    "Nessun risultato",
                    systemImage: "magnifyingglass",
                    description: Text("Prova con altre parole chiave.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredTrips) { trip in
                            let legs = legsByTripId[trip.id] ?? []
                            let selected = selectedIds.contains(trip.id)
                            Button {
                                if isSelecting {
                                    toggleSelection(trip.id)
                                } else {
                                    coordinator.navigate(
                                        to: .travelTripDetail(familyId: familyId, tripId: trip.id)
                                    )
                                }
                            } label: {
                                TravelTripCardView(
                                    trip: trip,
                                    legs: legs,
                                    isSelected: selected,
                                    showsSelectionBadge: isSelecting
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle(isSelecting ? "Seleziona viaggi" : "Tutti i viaggi")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Cerca viaggio o destinazione…")
        .toolbar {
            if !trips.isEmpty {
                if isSelecting {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") {
                            isSelecting = false
                            selectedIds.removeAll()
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(selectedIds.count == filteredTrips.count ? "Deseleziona" : "Tutti") {
                            if selectedIds.count == filteredTrips.count {
                                selectedIds.removeAll()
                            } else {
                                selectedIds = Set(filteredTrips.map(\.id))
                            }
                        }
                        Button("Elimina", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .disabled(selectedIds.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Seleziona") {
                            isSelecting = true
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) viaggi?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                deleteSelectedTrips()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questa azione non può essere annullata.")
        }
        .onDisappear {
            isSelecting = false
            selectedIds.removeAll()
        }
    }

    private func toggleSelection(_ tripId: String) {
        if selectedIds.contains(tripId) {
            selectedIds.remove(tripId)
        } else {
            selectedIds.insert(tripId)
        }
    }

    private func deleteSelectedTrips() {
        let toDelete = trips.filter { selectedIds.contains($0.id) }
        guard !toDelete.isEmpty else { return }
        Task { @MainActor in
            let store = TripRemoteStore()
            for trip in toDelete {
                await store.deleteTrip(trip, modelContext: modelContext)
            }
            selectedIds.removeAll()
            isSelecting = false
        }
    }
}
