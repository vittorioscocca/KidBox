//
//  VehicleEventDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct VehicleEventDetailView: View {
    let familyId: String
    let vehicleId: String
    let eventId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var events: [KBVehicleEvent]

    @State private var showEdit = false
    @State private var showDelete = false

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

    private var event: KBVehicleEvent? { events.first }

    init(familyId: String, vehicleId: String, eventId: String) {
        self.familyId = familyId
        self.vehicleId = vehicleId
        self.eventId = eventId
        let fid = familyId
        let eid = eventId
        _events = Query(filter: #Predicate<KBVehicleEvent> { $0.id == eid && $0.familyId == fid })
    }

    var body: some View {
        Group {
            if let e = event {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        row("Titolo", e.title)
                        row("Tipo", KidBoxVehicleEventType.localized(e.eventTypeRaw))
                        row("Data", VehicleEventDetailView.dtf.string(from: e.date))
                        if let k = e.km { row("Chilometri", "\(k) km") }
                        if let c = e.cost { row("Costo", KidBoxDecimalFormat.string(from: c) + " €") }
                        if let g = e.garageName, !g.isEmpty { row("Officina", g) }
                        if let n = e.notes, !n.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Note").font(.caption).foregroundStyle(.secondary)
                                Text(n).font(.custom("Nunito", size: 15))
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding()
                }
            } else {
                ContentUnavailableView("Intervento non trovato", systemImage: "wrench")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Intervento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if event != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { showDelete = true } label: { Image(systemName: "trash") }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let e = event {
                VehicleEventFormView(familyId: familyId, vehicleId: vehicleId, existing: e)
            }
        }
        .alert("Eliminare questo intervento?", isPresented: $showDelete) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) { deleteEv() }
        } message: {
            Text("L’operazione non può essere annullata.")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).font(.custom("Nunito", size: 16))
        }
    }

    private static let dtf: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func deleteEv() {
        guard let e = event else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        e.isDeleted = true
        e.updatedAt = Date()
        e.updatedBy = uid
        e.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueVehicleEventDelete(eventId: e.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.path.removeLast()
    }
}
