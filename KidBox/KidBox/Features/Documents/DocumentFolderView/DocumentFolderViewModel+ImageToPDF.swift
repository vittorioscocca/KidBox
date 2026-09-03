//
//  DocumentFolderViewModel+ImageToPDF.swift
//  KidBox
//

import Foundation
import SwiftData
import OSLog

extension DocumentFolderViewModel {

    // MARK: - Selection helpers

    /// Le immagini selezionate, nell'ordine in cui compaiono nella cartella.
    ///
    /// `selectedItems` è un Set: mappandolo direttamente l'ordine delle pagine
    /// sarebbe casuale. Si parte da `docs`, che è l'ordine che l'utente vede,
    /// e da lì può riordinare nel foglio.
    var selectedImageDocs: [KBDocument] {
        let selectedIds = Set(selectedItems.compactMap { item -> String? in
            guard case .doc(let id) = item else { return nil }
            return id
        })
        return docs.filter { selectedIds.contains($0.id) && PDFFromImagesService.isConvertibleImage($0) }
    }

    /// Vero se TUTTI i selezionati sono immagini convertibili (almeno una).
    /// Mostra il pulsante «In PDF» nella barra di selezione.
    var canConvertSelectedToPDF: Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedImageDocs.count == selectedItems.count
    }

    // MARK: - Convert action

    /// Costruisce un PDF dalle immagini scelte e lo carica come nuovo documento
    /// nella cartella corrente. Le immagini originali restano dove sono.
    @MainActor
    func convertImagesToPDF(orderedDocs: [KBDocument], title: String, modelContext: ModelContext) async {
        guard !orderedDocs.isEmpty else {
            errorText = "Seleziona almeno un'immagine da trasformare in PDF."
            return
        }

        KBLog.data.kbInfo("DocumentFolderViewModel convertImagesToPDF started count=\(orderedDocs.count)")

        isUploading = true
        uploadCurrentName = "Creazione PDF in corso…"
        errorText = nil

        defer {
            isUploading = false
            uploadCurrentName = ""
        }

        do {
            let pdfData = try await PDFFromImagesService.makePDF(docs: orderedDocs, modelContext: modelContext)

            // File temporaneo con estensione .pdf: `uploadSingleFileFromData`
            // ricava il MIME dall'URL, come per l'unione.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try pdfData.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let ok = await uploadSingleFileFromData(
                pdfData,
                fileURL: tempURL,
                forcedMime: "application/pdf",
                forcedTitle: "\(title).pdf"
            )

            if ok {
                KBLog.data.kbInfo("DocumentFolderViewModel convertImagesToPDF upload OK")
                uploadDone = 1
                uploadFailures = 0
                exitSelectionMode()
                reload()
                if let ctx = self.modelContext {
                    SyncCenter.shared.flushGlobal(modelContext: ctx)
                }
            } else {
                uploadFailures = 1
                errorText = "Caricamento del PDF non riuscito."
                KBLog.data.kbError("DocumentFolderViewModel convertImagesToPDF upload failed")
            }
        } catch {
            errorText = error.localizedDescription
            KBLog.data.kbError("DocumentFolderViewModel convertImagesToPDF error: \(error.localizedDescription)")
        }
    }
}
