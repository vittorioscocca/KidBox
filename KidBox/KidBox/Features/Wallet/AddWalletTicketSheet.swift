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

    @State private var title: String = ""
    @State private var kind: KBWalletTicketKind = .other
    @State private var hasEventDate = false
    @State private var eventDate: Date = .now
    @State private var location: String = ""
    @State private var bookingCode: String = ""
    @State private var notes: String = ""
    @State private var addToWalletURL: String = ""

    @State private var selectedFileName: String = ""
    @State private var selectedPDFData: Data?
    @State private var parsedBarcodeText: String?
    @State private var parsedBarcodeFormat: String?
    @State private var parsedEmitter: String?
    @State private var showImporter = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let pdfStore = WalletPDFStore()

    var body: some View {
        NavigationStack {
            Form {
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
                        Label("Scegli PDF", systemImage: "doc.richtext")
                    }
                }

                Section("Dati biglietto") {
                    TextField("Titolo", text: $title)
                    Picker("Tipo", selection: $kind) {
                        ForEach(KBWalletTicketKind.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }

                    Toggle("Data evento", isOn: $hasEventDate)
                    if hasEventDate {
                        DatePicker("Quando", selection: $eventDate)
                    }

                    TextField("Luogo (opzionale)", text: $location)
                    TextField("Codice prenotazione (opzionale)", text: $bookingCode)
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
        }
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

        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            errorMessage = "Impossibile leggere il PDF selezionato."
            return
        }
        selectedPDFData = data
        selectedFileName = url.lastPathComponent

        let parsed = WalletPDFParser.parse(pdfData: data, fileName: url.lastPathComponent)
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
                eventEndDate: nil,
                location: sanitized(location),
                seat: nil,
                bookingCode: sanitized(bookingCode),
                notes: sanitized(notes),
                emitter: parsedEmitter,
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
