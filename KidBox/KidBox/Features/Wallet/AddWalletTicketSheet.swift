//
//  AddWalletTicketSheet.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit
import FirebaseAuth

struct AddWalletTicketSheet: View {
    let familyId: String
    let prefilledLocalPDFPath: String?
    let prefilledTitle: String?
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var members: [KBFamilyMember]

    @State private var title: String = ""
    @State private var kind: KBWalletTicketKind = .other
    @State private var hasEventDate = false
    @State private var eventDate: Date = .now
    @State private var hasArrivalDate = false
    @State private var arrivalDate: Date = .now
    @State private var location: String = ""
    @State private var arrivalLocation: String = ""
    @State private var holderName: String = ""
    @State private var bookingCode: String = ""
    @State private var notes: String = ""
    @State private var addToWalletURL: String = ""

    @State private var selectedFileName: String = ""
    @State private var selectedPDFData: Data?
    @State private var parsedBarcodeText: String?
    @State private var parsedBarcodeFormat: String?
    @State private var parsedEmitter: String?
    @State private var parsedRawText: String = ""
    @State private var showImporter = false
    @State private var showKidBoxDocumentPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var isAIReading = false
    @State private var showAICostConfirm = false
    @State private var showUpgradeSheet = false

    @State private var selectedVisibilityScope: String = KBVisibilityScope.onlyCreator
    @State private var selectedVisibilityMemberIds: Set<String> = []
    @State private var isVisibilitySheetPresented = false

    private let pdfStore = WalletPDFStore()

    init(
        familyId: String,
        prefilledLocalPDFPath: String?,
        prefilledTitle: String?,
        onSaved: @escaping (String) -> Void
    ) {
        self.familyId = familyId
        self.prefilledLocalPDFPath = prefilledLocalPDFPath
        self.prefilledTitle = prefilledTitle
        self.onSaved = onSaved
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var selectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }

    private var isMaxPlan: Bool { KBSubscriptionManager.shared.currentPlan == .max }
    private var usedImageFallbackForAI: Bool { parsedRawText.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 }
    private var aiMessageCost: Int { WalletTicketAIExtractor.estimatedMessageUnits(usedImageFallback: usedImageFallbackForAI) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Visibilità") {
                    Button {
                        isVisibilitySheetPresented = true
                    } label: {
                        HStack {
                            Text(KBVisibilityScope.chipLabel(for: selectedVisibilityScope))
                                .font(.custom("Nunito", size: 14))
                                .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }

                Section("PDF") {
                    if !selectedFileName.isEmpty {
                        Text(selectedFileName)
                            .font(.subheadline)
                    } else {
                        Text("Nessun PDF selezionato")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showImporter = true
                    } label: {
                        Label("Da file / Files", systemImage: "folder")
                    }

                    Button {
                        showKidBoxDocumentPicker = true
                    } label: {
                        Label("Da documenti KidBox", systemImage: "doc.text.magnifyingglass")
                    }
                }

                if selectedPDFData != nil {
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
                        Text("Lettura assistita dall'AI: più precisa di data/luogo/codice estratti automaticamente. Disponibile con il piano Max; consuma \(aiMessageCost) messaggi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Dati biglietto") {
                    TextField("Titolo", text: $title)
                    Picker("Tipo", selection: $kind) {
                        ForEach(KBWalletTicketKind.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("Nome titolare (opzionale)", text: $holderName)
                        .textInputAutocapitalization(.words)

                    Toggle("Ora di partenza", isOn: $hasEventDate)
                    if hasEventDate {
                        DatePicker("Partenza", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    }
                    TextField("Luogo di partenza (opzionale)", text: $location)

                    Toggle("Ora di arrivo", isOn: $hasArrivalDate)
                    if hasArrivalDate {
                        DatePicker("Arrivo", selection: $arrivalDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                    }
                    TextField("Luogo di arrivo (opzionale)", text: $arrivalLocation)

                    TextField("Codice biglietto (opzionale)", text: $bookingCode)
                    TextField("Link Add to Apple Wallet (opzionale)", text: $addToWalletURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Note (opzionale)", text: $notes, axis: .vertical)
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nuovo biglietto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        Task { await saveTicket() }
                    }
                    .disabled(isSaving || selectedPDFData == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    loadPDF(from: url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Salvataggio...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .onAppear {
                if title.isEmpty {
                    title = prefilledTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                if let prefilledLocalPDFPath, !prefilledLocalPDFPath.isEmpty {
                    loadPrefilledPDF(path: prefilledLocalPDFPath)
                }
            }
            .sheet(isPresented: $isVisibilitySheetPresented) {
                VisibilityPickerSheet(
                    selectedScope: $selectedVisibilityScope,
                    selectedMemberIds: $selectedVisibilityMemberIds,
                    members: selectableMembers,
                    currentUid: currentUid,
                    scopeSectionTitle: "Chi può vedere questo biglietto"
                ) { scope, memberIds in
                    selectedVisibilityScope = scope
                    selectedVisibilityMemberIds = memberIds
                }
            }
            .sheet(isPresented: $showKidBoxDocumentPicker) {
                KidBoxDocumentPickerSheet(familyId: familyId, pdfOnly: true) { url in
                    loadPDF(from: url)
                }
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
                Text("Le informazioni del biglietto verranno analizzate dall'AI. Questa operazione consumerà \(aiMessageCost) messaggi del tuo piano Max.")
            }
        }
    }

    /// Lettura AI (piano Max): usa il testo già estratto dal PDF, o un'immagine di fallback se il testo è insufficiente.
    private func runAIExtraction() async {
        isAIReading = true
        errorMessage = nil
        defer { isAIReading = false }
        do {
            let fallbackImage = usedImageFallbackForAI ? selectedPDFData.flatMap(firstPageImage(from:)) : nil
            let result = try await WalletTicketAIExtractor.extract(text: parsedRawText, fallbackImage: fallbackImage)
            if let v = result.holderName { holderName = v }
            if let v = result.bookingCode { bookingCode = v }
            if let v = result.kind { kind = v }
            if let v = result.emitter { parsedEmitter = v }
            if let v = result.departureLocation { location = v }
            if let v = result.departureDateTime { hasEventDate = true; eventDate = v }
            if let v = result.arrivalLocation { arrivalLocation = v }
            if let v = result.arrivalDateTime { hasArrivalDate = true; arrivalDate = v }
        } catch {
            errorMessage = "Lettura AI non riuscita: \(error.localizedDescription)"
        }
    }

    private func firstPageImage(from pdfData: Data) -> UIImage? {
        guard let doc = PDFDocument(data: pdfData), let page = doc.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 1600, height: 1600), for: .cropBox)
    }

    private func loadPrefilledPDF(path: String) {
        let url = URL(fileURLWithPath: path)
        loadPDF(from: url)
    }

    private func loadPDF(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        var data = try? Data(contentsOf: url)
        if data == nil || data?.isEmpty == true {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("kidbox_wallet_\(UUID().uuidString).pdf", isDirectory: false)
            do {
                try FileManager.default.copyItem(at: url, to: temp)
                data = try? Data(contentsOf: temp)
                try? FileManager.default.removeItem(at: temp)
            } catch {
                data = nil
            }
        }

        guard let pdfBytes = data, !pdfBytes.isEmpty else {
            errorMessage = "Impossibile leggere il PDF. Se è in iCloud, apri il file nell’app File e attendi il download, oppure salva una copia sul dispositivo e riselezionalo."
            return
        }
        selectedPDFData = pdfBytes
        selectedFileName = url.lastPathComponent.isEmpty ? "ticket.pdf" : url.lastPathComponent

        let parsed = WalletPDFParser.parse(pdfData: pdfBytes, fileName: url.lastPathComponent)
        applyParsedData(parsed)
    }

    private func applyParsedData(_ parsed: WalletParsedTicketData) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = parsed.suggestedTitle
        }
        kind = parsed.kind
        if let parsedDate = parsed.eventDate {
            hasEventDate = true
            eventDate = parsedDate
        }
        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedLocation = parsed.location {
            location = parsedLocation
        }
        if bookingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedBookingCode = parsed.bookingCode {
            bookingCode = parsedBookingCode
        }
        if addToWalletURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedURL = parsed.addToAppleWalletURL {
            addToWalletURL = parsedURL
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedNotes = parsed.notes {
            notes = parsedNotes
        }
        parsedBarcodeText = parsed.barcodeText
        parsedBarcodeFormat = parsed.barcodeFormat
        parsedEmitter = parsed.emitter
        parsedRawText = parsed.rawText
    }

    private func saveTicket() async {
        guard let pdfData = selectedPDFData else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let ticketId = UUID().uuidString
        let fileName = selectedFileName.isEmpty ? "ticket.pdf" : selectedFileName

        do {
            let upload = try await pdfStore.upload(
                familyId: familyId,
                ticketId: ticketId,
                originalFileName: fileName,
                pdfData: pdfData
            )

            let uid = Auth.auth().currentUser?.uid ?? "local"
            let displayName = Auth.auth().currentUser?.displayName ?? ""
            let ticket = KBWalletTicket(
                id: ticketId,
                familyId: familyId,
                title: cleanTitle,
                kind: kind,
                eventDate: hasEventDate ? eventDate : nil,
                eventEndDate: hasArrivalDate ? arrivalDate : nil,
                location: sanitized(location),
                seat: nil,
                bookingCode: sanitized(bookingCode),
                arrivalLocation: sanitized(arrivalLocation),
                holderName: sanitized(holderName),
                notes: sanitized(notes),
                emitter: parsedEmitter,
                visibilityScope: selectedVisibilityScope,
                visibilityMemberIds: selectedVisibilityScope == KBVisibilityScope.members
                    ? Array(selectedVisibilityMemberIds).sorted()
                    : [],
                pdfStorageURL: upload.downloadURL,
                pdfFileName: fileName,
                pdfStorageBytes: upload.encryptedBytes,
                pdfThumbnailData: makeThumbnailData(from: pdfData),
                addToAppleWalletURL: sanitized(addToWalletURL),
                extractedBarcodeText: parsedBarcodeText,
                extractedBarcodeFormat: parsedBarcodeFormat,
                createdBy: uid,
                createdByName: displayName,
                updatedBy: uid,
                updatedByName: displayName,
                createdAt: .now,
                updatedAt: .now,
                isDeleted: false
            )
            ticket.syncState = .pendingUpsert
            modelContext.insert(ticket)
            try modelContext.save()

            SyncCenter.shared.enqueueWalletTicketUpsert(
                ticketId: ticket.id,
                familyId: familyId,
                modelContext: modelContext
            )

            // Flush immediato: senza questo l'op resta nell'outbox fino al prossimo
            // scene .active → user B non vedrebbe il biglietto e la CF
            // notifyNewWalletTicket non partirebbe (niente push).
            SyncCenter.shared.flushGlobal(modelContext: modelContext)

            await WalletReminderService.shared.scheduleReminders(for: ticket)
            onSaved(ticket.id)
            dismiss()
        } catch {
            errorMessage = "Salvataggio non riuscito: \(error.localizedDescription)"
        }
    }

    private func sanitized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeThumbnailData(from pdfData: Data) -> Data? {
        guard let doc = PDFDocument(data: pdfData),
              let page = doc.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 400, height: 560), for: .cropBox)
        return image.jpegData(compressionQuality: 0.72)
    }
}
