//
//  DocumentCategoryDeleteService.swift
//  KidBox
//
//  Created by vscocca on 07/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

final class DocumentCategoryDeleteService {
    private let db = Firestore.firestore()
    private let docDelete = DocumentDeleteService()
    
    func deleteCategoryCascadeHard(
        familyId: String,
        categoryId: String,
        docsInCategory: [KBDocument]
    ) async throws {
        
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // 1) cancella TUTTI i documenti (Storage + Firestore)
        for d in docsInCategory {
            try await docDelete.deleteDocumentHard(familyId: familyId, doc: d)
        }
        
        // 2) cancella la categoria (Firestore)
        try await db.collection("families")
            .document(familyId)
            .collection("documentCategories")
            .document(categoryId)
            .delete()
    }
}
