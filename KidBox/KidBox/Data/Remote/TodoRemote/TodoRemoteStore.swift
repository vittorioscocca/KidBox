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

// MARK: - Payloads / DTOs

/// Outbound payload used to write (upsert) a Todo on Firestore.
struct RemoteTodoWrite {
    let id: String
    let familyId: String
    let childId: String
    let title: String
    let isDone: Bool
}

/// Inbound DTO decoded from Firestore.
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

/// Realtime change event from Firestore.
enum TodoRemoteChange {
    case upsert(TodoRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

/// Firestore remote store for Todos.
///
/// Responsibilities:
/// - Upsert Todo documents
/// - Soft-delete Todo documents
/// - Listen to realtime changes (filtered by childId)
///
/// Notes:
/// - Requires an authenticated Firebase user for writes.
final class TodoRemoteStore {
    
    /// Firestore handle (computed as in original code).
    var db: Firestore { Firestore.firestore() }
    
    /// Upserts a Todo document.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Writes fields + `updatedAt` server timestamp.
    /// - Writes `createdAt` using merge=true (still setData with merge true).
    func upsert(todo: RemoteTodoWrite) async throws {
        guard let _ = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("TodoRemoteStore.upsert failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbDebug("TodoRemoteStore.upsert start familyId=\(todo.familyId) todoId=\(todo.id) childId=\(todo.childId)")
        
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
            "updatedBy": Auth.auth().currentUser?.uid ?? "",
            "updatedAt": FieldValue.serverTimestamp(),
            // created only the first time (still sent, merge=true keeps it if already exists)
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbDebug("TodoRemoteStore.upsert OK familyId=\(todo.familyId) todoId=\(todo.id)")
    }
    
    /// Soft-deletes a Todo document.
    ///
    /// Behavior (unchanged):
    /// - Requires authenticated user.
    /// - Sets `isDeleted=true` and updates `updatedAt` server timestamp.
    func softDelete(todoId: String, familyId: String) async throws {
        guard let _ = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("TodoRemoteStore.softDelete failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        KBLog.sync.kbDebug("TodoRemoteStore.softDelete start familyId=\(familyId) todoId=\(todoId)")
        
        let ref = db
            .collection("families")
            .document(familyId)
            .collection("todos")
            .document(todoId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": Auth.auth().currentUser?.uid ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbDebug("TodoRemoteStore.softDelete OK familyId=\(familyId) todoId=\(todoId)")
    }
}

// MARK: - Realtime listener

extension TodoRemoteStore {
    
    /// Starts a realtime listener for todos of a given child in a family.
    ///
    /// Behavior (unchanged):
    /// - Listens on `families/{familyId}/todos` filtered by `childId`.
    /// - Maps Firestore documentChanges to `TodoRemoteChange` array.
    /// - Calls `onChange` only when changes is not empty.
    func listenTodos(
        familyId: String,
        childId: String,
        onChange: @escaping ([TodoRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("TodoRemoteStore.listenTodos attach familyId=\(familyId) childId=\(childId)")
        
        let db = Firestore.firestore()
        
        return db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("childId", isEqualTo: childId)
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("Todos listener error: \(err.localizedDescription) familyId=\(familyId) childId=\(childId)")
                    onError(err)
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("Todos listener snapshot nil familyId=\(familyId) childId=\(childId)")
                    return
                }
                
                KBLog.sync.kbDebug("Todos snapshot size=\(snap.documents.count) changes=\(snap.documentChanges.count) familyId=\(familyId) childId=\(childId)")
                
                let changes: [TodoRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let data = doc.data()
                    
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
                    KBLog.sync.kbDebug("Todos onChange firing changes=\(changes.count) familyId=\(familyId) childId=\(childId)")
                    onChange(changes)
                }
            }
    }
}
