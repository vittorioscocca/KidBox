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

final class DocumentDeleteService {
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    func deleteDocumentHard(familyId: String, doc: KBDocument) async throws {
        guard Auth.auth().currentUser != nil else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // 1) Storage cleanup (se abbiamo il path)
        let path = doc.storagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty {
            try await storage.reference(withPath: path).delete()
        } else {
            // fallback: se vuoi, costruisci un path standard (se lo usi sempre)
            // try await storage.reference(withPath: "families/\(familyId)/documents/\(doc.id)").delete()
        }
        
        // 2) Firestore metadata delete
        try await db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(doc.id)
            .delete()
    }
}
