//
//  HousePaymentFormView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct HousePaymentFormView: View {
    let familyId: String
    var existing: KBHousePayment?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var typeRaw: String = KidBoxHousePaymentType.bolletta.rawValue
    @State private var subtypeRaw: String = ""
    @State private var importoText: String = ""
    @State private var hasGiorno = false
    @State private var giorno: Int = 5
    @State private var hasDataScadenza = false
    @State private var dataScadenza = Date()
    @State private var hasDataContratto = false
    @State private var dataContratto = Date()
    @State private var fornitore: String = ""
    @State private var note: String = ""
    @State private var reminderOn = true

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private let billSubtypes: [(String, String)] = [
        ("Luce", "luce"), ("Gas", "gas"), ("Internet", "internet"), ("Telefono", "telefono"),
        ("Acqua", "acqua"), ("Condominio", "condominio"),
    ]
    private let taxSubtypes: [(String, String)] = [
        ("IMU", "IMU"), ("TARI", "TARI"), ("Dichiarazione redditi", "dichiarazione redditi"),
        ("Bollo auto", "bollo auto"), ("Altre", "altre"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                    Picker("Tipo", selection: $typeRaw) {
                        ForEach(KidBoxHousePaymentType.allCases, id: \.rawValue) { t in
                            Text(t.title).tag(t.rawValue)
                        }
                    }
                    .onChange(of: typeRaw) { _, new in
                        if KidBoxHousePaymentType(rawValue: new) == .bolletta {
                            if subtypeRaw.isEmpty || taxSubtypes.contains(where: { $0.1 == subtypeRaw }) {
                                subtypeRaw = "luce"
                            }
                        } else if KidBoxHousePaymentType(rawValue: new) == .tassa {
                            if subtypeRaw.isEmpty || billSubtypes.contains(where: { $0.1 == subtypeRaw }) {
                                subtypeRaw = "IMU"
                            }
                        }
                    }

                    if KidBoxHousePaymentType(rawValue: typeRaw) == .bolletta {
                        Picker("Tipologia", selection: $subtypeRaw) {
                            ForEach(billSubtypes, id: \.1) { pair in
                                Text(pair.0).tag(pair.1)
                            }
                        }
                    } else if KidBoxHousePaymentType(rawValue: typeRaw) == .tassa {
                        Picker("Tipologia", selection: $subtypeRaw) {
                            ForEach(taxSubtypes, id: \.1) { pair in
                                Text(pair.0).tag(pair.1)
                            }
                        }
                    } else if KidBoxHousePaymentType(rawValue: typeRaw) == .altro {
                        TextField("Tipologia (libero)", text: $subtypeRaw)
                    } else {
                        TextField("Dettaglio (opzionale)", text: $subtypeRaw)
                    }

                    TextField("Importo (opzionale)", text: $importoText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    if showsGiorno {
                        Toggle("Giorno di scadenza nel mese", isOn: $hasGiorno)
                        if hasGiorno {
                            Stepper(value: $giorno, in: 1...31) {
                                Text("Giorno: \(giorno)")
                            }
                        }
                    }
                    if showsDataScadenza {
                        Toggle("Data scadenza annuale", isOn: $hasDataScadenza)
                        if hasDataScadenza {
                            DatePicker("Scadenza", selection: $dataScadenza, displayedComponents: .date)
                        }
                    }
                    if showsDataContratto {
                        Toggle("Scadenza contratto", isOn: $hasDataContratto)
                        if hasDataContratto {
                            DatePicker("Contratto fino al", selection: $dataContratto, displayedComponents: .date)
                        }
                    }
                }

                Section {
                    TextField("Banca / gestore / agenzia", text: $fornitore)
                } header: { Text("Fornitore") }

                Section {
                    TextEditor(text: $note)
                        .frame(minHeight: 80)
                } header: { Text("Note") }

                Section {
                    Toggle("Promemoria (3 giorni prima)", isOn: $reminderOn)
                }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle(existing == nil ? "Nuova scadenza" : "Modifica")
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
                guard let e = existing else {
                    if KidBoxHousePaymentType(rawValue: typeRaw) == .bolletta { subtypeRaw = "luce" }
                    if KidBoxHousePaymentType(rawValue: typeRaw) == .tassa { subtypeRaw = "IMU" }
                    return
                }
                name = e.name
                typeRaw = e.typeRaw
                subtypeRaw = e.subtypeRaw ?? ""
                if let imp = e.importo { importoText = String(format: "%.2f", imp).replacingOccurrences(of: ".", with: ",") }
                if let g = e.giornoDiScadenzaMensile { hasGiorno = true; giorno = g }
                if let d = e.dataScadenza { hasDataScadenza = true; dataScadenza = d }
                if let c = e.dataScadenzaContratto { hasDataContratto = true; dataContratto = c }
                fornitore = e.fornitore ?? ""
                note = e.note ?? ""
                reminderOn = e.reminderOn
            }
        }
    }

    private var showsGiorno: Bool {
        switch KidBoxHousePaymentType(rawValue: typeRaw) {
        case .mutuo, .affitto, .bolletta, .altro: return true
        default: return false
        }
    }

    private var showsDataScadenza: Bool {
        switch KidBoxHousePaymentType(rawValue: typeRaw) {
        case .tassa, .altro: return true
        default: return false
        }
    }

    private var showsDataContratto: Bool {
        switch KidBoxHousePaymentType(rawValue: typeRaw) {
        case .mutuo, .affitto: return true
        default: return false
        }
    }

    private func parsedImporto() -> Double? {
        let t = importoText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let v = Double(t) else { return nil }
        return v
    }

    private func normalizedSubtype() -> String? {
        let t = subtypeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let giornoVal: Int? = (hasGiorno && showsGiorno) ? giorno : nil
        let dataScad: Date? = (hasDataScadenza && showsDataScadenza) ? dataScadenza : nil
        let dataContr: Date? = (hasDataContratto && showsDataContratto) ? dataContratto : nil

        if let ex = existing {
            ex.name = n
            ex.typeRaw = typeRaw
            ex.subtypeRaw = normalizedSubtype()
            ex.importo = parsedImporto()
            ex.giornoDiScadenzaMensile = giornoVal
            ex.dataScadenza = dataScad
            ex.dataScadenzaContratto = dataContr
            ex.fornitore = fornitore.trimmedNil
            ex.note = note.trimmedNil
            ex.reminderOn = reminderOn
            ex.updatedAt = now
            ex.updatedBy = uid
            ex.syncState = .pendingUpsert
            ex.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueueHousePaymentUpsert(paymentId: ex.id, familyId: familyId, modelContext: modelContext)
            Task { await HousePaymentReminderService.shared.scheduleNext(for: ex) }
        } else {
            let row = KBHousePayment(
                familyId: familyId,
                name: n,
                typeRaw: typeRaw,
                subtypeRaw: normalizedSubtype(),
                importo: parsedImporto(),
                giornoDiScadenzaMensile: giornoVal,
                dataScadenza: dataScad,
                dataScadenzaContratto: dataContr,
                fornitore: fornitore.trimmedNil,
                note: note.trimmedNil,
                reminderOn: reminderOn,
                createdBy: uid,
                updatedBy: uid
            )
            modelContext.insert(row)
            try? modelContext.save()
            SyncCenter.shared.enqueueHousePaymentUpsert(paymentId: row.id, familyId: familyId, modelContext: modelContext)
            Task { await HousePaymentReminderService.shared.scheduleNext(for: row) }
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
