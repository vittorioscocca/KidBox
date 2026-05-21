//
//  PDFMergeService.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//

import Foundation
import PDFKit
import SwiftData
import OSLog

/// Merges multiple KBDocument PDFs into a single PDF file.
///
/// Flow:
/// 1. Download & decrypt each document to a temp URL via `DocumentLocalCache`
/// 2. Load them as `PDFDocument`
/// 3. Append all pages into a new `PDFDocument`
/// 4. Return the merged data + a suggested title
///
/// - Note: All temp files are cleaned up after the merge regardless of success/failure.
enum PDFMergeService {
    
    enum MergeError: LocalizedError {
        case noPDFsSelected
        case invalidPDF(String)
        case noPages
        case saveFailed
        
        var errorDescription: String? {
            switch self {
            case .noPDFsSelected:    return "Nessun PDF selezionato per l'unione."
            case .invalidPDF(let f): return "Impossibile leggere il PDF: \(f)"
            case .noPages:           return "I PDF selezionati non contengono pagine."
            case .saveFailed:        return "Impossibile salvare il PDF unito."
            }
        }
    }
    
    // MARK: - Public
    
    /// Merges the given documents (must all be PDF) into a single `Data` blob.
    ///
    /// - Parameters:
    ///   - docs: Documents to merge, in the desired page order.
    ///   - modelContext: Used by `DocumentLocalCache.downloadToLocal`.
    /// - Returns: Raw PDF `Data` for the merged document.
    static func merge(
        docs: [KBDocument],
        modelContext: ModelContext
    ) async throws -> Data {
        guard !docs.isEmpty else { throw MergeError.noPDFsSelected }
        
        KBLog.data.kbInfo("PDFMergeService merge started count=\(docs.count)")
        
        var tempURLs: [URL] = []
        defer {
            // Clean up all temp files regardless of success/failure
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
                KBLog.data.kbDebug("PDFMergeService cleanup tempURL=\(url.lastPathComponent)")
            }
        }
        
        // 1) Download & decrypt each doc
        for doc in docs {
            KBLog.data.kbDebug("PDFMergeService downloading docId=\(doc.id)")
            let tempURL = try await DocumentLocalCache.downloadToLocal(doc: doc, modelContext: modelContext)
            tempURLs.append(tempURL)
        }
        
        // 2) Build merged PDF
        let merged = PDFDocument()
        
        for (index, tempURL) in tempURLs.enumerated() {
            guard let pdfDoc = PDFDocument(url: tempURL) else {
                let docName = docs[safe: index]?.fileName ?? tempURL.lastPathComponent
                KBLog.data.kbError("PDFMergeService invalid PDF docName=\(docName)")
                throw MergeError.invalidPDF(docName)
            }
            
            for pageIndex in 0 ..< pdfDoc.pageCount {
                guard let page = pdfDoc.page(at: pageIndex) else { continue }
                merged.insert(page, at: merged.pageCount)
            }
            KBLog.data.kbDebug("PDFMergeService appended pages=\(pdfDoc.pageCount) from docIndex=\(index)")
        }
        
        guard merged.pageCount > 0 else {
            KBLog.data.kbError("PDFMergeService result has 0 pages")
            throw MergeError.noPages
        }
        
        // 3) Serialize to Data
        // PDFDocument.dataRepresentation() returns nil only in degenerate cases
        guard let data = merged.dataRepresentation() else {
            KBLog.data.kbError("PDFMergeService dataRepresentation() returned nil")
            throw MergeError.saveFailed
        }
        
        KBLog.data.kbInfo("PDFMergeService merge completed pages=\(merged.pageCount) bytes=\(data.count)")
        return data
    }
}

// MARK: - Safe subscript helper (local)

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
