//
//  ReferenceDoctorFormView.swift
//  KidBox
//

import SwiftUI

struct ReferenceDoctorDraft: Equatable {
    var name: String = ""
    var email: String = ""
    var address: String = ""
    var website: String = ""
    var officeHours: [KBDoctorOfficeHourSlot] = []
}

struct ReferenceDoctorFormView: View {
    @Environment(\.dismiss) private var dismiss

    let isChild: Bool
    let initial: ReferenceDoctorDraft
    let onSave: (ReferenceDoctorDraft) -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var address = ""
    @State private var website = ""
    @State private var officeHours: [KBDoctorOfficeHourSlot] = []

    private var title: String {
        isChild ? "Pediatra di riferimento" : "Medico di riferimento"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dati medico") {
                    TextField("Nome e cognome", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Indirizzo studio", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Sito web (opzionale)", text: $website)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    if officeHours.isEmpty {
                        Text("Nessun orario di ricevimento")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach($officeHours) { $slot in
                            OfficeHourSlotEditor(slot: $slot)
                        }
                        .onDelete { indexSet in
                            officeHours.remove(atOffsets: indexSet)
                        }
                    }

                    Button {
                        officeHours.append(
                            KBDoctorOfficeHourSlot(
                                weekday: KBItalianWeekday.lunedi.rawValue,
                                fromTime: "09:00",
                                toTime: "13:00"
                            )
                        )
                    } label: {
                        Label("Aggiungi fascia oraria", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Orari di studio")
                } footer: {
                    Text("Indica il giorno e scegli le fasce dalle/alle con i selettori orario.")
                        .font(.caption)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        onSave(
                            ReferenceDoctorDraft(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                                address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                                website: website.trimmingCharacters(in: .whitespacesAndNewlines),
                                officeHours: officeHours
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                name = initial.name
                email = initial.email
                address = initial.address
                website = initial.website
                officeHours = initial.officeHours
            }
        }
    }
}

private struct OfficeHourSlotEditor: View {
    @Binding var slot: KBDoctorOfficeHourSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Giorno", selection: $slot.weekday) {
                ForEach(KBItalianWeekday.allCases) { day in
                    Text(day.uiLabel).tag(day.rawValue)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dalle").font(.caption).foregroundStyle(.secondary)
                    TimePickerField(timeString: $slot.fromTime)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alle").font(.caption).foregroundStyle(.secondary)
                    TimePickerField(timeString: $slot.toTime)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
