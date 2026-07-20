//
//  PetFormView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PetFormView: View {
    let familyId: String
    var existingPet: KBPet?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String = ""
    @State private var speciesRaw: String = "cane"
    @State private var breed: String = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var colorText: String = ""
    @State private var chipCode: String = ""
    @State private var notes: String = ""

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let speciesOptions: [(label: LocalizedStringKey, value: String)] = [
        ("Cane", "cane"),
        ("Gatto", "gatto"),
        ("Coniglio", "coniglio"),
        ("Criceto", "criceto"),
        ("Uccello", "uccello"),
        ("Altro", "altro"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $name)
                        .font(.custom("Nunito", size: 16))
                    Picker("Specie", selection: $speciesRaw) {
                        ForEach(speciesOptions, id: \.value) { opt in
                            Text(opt.label).tag(opt.value)
                        }
                    }
                    .font(.custom("Nunito", size: 16))
                    TextField("Razza (opzionale)", text: $breed)
                        .font(.custom("Nunito", size: 16))
                }
                Section {
                    Toggle("Data di nascita", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Data", selection: $birthDate, displayedComponents: .date)
                    }
                    TextField("Colore", text: $colorText)
                        .font(.custom("Nunito", size: 16))
                    TextField("Microchip", text: $chipCode)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.custom("Nunito", size: 16))
                }
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .font(.custom("Nunito", size: 15))
                } header: {
                    Text("Note")
                }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundColor)
            .navigationTitle(existingPet == nil ? "Nuovo animale domestico" : "Modifica animale domestico")
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
                guard let p = existingPet else { return }
                name = p.name
                speciesRaw = p.species
                breed = p.breed ?? ""
                if let b = p.birthDate {
                    hasBirthDate = true
                    birthDate = b
                }
                colorText = p.color ?? ""
                chipCode = p.chipCode ?? ""
                notes = p.notes ?? ""
            }
        }
    }

    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = colorText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chip = chipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = existingPet {
            existing.name = trimmedName
            existing.species = speciesRaw
            existing.breed = b.isEmpty ? nil : b
            existing.birthDate = hasBirthDate ? birthDate : nil
            existing.color = c.isEmpty ? nil : c
            existing.chipCode = chip.isEmpty ? nil : chip
            existing.notes = n.isEmpty ? nil : n
            existing.updatedAt = now
            existing.updatedBy = uid
            existing.syncState = .pendingUpsert
            existing.lastSyncError = nil
            try? modelContext.save()
            SyncCenter.shared.enqueuePetUpsert(petId: existing.id, familyId: familyId, modelContext: modelContext)
        } else {
            let pet = KBPet(
                familyId: familyId,
                name: trimmedName,
                species: speciesRaw,
                breed: b.isEmpty ? nil : b,
                birthDate: hasBirthDate ? birthDate : nil,
                color: c.isEmpty ? nil : c,
                chipCode: chip.isEmpty ? nil : chip,
                notes: n.isEmpty ? nil : n,
                photoURL: nil,
                createdBy: uid,
                updatedBy: uid
            )
            modelContext.insert(pet)
            try? modelContext.save()
            SyncCenter.shared.enqueuePetUpsert(petId: pet.id, familyId: familyId, modelContext: modelContext)
        }
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}
