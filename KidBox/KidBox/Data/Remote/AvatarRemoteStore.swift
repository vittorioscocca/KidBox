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

extension AvatarRemoteStore {
    
    /// Upload avatar user-scoped (sempre disponibile anche senza famiglia).
    @discardableResult
    func uploadUserAvatar(imageData: Data, uid: String) async -> String? {
        // resize
        guard let resized = resized(data: imageData, maxSide: 256),
              let jpegData = resized.jpegData(compressionQuality: 0.8)
        else {
            KBLog.app.error("AvatarRemoteStore: resize/jpeg conversion failed (user)")
            return nil
        }
        
        let ref = storage.reference().child("users/\(uid)/avatar.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        do {
            _ = try await ref.putDataAsync(jpegData, metadata: metadata)
            let url = try await ref.downloadURL()
            let urlString = url.absoluteString
            
            try await db.collection("users")
                .document(uid)
                .setData([
                    "avatarURL": urlString,
                    "updatedAt": Timestamp(date: Date())
                ], merge: true)
            
            KBLog.app.info("AvatarRemoteStore: uploaded USER avatar uid=\(uid, privacy: .public)")
            return urlString
        } catch {
            KBLog.app.error("AvatarRemoteStore USER upload failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    private func download(path: String, maxSize: Int64) async throws -> Data {
        let ref = storage.reference().child(path)
        return try await withCheckedThrowingContinuation { cont in
            ref.getData(maxSize: maxSize) { data, error in
                if let error { cont.resume(throwing: error); return }
                guard let data else {
                    cont.resume(throwing: NSError(
                        domain: "AvatarRemoteStore",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Avatar data missing"]
                    ))
                    return
                }
                cont.resume(returning: data)
            }
        }
    }
    
    /// Scarica avatar: prova prima user-scoped, poi (se c'è) family-scoped.
    func downloadAvatar(uid: String, familyId: String?, maxSize: Int64 = 5 * 1024 * 1024) async throws -> Data {
        // 1) prova user-scoped
        do {
            return try await download(path: "users/\(uid)/avatar.jpg", maxSize: maxSize)
        } catch {
            // se non esiste, prova family (solo se disponibile)
            let ns = error as NSError
            let isNotFound =
            ns.domain == StorageErrorDomain &&
            ns.code == StorageErrorCode.objectNotFound.rawValue
            
            if isNotFound, let familyId {
                return try await download(path: "families/\(familyId)/avatars/\(uid).jpg", maxSize: maxSize)
            }
            throw error
        }
    }
}
