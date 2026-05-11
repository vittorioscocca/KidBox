//
//  VehicleEventsListView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct VehicleEventsListView: View {
    let familyId: String
    let vehicleId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var events: [KBVehicleEvent]

    @State private var searchText = ""

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.18)
            : Color(.systemBackground)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var vehicleEvents: [KBVehicleEvent] {
        events.filter { $0.vehicleId == vehicleId && !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }

    private var filteredEvents: [KBVehicleEvent] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return vehicleEvents }
        return vehicleEvents.filter { ev in
            if ev.title.lowercased().contains(q) { return true }
            if (ev.notes ?? "").lowercased().contains(q) { return true }
            if (ev.garageName ?? "").lowercased().contains(q) { return true }
            if KidBoxVehicleEventType.localized(ev.eventTypeRaw).lowercased().contains(q) { return true }
            if let k = ev.km, String(k).contains(q) { return true }
            if let c = ev.cost {
                let costStr = KidBoxDecimalFormat.string(from: c)
                if costStr.lowercased().contains(q) { return true }
            }
            return false
        }
    }

    init(familyId: String, vehicleId: String) {
        self.familyId = familyId
        self.vehicleId = vehicleId
        let fid = familyId
        let vid = vehicleId
        _events = Query(
            filter: #Predicate<KBVehicleEvent> { $0.familyId == fid && $0.vehicleId == vid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBVehicleEvent.date, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if filteredEvents.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "Nessun intervento" : "Nessun risultato",
                    systemImage: "wrench.and.screwdriver",
                    description: Text(searchText.isEmpty ? "Aggiungi interventi dalla scheda veicolo." : "Prova con altre parole chiave.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEvents, id: \.id) { ev in
                            eventRow(ev)
                            Divider()
                        }
                    }
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Interventi")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Cerca per titolo, tipo, officina…")
        .onAppear {
            SyncCenter.shared.startVehicleEventsRealtime(familyId: familyId, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func eventRow(_ ev: KBVehicleEvent) -> some View {
        Button {
            coordinator.navigate(to: .vehicleEventDetail(familyId: familyId, vehicleId: vehicleId, eventId: ev.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: KidBoxVehicleEventType.symbol(for: ev.eventTypeRaw))
                    .foregroundStyle(accentOrange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ev.title)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(VehicleEventsListView.dtf.string(from: ev.date))
                        .font(.custom("Nunito", size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let k = ev.km { Text("\(k) km").font(.caption) }
                        if let c = ev.cost {
                            Text(KidBoxDecimalFormat.string(from: c) + " €")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.secondary)
                    if let g = ev.garageName?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty {
                        Text(g)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }

    private static let dtf: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}
