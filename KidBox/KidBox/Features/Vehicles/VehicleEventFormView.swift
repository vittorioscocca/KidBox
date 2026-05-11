//
//  VehicleEventFormView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct VehicleEventFormView: View {
    let familyId: String
    let vehicleId: String
    var existing: KBVehicleEvent?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var title: String = ""
    @State private var typeRaw: String = "service"
    @State private var date = Date()
    @State private var kmText: String = ""
    @State private var costText: String = ""
    @State private var garage: String = ""
    @State private var notes: String = ""
    @State private var attachmentEventId: String
    @State private var saveCompleted = false

    init(familyId: String, vehicleId: String, existing: KBVehicleEvent?) {
        self.familyId = familyId
        self.vehicleId = vehicleId
        self.existing = existing
        _attachmentEventId = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private let types: [(String, String)] = [
        ("Tagliando", "service"),
        ("Filtro olio", "oil_filter"),
        ("Filtro GPL", "gpl_filter"),
        ("Pasticche freni", "brake_pads"),
        ("Riparazione", "repair"),
        ("Cambio gomme", "tire"),
        ("Revisione", "revision"),
        ("Altro", "other"),
    ]

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titolo", text: $title)
                    Picker("Tipo", selection: $typeRaw) {
                        ForEach(types, id: \.1) { t in
                            Text(t.0).tag(t.1)
                        }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    TextField("Chilometri", text: $kmText)
                        .keyboardType(.numberPad)
                    TextField("Costo", text: $costText)
                        .keyboardType(.decimalPad)
                    TextField("Officina", text: $garage)
                }
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: { Text("Note") }
                Section {
                    VehicleEventAttachmentsSection(eventId: attachmentEventId, familyId: familyId)
                } header: { Text("Allegati") }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle(existing == nil ? "Nuovo intervento" : "Modifica intervento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(!canSave)
                        .tint(accentOrange)
                }
            }
            .onAppear {
                guard let e = existing else { return }
                title = e.title
                typeRaw = e.eventTypeRaw
                date = e.date
                if let k = e.km { kmText = "\(k)" }
                if let c = e.cost { costText = KidBoxDecimalFormat.string(from: c) }
                garage = e.garageName ?? ""
                notes = e.notes ?? ""
            }
            .onDisappear {
                if existing == nil && !saveCompleted {
                    VehicleAttachmentService.shared.deleteAllForEvent(
                        eventId: attachmentEventId,
                        familyId: familyId,
                        modelContext: modelContext
                    )
                }
            }
        }
    }

    private func save() {
        saveCompleted = true
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let km = Int(kmText.trimmingCharacters(in: .whitespacesAndNewlines))
        let cost = KidBoxDecimalFormat.parse(costText)
        let g = garage.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ex = existing {
            ex.title = t
            ex.eventTypeRaw = typeRaw
            ex.date = date
            ex.km = km
            ex.cost = cost
            ex.garageName = g.isEmpty ? nil : g
            ex.notes = n.isEmpty ? nil : n
            ex.updatedAt = now
            ex.updatedBy = uid
            ex.syncState = .pendingUpsert
            ex.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueVehicleEventUpsert(eventId: ex.id, familyId: familyId, modelContext: modelContext)
        } else {
            let ev = KBVehicleEvent(
                id: attachmentEventId,
                familyId: familyId,
                vehicleId: vehicleId,
                title: t,
                eventTypeRaw: typeRaw,
                date: date,
                km: km,
                cost: cost,
                garageName: g.isEmpty ? nil : g,
                notes: n.isEmpty ? nil : n,
                createdBy: uid,
                updatedBy: uid
            )
            modelContext.insert(ev)
            try? modelContext.save()
            SyncCenter.shared.enqueueVehicleEventUpsert(eventId: ev.id, familyId: familyId, modelContext: modelContext)
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}
