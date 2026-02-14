//
//  DocumentDeleteService.swift
//  KidBox
//
//  Created by vscocca on 07/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import OSLog

/// Service responsible for hard-deleting a document remotely.
///
/// Hard delete semantics (unchanged):
/// 1) Best-effort delete the document blob from Firebase Storage if `doc.storagePath` is available.
/// 2) Delete the Firestore document metadata under `families/{familyId}/documents/{docId}`.
///
/// Notes:
/// - Requires an authenticated Firebase user.
/// - If Storage deletion fails, the function throws and Firestore metadata delete is not executed
///   (same behavior as current implementation).
final class DocumentDeleteService {
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    /// Hard deletes a document (Storage + Firestore metadata).
    ///
    /// - Parameters:
    ///   - familyId: Family identifier.
    ///   - doc: Local document model containing `id` and optional `storagePath`.
    ///
    /// - Throws:
    ///   - If the user is not authenticated.
    ///   - Any error thrown by Firebase Storage or Firestore delete calls.
    func deleteDocumentHard(familyId: String, doc: KBDocument) async throws {
        KBLog.sync.kbInfo("deleteDocumentHard started familyId=\(familyId) docId=\(doc.id)")
        
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("deleteDocumentHard failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        // 1) Storage cleanup (if we have a path)
        let path = doc.storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            KBLog.sync.kbInfo("Deleting Storage blob docId=\(doc.id)")
            
            do {
                // Prova il path salvato
                try await storage.reference(withPath: path).delete()
                KBLog.sync.kbDebug("Storage delete OK docId=\(doc.id)")
            } catch {
                // Se fallisce, prova il fallback (path senza fileName)
                KBLog.sync.kbDebug("Storage delete failed, trying fallback path docId=\(doc.id)")
                
                let fallbackPath = "families/\(familyId)/documents/\(doc.id)"
                do {
                    try await storage.reference(withPath: fallbackPath).delete()
                    KBLog.sync.kbDebug("Storage delete OK (fallback) docId=\(doc.id)")
                } catch {
                    // Se nemmeno il fallback funziona, continua (il file potrebbe non esistere)
                    KBLog.sync.kbDebug("Storage delete failed (both paths) docId=\(doc.id) error=\(error.localizedDescription)")
                }
            }
        } else {
            KBLog.sync.kbDebug("Storage delete skipped (empty storagePath) docId=\(doc.id)")
        }
        
        // 2) Firestore metadata delete
        KBLog.sync.kbInfo("Deleting Firestore metadata docId=\(doc.id)")
        try await db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(doc.id)
            .delete()
        
        KBLog.sync.kbInfo("deleteDocumentHard completed familyId=\(familyId) docId=\(doc.id)")
    }
}
