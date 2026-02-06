//
//  TodoRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

struct RemoteTodoWrite {
    let id: String
    let familyId: String
    let childId: String
    let title: String
    let isDone: Bool
}

struct TodoRemoteDTO {
    let id: String
    let familyId: String
    let childId: String
    let title: String
    let isDone: Bool
    let isDeleted: Bool
    let updatedAt: Date?
    let updatedBy: String?
}

enum TodoRemoteChange {
    case upsert(TodoRemoteDTO)
    case remove(String)
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

extension TodoRemoteStore {
    
    func listenTodos(
        familyId: String,
        childId: String,
        onChange: @escaping ([TodoRemoteChange]) -> Void
    ) -> ListenerRegistration {
        
        let db = Firestore.firestore()
        
        return db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("childId", isEqualTo: childId)
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.error("Firestore listener error: \(err.localizedDescription, privacy: .public)")
                    return
                }
                guard let snap else { return }
                
                let changes: [TodoRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
                    // Mappa i tuoi campi
                    let dto = TodoRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        childId: data["childId"] as? String ?? "",
                        title: data["title"] as? String ?? "",
                        isDone: data["isDone"] as? Bool ?? false,
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
                    onChange(changes)
                }
            }
    }
}
