//
//  HomeItemFormView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct HomeItemFormView: View {
    let familyId: String
    var existing: KBHomeItem?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Id stabile per allegati prima del primo salvataggio.
    @State private var attachmentHomeItemId: String
    @State private var saveCompleted = false

    @State private var name: String = ""
    @State private var categoryRaw: String = "appliance"
    @State private var brand: String = ""
    @State private var model: String = ""
    @State private var serialNumber: String = ""
    @State private var hasPurchase = false
    @State private var purchaseDate = Date()
    @State private var hasWarranty = false
    @State private var warrantyDate = Date()
    @State private var hasService = false
    @State private var serviceDate = Date()
    @State private var hasPeriod = false
    @State private var serviceMonths: Int = 12
    @State private var notes: String = ""

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let cats: [(String, String)] = [
        ("Elettrodomestico", "appliance"),
        ("Impianto", "system"),
        ("Contratto", "contract"),
        ("Altro", "other"),
    ]

    init(familyId: String, existing: KBHomeItem?) {
        self.familyId = familyId
        self.existing = existing
        _attachmentHomeItemId = State(initialValue: existing?.id ?? UUID().uuidString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                    Picker("Categoria", selection: $categoryRaw) {
                        ForEach(cats, id: \.1) { c in
                            Text(c.0).tag(c.1)
                        }
                    }
                    TextField("Marca", text: $brand)
                    TextField("Modello", text: $model)
                    TextField("Numero di serie", text: $serialNumber)
                }
                Section {
                    Toggle("Data acquisto", isOn: $hasPurchase)
                    if hasPurchase { DatePicker("Acquisto", selection: $purchaseDate, displayedComponents: .date) }
                    Toggle("Scadenza garanzia", isOn: $hasWarranty)
                    if hasWarranty { DatePicker("Garanzia", selection: $warrantyDate, displayedComponents: .date) }
                    Toggle("Prossima manutenzione", isOn: $hasService)
                    if hasService {
                        DatePicker("Manutenzione", selection: $serviceDate, displayedComponents: .date)
                        Toggle("Periodicità (mesi)", isOn: $hasPeriod)
                        if hasPeriod {
                            Stepper(value: $serviceMonths, in: 1...60) {
                                Text("Ogni \(serviceMonths) mesi")
                            }
                        }
                    }
                }
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                } header: { Text("Note") }
                Section {
                    HomeItemAttachmentsSection(homeItemId: attachmentHomeItemId, familyId: familyId)
                } header: { Text("Allegati") }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle(existing == nil ? "Nuovo elemento" : "Modifica")
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
                guard let e = existing else { return }
                name = e.name
                categoryRaw = e.categoryRaw
                brand = e.brand ?? ""
                model = e.model ?? ""
                serialNumber = e.serialNumber ?? ""
                if let p = e.purchaseDate { hasPurchase = true; purchaseDate = p }
                if let w = e.warrantyExpiryDate { hasWarranty = true; warrantyDate = w }
                if let s = e.nextServiceDate { hasService = true; serviceDate = s }
                if let m = e.servicePeriodMonths { hasPeriod = true; serviceMonths = m }
                notes = e.notes ?? ""
            }
            .onDisappear {
                if existing == nil && !saveCompleted {
                    HomeAttachmentService.shared.deleteAllForHomeItem(
                        homeItemId: attachmentHomeItemId,
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
        let reminder = hasWarranty || hasService

        if let ex = existing {
            ex.name = n
            ex.categoryRaw = categoryRaw
            ex.brand = brand.trimmedNil
            ex.model = model.trimmedNil
            ex.serialNumber = serialNumber.trimmedNil
            ex.purchaseDate = hasPurchase ? purchaseDate : nil
            ex.warrantyExpiryDate = hasWarranty ? warrantyDate : nil
            ex.nextServiceDate = hasService ? serviceDate : nil
            ex.servicePeriodMonths = (hasService && hasPeriod) ? serviceMonths : nil
            ex.notes = notes.trimmedNil
            ex.reminderEnabled = reminder
            ex.updatedAt = now
            ex.updatedBy = uid
            ex.syncState = .pendingUpsert
            ex.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueHomeItemUpsert(itemId: ex.id, familyId: familyId, modelContext: modelContext)
        } else {
            let row = KBHomeItem(
                id: attachmentHomeItemId,
                familyId: familyId,
                name: n,
                categoryRaw: categoryRaw,
                brand: brand.trimmedNil,
                model: model.trimmedNil,
                serialNumber: serialNumber.trimmedNil,
                purchaseDate: hasPurchase ? purchaseDate : nil,
                warrantyExpiryDate: hasWarranty ? warrantyDate : nil,
                nextServiceDate: hasService ? serviceDate : nil,
                servicePeriodMonths: (hasService && hasPeriod) ? serviceMonths : nil,
                notes: notes.trimmedNil,
                createdBy: uid,
                updatedBy: uid,
                reminderEnabled: reminder,
                reminderId: nil
            )
            modelContext.insert(row)
            try? modelContext.save()
            SyncCenter.shared.enqueueHomeItemUpsert(itemId: row.id, familyId: familyId, modelContext: modelContext)
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
