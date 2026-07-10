//
//  LinkExistingWalletDocumentSheet.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Collega al Wallet un documento già caricato nella sezione Documenti
//  (es. una foto della Tessera Sanitaria salvata in passato), senza
//  duplicarlo: si limita a taggare il `KBDocument` esistente (`notes` +
//  eventuale `childId`) e a ripubblicarlo via sync — stesso pattern minimale
//  di `DocumentFolderViewModel.renameDocument`.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct LinkExistingWalletDocumentSheet: View {
    let familyId: String
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]

    @State private var kind: KBWalletDocumentKind = .tesseraSanitaria
    @State private var selectedOwner: WalletDocumentOwner = .family
    @State private var selectedDocument: KBDocument?
    @State private var showDocumentPicker = false
    @State private var isExtracting = false

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

    @State private var ocrRawText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var aiImages: [UIImage] = []
    @State private var isAIReading = false
    @State private var showAICostConfirm = false
    @State private var showUpgradeSheet = false

    private var isMaxPlan: Bool { KBSubscriptionManager.shared.currentPlan == .max }
    private var aiMessageCost: Int { WalletDocumentAIExtractor.estimatedMessageUnits(imageCount: max(aiImages.count, 1)) }

    init(familyId: String, onSaved: @escaping (String) -> Void) {
        self.familyId = familyId
        self.onSaved = onSaved
        let fid = familyId
        _children = Query(
            filter: #Predicate<KBChild> { $0.familyId == fid },
            sort: [SortDescriptor(\KBChild.name)]
        )
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: [SortDescriptor(\KBFamilyMember.displayName)]
        )
    }

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

                Section("Documento") {
                    if let selectedDocument {
                        HStack(spacing: 10) {
                            Image(systemName: selectedDocument.isPDFDocument ? "doc.richtext.fill" : "photo.fill")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedDocument.title).foregroundStyle(.primary)
                                Text(selectedDocument.fileName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Cambia documento") { showDocumentPicker = true }
                    } else {
                        Button {
                            showDocumentPicker = true
                        } label: {
                            Label("Scegli da Documenti", systemImage: "folder")
                        }
                    }
                }

                Section("Dati") {
                    if isExtracting {
                        HStack {
                            ProgressView()
                            Text("Lettura dati in corso…").foregroundStyle(.secondary)
                        }
                    }
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

                if selectedDocument != nil {
                    Section {
                        Button {
                            if isMaxPlan { showAICostConfirm = true } else { showUpgradeSheet = true }
                        } label: {
                            HStack {
                                if isAIReading { ProgressView() } else { Label("Leggi con AI", systemImage: "sparkles") }
                                Spacer()
                                Text("\(aiMessageCost) msg").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isAIReading)
                        Text("Lettura assistita dall'AI: più precisa su patente e tabelle. Disponibile con il piano Max; consuma \(aiMessageCost) messaggi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Lettura assistita")
                    }
                }

                if kind == .patente {
                    PatenteCategoriesEditor(categories: $patenteCategories)
                    Section {
                        Toggle("Avvisami una settimana prima della scadenza", isOn: $notifyBeforeExpiry)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Collega documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Salva") {
                            Task { await save() }
                        }
                        .disabled(selectedDocument == nil)
                    }
                }
            }
            .sheet(isPresented: $showDocumentPicker) {
                WalletDocumentPickerSheet(
                    familyId: familyId,
                    onSelect: { doc in
                        selectedDocument = doc
                        showDocumentPicker = false
                        Task { await runExtraction(on: doc) }
                    },
                    onCancel: { showDocumentPicker = false }
                )
            }
            .sheet(isPresented: $showUpgradeSheet) {
                UpgradeSheetView()
            }
            .confirmationDialog("Lettura con AI", isPresented: $showAICostConfirm, titleVisibility: .visible) {
                Button("Leggi con AI (\(aiMessageCost) messaggi)") {
                    Task { await runAIExtraction() }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Le immagini del documento verranno analizzate dall'AI. Questa operazione consumerà \(aiMessageCost) messaggi del tuo piano Max.")
            }
        }
    }

    /// Lettura AI (piano Max) sul documento collegato: sovrascrive i campi.
    private func runAIExtraction() async {
        guard let document = selectedDocument else { return }
        isAIReading = true
        errorMessage = nil
        defer { isAIReading = false }
        do {
            let images = aiImages.isEmpty
                ? try await WalletDocumentFileLoader.decryptToImages(document: document)
                : aiImages
            let result = try await WalletDocumentAIExtractor.extract(images: images, kind: kind)
            if let v = result.holderName { holderName = v }
            if let v = result.birthInfo { birthInfo = v }
            if let v = result.documentNumber { documentNumber = v }
            if kind != .patente, let v = result.codiceFiscale { codiceFiscale = v }
            if kind != .patente, let issue = result.issueDate { hasIssueDate = true; issueDate = issue }
            if kind != .patente, let expiry = result.expiryDate { hasExpiryDate = true; expiryDate = expiry }
            if kind == .patente, !result.patenteCategories.isEmpty { patenteCategories = result.patenteCategories }
        } catch {
            errorMessage = "Lettura AI non riuscita: \(error.localizedDescription)"
        }
    }

    /// OCR sul documento esistente (decripta il file e ne legge i dati) per
    /// precompilare nome, numero, Codice Fiscale e date. L'utente può correggere.
    private func runExtraction(on document: KBDocument) async {
        isExtracting = true
        defer { isExtracting = false }
        do {
            let data = try await WalletDocumentFileLoader.decryptedData(for: document)
            aiImages = (try? await WalletDocumentFileLoader.decryptToImages(document: document)) ?? []
            let result = await WalletDocumentExtractor.extract(fromFileData: data, mimeType: document.mimeType, kind: kind)
            if holderName.isEmpty { holderName = result.holderName ?? "" }
            if birthInfo.isEmpty { birthInfo = result.birthInfo ?? "" }
            if documentNumber.isEmpty { documentNumber = result.documentNumber ?? "" }
            if codiceFiscale.isEmpty { codiceFiscale = result.codiceFiscale ?? "" }
            ocrRawText = result.rawText
            if !hasIssueDate, let issue = result.issueDate { hasIssueDate = true; issueDate = issue }
            if !hasExpiryDate, let expiry = result.expiryDate { hasExpiryDate = true; expiryDate = expiry }
            if kind == .patente, patenteCategories.isEmpty, !result.patenteCategories.isEmpty {
                patenteCategories = result.patenteCategories
            }
        } catch {
            // best-effort: se non riusciamo a leggere il file, l'utente compila a mano
        }
    }

    private func save() async {
        guard let document = selectedDocument else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

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
        document.walletMetadata = metadata
        let trimmedOCR = ocrRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOCR.isEmpty, (document.extractedText ?? "").isEmpty {
            document.extractedText = trimmedOCR
        }
        document.childId = selectedOwner.childId

        // Sposta (non elimina) il documento nella cartella "Documenti d'identità"
        // della sezione Documenti, così resta visibile lì e organizzato con gli
        // altri documenti d'identità, oltre a comparire nel Wallet.
        let uid = Auth.auth().currentUser?.uid ?? "local"
        if let categoryId = try? WalletIdentityFolder.findOrCreate(familyId: familyId, uid: uid, modelContext: modelContext) {
            document.categoryId = categoryId
        }

        document.updatedAt = Date()
        document.updatedBy = uid
        document.syncState = .pendingUpsert
        document.lastSyncError = nil

        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: document.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)

            if notifyBeforeExpiry, let expiry = metadata.effectiveExpiryDate {
                await WalletDocumentReminderService.shared.scheduleReminders(
                    documentId: document.id, familyId: familyId, title: document.title,
                    kind: kind, expiryDate: expiry)
            }

            onSaved(document.id)
            dismiss()
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }
}
