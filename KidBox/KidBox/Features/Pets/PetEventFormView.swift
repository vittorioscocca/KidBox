//
//  PetEventFormView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PetEventFormView: View {
    let familyId: String
    let petId: String
    var existingEvent: KBPetEvent?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// Id stabile per allegati prima del primo salvataggio (parity HomeItemFormView).
    @State private var attachmentEventId: String
    @State private var saveCompleted = false

    @State private var title: String = ""
    @State private var eventTypeRaw: String = "vaccine"
    @State private var date = Date()
    @State private var hasNextDue = false
    @State private var nextDueDate = Date()
    @State private var vetName: String = ""
    @State private var costText: String = ""
    @State private var notes: String = ""

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private let typeOptions: [(label: String, value: String)] = [
        ("Vaccino", "vaccine"),
        ("Visita veterinaria", "vet_visit"),
        ("Farmaco", "medication"),
        ("Toelettatura", "grooming"),
        ("Altro", "other"),
    ]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(familyId: String, petId: String, existingEvent: KBPetEvent?) {
        self.familyId = familyId
        self.petId = petId
        self.existingEvent = existingEvent
        _attachmentEventId = State(initialValue: existingEvent?.id ?? UUID().uuidString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titolo", text: $title)
                        .font(.custom("Nunito", size: 16))
                    Picker("Tipo evento", selection: $eventTypeRaw) {
                        ForEach(typeOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
                Section {
                    Toggle("Prossima scadenza", isOn: $hasNextDue)
                    if hasNextDue {
                        DatePicker("Prossima scadenza", selection: $nextDueDate, displayedComponents: [.date])
                    }
                    TextField("Veterinario", text: $vetName)
                    TextField("Costo", text: $costText)
                        .keyboardType(.decimalPad)
                }
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                        .font(.custom("Nunito", size: 15))
                } header: {
                    Text("Note")
                }
                Section {
                    PetEventAttachmentsSection(eventId: attachmentEventId, familyId: familyId)
                } header: {
                    Text("Allegati")
                }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle(existingEvent == nil ? "Nuovo evento" : "Modifica evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .tint(accentOrange)
                }
            }
            .onAppear {
                guard let e = existingEvent else { return }
                title = e.title
                eventTypeRaw = e.eventTypeRaw
                date = e.date
                if let nd = e.nextDueDate {
                    hasNextDue = true
                    nextDueDate = nd
                }
                vetName = e.vetName ?? ""
                if let c = e.cost { costText = KidBoxDecimalFormat.string(from: c) }
                notes = e.notes ?? ""
            }
        }
    }

    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let v = vetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cost = KidBoxDecimalFormat.parse(costText)

        let reminder = hasNextDue

        if let existing = existingEvent {
            existing.title = t
            existing.eventTypeRaw = eventTypeRaw
            existing.date = date
            existing.nextDueDate = hasNextDue ? nextDueDate : nil
            existing.notes = n.isEmpty ? nil : n
            existing.vetName = v.isEmpty ? nil : v
            existing.cost = cost
            existing.reminderEnabled = reminder
            existing.updatedAt = now
            existing.updatedBy = uid
            existing.syncState = .pendingUpsert
            existing.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueuePetEventUpsert(eventId: existing.id, familyId: familyId, modelContext: modelContext)
        } else {
            let ev = KBPetEvent(
                id: attachmentEventId,
                familyId: familyId,
                petId: petId,
                title: t,
                eventTypeRaw: eventTypeRaw,
                date: date,
                nextDueDate: hasNextDue ? nextDueDate : nil,
                notes: n.isEmpty ? nil : n,
                vetName: v.isEmpty ? nil : v,
                cost: cost,
                createdBy: uid,
                updatedBy: uid,
                reminderEnabled: reminder,
                reminderId: nil
            )
            modelContext.insert(ev)
            try? modelContext.save()
            SyncCenter.shared.enqueuePetEventUpsert(eventId: ev.id, familyId: familyId, modelContext: modelContext)
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}

enum KidBoxDecimalFormat {
    static func parse(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return Double(t)
    }

    static func string(from d: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: d)) ?? "\(d)"
    }
}
