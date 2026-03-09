//
//  PediatricMedicalRecordView.swift
//  KidBox
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
    
    // Contatti emergenza
    @State private var contacts: [KBEmergencyContact] = []
    @State private var showAddContact = false
    @State private var editingContact: KBEmergencyContact? = nil
    
    private let bloodGroups = ["Non specificato", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]
    
    var body: some View {
        Form {
            Section("Gruppo sanguigno") {
                Picker("Gruppo sanguigno", selection: $bloodGroup) {
                    ForEach(bloodGroups, id: \.self) { Text($0).tag($0) }
                }
            }
            
            Section("Allergie conosciute") {
                TextField("es. Latte, uova, pollini", text: $allergies, axis: .vertical)
                    .lineLimit(2...4)
            }
            
            Section("Pediatra di riferimento") {
                TextField("Dott./Dott.ssa", text: $doctorName)
                TextField("Telefono", text: $doctorPhone)
                    .keyboardType(.phonePad)
            }
            
            // MARK: - Contatti emergenza
            Section {
                if contacts.isEmpty {
                    Text("Nessun contatto aggiunto")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(contacts) { contact in
                        Button {
                            editingContact = contact
                        } label: {
                            EmergencyContactRow(contact: contact)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        contacts.remove(atOffsets: indexSet)
                    }
                }
                
                Button {
                    showAddContact = true
                } label: {
                    Label("Aggiungi contatto", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Contatti emergenza")
            } footer: {
                Text("Persone da contattare in caso di emergenza (nonni, babysitter, secondo genitore…)")
                    .font(.caption)
            }
            
            Section("Note mediche") {
                TextField("Eventuali condizioni o note importanti", text: $medicalNotes, axis: .vertical)
                    .lineLimit(3...6)
            }
            
            Section {
                Button(isSaving ? "Salvataggio..." : "Salva scheda") { save() }
                    .disabled(isSaving)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Scheda Medica")
        .onAppear {
            load()
            SyncCenter.shared.startPediatricProfileRealtime(
                familyId: familyId, childId: childId, modelContext: modelContext
            )
        }
        .onDisappear {
            SyncCenter.shared.stopPediatricProfileRealtime()
        }
        .sheet(isPresented: $showAddContact) {
            EmergencyContactFormView(contact: nil) { newContact in
                contacts.append(newContact)
            }
        }
        // Sheet: modifica contatto
        .sheet(item: $editingContact) { contact in
            EmergencyContactFormView(contact: contact) { updated in
                if let idx = contacts.firstIndex(where: { $0.id == updated.id }) {
                    contacts[idx] = updated
                }
            }
        }
    }
    
    // MARK: - Load
    
    private func load() {
        let cid = childId
        let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
        if let p = try? modelContext.fetch(desc).first {
            profile      = p
            bloodGroup   = p.bloodGroup   ?? ""
            allergies    = p.allergies    ?? ""
            medicalNotes = p.medicalNotes ?? ""
            doctorName   = p.doctorName   ?? ""
            doctorPhone  = p.doctorPhone  ?? ""
            contacts     = p.emergencyContacts
        }
    }
    
    // MARK: - Save
    
    private func save() {
        isSaving = true
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        if let p = profile {
            p.bloodGroup    = bloodGroup.isEmpty    ? nil : bloodGroup
            p.allergies     = allergies.isEmpty      ? nil : allergies
            p.medicalNotes  = medicalNotes.isEmpty   ? nil : medicalNotes
            p.doctorName    = doctorName.isEmpty     ? nil : doctorName
            p.doctorPhone   = doctorPhone.isEmpty    ? nil : doctorPhone
            p.emergencyContacts = contacts
            p.updatedAt  = now
            p.updatedBy  = uid
            p.syncState  = .pendingUpsert
        } else {
            let p = KBPediatricProfile(
                childId:      childId,
                familyId:     familyId,
                bloodGroup:   bloodGroup.isEmpty    ? nil : bloodGroup,
                allergies:    allergies.isEmpty      ? nil : allergies,
                medicalNotes: medicalNotes.isEmpty   ? nil : medicalNotes,
                doctorName:   doctorName.isEmpty     ? nil : doctorName,
                doctorPhone:  doctorPhone.isEmpty    ? nil : doctorPhone,
                updatedAt:    now,
                updatedBy:    uid
            )
            p.emergencyContacts = contacts
            p.syncState = .pendingUpsert
            modelContext.insert(p)
            profile = p
        }
        
        try? modelContext.save()
        
        // Enqueue Firestore sync
        SyncCenter.shared.enqueuePediatricProfileUpsert(
            childId: childId,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        isSaving = false
    }
}

// MARK: - EmergencyContactRow

private struct EmergencyContactRow: View {
    let contact: KBEmergencyContact
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.teal)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.body)
                Text(contact.relation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Tap sul telefono → chiama direttamente
            if !contact.phone.isEmpty,
               let url = URL(string: "tel:\(contact.phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) {
                    Label(contact.phone, systemImage: "phone.fill")
                        .font(.caption)
                        .foregroundStyle(.teal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - EmergencyContactFormView

struct EmergencyContactFormView: View {
    @Environment(\.dismiss) private var dismiss
    
    let contact: KBEmergencyContact?
    let onSave: (KBEmergencyContact) -> Void
    
    @State private var name     = ""
    @State private var relation = ""
    @State private var phone    = ""
    
    private var isEditing: Bool { contact != nil }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dati contatto") {
                    TextField("Nome e cognome", text: $name)
                    TextField("Relazione (es. Nonna, Babysitter)", text: $relation)
                    TextField("Telefono", text: $phone)
                        .keyboardType(.phonePad)
                }
            }
            .navigationTitle(isEditing ? "Modifica contatto" : "Nuovo contatto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        var c = contact ?? KBEmergencyContact(name: "", relation: "", phone: "")
                        c.name     = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        c.relation = relation.trimmingCharacters(in: .whitespacesAndNewlines)
                        c.phone    = phone.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(c)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let c = contact {
                    name     = c.name
                    relation = c.relation
                    phone    = c.phone
                }
            }
        }
    }
}
