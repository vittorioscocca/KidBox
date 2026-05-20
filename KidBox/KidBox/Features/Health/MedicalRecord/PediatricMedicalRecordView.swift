//
//  PediatricMedicalRecordView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import Contacts

// MARK: - Scheda Medica

struct PediatricMedicalRecordView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    let familyId: String
    let childId: String

    @Query private var children: [KBChild]

    @State private var profile: KBPediatricProfile? = nil
    @State private var bloodGroup   = ""
    @State private var allergies    = ""
    @State private var medicalNotes = ""
    @State private var doctorDraft  = ReferenceDoctorDraft()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var showSaveSuccess = false
    @State private var hasLoadedFromStore = false

    // Contatti emergenza
    @State private var contacts: [KBEmergencyContact] = []
    @State private var showAddContact = false
    @State private var editingContact: KBEmergencyContact? = nil
    @State private var showContactPicker = false
    @State private var showContactsPermissionAlert = false
    @State private var showReferenceDoctorForm = false
    @State private var linkedBirthDate = Date()
    @State private var hasHealthLink = false

    private let bloodGroups = ["Non specificato", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    private var linkedAgeDescription: String {
        KBHealthAgeFormatting.ageDescription(from: linkedBirthDate)
    }

    private var isChild: Bool {
        children.contains { $0.id == childId }
    }

    private var referenceDoctorSectionTitle: String {
        isChild ? "Pediatra di riferimento" : "Medico di riferimento"
    }

    private var addReferenceDoctorTitle: String {
        if doctorDraft.name.isEmpty {
            return isChild
                ? "Aggiungi Pediatra di riferimento"
                : "Aggiungi Medico di riferimento"
        }
        return isChild
            ? "Modifica Pediatra di riferimento"
            : "Modifica Medico di riferimento"
    }

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Data di nascita",
                    selection: $linkedBirthDate,
                    displayedComponents: .date
                )
                Text("Età: \(linkedAgeDescription)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Età")
            } footer: {
                if hasHealthLink {
                    Text("Data importata da Apple Salute. Puoi correggerla qui: verrà salvata sul profilo e nella scheda.")
                        .font(.caption)
                } else {
                    Text("Imposta la data di nascita del bambino. Collega Apple Salute per importarla automaticamente.")
                        .font(.caption)
                }
            }

            Section("Gruppo sanguigno") {
                Picker("Gruppo sanguigno", selection: $bloodGroup) {
                    ForEach(bloodGroups, id: \.self) { Text($0).tag($0) }
                }
            }

            Section("Allergie conosciute") {
                TextField("es. Latte, uova, pollini", text: $allergies, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                if doctorDraft.name.isEmpty {
                    Text("Nessun medico aggiunto")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ReferenceDoctorSummaryCard(draft: doctorDraft)
                }

                Button {
                    showReferenceDoctorForm = true
                } label: {
                    Label(addReferenceDoctorTitle, systemImage: "plus.circle.fill")
                }
            } header: {
                Text(referenceDoctorSectionTitle)
            } footer: {
                Text("Dopo aver aggiunto o modificato il medico, premi Salva scheda per confermare.")
                    .font(.caption)
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
                    pickEmergencyContactFromAddressBook()
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
                Text("Premi Salva scheda in basso per confermare medico, contatti e note.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Scheda Medica")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                save()
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Salva scheda")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(KBTheme.background(colorScheme).opacity(0.98))
        }
        .onAppear {
            if !hasLoadedFromStore {
                loadFromStore()
                hasLoadedFromStore = true
            }
            SyncCenter.shared.startPediatricProfileRealtime(
                familyId: familyId, childId: childId, modelContext: modelContext
            )
        }
        .onDisappear {
            SyncCenter.shared.stopPediatricProfileRealtime()
        }
        .alert("Salvataggio non riuscito", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Riprova tra qualche secondo.")
        }
        .alert("Scheda salvata", isPresented: $showSaveSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("I dati sono stati salvati sul dispositivo e sincronizzati con la famiglia.")
        }
        .sheet(isPresented: $showAddContact) {
            EmergencyContactFormView(contact: nil) { newContact in
                contacts.append(newContact)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerRepresentable(
                onPick: { payload in
                    let contact = KBEmergencyContact(
                        name: payload.fullName,
                        relation: "",
                        phone: payload.primaryPhone ?? ""
                    )
                    contacts.append(contact)
                    showContactPicker = false
                },
                onCancel: {
                    showContactPicker = false
                }
            )
        }
        .alert("Accesso ai contatti negato", isPresented: $showContactsPermissionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Per selezionare un contatto, abilita l'accesso ai contatti nelle impostazioni.")
        }
        .sheet(item: $editingContact) { contact in
            EmergencyContactFormView(contact: contact) { updated in
                if let idx = contacts.firstIndex(where: { $0.id == updated.id }) {
                    contacts[idx] = updated
                }
            }
        }
        .sheet(isPresented: $showReferenceDoctorForm) {
            ReferenceDoctorFormView(
                isChild: isChild,
                initial: doctorDraft
            ) { updated in
                doctorDraft = updated
            }
        }
    }

    init(familyId: String, childId: String) {
        self.familyId = familyId
        self.childId = childId
        let fid = familyId
        _children = Query(filter: #Predicate<KBChild> { $0.familyId == fid })
    }

    // MARK: - Load

    private func normalizedBloodGroup(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty || !bloodGroups.contains(value) {
            return "Non specificato"
        }
        return value
    }

    private func bloodGroupForSave(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value == "Non specificato" { return nil }
        return value
    }

    private func loadFromStore() {
        let cid = childId
        let desc = FetchDescriptor<KBPediatricProfile>(predicate: #Predicate { $0.childId == cid })
        guard let p = try? modelContext.fetch(desc).first else {
            profile = nil
            bloodGroup = "Non specificato"
            allergies = ""
            medicalNotes = ""
            doctorDraft = ReferenceDoctorDraft()
            contacts = []
            applyHealthLinkToScheda()
            return
        }

        profile = p
        bloodGroup = normalizedBloodGroup(p.bloodGroup)
        allergies = p.allergies ?? ""
        medicalNotes = p.medicalNotes ?? ""
        doctorDraft = ReferenceDoctorDraft(
            name: p.doctorName ?? "",
            email: p.doctorEmail ?? "",
            address: p.doctorAddress ?? "",
            website: p.doctorWebsite ?? "",
            officeHours: p.doctorOfficeHours
        )
        contacts = p.emergencyContacts
        applyHealthLinkToScheda()
    }

    /// Gruppo sanguigno da Salute; data di nascita prioritaria dall'abbinamento Apple Salute.
    private func applyHealthLinkToScheda() {
        let linked = KBHealthLinkStore.load(childId: childId)
        hasHealthLink = linked != nil

        if let linked {
            let profileBlood = normalizedBloodGroup(profile?.bloodGroup)
            if profileBlood == "Non specificato",
               let bg = linked.bloodGroup,
               bloodGroups.contains(bg) {
                bloodGroup = bg
            }

            if let dob = linked.birthDate {
                linkedBirthDate = dob
                return
            }
        }

        if let child = children.first, let dob = child.birthDate {
            linkedBirthDate = dob
        }
    }

    private func persistBirthDate(uid: String, now: Date) {
        if let child = children.first {
            child.birthDate = linkedBirthDate
            child.updatedAt = now
            child.updatedBy = uid
        }

        var snapshot = KBHealthLinkStore.load(childId: childId) ?? KBHealthImportSnapshot(syncedAt: now)
        snapshot.birthDate = linkedBirthDate
        snapshot.syncedAt = now
        KBHealthLinkStore.save(snapshot, childId: childId)

        try? modelContext.save()
        if let child = children.first {
            Task { try? await ChildSyncService().upsert(child: child) }
        }
    }

    private func applyFormToProfile(_ p: KBPediatricProfile, uid: String, now: Date) {
        let trimmedDoctorName = doctorDraft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.bloodGroup = bloodGroupForSave(bloodGroup)
        p.allergies = allergies.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.medicalNotes = medicalNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.doctorName = trimmedDoctorName.nilIfEmpty
        p.doctorEmail = doctorDraft.email.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.doctorAddress = doctorDraft.address.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.doctorWebsite = doctorDraft.website.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        p.doctorOfficeHours = doctorDraft.officeHours
        p.emergencyContacts = contacts
        p.updatedAt = now
        p.updatedBy = uid
        p.syncState = .pendingUpsert
        p.lastSyncError = nil
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        saveError = nil
        showSaveSuccess = false

        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()

        SyncCenter.shared.stopPediatricProfileRealtime()

        let activeProfile: KBPediatricProfile
        if let p = profile {
            activeProfile = p
        } else {
            let p = KBPediatricProfile(
                childId: childId,
                familyId: familyId,
                updatedAt: now,
                updatedBy: uid
            )
            modelContext.insert(p)
            profile = p
            activeProfile = p
        }

        applyFormToProfile(activeProfile, uid: uid, now: now)
        persistBirthDate(uid: uid, now: now)

        do {
            try modelContext.save()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            showSaveError = true
            SyncCenter.shared.startPediatricProfileRealtime(
                familyId: familyId, childId: childId, modelContext: modelContext
            )
            return
        }

        Task { @MainActor in
            defer {
                isSaving = false
                SyncCenter.shared.startPediatricProfileRealtime(
                    familyId: familyId, childId: childId, modelContext: modelContext
                )
            }

            do {
                try await SyncCenter.shared.pushPediatricProfileToRemote(
                    activeProfile,
                    modelContext: modelContext
                )
                loadFromStore()
                showSaveSuccess = true
            } catch {
                activeProfile.lastSyncError = error.localizedDescription
                try? modelContext.save()
                saveError = error.localizedDescription
                showSaveError = true
                SyncCenter.shared.enqueuePediatricProfileUpsert(
                    childId: childId,
                    familyId: familyId,
                    modelContext: modelContext
                )
            }
        }
    }

    private func pickEmergencyContactFromAddressBook() {
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            showContactPicker = true
        case .notDetermined:
            store.requestAccess(for: .contacts) { granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        showContactPicker = true
                    } else {
                        showContactsPermissionAlert = true
                    }
                }
            }
        default:
            showContactsPermissionAlert = true
        }
    }
}

// MARK: - ReferenceDoctorSummaryCard

private struct ReferenceDoctorSummaryCard: View {
    let draft: ReferenceDoctorDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.name)
                .font(.body.weight(.semibold))
            if !draft.email.isEmpty {
                if let url = URL(string: "mailto:\(draft.email)") {
                    Link(destination: url) {
                        Label(draft.email, systemImage: "envelope.fill")
                            .font(.subheadline)
                    }
                } else {
                    Label(draft.email, systemImage: "envelope.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !draft.address.isEmpty {
                Label(draft.address, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !draft.website.isEmpty {
                if let url = normalizedURL(draft.website) {
                    Link(destination: url) {
                        Label(draft.website, systemImage: "globe")
                            .font(.subheadline)
                    }
                } else {
                    Text(draft.website)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !draft.officeHours.isEmpty {
                ForEach(draft.officeHours.groupedOfficeHourDisplayLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func normalizedURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("http") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
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
