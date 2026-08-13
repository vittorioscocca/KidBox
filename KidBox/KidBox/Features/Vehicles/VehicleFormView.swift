//
//  VehicleFormView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct VehicleFormView: View {
    let familyId: String
    var existing: KBVehicle?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var licensePlate: String = ""
    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var yearText: String = ""
    @State private var fuelRaw: String = "benzina"
    @State private var color: String = ""
    @State private var vin: String = ""
    @State private var hasIns = false
    @State private var insDate = Date()
    @State private var insOffsets: Set<Int> = Set(VehicleReminderOffsets.defaultOffsets)
    @State private var hasRev = false
    @State private var revDate = Date()
    @State private var revOffsets: Set<Int> = Set(VehicleReminderOffsets.defaultOffsets)
    @State private var hasTax = false
    @State private var taxDate = Date()
    @State private var taxOffsets: Set<Int> = Set(VehicleReminderOffsets.defaultOffsets)
    @State private var hasService = false
    @State private var serviceDate = Date()
    @State private var serviceOffsets: Set<Int> = Set(VehicleReminderOffsets.defaultOffsets)
    @State private var kmText: String = ""
    @State private var notes: String = ""
    /// Id stabile per allegati (nuovo veicolo = UUID assegnato all’apertura del form).
    @State private var attachmentVehicleId: String
    @State private var saveCompleted = false

    init(familyId: String, existing: KBVehicle?) {
        self.familyId = familyId
        self.existing = existing
        _attachmentVehicleId = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let fuels: [(String, String)] = [
        ("Benzina", "benzina"),
        ("Diesel", "diesel"),
        ("Elettrica", "elettrica"),
        ("Ibrida", "ibrida"),
        ("GPL", "gpl"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                    TextField("Targa", text: $licensePlate)
                    TextField("Marca", text: $brand)
                    TextField("Modello", text: $model)
                    TextField("Anno", text: $yearText)
                        .keyboardType(.numberPad)
                    Picker("Carburante", selection: $fuelRaw) {
                        ForEach(fuels, id: \.1) { f in
                            Text(f.0).tag(f.1)
                        }
                    }
                    TextField("Colore", text: $color)
                    TextField("Numero telaio / VIN", text: $vin)
                }
                Section("Scadenze") {
                    Toggle("Assicurazione", isOn: $hasIns)
                    if hasIns {
                        DatePicker("Scadenza", selection: $insDate, displayedComponents: .date)
                        VehicleReminderOffsetPicker(selected: $insOffsets, accentColor: accentOrange)
                    }
                    Toggle("Revisione", isOn: $hasRev)
                    if hasRev {
                        DatePicker("Scadenza", selection: $revDate, displayedComponents: .date)
                        VehicleReminderOffsetPicker(selected: $revOffsets, accentColor: accentOrange)
                    }
                    Toggle("Bollo", isOn: $hasTax)
                    if hasTax {
                        DatePicker("Scadenza", selection: $taxDate, displayedComponents: .date)
                        VehicleReminderOffsetPicker(selected: $taxOffsets, accentColor: accentOrange)
                    }
                    Toggle("Prossimo tagliando", isOn: $hasService)
                    if hasService {
                        DatePicker("Data", selection: $serviceDate, displayedComponents: .date)
                        VehicleReminderOffsetPicker(selected: $serviceOffsets, accentColor: accentOrange)
                    }
                }
                Section {
                    TextField("Chilometri attuali", text: $kmText)
                        .keyboardType(.numberPad)
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: { Text("Note") }
                Section {
                    VehicleAttachmentsSection(vehicleId: attachmentVehicleId, familyId: familyId)
                } header: { Text("Allegati") }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle(existing == nil ? "Nuovo veicolo" : "Modifica veicolo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .tint(accentOrange)
                }
            }
            .onAppear {
                guard let v = existing else { return }
                name = v.name
                licensePlate = v.licensePlate ?? ""
                brand = v.brand ?? ""
                model = v.model ?? ""
                if let y = v.year { yearText = "\(y)" }
                fuelRaw = v.fuelTypeRaw ?? "benzina"
                color = v.color ?? ""
                vin = v.vin ?? ""
                if let d = v.insuranceExpiryDate { hasIns = true; insDate = d }
                if let d = v.revisionExpiryDate { hasRev = true; revDate = d }
                if let d = v.taxExpiryDate { hasTax = true; taxDate = d }
                if let d = v.nextServiceDate { hasService = true; serviceDate = d }
                let offsets = VehicleReminderOffsets.decode(json: v.reminderOffsetsJson)
                insOffsets = Set(offsets.insurance)
                revOffsets = Set(offsets.revision)
                taxOffsets = Set(offsets.tax)
                serviceOffsets = Set(offsets.service)
                if let k = v.currentKm { kmText = "\(k)" }
                notes = v.notes ?? ""
            }
            .onDisappear {
                if existing == nil && !saveCompleted {
                    VehicleAttachmentService.shared.deleteAllForVehicle(
                        vehicleId: attachmentVehicleId,
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
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(yearText.trimmingCharacters(in: .whitespacesAndNewlines))
        let km = Int(kmText.trimmingCharacters(in: .whitespacesAndNewlines))
        let reminder = hasIns || hasRev || hasTax || hasService
        let reminderOffsetsJson = VehicleReminderOffsets(
            insurance: Array(insOffsets).sorted(),
            revision: Array(revOffsets).sorted(),
            tax: Array(taxOffsets).sorted(),
            service: Array(serviceOffsets).sorted()
        ).encoded()

        if let ex = existing {
            ex.name = n
            ex.licensePlate = licensePlate.trimmedNil
            ex.brand = brand.trimmedNil
            ex.model = model.trimmedNil
            ex.year = year
            ex.fuelTypeRaw = fuelRaw
            ex.color = color.trimmedNil
            ex.vin = vin.trimmedNil
            ex.insuranceExpiryDate = hasIns ? insDate : nil
            ex.revisionExpiryDate = hasRev ? revDate : nil
            ex.taxExpiryDate = hasTax ? taxDate : nil
            ex.nextServiceDate = hasService ? serviceDate : nil
            ex.currentKm = km
            ex.notes = notes.trimmedNil
            ex.reminderEnabled = reminder
            ex.reminderOffsetsJson = reminderOffsetsJson
            ex.updatedAt = now
            ex.updatedBy = uid
            ex.syncState = .pendingUpsert
            ex.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueVehicleUpsert(vehicleId: ex.id, familyId: familyId, modelContext: modelContext)
            Task { await VehicleReminderService.shared.scheduleReminders(for: ex) }
        } else {
            let v = KBVehicle(
                id: attachmentVehicleId,
                familyId: familyId,
                name: n,
                licensePlate: licensePlate.trimmedNil,
                brand: brand.trimmedNil,
                model: model.trimmedNil,
                year: year,
                fuelTypeRaw: fuelRaw,
                color: color.trimmedNil,
                vin: vin.trimmedNil,
                insuranceExpiryDate: hasIns ? insDate : nil,
                revisionExpiryDate: hasRev ? revDate : nil,
                taxExpiryDate: hasTax ? taxDate : nil,
                lastServiceDate: nil,
                nextServiceDate: hasService ? serviceDate : nil,
                currentKm: km,
                notes: notes.trimmedNil,
                photoURL: nil,
                createdBy: uid,
                updatedBy: uid,
                reminderEnabled: reminder,
                reminderId: nil,
                reminderOffsetsJson: reminderOffsetsJson
            )
            modelContext.insert(v)
            try? modelContext.save()
            SyncCenter.shared.enqueueVehicleUpsert(vehicleId: v.id, familyId: familyId, modelContext: modelContext)
            Task { await VehicleReminderService.shared.scheduleReminders(for: v) }
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}

private extension String {
    var trimmedNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Chip multi-select per gli offset di preavviso (giorno stesso / 2 giorni prima / 1 settimana prima) di una scadenza.
struct VehicleReminderOffsetPicker: View {
    @Binding var selected: Set<Int>
    var accentColor: Color

    private let options: [(days: Int, label: String)] = [
        (0, "Stesso giorno"),
        (2, "2 giorni prima"),
        (7, "1 settimana prima"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Avvisi"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.days) { option in
                        let isOn = selected.contains(option.days)
                        Button {
                            if isOn { selected.remove(option.days) } else { selected.insert(option.days) }
                        } label: {
                            Text(option.label)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(isOn ? accentColor : Color.gray.opacity(0.15))
                                )
                                .foregroundColor(isOn ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
