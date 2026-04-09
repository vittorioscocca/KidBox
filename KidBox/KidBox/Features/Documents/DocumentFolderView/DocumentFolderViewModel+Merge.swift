//
//  DocumentFolderViewModel+merge.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//

import Foundation
import SwiftData
import OSLog

extension DocumentFolderViewModel {
    
    // MARK: - Selection helpers
    
    /// Returns true if ALL selected items are PDF documents (and at least 2 are selected).
    /// Used to show/hide the "Unisci PDF" button in the toolbar.
    var canMergeSelectedAsPDF: Bool {
        guard selectedItems.count >= 2 else { return false }
        return selectedPDFDocs.count == selectedItems.count
    }
    
    /// The `KBDocument` objects currently selected, filtered to PDF only,
    /// in selection order. The sheet will let the user reorder from here.
    var selectedPDFDocs: [KBDocument] {
        selectedItems.compactMap { item -> KBDocument? in
            guard case .doc(let id) = item else { return nil }
            return docs.first(where: { $0.id == id && $0.mimeType.lowercased().contains("pdf") })
        }
    }
    
    // MARK: - Merge action
    
    /// Downloads, merges (in the given order), and re-uploads the PDFs as a
    /// single new document in the current folder.
    ///
    /// - Parameters:
    ///   - orderedDocs: Documents in the user-chosen page order.
    ///   - title: User-supplied title for the merged PDF.
    ///   - modelContext: The view's model context.
    @MainActor
    func mergePDFs(orderedDocs: [KBDocument], title: String, modelContext: ModelContext) async {
        guard orderedDocs.count >= 2 else {
            errorText = "Seleziona almeno 2 PDF per unirli."
            KBLog.data.error("DocumentFolderViewModel mergePDFs: insufficient PDFs count=\(orderedDocs.count)")
            return
        }
        
        KBLog.data.info("DocumentFolderViewModel mergePDFs started count=\(orderedDocs.count) title=\(title)")
        
        isUploading = true
        uploadCurrentName = "Unione PDF in corso…"
        errorText = nil
        
        defer {
            isUploading = false
            uploadCurrentName = ""
        }
        
        do {
            // 1) Merge in user-chosen order
            let mergedData = try await PDFMergeService.merge(docs: orderedDocs, modelContext: modelContext)
            KBLog.data.info("DocumentFolderViewModel mergePDFs merge OK bytes=\(mergedData.count)")
            
            // 2) Write to a named temp URL so uploadSingleFileFromData infers MIME correctly
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("pdf")
            try mergedData.write(to: tempURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            // 3) Upload via existing pipeline (encrypts + syncs to Firebase)
            let fileName = "\(title).pdf"
            let ok = await uploadSingleFileFromData(
                mergedData,
                fileURL: tempURL,
                forcedMime: "application/pdf",
                forcedTitle: fileName
            )
            
            if ok {
                KBLog.data.info("DocumentFolderViewModel mergePDFs upload OK")
                uploadDone = 1
                uploadFailures = 0
                exitSelectionMode()
                reload()
                if let ctx = self.modelContext {
                    SyncCenter.shared.flushGlobal(modelContext: ctx)
                }
            } else {
                uploadFailures = 1
                errorText = "Caricamento del PDF unito non riuscito."
                KBLog.data.error("DocumentFolderViewModel mergePDFs upload failed")
            }
            
        } catch {
            errorText = error.localizedDescription
            KBLog.data.error("DocumentFolderViewModel mergePDFs error: \(error.localizedDescription)")
        }
    }
}
