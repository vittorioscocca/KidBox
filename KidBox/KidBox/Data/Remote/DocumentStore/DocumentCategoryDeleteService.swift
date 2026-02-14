//
//  DocumentCategoryDeleteService.swift
//  KidBox
//
//  Created by vscocca on 07/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import OSLog

/// Service responsible for deleting a document category and all its documents ("hard delete").
///
/// Hard delete semantics (unchanged):
/// 1) For every document in the category: delete remotely (Storage + Firestore) via `DocumentDeleteService`.
/// 2) Delete the category document from Firestore.
///
/// Notes:
/// - Requires an authenticated Firebase user.
/// - This operation can be partially applied if a failure occurs mid-loop
///   (same behavior as current implementation).
final class DocumentCategoryDeleteService {
    
    private let db = Firestore.firestore()
    private let docDelete = DocumentDeleteService()
    
    /// Deletes a category and all its contained documents, remotely.
    ///
    /// - Parameters:
    ///   - familyId: Family identifier.
    ///   - categoryId: Category identifier.
    ///   - docsInCategory: Documents currently associated with the category.
    ///
    /// - Throws:
    ///   - If the user is not authenticated.
    ///   - Any error thrown by the underlying delete operations (document or category).
    func deleteCategoryCascadeHard(
        familyId: String,
        categoryId: String,
        docsInCategory: [KBDocument]
    ) async throws {
        
        KBLog.sync.kbInfo("deleteCategoryCascadeHard started familyId=\(familyId) categoryId=\(categoryId) docs=\(docsInCategory.count)")
        
        guard Auth.auth().currentUser != nil else {
            KBLog.auth.kbError("deleteCategoryCascadeHard failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        // 1) Delete all documents (Storage + Firestore)
        KBLog.sync.kbInfo("Deleting documents in category count=\(docsInCategory.count)")
        for d in docsInCategory {
            KBLog.sync.kbDebug("Deleting document docId=\(d.id)")
            try await docDelete.deleteDocumentHard(familyId: familyId, doc: d)
        }
        
        // 2) Delete the category (Firestore)
        KBLog.sync.kbInfo("Deleting Firestore category categoryId=\(categoryId)")
        try await db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .document(categoryId)
            .delete()
        
        KBLog.sync.kbInfo("deleteCategoryCascadeHard completed familyId=\(familyId) categoryId=\(categoryId)")
    }
}
