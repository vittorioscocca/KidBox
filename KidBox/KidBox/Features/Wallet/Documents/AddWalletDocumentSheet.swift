//
//  AddWalletDocumentSheet.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Acquisizione di un documento d'identità (Tessera Sanitaria, Carta
//  d'identità, ...) per la sezione "Documenti" del Wallet:
//  1. scelta tipo documento + titolare (figlio o genitore/famiglia)
//  2. scansione con lo scanner di sistema (`WalletDocumentScannerView`)
//  3. estrazione automatica (`WalletDocumentExtractor`) con conferma/editing
//  4. salvataggio come `KBDocument` — stessa infrastruttura (cifratura,
//     storage, sync) della sezione Documenti generica, così il documento
//     resta consultabile/condivisibile da entrambi i punti.
//

import SwiftUI
import SwiftData
import PDFKit
import VisionKit
import FirebaseAuth

/// Titolare del documento: un figlio, un genitore/membro, o "famiglia" generico
/// (`childId == nil`, stessa semantica già usata per i documenti di famiglia).
/// Condiviso anche da `LinkExistingWalletDocumentSheet` (import di un documento già in Documenti).
enum WalletDocumentOwner: Identifiable, Hashable {
    case child(KBChild)
    case member(KBFamilyMember)
    case family

    var id: String {
        switch self {
        case .child(let c):  return "child-\(c.id)"
        case .member(let m): return "member-\(m.userId)"
        case .family:        return "family"
        }
    }

    var displayName: String {
        switch self {
        case .child(let c):  return c.name
        case .member(let m): return m.displayName ?? "Membro famiglia"
        case .family:        return "Famiglia (documento generico)"
        }
    }

    /// Valore da salvare in `KBDocument.childId`.
    var childId: String? {
        switch self {
        case .child(let c):  return c.id
        case .member(let m): return m.userId
        case .family:        return nil
        }
    }

    static func == (lhs: WalletDocumentOwner, rhs: WalletDocumentOwner) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AddWalletDocumentSheet: View {
    let familyId: String
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]

    @State private var kind: KBWalletDocumentKind = .tesseraSanitaria
    @State private var selectedOwner: WalletDocumentOwner = .family

    @State private var showScanner = false
    @State private var isAppendingScan = false
    @State private var scannedPages: [UIImage] = []
    @State private var isExtracting = false

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

    @State private var ocrRawText: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var isAIReading = false
    @State private var showAICostConfirm = false
    @State private var showUpgradeSheet = false

    private var isMaxPlan: Bool { KBSubscriptionManager.shared.currentPlan == .max }
    private var aiMessageCost: Int { WalletDocumentAIExtractor.estimatedMessageUnits(imageCount: scannedPages.count) }

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

    /// Numero minimo di pagine consigliato: passaporto 2–3 (pagina foto + pagine
    /// dati/visti), tutti gli altri 2 (fronte + retro).
    private var recommendedPages: Int { kind == .passaporto ? 3 : 2 }
    private var minPages: Int { 2 }

    private var scanHint: String {
        kind == .passaporto
            ? "Scansiona almeno 2–3 pagine: pagina con foto e dati, ed eventuali pagine con visti."
            : "Scansiona fronte e retro del documento (2 pagine)."
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

                if scannedPages.isEmpty {
                    Section {
                        Button {
                            isAppendingScan = false
                            showScanner = true
                        } label: {
                            Label("Scansiona documento", systemImage: "doc.viewfinder")
                        }
                        .disabled(!VNDocumentCameraViewController.isSupported)
                        Text(scanHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !VNDocumentCameraViewController.isSupported {
                            Text("Scanner non disponibile su questo dispositivo.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(scannedPages.enumerated()), id: \.offset) { index, page in
                                    VStack(spacing: 4) {
                                        Image(uiImage: page)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 150)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Text(pageLabel(index))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if scannedPages.count < minPages {
                            Label("Aggiungi anche il retro (min. \(minPages) pagine).", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Button {
                            isAppendingScan = true
                            showScanner = true
                        } label: {
                            Label("Aggiungi pagine", systemImage: "plus.viewfinder")
                        }
                        .disabled(!VNDocumentCameraViewController.isSupported)

                        Button("Rifai la scansione", role: .destructive) {
                            scannedPages = []
                            resetExtractedFields()
                        }
                    } header: {
                        Text("Pagine scansionate (\(scannedPages.count))")
                    }

                    Section {
                        Button {
                            if isMaxPlan { showAICostConfirm = true } else { showUpgradeSheet = true }
                        } label: {
                            HStack {
                                if isAIReading {
                                    ProgressView()
                                } else {
                                    Label("Leggi con AI", systemImage: "sparkles")
                                }
                                Spacer()
                                Text("\(aiMessageCost) msg")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isAIReading || scannedPages.isEmpty)
                        Text("Lettura assistita dall'AI: più precisa su patente e tabelle. Disponibile con il piano Max; consuma \(aiMessageCost) messaggi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Lettura assistita")
                    }

                    Section("Dati") {
                        if isExtracting {
                            HStack {
                                ProgressView()
                                Text("Lettura dati in corso…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
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
                    }

                    if !isExtracting && kind == .patente {
                        PatenteCategoriesEditor(categories: $patenteCategories)
                        Section {
                            Toggle("Avvisami una settimana prima della scadenza", isOn: $notifyBeforeExpiry)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nuovo documento")
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
                            Task { await saveDocument() }
                        }
                        .disabled(scannedPages.isEmpty || isExtracting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                WalletDocumentScannerView(
                    onFinish: { pages in
                        let allPages = isAppendingScan ? scannedPages + pages : pages
                        scannedPages = allPages
                        Task { await runExtraction(pages: allPages) }
                    },
                    onCancel: {}
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showUpgradeSheet) {
                UpgradeSheetView()
            }
            .confirmationDialog(
                "Lettura con AI",
                isPresented: $showAICostConfirm,
                titleVisibility: .visible
            ) {
                Button("Leggi con AI (\(aiMessageCost) messaggi)") {
                    Task { await runAIExtraction() }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Le immagini del documento verranno analizzate dall'AI. Questa operazione consumerà \(aiMessageCost) messaggi del tuo piano Max.")
            }
        }
    }

    // MARK: - Extraction

    private func pageLabel(_ index: Int) -> String {
        switch index {
        case 0:  return "Fronte"
        case 1:  return "Retro"
        default: return "Pag. \(index + 1)"
        }
    }

    private func resetExtractedFields() {
        title = ""
        holderName = ""
        birthInfo = ""
        documentNumber = ""
        codiceFiscale = ""
        hasIssueDate = false
        issueDate = .now
        hasExpiryDate = false
        expiryDate = .now
        patenteCategories = []
        notifyBeforeExpiry = true
        ocrRawText = ""
    }

    private func runExtraction(pages: [UIImage]) async {
        isExtracting = true
        defer { isExtracting = false }

        let result = await WalletDocumentExtractor.extract(from: pages, kind: kind)

        // Non sovrascrivere ciò che è già presente (utile quando si aggiungono
        // pagine dopo una prima scansione o dopo una correzione manuale).
        if title.isEmpty {
            if case .family = selectedOwner {
                title = kind.displayName
            } else {
                title = "\(kind.displayName) — \(selectedOwner.displayName)"
            }
        }
        if holderName.isEmpty { holderName = result.holderName ?? "" }
        if birthInfo.isEmpty { birthInfo = result.birthInfo ?? "" }
        if documentNumber.isEmpty { documentNumber = result.documentNumber ?? "" }
        if codiceFiscale.isEmpty { codiceFiscale = result.codiceFiscale ?? "" }
        ocrRawText = result.rawText
        if !hasIssueDate, let issue = result.issueDate {
            hasIssueDate = true
            issueDate = issue
        }
        if !hasExpiryDate, let expiry = result.expiryDate {
            hasExpiryDate = true
            expiryDate = expiry
        }
        // Patente: categorie con rilascio/scadenza lette dalla tabella sul retro
        // (colonna 10 = rilascio, colonna 11 = scadenza).
        if kind == .patente, patenteCategories.isEmpty, !result.patenteCategories.isEmpty {
            patenteCategories = result.patenteCategories
        }
    }

    /// Lettura AI (piano Max): sovrascrive i campi con quanto letto dal modello
    /// vision, che è più affidabile su patente/tabelle rispetto all'OCR locale.
    private func runAIExtraction() async {
        isAIReading = true
        errorMessage = nil
        defer { isAIReading = false }
        do {
            let result = try await WalletDocumentAIExtractor.extract(images: scannedPages, kind: kind)
            if let v = result.holderName { holderName = v }
            if let v = result.birthInfo { birthInfo = v }
            if let v = result.documentNumber { documentNumber = v }
            if kind != .patente, let v = result.codiceFiscale { codiceFiscale = v }
            if kind != .patente, let issue = result.issueDate { hasIssueDate = true; issueDate = issue }
            if kind != .patente, let expiry = result.expiryDate { hasExpiryDate = true; expiryDate = expiry }
            if kind == .patente, !result.patenteCategories.isEmpty { patenteCategories = result.patenteCategories }
            if title.isEmpty || title == kind.displayName {
                if case .family = selectedOwner {
                    title = kind.displayName
                } else {
                    title = "\(kind.displayName) — \(selectedOwner.displayName)"
                }
            }
        } catch {
            errorMessage = "Lettura AI non riuscita: \(error.localizedDescription)"
        }
    }

    // MARK: - Save

    private func saveDocument() async {
        guard let pdfData = makePDF(from: scannedPages) else {
            errorMessage = "Impossibile generare il PDF dalla scansione."
            return
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            let documentId = UUID().uuidString
            let fileName = "\(kind.rawValue).pdf"
            let categoryId = try WalletIdentityFolder.findOrCreate(familyId: familyId, uid: uid, modelContext: modelContext)
            let storagePath = "families/\(familyId)/documents/\(documentId)/\(fileName).kbenc"

            let encryptedData = try DocumentCryptoService.encrypt(pdfData, familyId: familyId, userId: uid)
            let localRelPath = try DocumentLocalCache.write(
                familyId: familyId, docId: documentId, fileName: fileName, data: encryptedData)

            let document = KBDocument(
                id: documentId,
                familyId: familyId,
                childId: selectedOwner.childId,
                categoryId: categoryId,
                title: cleanTitle,
                fileName: fileName,
                mimeType: "application/pdf",
                fileSize: Int64(pdfData.count),
                localPath: localRelPath,
                storagePath: storagePath,
                downloadURL: nil,
                notes: nil,
                createdBy: uid,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now,
                isDeleted: false
            )
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
            if !trimmedOCR.isEmpty { document.extractedText = trimmedOCR }
            document.syncState = .pendingUpsert
            modelContext.insert(document)
            try modelContext.save()

            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: document.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)

            do {
                let storageService = DocumentStorageService()
                let (_, downloadURL) = try await storageService.upload(
                    familyId: familyId, docId: documentId, fileName: fileName,
                    originalMimeType: "application/pdf", encryptedData: encryptedData)
                document.downloadURL = downloadURL
                document.syncState = .synced
                document.lastSyncError = nil
                document.updatedAt = Date()
                try modelContext.save()
            } catch {
                document.syncState = .error
                document.lastSyncError = error.localizedDescription
                try? modelContext.save()
            }

            if notifyBeforeExpiry, let expiry = metadata.effectiveExpiryDate {
                await WalletDocumentReminderService.shared.scheduleReminders(
                    documentId: document.id, familyId: familyId, title: cleanTitle,
                    kind: kind, expiryDate: expiry)
            }

            onSaved(document.id)
            dismiss()
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    private func makePDF(from pages: [UIImage]) -> Data? {
        guard !pages.isEmpty else { return nil }
        let pdfDocument = PDFDocument()
        for (index, image) in pages.enumerated() {
            guard let page = PDFPage(image: image) else { continue }
            pdfDocument.insert(page, at: index)
        }
        return pdfDocument.dataRepresentation()
    }
}
