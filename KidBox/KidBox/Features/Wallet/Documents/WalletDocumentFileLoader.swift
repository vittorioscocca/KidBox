//
//  WalletDocumentFileLoader.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Carica e decripta il file di un `KBDocument` (da cache locale o da Firebase
//  Storage), restituendo i bytes in chiaro. Stessa logica di
//  `DocumentFolderViewModel.open()`, condivisa tra la detail view del Wallet
//  (anteprima QuickLook) e il flusso di collegamento (OCR sul file esistente).
//

import Foundation
import UIKit
import PDFKit
import FirebaseAuth
import FirebaseStorage

enum WalletDocumentFileLoader {

    /// Restituisce i bytes in chiaro del documento.
    static func decryptedData(for document: KBDocument) async throws -> Data {
        let userId = Auth.auth().currentUser?.uid ?? "local"
        let isPlain = DocumentCryptoService.storedKBDocumentPayloadIsPlaintext(
            notes: document.notes, storagePath: document.storagePath)

        if !isPlain, !(await FamilyKeyEscrowService.ensureFamilyKeyAvailable(familyId: document.familyId, userId: userId)) {
            throw NSError(domain: "KidBox", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "Chiave famiglia non disponibile su questo dispositivo"])
        }

        let cipherData: Data
        if let localPath = document.localPath, !localPath.isEmpty, DocumentLocalCache.exists(localPath: localPath) != nil {
            cipherData = try DocumentLocalCache.readEncrypted(localPath: localPath)
        } else {
            guard !document.storagePath.isEmpty else {
                throw NSError(domain: "KidBox", code: -11,
                              userInfo: [NSLocalizedDescriptionKey: "Percorso file mancante"])
            }
            let ref = Storage.storage().reference(withPath: document.storagePath)
            cipherData = try await ref.data(maxSize: 50 * 1024 * 1024)
        }

        return try DocumentCryptoService.decryptStoredKBDocumentPayload(
            cipherData,
            storagePath: document.storagePath,
            notes: document.notes,
            familyId: document.familyId,
            userId: userId
        )
    }

    /// Decripta il documento e ne rende le pagine come immagini (una per pagina
    /// PDF, o l'immagine stessa). Usato per la vista fronte/retro della patente.
    static func decryptToImages(document: KBDocument) async throws -> [UIImage] {
        let data = try await decryptedData(for: document)
        if document.mimeType == "application/pdf" || data.prefix(4) == Data([0x25, 0x50, 0x44, 0x46]) {
            guard let pdf = PDFDocument(data: data) else { return [] }
            var images: [UIImage] = []
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                images.append(page.thumbnail(of: CGSize(width: 2400, height: 2400), for: .cropBox))
            }
            return images
        }
        if let image = UIImage(data: data) { return [image] }
        return []
    }

    /// Decripta il documento e lo scrive in un file temporaneo pronto per QuickLook.
    static func decryptToPreviewFile(document: KBDocument) async throws -> URL {
        let plainData = try await decryptedData(for: document)
        let subdir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let fileName = document.fileName.isEmpty ? document.id : document.fileName
        let url = subdir.appendingPathComponent(fileName)
        try plainData.write(to: url, options: .atomic)
        return url
    }
}
