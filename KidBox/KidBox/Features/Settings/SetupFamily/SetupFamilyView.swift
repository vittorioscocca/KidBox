//
//  SetupFamilyView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import CryptoKit
internal import os

/// Setup / modifica della famiglia.
struct SetupFamilyView: View {
    enum Mode {
        case create
        case edit(family: KBFamily, child: KBChild)
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // MARK: - Dynamic theme (same as LoginView)
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    @Query private var allChildren: [KBChild]
    
    private let mode: Mode
    
    @State private var familyName: String = ""
    
    private struct ChildDraft: Identifiable, Equatable {
        let id: String
        var name: String
        var birthDate: Date?
    }
    
    @State private var drafts: [ChildDraft] = [
        .init(id: UUID().uuidString, name: "", birthDate: nil)
    ]
    
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var didHydrate = false
    
    init(mode: Mode = .create) {
        self.mode = mode
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 12) {
                    header
                    
                    KBSettingsCardWithExtra(
                        title: "Famiglia",
                        subtitle: modeSubtitle,
                        systemImage: "person.2.fill",
                        style: .info,
                        action: nil
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Nome famiglia", text: $familyName)
                                .textInputAutocapitalization(.words)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    
                    setupFamilyChildrenCard
                    
                    if let errorText {
                        KBSettingsCard(
                            title: "Errore",
                            // errorText può contenere testo arbitrario (es. error.localizedDescription):
                            // esegue l'escape di "%" per evitare che LocalizedStringKey lo interpreti
                            // come specificatore di formato.
                            subtitle: LocalizedStringKey(errorText.replacingOccurrences(of: "%", with: "%%")),
                            systemImage: "exclamationmark.triangle",
                            style: .danger,
                            action: nil
                        )
                    }
                    
                    KBSettingsCard(
                        title: isBusy ? buttonBusyTitle : buttonTitle,
                        subtitle: buttonSubtitle,
                        systemImage: "checkmark.circle.fill",
                        style: .primary,
                        action: { Task { await primaryAction() } }
                    )
                    .disabled(primaryDisabled)
                }
                .padding()
            }
        }
        .navigationTitle(navTitle)
        .onAppear {
            hydrateIfNeeded()
        }
    }
    
    // MARK: - UI
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Setup Famiglia")
                .font(.title2).bold()
            Text("Crea la famiglia e gestisci i profili dei figli.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
    
    private var navTitle: LocalizedStringKey {
        switch mode {
        case .create: return "Crea famiglia"
        case .edit:   return "Modifica famiglia"
        }
    }

    private var modeSubtitle: LocalizedStringKey {
        switch mode {
        case .create: return "Imposta nome famiglia e figli."
        case .edit:   return "Aggiorna nome famiglia e gestisci i figli."
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch mode {
        case .create: return "Crea famiglia"
        case .edit:   return "Salva modifiche"
        }
    }

    private var buttonBusyTitle: LocalizedStringKey {
        switch mode {
        case .create: return "Creazione…"
        case .edit:   return "Salvataggio…"
        }
    }

    private var buttonSubtitle: LocalizedStringKey {
        switch mode {
        case .create: return "La famiglia verrà creata con i figli inseriti."
        case .edit:   return "Le modifiche verranno sincronizzate."
        }
    }
    
    private var primaryDisabled: Bool {
        if isBusy { return true }
        if familyName.trimmed.isEmpty { return true }
        
        switch mode {
        case .create:
            if drafts.isEmpty { return true }
            if drafts.contains(where: { $0.name.trimmed.isEmpty }) { return true }
            return false
        case .edit:
            return false
        }
    }
    
    // MARK: - Children sources
    
    private var familyIdInEdit: String? {
        if case let .edit(family, _) = mode { return family.id }
        return nil
    }
    
    private var childrenForEditFamily: [KBChild] {
        guard let fid = familyIdInEdit else { return [] }
        return allChildren
            .filter { $0.familyId == fid }
            .sorted { ($0.birthDate ?? .distantPast) < ($1.birthDate ?? .distantPast) }
    }
    
    // MARK: - Card routing
    
    private var setupFamilyChildrenCard: some View {
        switch mode {
        case .create:
            return AnyView(createChildrenCard)
        case .edit(let family, _):
            return AnyView(editChildrenCard(family: family))
        }
    }
    
    private var createChildrenCard: some View {
        let validDrafts = drafts.filter { !$0.name.trimmed.isEmpty }
        
        return KBSettingsCardWithExtra(
            title: "Figli",
            subtitle: childrenSubtitleCount(count: validDrafts.count),
            systemImage: "figure.and.child.holdinghands",
            style: .secondary,
            action: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                
                ForEach($drafts) { $d in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "face.smiling")
                                .foregroundStyle(.secondary)
                            TextField("Nome", text: $d.name)
                                .textInputAutocapitalization(.words)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Toggle("Inserisci data di nascita", isOn: Binding(
                            get: { d.birthDate != nil },
                            set: { on in
                                d.birthDate = on ? Date() : nil
                            }
                        ))
                        
                        if let _ = d.birthDate {
                            DatePicker(
                                "Data di nascita",
                                selection: Binding(
                                    get: { d.birthDate ?? Date() },
                                    set: { d.birthDate = $0 }
                                ),
                                displayedComponents: .date
                            )
                        }
                    }
                    .padding(.vertical, 6)
                    .swipeActions {
                        if drafts.count > 1 {
                            Button(role: .destructive) {
                                KBLog.data.kbInfo("SetupFamilyView: remove draft childDraftId=\(d.id)")
                                removeDraft(id: d.id)
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                    }
                }
                
                Divider().padding(.vertical, 6)
                
                Button(action: {
                    KBLog.data.kbInfo("SetupFamilyView: add draft")
                    addDraft()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("Aggiungi figlio")
                        Spacer()
                    }
                }
                .font(.subheadline)
            }
        }
    }
    
    private func editChildrenCard(family: KBFamily) -> some View {
        let rows = childrenForEditFamily
        
        return KBSettingsCardWithExtra(
            title: "Figli",
            subtitle: childrenSubtitleCount(count: rows.count),
            systemImage: "figure.and.child.holdinghands",
            style: .secondary,
            action: nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "figure.child")
                        Text("Nessun figlio ancora inserito.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(rows, id: \.id) { r in
                        Button {
                            KBLog.navigation.kbInfo(
                                "SetupFamilyView: open EditChild familyId=\(family.id) childId=\(r.id)"
                            )
                            coordinator.navigate(to: .editChild(familyId: family.id, childId: r.id))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "face.smiling")
                                    .foregroundStyle(.secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.name.isEmpty ? "Senza nome" : r.name)
                                        .font(.subheadline)
                                    
                                    if let birth = r.birthDate {
                                        Text("Nato/a: \(birth.formatted(date: .numeric, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                KBLog.data.kbInfo(
                                    "SetupFamilyView: delete child requested familyId=\(family.id) childId=\(r.id)"
                                )
                                deleteChild(by: r.id, familyId: family.id)
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                    }
                }
                
                Divider().padding(.vertical, 6)
                
                Button {
                    KBLog.data.kbInfo("SetupFamilyView: create empty child then open edit familyId=\(family.id)")
                    createChildAndOpenEdit(familyId: family.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("Aggiungi figlio")
                        Spacer()
                    }
                }
                .font(.subheadline)
            }
        }
    }
    
    private func childrenSubtitleCount(count: Int) -> LocalizedStringKey {
        if count == 0 { return "Gestisci i profili dei figli." }
        if count == 1 { return "1 figlio configurato." }
        return "\(count) figli configurati."
    }
    
    // MARK: - Hydrate
    
    private func hydrateIfNeeded() {
        guard !didHydrate else { return }
        didHydrate = true
        
        guard case let .edit(family, _) = mode else { return }
        familyName = family.name
        KBLog.data.kbInfo("SetupFamilyView hydrate (edit) familyId=\(family.id)")
    }
    
    // MARK: - Actions
    
    @MainActor
    private func primaryAction() async {
        errorText = nil
        isBusy = true
        defer { isBusy = false }
        
        switch mode {
        case .create:
            KBLog.data.kbInfo("SetupFamilyView primaryAction: create")
            await createFamilyWithDrafts()
        case let .edit(family, _):
            KBLog.data.kbInfo("SetupFamilyView primaryAction: update family name familyId=\(family.id)")
            await updateFamilyNameOnly(family: family)
        }
    }
    
    @MainActor
    private func createFamilyWithDrafts() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorText = "Utente non autenticato."
            KBLog.auth.kbError("SetupFamilyView create: not authenticated")
            return
        }
        
        guard let first = drafts.first else {
            errorText = "Inserisci almeno un figlio."
            KBLog.data.kbError("SetupFamilyView create: missing first draft")
            return
        }
        
        do {
            let service = FamilyCreationService(remote: FamilyRemoteStore(), modelContext: modelContext)
            
            let created = try await service.createFamily(
                name: familyName.trimmed,
                childName: first.name.trimmed,
                childBirthDate: first.birthDate
            )
            
            let familyId = created.familyId
            
            KBLog.crypto.kbInfo("Creating master key for familyId=\(familyId)")
            do {
                let masterKey = InviteCrypto.randomBytes(32)
                let key = CryptoKit.SymmetricKey(data: masterKey)
                try FamilyKeychainStore.saveFamilyKey(key, familyId: familyId, userId: Auth.auth().currentUser?.uid ?? "local")
                KBLog.crypto.kbInfo("Master key saved to Keychain familyId=\(familyId)")
            } catch {
                KBLog.crypto.kbError(
                    "Master key creation failed familyId=\(familyId) err=\(error.localizedDescription)"
                )
                errorText = "Errore nella creazione della chiave: \(error.localizedDescription)"
                return
            }
            
            let now = Date()
            for extra in drafts.dropFirst() {
                let child = KBChild(
                    id: UUID().uuidString,
                    familyId: familyId,
                    name: extra.name.trimmed,
                    birthDate: extra.birthDate,
                    createdBy: uid,
                    createdAt: now,
                    updatedBy: uid,
                    updatedAt: now
                )
                modelContext.insert(child)
                
                do {
                    try modelContext.save()
                } catch {
                    KBLog.data.kbError(
                        "SetupFamilyView create: save extra child failed childId=\(child.id) err=\(error.localizedDescription)"
                    )
                }
                
                Task {
                    do {
                        try await ChildSyncService().upsert(child: child)
                        KBLog.sync.kbInfo(
                            "SetupFamilyView create: extra child upserted childId=\(child.id) familyId=\(familyId)"
                        )
                    } catch {
                        KBLog.sync.kbError(
                            "SetupFamilyView create: extra child upsert failed childId=\(child.id) err=\(error.localizedDescription)"
                        )
                    }
                }
            }
            
            KBLog.data.kbInfo("SetupFamilyView create completed familyId=\(familyId)")
            dismiss()
            
        } catch {
            errorText = error.localizedDescription
            KBLog.data.kbError("SetupFamilyView create failed: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func updateFamilyNameOnly(family: KBFamily) async {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        family.name = familyName.trimmed
        family.updatedBy = uid
        family.updatedAt = now
        
        do {
            try modelContext.save()
            KBLog.data.kbInfo("SetupFamilyView update: SwiftData save OK familyId=\(family.id)")
        } catch {
            errorText = "SwiftData save failed: \(error.localizedDescription)"
            KBLog.data.kbError(
                "SetupFamilyView update: SwiftData save failed familyId=\(family.id) err=\(error.localizedDescription)"
            )
            return
        }
        
        SyncCenter.shared.enqueueFamilyBundleUpsert(familyId: family.id, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        KBLog.sync.kbInfo("SetupFamilyView update: enqueued+flush familyId=\(family.id)")
        
        dismiss()
    }
    
    // MARK: - Draft helpers
    
    private func addDraft() {
        drafts.append(.init(id: UUID().uuidString, name: "", birthDate: nil))
    }
    
    private func removeDraft(id: String) {
        drafts.removeAll { $0.id == id }
        if drafts.isEmpty {
            drafts = [.init(id: UUID().uuidString, name: "", birthDate: nil)]
        }
    }
    
    // MARK: - Edit-mode child actions
    
    @MainActor
    private func createChildAndOpenEdit(familyId: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("SetupFamilyView create child: not authenticated")
            return
        }
        
        let now = Date()
        let child = KBChild(
            id: UUID().uuidString,
            familyId: familyId,
            name: "",
            birthDate: nil,
            createdBy: uid,
            createdAt: now,
            updatedBy: uid,
            updatedAt: now
        )
        
        modelContext.insert(child)
        
        do {
            try modelContext.save()
            KBLog.data.kbInfo("SetupFamilyView: local child created childId=\(child.id) familyId=\(familyId)")
        } catch {
            errorText = error.localizedDescription
            KBLog.data.kbError(
                "SetupFamilyView: local child create failed familyId=\(familyId) err=\(error.localizedDescription)"
            )
            return
        }
        
        Task {
            do {
                try await ChildSyncService().upsert(child: child)
                KBLog.sync.kbInfo("SetupFamilyView: child upserted childId=\(child.id)")
            } catch {
                KBLog.sync.kbError(
                    "SetupFamilyView: child upsert failed childId=\(child.id) err=\(error.localizedDescription)"
                )
            }
        }
        
        coordinator.navigate(to: .editChild(familyId: familyId, childId: child.id))
    }
    
    @MainActor
    private func deleteChild(by childId: String, familyId: String) {
        do {
            let desc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == childId })
            if let child = try modelContext.fetch(desc).first {
                modelContext.delete(child)
                try modelContext.save()
                KBLog.data.kbInfo("SetupFamilyView: local child deleted childId=\(childId)")
            } else {
                KBLog.data.kbInfo("SetupFamilyView: child not found for delete childId=\(childId)")
            }
            
            Task {
                do {
                    try await ChildSyncService().softDeleteChild(
                        familyId: familyId,
                        childId: childId,
                        updatedBy: Auth.auth().currentUser?.uid
                    )
                    KBLog.sync.kbInfo("SetupFamilyView: remote child soft-delete OK childId=\(childId)")
                } catch {
                    KBLog.sync.kbError(
                        "SetupFamilyView: remote child soft-delete failed childId=\(childId) err=\(error.localizedDescription)"
                    )
                }
            }
            
        } catch {
            errorText = error.localizedDescription
            KBLog.data.kbError("SetupFamilyView: delete child failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helper

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
