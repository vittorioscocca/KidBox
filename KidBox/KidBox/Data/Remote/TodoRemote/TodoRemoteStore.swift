//
//  TodoRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct RemoteTodoWrite {
    let id: String
    let familyId: String
    let childId: String
    let title: String
    let isDone: Bool
}

final class TodoRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    func upsert(todo: RemoteTodoWrite) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        let ref = db
            .collection("families")
            .document(todo.familyId)
            .collection("todos")
            .document(todo.id)
        
        try await ref.setData([
            "childId": todo.childId,
            "title": todo.title,
            "isDone": todo.isDone,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            // creato solo la prima volta
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func softDelete(todoId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        let ref = db
            .collection("families")
            .document(familyId)
            .collection("todos")
            .document(todoId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}
