//
//  DocumentFolderViewModel+Unlock.swift
//  KidBox
//
//  Created by vscocca on 25/05/26.
//

import Foundation
import SwiftData
import OSLog

extension DocumentFolderViewModel {

    // MARK: - Selection helpers

    /// Returns true if exactly ONE selected item is a PDF document.
    /// Used to show/hide the "Sblocca PDF" button in the toolbar.
    var canUnlockSelectedAsPDF: Bool {
        guard selectedItems.count == 1 else { return false }
        return selectedPDFDocs.count == 1
    }

    /// Convenience to fetch the single selected PDF doc (or nil).
    var singleSelectedPDFDoc: KBDocument? {
        guard canUnlockSelectedAsPDF else { return nil }
        return selectedPDFDocs.first
    }

    // MARK: - Unlock action

    /// Downloads the source PDF, removes its password protection using the
    /// supplied password and uploads the resulting password-free copy as a
    /// new document in the current folder. The original document is preserved.
    ///
    /// - Parameters:
    ///   - doc: Source PDF document.
    ///   - password: User-supplied PDF password.
    ///   - title: User-supplied title for the unlocked PDF (without extension).
    ///   - modelContext: The view's model context.
    @MainActor
    func unlockPDF(
        doc: KBDocument,
        password: String,
        title: String,
        modelContext: ModelContext
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty, !trimmedTitle.isEmpty else {
            errorText = "Password e nome del nuovo PDF sono richiesti."
            KBLog.data.kbError("DocumentFolderViewModel unlockPDF: missing password or title")
            return
        }

        KBLog.data.kbInfo("DocumentFolderViewModel unlockPDF started docId=\(doc.id)")

        isUploading = true
        uploadCurrentName = "Sblocco PDF in corso…"
        errorText = nil

        defer {
            isUploading = false
            uploadCurrentName = ""
        }

        do {
            // 1) Decrypt locally with the user-supplied password.
            //    On wrong password this throws .wrongPassword.
            let unlockedData = try await PDFUnlockService.unlock(
                doc: doc,
                password: password,
                modelContext: modelContext
            )
            KBLog.data.kbInfo("DocumentFolderViewModel unlockPDF unlock OK bytes=\(unlockedData.count)")

            // 2) Write to a named temp URL so uploadSingleFileFromData infers MIME correctly.
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try unlockedData.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            // 3) Upload via existing pipeline (encrypts at rest + syncs to Firebase).
            //    Always force the "pdf" extension so the new file shows the
            //    correct icon and content type even if the user typed a name
            //    without extension.
            let baseName = trimmedTitle.lowercased().hasSuffix(".pdf")
                ? String(trimmedTitle.dropLast(4))
                : trimmedTitle
            let fileName = "\(baseName).pdf"
            let ok = await uploadSingleFileFromData(
                unlockedData,
                fileURL: tempURL,
                forcedMime: "application/pdf",
                forcedTitle: fileName
            )

            if ok {
                KBLog.data.kbInfo("DocumentFolderViewModel unlockPDF upload OK")
                uploadDone = 1
                uploadFailures = 0
                exitSelectionMode()
                reload()
                if let ctx = self.modelContext {
                    SyncCenter.shared.flushGlobal(modelContext: ctx)
                }
            } else {
                uploadFailures = 1
                errorText = "Caricamento del PDF sbloccato non riuscito."
                KBLog.data.kbError("DocumentFolderViewModel unlockPDF upload failed")
            }

        } catch {
            errorText = error.localizedDescription
            KBLog.data.kbError("DocumentFolderViewModel unlockPDF error: \(error.localizedDescription)")
        }
    }
}
