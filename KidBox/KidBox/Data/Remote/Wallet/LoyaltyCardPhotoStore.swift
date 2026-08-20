//
//  LoyaltyCardPhotoStore.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Upload/download/delete delle foto fronte-retro della tessera fisica di una
//  carta fedeltà su Firebase Storage.
//
//  Le foto sono **cifrate** con `DocumentCryptoService` (AES-GCM, chiave di
//  famiglia) esattamente come i documenti d'identità del Wallet: il numero
//  carta resta in chiaro per scelta, ma una foto della tessera può mostrare il
//  nome dell'intestatario.
//
//  Convenzione path — deliberatamente DENTRO il sottoalbero `wallet/`:
//  `families/{familyId}/wallet/loyaltyCards/{cardId}/{front|back}.jpg.kbenc`
//
//  Le Storage Rules (gestite in console, non nel repo) sono un allowlist di
//  sottopath espliciti sotto `families/{familyId}/`: NON esiste un catch-all,
//  quindi un path di primo livello `loyaltyCards/...` verrebbe negato. La regola
//  `match /families/{familyId}/wallet/{allPaths=**}` esiste già e copre questo
//  path senza toccare le regole in produzione. Le carte fedeltà sono a tutti
//  gli effetti contenuto del Wallet, quindi la collocazione è anche corretta.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

enum LoyaltyCardPhotoStoreError: Error {
    case notAuthenticated
    case invalidImage
    case downloadFailed
}

/// Lato della tessera fotografato.
enum LoyaltyCardPhotoSide: String, CaseIterable, Identifiable {
    case front
    case back

    var id: String { rawValue }
}

final class LoyaltyCardPhotoStore {

    private let storage = Storage.storage()

    /// Qualità JPEG: una tessera fedeltà è leggibile ben prima della qualità
    /// massima, e il blob cifrato viaggia intero a ogni apertura.
    private static let jpegQuality: CGFloat = 0.82
    /// Lato lungo massimo dell'immagine salvata.
    private static let maxSide: CGFloat = 2000

    // MARK: - Path helpers

    static func storagePath(familyId: String, cardId: String, side: LoyaltyCardPhotoSide) -> String {
        "families/\(familyId)/wallet/loyaltyCards/\(cardId)/\(side.rawValue).jpg.kbenc"
    }

    // MARK: - Upload

    /// Comprime, cifra e carica la foto di un lato della tessera.
    /// - Returns: `(storagePath, downloadURL)` da salvare sul `KBLoyaltyCard`.
    func upload(
        familyId: String,
        cardId: String,
        side: LoyaltyCardPhotoSide,
        image: UIImage
    ) async throws -> (storagePath: String, downloadURL: String) {

        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[LoyaltyCardPhoto] upload failed: not authenticated")
            throw LoyaltyCardPhotoStoreError.notAuthenticated
        }

        let normalized = Self.downscaled(image, maxSide: Self.maxSide)
        guard let jpeg = normalized.jpegData(compressionQuality: Self.jpegQuality), !jpeg.isEmpty else {
            throw LoyaltyCardPhotoStoreError.invalidImage
        }

        let encrypted = try DocumentCryptoService.encrypt(jpeg, familyId: familyId, userId: uid)

        let path = Self.storagePath(familyId: familyId, cardId: cardId, side: side)
        let ref = storage.reference(withPath: path)

        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = [
            "kb_encrypted": "1",
            "kb_alg": "AES-GCM",
            "kb_orig_mime": "image/jpeg",
            "kb_orig_name": "\(side.rawValue).jpg",
            "kb_module": "loyaltyCard"
        ]

        KBLog.sync.kbInfo("[LoyaltyCardPhoto] upload start cardId=\(cardId) side=\(side.rawValue) encBytes=\(encrypted.count)")

        _ = try await ref.putDataAsync(encrypted, metadata: metadata)
        let url = try await ref.downloadURL()

        KBLog.sync.kbInfo("[LoyaltyCardPhoto] upload OK cardId=\(cardId) side=\(side.rawValue)")
        return (storagePath: path, downloadURL: url.absoluteString)
    }

    // MARK: - Download

    /// Scarica e decifra la foto di un lato, restituendo l'immagine pronta.
    func download(
        familyId: String,
        cardId: String,
        side: LoyaltyCardPhotoSide,
        storagePath: String? = nil,
        maxBytes: Int64 = 15 * 1024 * 1024
    ) async throws -> UIImage {

        let uid = Auth.auth().currentUser?.uid ?? "local"

        // Stessa guardia della detail view dei documenti: senza chiave di
        // famiglia in Keychain la decifratura fallirebbe con un errore opaco.
        guard await FamilyKeyEscrowService.ensureFamilyKeyAvailable(familyId: familyId, userId: uid) else {
            throw FamilyKeyMissing.error()
        }

        let path = storagePath?.isEmpty == false
            ? storagePath!
            : Self.storagePath(familyId: familyId, cardId: cardId, side: side)

        let encrypted = try await storage.reference(withPath: path).data(maxSize: maxBytes)
        let plain = try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: uid)

        guard let image = UIImage(data: plain) else {
            throw LoyaltyCardPhotoStoreError.downloadFailed
        }
        return image
    }

    // MARK: - Delete

    /// Elimina la foto di un lato. Idempotente: ignora "object not found".
    func delete(familyId: String, cardId: String, side: LoyaltyCardPhotoSide, storagePath: String? = nil) async throws {
        let path = storagePath?.isEmpty == false
            ? storagePath!
            : Self.storagePath(familyId: familyId, cardId: cardId, side: side)

        do {
            try await storage.reference(withPath: path).delete()
            KBLog.sync.kbInfo("[LoyaltyCardPhoto] delete OK cardId=\(cardId) side=\(side.rawValue)")
        } catch {
            let ns = error as NSError
            if ns.domain == StorageErrorDomain && ns.code == StorageErrorCode.objectNotFound.rawValue {
                KBLog.sync.kbDebug("[LoyaltyCardPhoto] delete: already gone, ignored")
                return
            }
            throw error
        }
    }

    // MARK: - Helpers

    /// Riduce il lato lungo a `maxSide` mantenendo le proporzioni.
    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
