//
//  DocumentCategoryRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import OSLog

/// DTO representing a remote document category stored in Firestore.
struct RemoteDocumentCategoryDTO {
    let id: String
    let familyId: String
    let title: String
    let sortOrder: Int
    let parentId: String?
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

/// Realtime change types for remote document categories.
enum DocumentCategoryRemoteChange {
    /// Insert or update a category.
    case upsert(RemoteDocumentCategoryDTO)
    /// Remove a category by id (Firestore removal event).
    case remove(String)
}

/// Remote store for document categories (Firestore).
///
/// Responsibilities:
/// - OUTBOUND:
///   - upsert category (create/update) with server timestamps
///   - soft delete (mark `isDeleted = true`)
///   - hard delete (delete Firestore document)
/// - INBOUND:
///   - listen to realtime changes for categories and map them to domain changes
///
/// Notes:
/// - Requires authenticated Firebase user for outbound writes.
/// - Listener maps added/modified to `.upsert` and removed to `.remove` (unchanged).
final class DocumentCategoryRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND (push)
    
    /// Creates or updates a remote category document.
    ///
    /// Behavior (unchanged):
    /// - Writes `familyId`, `title`, `sortOrder`, `isDeleted`, `updatedBy`, `updatedAt`.
    /// - Writes `createdAt` only when document does not exist yet.
    /// - Writes/clears `parentId` depending on `dto.parentId`.
    func upsert(dto: RemoteDocumentCategoryDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("DocCategory upsert failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("DocCategory upsert started familyId=\(dto.familyId) categoryId=\(dto.id)")
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("documentCategories")
            .document(dto.id)
        
        var data: [String: Any] = [
            "familyId": dto.familyId,
            "title": dto.title,
            "sortOrder": dto.sortOrder,
            "isDeleted": dto.isDeleted,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp() // will be removed if doc exists
        ]
        
        if let parentId = dto.parentId {
            data["parentId"] = parentId
        } else {
            data["parentId"] = FieldValue.delete()
        }
        
        // Write createdAt only if document does not already exist.
        let snap = try await ref.getDocument()
        if snap.exists {
            data.removeValue(forKey: "createdAt")
            KBLog.sync.kbDebug("DocCategory exists -> preserving createdAt")
        } else {
            KBLog.sync.kbDebug("DocCategory new -> writing createdAt")
        }
        
        try await ref.setData(data, merge: true)
        KBLog.sync.kbInfo("DocCategory upsert completed familyId=\(dto.familyId) categoryId=\(dto.id)")
    }
    
    /// Soft deletes a remote category (sets `isDeleted = true`).
    func softDelete(familyId: String, categoryId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("DocCategory softDelete failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("DocCategory softDelete started familyId=\(familyId) categoryId=\(categoryId)")
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .document(categoryId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("DocCategory softDelete completed familyId=\(familyId) categoryId=\(categoryId)")
    }
    
    /// Hard deletes a remote category document from Firestore.
    func delete(familyId: String, categoryId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("DocCategory delete failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbInfo("DocCategory delete started familyId=\(familyId) categoryId=\(categoryId)")
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .document(categoryId)
        
        try await ref.delete()
        KBLog.sync.kbInfo("DocCategory delete completed familyId=\(familyId) categoryId=\(categoryId)")
    }
    
    // MARK: - INBOUND (realtime)
    
    /// Starts a realtime listener for categories under a family.
    ///
    /// - Parameters:
    ///   - familyId: Family identifier.
    ///   - onChange: Callback invoked with an array of remote changes.
    /// - Returns: Firestore `ListenerRegistration` to stop listening.
    func listenCategories(
        familyId: String,
        onChange: @escaping ([DocumentCategoryRemoteChange]) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("DocCategories listener attach familyId=\(familyId)")
        
        return db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("DocCategories listener error: \(err.localizedDescription)")
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("DocCategories listener snapshot nil")
                    return
                }
                
                let changes: [DocumentCategoryRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
                    let dto = RemoteDocumentCategoryDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        title: data["title"] as? String ?? "Categoria",
                        sortOrder: data["sortOrder"] as? Int ?? 0,
                        parentId: data["parentId"] as? String,
                        isDeleted: data["isDeleted"] as? Bool ?? false,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                        updatedBy: data["updatedBy"] as? String
                    )
                    
                    switch diff.type {
                    case .added, .modified:
                        return .upsert(dto)
                    case .removed:
                        return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty {
                    KBLog.sync.kbDebug("DocCategories listener changes=\(changes.count)")
                    onChange(changes)
                }
            }
    }
}
