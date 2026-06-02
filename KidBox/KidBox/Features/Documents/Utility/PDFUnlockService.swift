//
//  PDFUnlockService.swift
//  KidBox
//
//  Created by vscocca on 25/05/26.
//

import Foundation
import PDFKit
import SwiftData
import OSLog

/// Removes the password protection from a single PDF document, producing a
/// new password-free copy that can be re-uploaded as a separate document.
///
/// Flow:
/// 1. Download & decrypt the source document to a temp URL via `DocumentLocalCache`
/// 2. Open it as a `PDFDocument` and call `unlock(withPassword:)` if locked
/// 3. Serialize the now-unlocked document back to `Data`
/// 4. Return the raw bytes; temp files are cleaned up on the way out
///
/// - Note: PDFKit's `unlock(withPassword:)` only succeeds when the supplied
///   password is the user/owner password. When the PDF has no password at all
///   we still rebuild it via `dataRepresentation()` so the caller always gets
///   a clean, unencrypted copy.
enum PDFUnlockService {

    enum UnlockError: LocalizedError {
        case invalidPDF
        case wrongPassword
        case saveFailed
        case notProtected

        var errorDescription: String? {
            switch self {
            case .invalidPDF:    return "Impossibile leggere il PDF."
            case .wrongPassword: return "Password errata."
            case .saveFailed:    return "Impossibile salvare il PDF sbloccato."
            case .notProtected:  return "Il PDF non è protetto da password."
            }
        }
    }

    // MARK: - Public

    /// Unlocks the given PDF document using `password` and returns the
    /// password-free `Data` blob.
    ///
    /// - Parameters:
    ///   - doc: PDF document to unlock.
    ///   - password: User-supplied password for the PDF.
    ///   - modelContext: Used by `DocumentLocalCache.downloadToLocal`.
    /// - Returns: Raw, password-free PDF `Data`.
    static func unlock(
        doc: KBDocument,
        password: String,
        modelContext: ModelContext
    ) async throws -> Data {
        KBLog.data.kbInfo("PDFUnlockService unlock started docId=\(doc.id)")

        let tempURL = try await DocumentLocalCache.downloadToLocal(doc: doc, modelContext: modelContext)
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            KBLog.data.kbDebug("PDFUnlockService cleanup tempURL=\(tempURL.lastPathComponent)")
        }

        guard let pdf = PDFDocument(url: tempURL) else {
            KBLog.data.kbError("PDFUnlockService invalid PDF url=\(tempURL.lastPathComponent)")
            throw UnlockError.invalidPDF
        }

        if pdf.isLocked {
            // unlock(withPassword:) returns false on wrong password; do not
            // log the password itself for obvious privacy reasons.
            let unlocked = pdf.unlock(withPassword: password)
            if !unlocked {
                KBLog.data.kbError("PDFUnlockService wrong password docId=\(doc.id)")
                throw UnlockError.wrongPassword
            }
            KBLog.data.kbInfo("PDFUnlockService unlocked docId=\(doc.id)")
        } else {
            // Even if the PDF is not locked it might still carry an
            // owner-password / encryption layer that limits printing or
            // copying. `dataRepresentation()` of a non-locked PDFDocument
            // strips that, so the resulting copy is fully unrestricted.
            KBLog.data.kbDebug("PDFUnlockService source not locked, normalizing copy docId=\(doc.id)")
        }

        guard let data = pdf.dataRepresentation() else {
            KBLog.data.kbError("PDFUnlockService dataRepresentation() returned nil docId=\(doc.id)")
            throw UnlockError.saveFailed
        }

        KBLog.data.kbInfo("PDFUnlockService unlock completed docId=\(doc.id) bytes=\(data.count)")
        return data
    }
}
