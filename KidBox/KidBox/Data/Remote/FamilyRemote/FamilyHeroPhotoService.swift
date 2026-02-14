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

/// Service responsible for setting and updating the family's "hero photo".
///
/// Responsibilities:
/// - Upload hero image to a stable Storage path (always overwritten).
/// - Store `heroPhotoURL` + crop parameters on the family document in Firestore.
/// - Update timestamps and `updatedBy`.
///
/// Notes:
/// - Requires authenticated user.
/// - Does not resize/transform image data; assumes JPEG bytes are provided.
final class FamilyHeroPhotoService {
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    /// Uploads the hero image and updates Firestore fields, returning the public download URL.
    ///
    /// Behavior (unchanged):
    /// - Upload always to: `families/{familyId}/hero/hero.jpg`
    /// - Reads downloadURL
    /// - Writes URL + crop + timestamps into `families/{familyId}` (merge)
    func setHeroPhoto(
        familyId: String,
        imageData: Data,
        crop: HeroCrop
    ) async throws -> String {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("setHeroPhoto failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        guard !imageData.isEmpty else {
            KBLog.sync.kbError("setHeroPhoto failed: invalid image data (empty)")
            throw NSError(domain: "KidBox", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }
        
        let path = "families/\(familyId)/hero/hero.jpg"
        KBLog.sync.kbInfo("Hero photo upload started familyId=\(familyId) bytes=\(imageData.count)")
        
        let ref = storage.reference(withPath: path)
        
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        KBLog.sync.kbDebug("Uploading hero photo to Storage (stable path)")
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        
        KBLog.sync.kbDebug("Upload OK, requesting downloadURL")
        let url = try await ref.downloadURL()
        let urlString = url.absoluteString
        
        KBLog.sync.kbInfo("Updating Firestore hero fields familyId=\(familyId)")
        try await db.collection("families").document(familyId).setData([
            "heroPhotoURL": urlString,
            "heroPhotoUpdatedAt": FieldValue.serverTimestamp(),
            "heroPhotoScale": crop.scale,
            "heroPhotoOffsetX": crop.offsetX,
            "heroPhotoOffsetY": crop.offsetY,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("Hero photo set completed familyId=\(familyId)")
        return urlString
    }
    
    /// Updates only the crop parameters without re-uploading the image.
    ///
    /// Behavior (unchanged):
    /// - Writes crop fields + timestamps into `families/{familyId}` (merge)
    func setHeroCropOnly(familyId: String, crop: HeroCrop) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("setHeroCropOnly failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("Hero crop update started familyId=\(familyId)")
        
        try await db.collection("families").document(familyId).setData([
            "heroPhotoUpdatedAt": FieldValue.serverTimestamp(),
            "heroPhotoScale": crop.scale,
            "heroPhotoOffsetX": crop.offsetX,
            "heroPhotoOffsetY": crop.offsetY,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("Hero crop update completed familyId=\(familyId)")
    }
}
