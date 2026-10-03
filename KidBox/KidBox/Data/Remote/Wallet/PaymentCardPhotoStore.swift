//
//  PaymentCardPhotoStore.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//
//  Foto fronte/retro delle carte di pagamento su Firebase Storage, cifrate
//  con la chiave di famiglia come quelle delle carte fedeltà.
//
//  Path, dentro il sottoalbero `wallet/` già ammesso dalle Storage Rules:
//  `families/{familyId}/wallet/paymentCards/{cardId}/{front|back}.jpg.kbenc`
//  Identico su Android e web, o le foto non si leggono fra un client e l'altro.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseStorage

final class PaymentCardPhotoStore {

    private let storage = Storage.storage()

    private static let jpegQuality: CGFloat = 0.82
    private static let maxSide: CGFloat = 2000

    static func storagePath(familyId: String, cardId: String, side: LoyaltyCardPhotoSide) -> String {
        "families/\(familyId)/wallet/paymentCards/\(cardId)/\(side.rawValue).jpg.kbenc"
    }

    /// Comprime, cifra e carica la foto di un lato.
    func upload(
        familyId: String,
        cardId: String,
        side: LoyaltyCardPhotoSide,
        image: UIImage
    ) async throws -> (storagePath: String, downloadURL: String) {
        guard let uid = Auth.auth().currentUser?.uid else {
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
            "kb_module": "paymentCard"
        ]

        _ = try await ref.putDataAsync(encrypted, metadata: metadata)
        let url = try await ref.downloadURL()
        KBLog.sync.kbInfo("[PaymentCardPhoto] upload OK cardId=\(cardId) side=\(side.rawValue)")
        return (storagePath: path, downloadURL: url.absoluteString)
    }

    /// Scarica e decifra la foto di un lato.
    func download(familyId: String, storagePath: String, maxBytes: Int64 = 15 * 1024 * 1024) async throws -> UIImage {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        guard await FamilyKeyEscrowService.ensureFamilyKeyAvailable(familyId: familyId, userId: uid) else {
            throw FamilyKeyMissing.error()
        }
        let encrypted = try await storage.reference(withPath: storagePath).data(maxSize: maxBytes)
        let plain = try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: uid)
        guard let image = UIImage(data: plain) else {
            throw LoyaltyCardPhotoStoreError.downloadFailed
        }
        return image
    }

    /// Elimina una foto. Idempotente: ignora «object not found».
    func delete(storagePath: String) async throws {
        do {
            try await storage.reference(withPath: storagePath).delete()
        } catch {
            let ns = error as NSError
            if ns.domain == StorageErrorDomain && ns.code == StorageErrorCode.objectNotFound.rawValue { return }
            throw error
        }
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        return UIGraphicsImageRenderer(size: target).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
