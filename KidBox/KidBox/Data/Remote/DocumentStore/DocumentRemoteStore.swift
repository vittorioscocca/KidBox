//
//  DocumentRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// DTO representing a remote document stored in Firestore.
struct RemoteDocumentDTO {
    let id: String
    let familyId: String
    let childId: String?
    let categoryId: String?
    
    let title: String
    let fileName: String
    let mimeType: String
    let fileSize: Int
    
    let storagePath: String
    let downloadURL: String?
    
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

/// Realtime change type for documents.
enum DocumentRemoteChange {
    case upsert(RemoteDocumentDTO)
    case remove(String)
}

/// Firestore remote store for documents.
///
/// Responsibilities:
/// - OUTBOUND:
///   - upsert document metadata
///   - soft delete
///   - hard delete
/// - INBOUND:
///   - listen to realtime changes
///
/// Notes:
/// - Requires authenticated user for outbound writes.
/// - Listener maps `.added/.modified` → `.upsert`, `.removed` → `.remove`.
final class DocumentRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - OUTBOUND
    
    /// Creates or updates a remote document metadata entry.
    ///
    /// Behavior (unchanged):
    /// - Always sets `updatedAt = serverTimestamp`
    /// - Always sets `createdAt = serverTimestamp` (Firestore merge handles idempotency)
    func upsert(dto: RemoteDocumentDTO) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("Document upsert failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("Document upsert started familyId=\(dto.familyId) docId=\(dto.id)")
        
        let ref = db.collection("families")
            .document(dto.familyId)
            .collection("documents")
            .document(dto.id)
        
        var data: [String: Any] = [
            "title": dto.title,
            "fileName": dto.fileName,
            "mimeType": dto.mimeType,
            "fileSize": dto.fileSize,
            "storagePath": dto.storagePath,
            "isDeleted": dto.isDeleted,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        if let categoryId = dto.categoryId {
            data["categoryId"] = categoryId
        } else {
            data["categoryId"] = FieldValue.delete()
        }
        
        if let childId = dto.childId {
            data["childId"] = childId
        } else {
            data["childId"] = FieldValue.delete()
        }
        
        if let downloadURL = dto.downloadURL {
            data["downloadURL"] = downloadURL
        }
        
        try await ref.setData(data, merge: true)
        
        KBLog.sync.kbInfo("Document upsert completed familyId=\(dto.familyId) docId=\(dto.id)")
    }
    
    /// Marks a document as soft-deleted.
    func softDelete(familyId: String, docId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("Document softDelete failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("Document softDelete started familyId=\(familyId) docId=\(docId)")
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(docId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbInfo("Document softDelete completed familyId=\(familyId) docId=\(docId)")
    }
    
    /// Hard deletes a document metadata entry from Firestore.
    func delete(familyId: String, docId: String) async throws {
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("Document delete failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("Document delete started familyId=\(familyId) docId=\(docId)")
        
        let ref = db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(docId)
        
        try await ref.delete()
        
        KBLog.sync.kbInfo("Document delete completed familyId=\(familyId) docId=\(docId)")
    }
    
    // MARK: - INBOUND (Realtime)
    
    /// Starts a realtime listener for documents under a family.
    ///
    /// - Parameter familyId: Family identifier.
    /// - Parameter onChange: Callback invoked with mapped remote changes.
    /// - Returns: Firestore listener registration.
    func listenDocuments(
        familyId: String,
        onChange: @escaping ([DocumentRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("Documents listener attach familyId=\(familyId)")
        
        return db.collection("families")
            .document(familyId)
            .collection("documents")
            .addSnapshotListener { snap, err in
                
                if let err {
                    KBLog.sync.kbError("Documents listener error: \(err.localizedDescription)")
                    onError(err)
                    return
                }
                
                guard let snap else {
                    KBLog.sync.kbDebug("Documents listener snapshot nil")
                    return
                }
                
                KBLog.sync.kbDebug("Documents snapshot size=\(snap.documents.count) changes=\(snap.documentChanges.count)")
                
                let changes: [DocumentRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
                    let dto = RemoteDocumentDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        childId: data["childId"] as? String,
                        categoryId: data["categoryId"] as? String,
                        title: data["title"] as? String ?? "",
                        fileName: data["fileName"] as? String ?? "",
                        mimeType: data["mimeType"] as? String ?? "application/octet-stream",
                        fileSize: data["fileSize"] as? Int ?? 0,
                        storagePath: data["storagePath"] as? String ?? "",
                        downloadURL: data["downloadURL"] as? String,
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
                    KBLog.sync.kbDebug("Documents listener emitting changes=\(changes.count)")
                    onChange(changes)
                }
            }
    }
}
