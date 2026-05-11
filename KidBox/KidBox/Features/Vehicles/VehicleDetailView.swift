//
//  VehicleDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct VehicleDetailView: View {
    let familyId: String
    let vehicleId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var vehicles: [KBVehicle]
    @Query private var events: [KBVehicleEvent]

    @State private var showEdit = false
    @State private var showAddEvent = false
    @State private var showDeleteVehicle = false

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

    private var vehicle: KBVehicle? { vehicles.first }

    private var vehicleEvents: [KBVehicleEvent] {
        events.filter { $0.vehicleId == vehicleId && !$0.isDeleted }
            .sorted { $0.date > $1.date }
    }

    init(familyId: String, vehicleId: String) {
        self.familyId = familyId
        self.vehicleId = vehicleId
        let fid = familyId
        let vid = vehicleId
        _vehicles = Query(filter: #Predicate<KBVehicle> { $0.id == vid && $0.familyId == fid })
        _events = Query(
            filter: #Predicate<KBVehicleEvent> { $0.familyId == fid && $0.vehicleId == vid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBVehicleEvent.date, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if let v = vehicle {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(v)
                        sectionHeader("Scadenze")
                        deadline("Assicurazione", v.insuranceExpiryDate)
                        deadline("Revisione", v.revisionExpiryDate)
                        deadline("Bollo", v.taxExpiryDate)
                        deadline("Prossimo tagliando", v.nextServiceDate)
                        sectionHeader("Storico interventi")
                        if vehicleEvents.isEmpty {
                            Text("Nessun intervento registrato")
                                .font(.custom("Nunito", size: 15))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(vehicleEvents, id: \.id) { ev in
                                    eventRow(ev)
                                    Divider()
                                }
                            }
                            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("Veicolo non trovato", systemImage: "car")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(vehicle?.name ?? "Veicolo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if vehicle != nil {
                    Button { showAddEvent = true } label: { Image(systemName: "plus") }
                        .tint(accentOrange)
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                    Button(role: .destructive) { showDeleteVehicle = true } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let v = vehicle { VehicleFormView(familyId: familyId, existing: v) }
        }
        .sheet(isPresented: $showAddEvent) {
            VehicleEventFormView(familyId: familyId, vehicleId: vehicleId, existing: nil)
        }
        .alert("Eliminare questo veicolo?", isPresented: $showDeleteVehicle) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) { Task { await deleteVehicleAsync() } }
        } message: {
            Text("Verranno eliminati anche gli interventi collegati.")
        }
        .onAppear {
            SyncCenter.shared.startVehiclesRealtime(familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.startVehicleEventsRealtime(familyId: familyId, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func header(_ v: KBVehicle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(v.name)
                .font(.custom("Nunito", size: 22).weight(.bold))
            let bm = [v.brand, v.model].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
            if !bm.isEmpty {
                Text(bm)
                    .font(.custom("Nunito", size: 16))
                    .foregroundStyle(.secondary)
            }
            if let y = v.year { Text("Anno: \(y)").font(.custom("Nunito", size: 15)) }
            if let f = v.fuelTypeRaw {
                Text("Carburante: \(KidBoxVehicleFuel.localized(f))")
                    .font(.custom("Nunito", size: 15))
            }
            if let c = v.color?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                Text("Colore: \(c)")
                    .font(.custom("Nunito", size: 15))
            }
            if let p = v.licensePlate?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
                Text("Targa: \(p)")
                    .font(.custom("Nunito", size: 15).weight(.semibold))
            }
            if let vin = v.vin?.trimmingCharacters(in: .whitespacesAndNewlines), !vin.isEmpty {
                Text("VIN: \(vin)")
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(.secondary)
            }
            if let k = v.currentKm {
                Text("Chilometri: \(k) km")
                    .font(.custom("Nunito", size: 15))
            }
            if let n = v.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                Text(n).font(.custom("Nunito", size: 14)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t)
            .font(.custom("Nunito", size: 13).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func deadline(_ title: String, _ date: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let d = date {
                    Text(VehicleDetailView.df.string(from: d))
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                    Text(KidBoxUrgency.label(days: KidBoxUrgency.daysRemaining(to: d)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(KidBoxUrgency.color(days: KidBoxUrgency.daysRemaining(to: d)))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let d = date {
                Circle()
                    .fill(KidBoxUrgency.color(days: KidBoxUrgency.daysRemaining(to: d)))
                    .frame(width: 10, height: 10)
            }
        }
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    Text(VehicleDetailView.dtf.string(from: ev.date))
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

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .medium
        return f
    }()

    private static let dtf: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func deleteVehicleAsync() async {
        guard let v = vehicle else { return }
        await VehicleReminderService.shared.cancelAll(vehicleId: v.id)
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        for ev in events where ev.vehicleId == v.id && !ev.isDeleted {
            ev.isDeleted = true
            ev.updatedAt = now
            ev.updatedBy = uid
            ev.syncState = .pendingDelete
            SyncCenter.shared.enqueueVehicleEventDelete(eventId: ev.id, familyId: familyId, modelContext: modelContext)
        }
        v.isDeleted = true
        v.updatedAt = now
        v.updatedBy = uid
        v.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueVehicleDelete(vehicleId: v.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.path.removeLast()
    }
}

enum KidBoxVehicleFuel {
    static func localized(_ raw: String) -> String {
        switch raw.lowercased() {
        case "diesel": return "Diesel"
        case "elettrica": return "Elettrica"
        case "ibrida": return "Ibrida"
        case "gpl": return "GPL"
        default: return "Benzina"
        }
    }
}

enum KidBoxVehicleEventType {
    static func symbol(for raw: String) -> String {
        switch raw {
        case "service": return "wrench.and.screwdriver"
        case "oil_filter": return "wrench.and.drop"
        case "gpl_filter": return "fuelpump"
        case "brake_pads": return "car.brakes"
        case "repair": return "hammer"
        case "tire": return "circle.circle"
        case "revision": return "checkmark.seal"
        default: return "ellipsis.circle"
        }
    }

    static func localized(_ raw: String) -> String {
        switch raw {
        case "service": return "Tagliando"
        case "oil_filter": return "Filtro olio"
        case "gpl_filter": return "Filtro GPL"
        case "brake_pads": return "Pasticche freni"
        case "repair": return "Riparazione"
        case "tire": return "Cambio gomme"
        case "revision": return "Revisione"
        default: return "Altro"
        }
    }
}
