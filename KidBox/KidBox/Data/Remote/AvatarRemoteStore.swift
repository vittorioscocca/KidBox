//
//  AvatarRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import UIKit
import FirebaseStorage
import FirebaseFirestore
internal import os

final class AvatarRemoteStore {
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    /// Ridimensiona, carica su Storage e salva l'URL sul documento locations/{uid}.
    /// Ritorna l'URL pubblico scaricabile, o nil in caso di errore.
    @discardableResult
    func uploadAvatar(
        imageData: Data,
        uid: String,
        familyId: String
    ) async -> String? {
        
        // 1. Ridimensiona a 256x256
        guard let resized = resized(data: imageData, maxSide: 256),
              let jpegData = resized.jpegData(compressionQuality: 0.8)
        else {
            KBLog.app.error("AvatarRemoteStore: resize/jpeg conversion failed")
            return nil
        }
        
        // 2. Upload su Storage: families/{familyId}/avatars/{uid}.jpg
        let ref = storage.reference().child("families/\(familyId)/avatars/\(uid).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        do {
            _ = try await ref.putDataAsync(jpegData, metadata: metadata)
            let url = try await ref.downloadURL()
            let urlString = url.absoluteString
            
            // 3. Salva URL su Firestore nel documento locations/{uid}
            try await db.collection("families")
                .document(familyId)
                .collection("locations")
                .document(uid)
                .setData(["avatarURL": urlString], merge: true)
            
            KBLog.app.info("AvatarRemoteStore: uploaded avatar for uid=\(uid, privacy: .public)")
            return urlString
            
        } catch {
            KBLog.app.error("AvatarRemoteStore upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - Resize
    
    private func resized(data: Data, maxSide: CGFloat) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        
        let size = image.size
        let scale = min(maxSide / size.width, maxSide / size.height)
        
        // Già piccola abbastanza
        if scale >= 1 { return image }
        
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
