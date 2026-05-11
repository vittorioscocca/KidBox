//
//  VehiclesHomeView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct VehiclesHomeView: View {
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var vehicles: [KBVehicle]

    @State private var showAdd = false

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
    private var titleInk: Color {
        colorScheme == .dark ? .white : (Color(hex: "#1A1A1A") ?? .primary)
    }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _vehicles = Query(
            filter: #Predicate<KBVehicle> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBVehicle.name, order: .forward)]
        )
    }

    var body: some View {
        Group {
            if vehicles.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(vehicles, id: \.id) { v in
                        row(v)
                            .listRowBackground(cardBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Garage")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").fontWeight(.semibold)
                }
                .tint(accentOrange)
            }
        }
        .sheet(isPresented: $showAdd) {
            VehicleFormView(familyId: familyId, existing: nil)
        }
        .onAppear {
            SyncCenter.shared.startVehiclesRealtime(familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.startVehicleEventsRealtime(familyId: familyId, modelContext: modelContext)
        }
        .onDisappear {
            SyncCenter.shared.stopVehiclesRealtime()
            SyncCenter.shared.stopVehicleEventsRealtime()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 52))
                .foregroundStyle(titleInk)
            Text("Nessun veicolo ancora")
                .font(.custom("Nunito", size: 18).weight(.semibold))
                .foregroundStyle(titleInk)
            Button { showAdd = true } label: {
                Text("Aggiungi veicolo")
                    .font(.custom("Nunito", size: 16).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(accentOrange, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(_ v: KBVehicle) -> some View {
        Button {
            coordinator.navigate(to: .vehicleDetail(familyId: familyId, vehicleId: v.id))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .foregroundStyle(titleInk)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.name)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(titleInk)
                    if let plate = v.licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines), !plate.isEmpty {
                        Text(plate)
                            .font(.custom("Nunito", size: 13))
                            .foregroundStyle(.secondary)
                    }
                    if let badge = nextExpiryBadge(v) {
                        Text(badge.text)
                            .font(.custom("Nunito", size: 12).weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badge.color, in: Capsule())
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func nextExpiryBadge(_ v: KBVehicle) -> (text: String, color: Color)? {
        var pairs: [(Date, String)] = []
        if let d = v.insuranceExpiryDate { pairs.append((d, "Assicurazione")) }
        if let d = v.revisionExpiryDate { pairs.append((d, "Revisione")) }
        if let d = v.taxExpiryDate { pairs.append((d, "Bollo")) }
        if let d = v.nextServiceDate { pairs.append((d, "Tagliando")) }
        guard let first = pairs.min(by: { $0.0 < $1.0 }) else { return nil }
        let days = KidBoxUrgency.daysRemaining(to: first.0)
        let color = KidBoxUrgency.color(days: days)
        let df = VehiclesHomeView.shortDF
        return ("\(first.1): \(df.string(from: first.0))", color)
    }

    private static let shortDF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        return f
    }()
}
