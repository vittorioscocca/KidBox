//
//  WalletDocumentDetailView.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Vista "quick glance" di un documento d'identità del Wallet (stesso spirito
//  di `WalletTicketDetailView` per i biglietti): mostra il Codice Fiscale
//  come barcode (con versione a tutto schermo per farlo scansionare), le
//  date di rilascio/scadenza con toggle promemoria, e un visualizzatore
//  diretto della scansione (decripta + QuickLook), oltre al link alla
//  `DocumentDetailView` esistente per rinomina/visibilità/condivisione.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct WalletDocumentDetailView: View {
    let familyId: String
    let documentId: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query private var documents: [KBDocument]
    @Query private var children: [KBChild]
    @Query private var members: [KBFamilyMember]

    @State private var showBarcodeFullscreen = false
    @State private var showFileDetail = false
    @State private var showEditSheet = false

    /// `id` stabile per `.sheet(item:)`/`.fullScreenCover(item:)`: un `UUID()` per-get
    /// causherebbe una nuova identità a ogni body pass (chiusura/riapertura in loop).
    private struct IdentifiableURL: Identifiable, Equatable {
        let url: URL
        var id: String { url.absoluteString }
    }

    @State private var previewItem: IdentifiableURL?
    @State private var isLoadingImage = false
    @State private var imageLoadError: String?

    @State private var isLoadingDocumentImages = false
    @State private var documentImages: [UIImage]?

    init(familyId: String, documentId: String) {
        self.familyId = familyId
        self.documentId = documentId
        _documents = Query(filter: #Predicate<KBDocument> { $0.id == documentId && $0.isDeleted == false })
        let fid = familyId
        _children = Query(filter: #Predicate<KBChild> { $0.familyId == fid })
        _members = Query(filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted })
    }

    private var document: KBDocument? { documents.first }
    private var metadata: KBWalletDocumentMetadata? { document?.walletMetadata }

    private var ownerName: String {
        guard let document, let childId = document.childId, !childId.isEmpty else { return "Famiglia" }
        if let child = children.first(where: { $0.id == childId }) { return child.name }
        if let member = members.first(where: { $0.userId == childId }) { return member.displayName ?? "Membro famiglia" }
        return "Famiglia"
    }

    /// Codice Fiscale robusto: dai metadati strutturati o, per i documenti
    /// creati prima dell'introduzione dei metadati, ricavato dal testo OCR
    /// salvato in `extractedText`. Così il barcode ricompare sempre quando
    /// il CF è presente in qualche forma.
    private var resolvedCodiceFiscale: String? {
        // La patente non riporta il Codice Fiscale.
        if metadata?.kind == .patente { return nil }
        if let cf = metadata?.codiceFiscale, !cf.isEmpty { return cf }
        if let text = document?.extractedText, !text.isEmpty {
            return WalletDocumentExtractor.codiceFiscale(in: text)
        }
        return nil
    }

    private var isPatente: Bool { metadata?.kind == .patente }

    /// La CIE non riporta il CF come barcode a barre: se il kind è CIE il
    /// Codice Fiscale va mostrato solo come testo, senza generare il barcode.
    private var isCIE: Bool { metadata?.kind == .cie }

    /// Documenti "a carta" per cui ha senso vedere fronte/retro come immagini
    /// vere invece che aprire il PDF con QuickLook.
    private var supportsFrontBackViewer: Bool {
        switch metadata?.kind {
        case .patente, .cartaIdentita, .cie, .codiceFiscale, .tesseraSanitaria: return true
        default: return false
        }
    }

    private var frontBackButtonLabel: String {
        switch metadata?.kind {
        case .patente:          return "Visualizza patente (fronte / retro)"
        case .cartaIdentita:    return "Visualizza carta d'identità (fronte / retro)"
        case .cie:              return "Visualizza CIE (fronte / retro)"
        case .codiceFiscale:    return "Visualizza tessera (fronte / retro)"
        case .tesseraSanitaria: return "Visualizza tessera sanitaria (fronte / retro)"
        default:                return "Visualizza documento (fronte / retro)"
        }
    }

    /// Nome del titolare per la vista barcode: preferisce il nome letto dal
    /// documento, altrimenti il titolare associato in famiglia.
    private var barcodeHolderName: String {
        if let holder = metadata?.holderName, !holder.isEmpty { return holder }
        return ownerName
    }

    var body: some View {
        Group {
            if let document {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: document)
                        infoCard
                        cardsSection
                        actionsSection
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Documento non trovato", systemImage: "questionmark.folder")
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle(document?.title ?? "Documento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if document != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifica") { showEditSheet = true }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditWalletDocumentSheet(familyId: familyId, documentId: documentId) {}
        }
        .fullScreenCover(isPresented: $showBarcodeFullscreen) {
            if let cf = resolvedCodiceFiscale {
                WalletDocumentBarcodeFullscreenView(codiceFiscale: cf, holderName: barcodeHolderName)
            }
        }
        .sheet(isPresented: $showFileDetail) {
            if let document {
                NavigationStack {
                    DocumentDetailView(document: document, members: members)
                }
            }
        }
        .fullScreenCover(item: $previewItem) { item in
            QuickLookPreview(urls: [item.url], initialIndex: 0, onFinished: { previewItem = nil })
                .ignoresSafeArea()
                .allowsAllOrientationsWhileVisible()
        }
        .fullScreenCover(item: Binding(
            get: { documentImages.map { WalletDocImages(images: $0) } },
            set: { documentImages = $0?.images }
        )) { item in
            WalletDocumentImagesFullscreenView(
                images: item.images,
                tint: (metadata?.kind ?? .altro).accentColor
            )
        }
    }

    private struct WalletDocImages: Identifiable {
        let id = UUID()
        let images: [UIImage]
    }

    // MARK: - Sezioni

    @ViewBuilder
    private var cardsSection: some View {
        // La CIE non stampa il CF come barcode: lo mostriamo solo in `infoCard`.
        if let cf = resolvedCodiceFiscale, !isCIE {
            barcodeCard(cf: cf)
        }
        if let categories = metadata?.patenteCategories, !categories.isEmpty {
            patenteCategoriesCard(categories)
        } else if metadata?.issueDate != nil || metadata?.expiryDate != nil {
            datesCard
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if supportsFrontBackViewer {
            Button {
                loadDocumentImages()
            } label: {
                if isLoadingDocumentImages {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label(frontBackButtonLabel, systemImage: "rectangle.portrait.on.rectangle.portrait")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingDocumentImages)
        }

        openFileButton

        if let imageLoadError {
            Text(imageLoadError).font(.caption).foregroundStyle(.red)
        }

        Button {
            showFileDetail = true
        } label: {
            Label("Gestisci documento (rinomina, visibilità, elimina)", systemImage: "slider.horizontal.3")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var openFileButton: some View {
        let label = Label(supportsFrontBackViewer ? "Apri file originale" : "Vedi immagine documento", systemImage: "photo")
            .frame(maxWidth: .infinity)
        if supportsFrontBackViewer {
            Button { loadDocumentImage() } label: {
                if isLoadingImage { ProgressView().frame(maxWidth: .infinity) } else { label }
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingImage)
        } else {
            Button { loadDocumentImage() } label: {
                if isLoadingImage { ProgressView().frame(maxWidth: .infinity) } else { label }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingImage)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(for document: KBDocument) -> some View {
        let kind = document.walletDocumentKind ?? .altro
        HStack(spacing: 14) {
            Image(systemName: kind.systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(kind.accentColor, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                Text(document.title).font(.title3.weight(.semibold))
                Text("\(kind.displayName) · \(ownerName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Info (titolare / numero documento / CF)

    @ViewBuilder
    private var infoCard: some View {
        let rows = infoRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows, id: \.0) { pair in
                    HStack(alignment: .top) {
                        Text(pair.0).font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(pair.1)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
            .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let holder = metadata?.holderName, !holder.isEmpty {
            rows.append(("Titolare", holder))
        }
        if let birth = metadata?.birthInfo, !birth.isEmpty {
            rows.append(("Nascita", birth))
        }
        if let docNum = metadata?.documentNumber, !docNum.isEmpty {
            rows.append((isPatente ? "Numero patente" : "Numero documento", docNum))
        }
        // La CIE non stampa il CF come barcode: lo mostriamo qui come testo.
        // Per gli altri kind il CF è nella `barcodeCard` (testo + barcode).
        if isCIE, let cf = resolvedCodiceFiscale {
            rows.append(("Codice Fiscale", cf))
        }
        return rows
    }

    // MARK: - Barcode

    private func barcodeCard(cf: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Codice Fiscale")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(cf)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            WalletBarcodeView(text: cf, format: "code39")
                .frame(maxWidth: .infinity)

            Button {
                showBarcodeFullscreen = true
            } label: {
                Label("Ingrandisci per farlo scansionare", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Date rilascio / scadenza

    private var datesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let issueDate = metadata?.issueDate {
                dateRow(label: "Data di rilascio", date: issueDate)
            }
            if let expiryDate = metadata?.expiryDate {
                dateRow(label: "Data di scadenza", date: expiryDate, highlightIfPast: true)

                Toggle("Avvisami una settimana prima della scadenza", isOn: notifyBinding)
                    .font(.subheadline)
            }
        }
        .padding(16)
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }

    private func dateRow(label: String, date: Date, highlightIfPast: Bool = false) -> some View {
        let isPast = highlightIfPast && date < Date()
        return HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPast ? .red : .primary)
        }
    }

    // MARK: - Categorie patente

    private func patenteCategoriesCard(_ categories: [KBPatenteCategory]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Categorie")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.code.isEmpty ? "—" : category.code)
                        .font(.headline)
                    if let issue = category.issueDate {
                        dateRow(label: "Rilascio", date: issue)
                    }
                    if let expiry = category.expiryDate {
                        dateRow(label: "Scadenza", date: expiry, highlightIfPast: true)
                    }
                    if category.issueDate == nil && category.expiryDate == nil {
                        Text("Nessuna data").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                if category.id != categories.last?.id {
                    Divider()
                }
            }

            if metadata?.effectiveExpiryDate != nil {
                Divider()
                Toggle("Avvisami una settimana prima della scadenza più vicina", isOn: notifyBinding)
                    .font(.subheadline)
            }
        }
        .padding(16)
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }

    private var notifyBinding: Binding<Bool> {
        Binding(
            get: { metadata?.notifyBeforeExpiry ?? true },
            set: { newValue in updateNotifyPreference(newValue) }
        )
    }

    private func updateNotifyPreference(_ enabled: Bool) {
        guard let document, var meta = document.walletMetadata else { return }
        meta.notifyBeforeExpiry = enabled
        document.walletMetadata = meta
        document.updatedAt = Date()
        document.updatedBy = Auth.auth().currentUser?.uid ?? "local"
        document.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueDocumentUpsert(documentId: document.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        Task {
            if enabled, let expiry = meta.effectiveExpiryDate {
                await WalletDocumentReminderService.shared.scheduleReminders(
                    documentId: document.id, familyId: familyId, title: document.title,
                    kind: meta.kind, expiryDate: expiry)
            } else {
                await WalletDocumentReminderService.shared.cancelReminders(documentId: document.id)
            }
        }
    }

    // MARK: - Vedi immagine documento

    private func loadDocumentImage() {
        guard let document else { return }
        isLoadingImage = true
        imageLoadError = nil
        Task {
            defer { isLoadingImage = false }
            do {
                let url = try await WalletDocumentFileLoader.decryptToPreviewFile(document: document)
                previewItem = IdentifiableURL(url: url)
            } catch {
                imageLoadError = "Apertura immagine non riuscita: \(error.localizedDescription)"
            }
        }
    }

    private func loadDocumentImages() {
        guard let document else { return }
        isLoadingDocumentImages = true
        imageLoadError = nil
        Task {
            defer { isLoadingDocumentImages = false }
            do {
                let images = try await WalletDocumentFileLoader.decryptToImages(document: document)
                guard !images.isEmpty else {
                    imageLoadError = "Nessuna immagine disponibile."
                    return
                }
                documentImages = images
            } catch {
                imageLoadError = "Apertura documento non riuscita: \(error.localizedDescription)"
            }
        }
    }
}
