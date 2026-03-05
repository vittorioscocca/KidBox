//
//  PediatricMedicalRecordView.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//
import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Scheda Medica

struct PediatricMedicalRecordView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let familyId: String
    let childId: String
    
    @State private var profile: KBPediatricProfile? = nil
    @State private var bloodGroup   = ""
    @State private var allergies    = ""
    @State private var medicalNotes = ""
    @State private var doctorName   = ""
    @State private var doctorPhone  = ""
    @State private var isSaving     = false
    
    private let bloodGroups = ["Non specificato", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
    
    var body: some View {
        Form {
            Section("Gruppo sanguigno") {
                Picker("Gruppo sanguigno", selection: $bloodGroup) {
                    ForEach(bloodGroups, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Allergie conosciute") {
                TextField("es. Latte, uova, pollini", text: $allergies, axis: .vertical).lineLimit(2...4)
            }
            Section("Pediatra di riferimento") {
                TextField("Dott./Dott.ssa", text: $doctorName)
                TextField("Telefono", text: $doctorPhone).keyboardType(.phonePad)
            }
            Section("Note mediche") {
                TextField("Eventuali condizioni o note importanti", text: $medicalNotes, axis: .vertical).lineLimit(3...6)
            }
            Section {
                Button(isSaving ? "Salvataggio..." : "Salva scheda") { save() }
                    .disabled(isSaving)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Scheda Medica")
        .onAppear { load() }
    }
    
    private func load() {
        let cid = childId
        let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
        if let p = try? modelContext.fetch(desc).first {
            profile = p
            bloodGroup   = p.bloodGroup   ?? ""
            allergies    = p.allergies    ?? ""
            medicalNotes = p.medicalNotes ?? ""
            doctorName   = p.doctorName   ?? ""
            doctorPhone  = p.doctorPhone  ?? ""
        }
    }
    
    private func save() {
        isSaving = true
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        if let p = profile {
            p.bloodGroup   = bloodGroup.isEmpty   ? nil : bloodGroup
            p.allergies    = allergies.isEmpty     ? nil : allergies
            p.medicalNotes = medicalNotes.isEmpty  ? nil : medicalNotes
            p.doctorName   = doctorName.isEmpty    ? nil : doctorName
            p.doctorPhone  = doctorPhone.isEmpty   ? nil : doctorPhone
            p.updatedAt = now; p.updatedBy = uid
        } else {
            let p = KBPediatricProfile(
                childId: childId, familyId: familyId,
                bloodGroup: bloodGroup.isEmpty ? nil : bloodGroup,
                allergies: allergies.isEmpty ? nil : allergies,
                medicalNotes: medicalNotes.isEmpty ? nil : medicalNotes,
                doctorName: doctorName.isEmpty ? nil : doctorName,
                doctorPhone: doctorPhone.isEmpty ? nil : doctorPhone,
                updatedAt: now, updatedBy: uid
            )
            modelContext.insert(p)
            profile = p
        }
        try? modelContext.save()
        isSaving = false
    }
}
