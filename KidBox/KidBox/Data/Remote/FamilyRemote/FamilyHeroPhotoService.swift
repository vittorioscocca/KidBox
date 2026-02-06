//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage


final class FamilyHeroPhotoService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    /// Upload sempre sullo stesso path + salva URL + crop su Firestore
    func setHeroPhoto(
        familyId: String,
        imageData: Data,
        crop: HeroCrop
    ) async throws -> String {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        guard !imageData.isEmpty else {
            throw NSError(domain: "KidBox", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        
        print("HERO UPLOAD uid =", Auth.auth().currentUser?.uid ?? "nil")
        print("HERO UPLOAD familyId =", familyId)
        print("HERO UPLOAD path = families/\(familyId)/hero/hero.jpg")
        
        let path = "families/\(familyId)/hero/hero.jpg"
        let ref = storage.reference(withPath: path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        
        let url = try await ref.downloadURL()
        let urlString = url.absoluteString
        
        try await db.collection("families").document(familyId).setData([
            "heroPhotoURL": urlString,
            "heroPhotoUpdatedAt": FieldValue.serverTimestamp(),
            "heroPhotoScale": crop.scale,
            "heroPhotoOffsetX": crop.offsetX,
            "heroPhotoOffsetY": crop.offsetY,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        return urlString
    }
    
    /// Se vuoi cambiare solo il crop (senza ricaricare la foto)
    func setHeroCropOnly(familyId: String, crop: HeroCrop) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        try await db.collection("families").document(familyId).setData([
            "heroPhotoUpdatedAt": FieldValue.serverTimestamp(),
            "heroPhotoScale": crop.scale,
            "heroPhotoOffsetX": crop.offsetX,
            "heroPhotoOffsetY": crop.offsetY,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
