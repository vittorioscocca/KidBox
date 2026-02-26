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
    let listId: String?
    let isDone: Bool
    let notes: String?
    let dueAt: Date?
    let doneAt: Date?
    let doneBy: String?
    let assignedTo: String?
    let createdBy: String?
    let priority: Int?
}

/// Inbound DTO decoded from Firestore.
struct TodoRemoteDTO {
    let id: String
    let familyId: String
    let childId: String
    let title: String
    let listId: String?
    let isDone: Bool
    let isDeleted: Bool
    let notes: String?
    let dueAt: Date?
    let doneAt: Date?
    let doneBy: String?
    let updatedAt: Date?
    let updatedBy: String?
    let assignedTo: String?
    let createdBy: String?
    let priority: Int?
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
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("TodoRemoteStore.upsert failed: not authenticated")
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbDebug("TodoRemoteStore.upsert start familyId=\(todo.familyId) todoId=\(todo.id) childId=\(todo.childId)")
        
        let ref = db
            .collection("families")
            .document(todo.familyId)
            .collection("todos")
            .document(todo.id)
        
        // ✅ check existence for createdBy
        let snap = try await ref.getDocument()
        let isNew = !snap.exists
        
        var data: [String: Any] = [
            "childId": todo.childId,
            "title": todo.title,
            "listId": todo.listId ?? "",
            "isDone": todo.isDone,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        // campi opzionali: scrivi sempre (nil = NSNull per cancellare il valore remoto)
        data["notes"]   = todo.notes as Any
        data["dueAt"]   = todo.dueAt.map { Timestamp(date: $0) } as Any
        data["doneAt"]  = todo.doneAt.map { Timestamp(date: $0) } as Any
        data["doneBy"]  = todo.doneBy as Any
        data["assignedTo"] = todo.assignedTo as Any
        data["priority"] = (todo.priority ?? 0)
        
        if isNew {
            data["createdBy"] = (todo.createdBy ?? uid)
        }
        
        try await ref.setData(data, merge: true)
        
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

// MARK: - TodoList remote support

/// Inbound DTO per una lista todo da Firestore.
struct TodoListRemoteDTO {
    let id: String
    let familyId: String
    let childId: String
    let name: String
    let isDeleted: Bool
    let updatedAt: Date?
}

/// Realtime change event per le liste.
enum TodoListRemoteChange {
    case upsert(TodoListRemoteDTO)
    case remove(String)
}

extension TodoRemoteStore {
    
    /// Upserta una lista su Firestore.
    func upsertList(list: KBTodoList) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbDebug("TodoRemoteStore.upsertList start familyId=\(list.familyId) listId=\(list.id)")
        
        let ref = db
            .collection("families")
            .document(list.familyId)
            .collection("todoLists")
            .document(list.id)
        
        try await ref.setData([
            "childId": list.childId,
            "name": list.name,
            "isDeleted": list.isDeleted,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbDebug("TodoRemoteStore.upsertList OK listId=\(list.id)")
    }
    
    /// Soft-delete di una lista su Firestore.
    func softDeleteList(listId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbDebug("TodoRemoteStore.softDeleteList start familyId=\(familyId) listId=\(listId)")
        
        let ref = db
            .collection("families")
            .document(familyId)
            .collection("todoLists")
            .document(listId)
        
        try await ref.setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.sync.kbDebug("TodoRemoteStore.softDeleteList OK listId=\(listId)")
    }
    
    /// Listener realtime per le liste di una famiglia/figlio.
    func listenTodoLists(
        familyId: String,
        childId: String,
        onChange: @escaping ([TodoListRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        KBLog.sync.kbInfo("TodoRemoteStore.listenTodoLists attach familyId=\(familyId) childId=\(childId)")
        
        return db.collection("families")
            .document(familyId)
            .collection("todoLists")
            .whereField("childId", isEqualTo: childId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener { snap, err in
                if let err {
                    onError(err)
                    return
                }
                guard let snap else { return }
                
                let changes: [TodoListRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()
                    guard let name = d["name"] as? String,
                          let cid = d["childId"] as? String else { return nil }
                    
                    let dto = TodoListRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        childId: cid,
                        name: name,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue()
                    )
                    
                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed:          return .remove(doc.documentID)
                    }
                }
                
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    /// Fetch iniziale di tutte le liste non eliminate per una famiglia.
    func fetchTodoLists(familyId: String, childId: String) async throws -> [TodoListRemoteDTO] {
        let snap = try await db.collection("families")
            .document(familyId)
            .collection("todoLists")
            .whereField("childId", isEqualTo: childId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        
        return snap.documents.compactMap { doc in
            let d = doc.data()
            guard let name = d["name"] as? String,
                  let cid = d["childId"] as? String else { return nil }
            return TodoListRemoteDTO(
                id: doc.documentID,
                familyId: familyId,
                childId: cid,
                name: name,
                isDeleted: d["isDeleted"] as? Bool ?? false,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue()
            )
        }
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
                        listId: data["listId"] as? String,
                        isDone: data["isDone"] as? Bool ?? false,
                        isDeleted: data["isDeleted"] as? Bool ?? false,
                        notes: data["notes"] as? String,
                        dueAt: (data["dueAt"] as? Timestamp)?.dateValue(),
                        doneAt: (data["doneAt"] as? Timestamp)?.dateValue(),
                        doneBy: data["doneBy"] as? String,
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                        updatedBy: data["updatedBy"] as? String,
                        assignedTo: data["assignedTo"] as? String,
                        createdBy: data["createdBy"] as? String,
                        priority: data["priority"] as? Int
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
