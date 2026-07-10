//
//  EditWalletDocumentSheet.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Modifica dei campi di un documento d'identità già nel Wallet: tipo,
//  titolo, titolare, nome sul documento, numero, Codice Fiscale, date di
//  rilascio/scadenza e preferenza notifica. Aggiorna `walletMetadata` sul
//  `KBDocument` esistente e rischedula il promemoria di scadenza.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct EditWalletDocumentSheet: View {
    let familyId: String
    let documentId: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var documents: [KBDocument]
    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]

    @State private var kind: KBWalletDocumentKind = .tesseraSanitaria
    @State private var selectedOwner: WalletDocumentOwner = .family
    @State private var title: String = ""
    @State private var holderName: String = ""
    @State private var birthInfo: String = ""
    @State private var documentNumber: String = ""
    @State private var codiceFiscale: String = ""
    @State private var hasIssueDate = false
    @State private var issueDate: Date = .now
    @State private var hasExpiryDate = false
    @State private var expiryDate: Date = .now
    @State private var patenteCategories: [KBPatenteCategory] = []
    @State private var notifyBeforeExpiry = true

    @State private var loaded = false
    @State private var errorMessage: String?

    init(familyId: String, documentId: String, onSaved: @escaping () -> Void) {
        self.familyId = familyId
        self.documentId = documentId
        self.onSaved = onSaved
        _documents = Query(filter: #Predicate<KBDocument> { $0.id == documentId })
        let fid = familyId
        _children = Query(filter: #Predicate<KBChild> { $0.familyId == fid }, sort: [SortDescriptor(\KBChild.name)])
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
                         sort: [SortDescriptor(\KBFamilyMember.displayName)])
    }

    private var document: KBDocument? { documents.first }

    private var owners: [WalletDocumentOwner] {
        children.map { .child($0) } + members.map { .member($0) } + [.family]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo documento") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(KBWalletDocumentKind.allCases) { k in
                            Label(k.displayName, systemImage: k.systemImage).tag(k)
                        }
                    }
                    Picker("Titolare", selection: $selectedOwner) {
                        ForEach(owners) { owner in
                            Text(owner.displayName).tag(owner)
                        }
                    }
                }

                Section("Dati") {
                    TextField("Titolo", text: $title)
                    TextField("Nome e cognome titolare", text: $holderName)
                        .textInputAutocapitalization(.words)
                    TextField("Data e luogo di nascita", text: $birthInfo)
                        .textInputAutocapitalization(.words)
                    TextField(kind == .patente ? "Numero patente" : "Numero documento", text: $documentNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if kind != .patente {
                        TextField("Codice Fiscale", text: $codiceFiscale)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Toggle("Data di rilascio", isOn: $hasIssueDate)
                        if hasIssueDate {
                            DatePicker("Rilascio", selection: $issueDate, displayedComponents: .date)
                        }
                        Toggle("Data di scadenza", isOn: $hasExpiryDate)
                        if hasExpiryDate {
                            DatePicker("Scadenza", selection: $expiryDate, displayedComponents: .date)
                            Toggle("Avvisami una settimana prima della scadenza", isOn: $notifyBeforeExpiry)
                        }
                    }
                }

                if kind == .patente {
                    PatenteCategoriesEditor(categories: $patenteCategories)
                    Section {
                        Toggle("Avvisami una settimana prima della scadenza", isOn: $notifyBeforeExpiry)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Modifica documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private func loadIfNeeded() {
        guard !loaded, let document else { return }
        loaded = true

        let meta = document.walletMetadata
        kind = meta?.kind ?? .altro
        title = document.title
        holderName = meta?.holderName ?? ""
        birthInfo = meta?.birthInfo ?? ""
        documentNumber = meta?.documentNumber ?? ""
        codiceFiscale = meta?.codiceFiscale ?? ""
        if let issue = meta?.issueDate { hasIssueDate = true; issueDate = issue }
        if let expiry = meta?.expiryDate { hasExpiryDate = true; expiryDate = expiry }
        patenteCategories = meta?.patenteCategories ?? []
        notifyBeforeExpiry = meta?.notifyBeforeExpiry ?? true
        selectedOwner = resolveOwner(childId: document.childId)
    }

    private func resolveOwner(childId: String?) -> WalletDocumentOwner {
        guard let childId, !childId.isEmpty else { return .family }
        if let child = children.first(where: { $0.id == childId }) { return .child(child) }
        if let member = members.first(where: { $0.userId == childId }) { return .member(member) }
        return .family
    }

    private func save() async {
        guard let document else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let cf = codiceFiscale.trimmingCharacters(in: .whitespacesAndNewlines)
        let holder = holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let birth = birthInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        let docNum = documentNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        let isPatente = kind == .patente
        let metadata = KBWalletDocumentMetadata(
            kind: kind,
            codiceFiscale: cf.isEmpty ? nil : cf,
            holderName: holder.isEmpty ? nil : holder,
            birthInfo: birth.isEmpty ? nil : birth,
            documentNumber: docNum.isEmpty ? nil : docNum,
            issueDate: (!isPatente && hasIssueDate) ? issueDate : nil,
            expiryDate: (!isPatente && hasExpiryDate) ? expiryDate : nil,
            patenteCategories: isPatente ? patenteCategories : [],
            notifyBeforeExpiry: notifyBeforeExpiry
        )
        document.title = cleanTitle
        document.childId = selectedOwner.childId
        document.walletMetadata = metadata
        document.updatedAt = Date()
        document.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        document.syncState = .pendingUpsert
        document.lastSyncError = nil

        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: document.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)

            if notifyBeforeExpiry, let expiry = metadata.effectiveExpiryDate {
                await WalletDocumentReminderService.shared.scheduleReminders(
                    documentId: document.id, familyId: familyId, title: cleanTitle,
                    kind: kind, expiryDate: expiry)
            } else {
                await WalletDocumentReminderService.shared.cancelReminders(documentId: document.id)
            }

            onSaved()
            dismiss()
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }
}
