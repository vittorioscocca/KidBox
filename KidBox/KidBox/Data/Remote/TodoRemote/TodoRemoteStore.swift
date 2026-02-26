//
//  TodoRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - Helpers (logging)

private func kbTrace(_ prefix: String = "") -> String {
    let s = UUID().uuidString
    let t = String(s.prefix(8))
    return prefix.isEmpty ? t : "\(prefix)\(t)"
}

private func kbMsSince(_ start: CFAbsoluteTime) -> Int {
    Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0)
}

private func kbBool(_ b: Bool) -> String { b ? "true" : "false" }

private func kbOptStr(_ s: String?) -> String { s ?? "nil" }
private func kbOptDate(_ d: Date?) -> String { d?.description ?? "nil" }

// MARK: - Payloads / DTOs

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

enum TodoRemoteChange {
    case upsert(TodoRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class TodoRemoteStore {
    
    var db: Firestore { Firestore.firestore() }
    
    // MARK: - Upsert Todo
    
    func upsert(todo: RemoteTodoWrite) async throws {
        let trace = kbTrace("todoUpsert:")
        let t0 = CFAbsoluteTimeGetCurrent()
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[\(trace)] TodoRemoteStore.upsert NOT AUTHENTICATED")
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Non loggo title/notes (PII). Loggo solo flags e ids.
        KBLog.sync.kbInfo("""
        [\(trace)] TodoRemoteStore.upsert START
        familyId=\(todo.familyId) childId=\(todo.childId) todoId=\(todo.id)
        listId=\(kbOptStr(todo.listId)) isDone=\(kbBool(todo.isDone)) dueAt=\(kbOptDate(todo.dueAt))
        hasNotes=\(kbBool(todo.notes != nil)) assignedToPresent=\(kbBool(todo.assignedTo != nil)) priority=\(todo.priority ?? 0)
        """)
        
        let ref = db
            .collection("families")
            .document(todo.familyId)
            .collection("todos")
            .document(todo.id)
        
        // ✅ check existence for createdBy
        let snap = try await ref.getDocument()
        let isNew = !snap.exists
        KBLog.sync.kbDebug("[\(trace)] TodoRemoteStore.upsert existence isNew=\(kbBool(isNew)) ms=\(kbMsSince(t0))")
        
        var data: [String: Any] = [
            "childId": todo.childId,
            "title": todo.title, // Non logghiamo, ma lo scriviamo ovviamente
            "listId": todo.listId ?? "",
            "isDone": todo.isDone,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }
        
        data["notes"] = todo.notes as Any
        data["dueAt"] = todo.dueAt.map { Timestamp(date: $0) } as Any
        data["doneAt"] = todo.doneAt.map { Timestamp(date: $0) } as Any
        data["doneBy"] = todo.doneBy as Any
        data["assignedTo"] = todo.assignedTo as Any
        data["priority"] = (todo.priority ?? 0)
        
        if isNew { data["createdBy"] = (todo.createdBy ?? uid) }
        
        try await ref.setData(data, merge: true)
        
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.upsert OK todoId=\(todo.id) ms=\(kbMsSince(t0))")
    }
    
    // MARK: - Soft delete Todo
    
    func softDelete(todoId: String, familyId: String) async throws {
        let trace = kbTrace("todoDel:")
        let t0 = CFAbsoluteTimeGetCurrent()
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[\(trace)] TodoRemoteStore.softDelete NOT AUTHENTICATED todoId=\(todoId)")
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.softDelete START familyId=\(familyId) todoId=\(todoId) uidPresent=\(kbBool(!uid.isEmpty))")
        
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
        
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.softDelete OK familyId=\(familyId) todoId=\(todoId) ms=\(kbMsSince(t0))")
    }
}

// MARK: - TodoList remote support

struct TodoListRemoteDTO {
    let id: String
    let familyId: String
    let childId: String
    let name: String
    let isDeleted: Bool
    let updatedAt: Date?
}

enum TodoListRemoteChange {
    case upsert(TodoListRemoteDTO)
    case remove(String)
}

extension TodoRemoteStore {
    
    func upsertList(list: KBTodoList) async throws {
        let trace = kbTrace("listUpsert:")
        let t0 = CFAbsoluteTimeGetCurrent()
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[\(trace)] TodoRemoteStore.upsertList NOT AUTHENTICATED listId=\(list.id)")
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // Non loggo il nome lista (potrebbe essere “PII” soft)
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.upsertList START familyId=\(list.familyId) childId=\(list.childId) listId=\(list.id) isDeleted=\(kbBool(list.isDeleted))")
        
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
        
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.upsertList OK listId=\(list.id) ms=\(kbMsSince(t0))")
    }
    
    func softDeleteList(listId: String, familyId: String) async throws {
        let trace = kbTrace("listDel:")
        let t0 = CFAbsoluteTimeGetCurrent()
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[\(trace)] TodoRemoteStore.softDeleteList NOT AUTHENTICATED listId=\(listId)")
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.softDeleteList START familyId=\(familyId) listId=\(listId) uidPresent=\(kbBool(!uid.isEmpty))")
        
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
        
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.softDeleteList OK listId=\(listId) ms=\(kbMsSince(t0))")
    }
    
    func listenTodoLists(
        familyId: String,
        childId: String,
        onChange: @escaping ([TodoListRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        let trace = kbTrace("listListen:")
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.listenTodoLists ATTACH familyId=\(familyId) childId=\(childId) query=isDeleted==false")
        
        return db.collection("families")
            .document(familyId)
            .collection("todoLists")
            .whereField("childId", isEqualTo: childId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener { snap, err in
                if let err {
                    KBLog.sync.kbError("[\(trace)] TodoLists listener ERROR familyId=\(familyId) childId=\(childId) err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("[\(trace)] TodoLists listener snapshot nil familyId=\(familyId) childId=\(childId)")
                    return
                }
                
                let meta = snap.metadata
                KBLog.sync.kbDebug("[\(trace)] TodoLists snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(kbBool(meta.isFromCache)) pendingWrites=\(kbBool(meta.hasPendingWrites))")
                
                var added = 0, modified = 0, removed = 0
                
                let changes: [TodoListRemoteChange] = snap.documentChanges.compactMap { diff in
                    switch diff.type {
                    case .added: added += 1
                    case .modified: modified += 1
                    case .removed: removed += 1
                    }
                    
                    let doc = diff.document
                    let d = doc.data()
                    guard let name = d["name"] as? String,
                          let cid = d["childId"] as? String else {
                        KBLog.sync.kbInfo("[\(trace)] TodoLists decode FAIL docId=\(doc.documentID) type=\(diff.type.rawValue)")
                        return nil
                    }
                    
                    let dto = TodoListRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        childId: cid,
                        name: name,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue()
                    )
                    
                    KBLog.sync.kbDebug("[\(trace)] TodoLists change type=\(diff.type.rawValue) id=\(dto.id) isDeleted=\(kbBool(dto.isDeleted)) updatedAt=\(kbOptDate(dto.updatedAt))")
                    
                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed: return .remove(doc.documentID)
                    }
                }
                
                KBLog.sync.kbInfo("[\(trace)] TodoLists snapshot summary added=\(added) modified=\(modified) removed=\(removed) emitting=\(changes.count)")
                
                if !changes.isEmpty { onChange(changes) }
            }
    }
    
    func fetchTodoLists(familyId: String, childId: String) async throws -> [TodoListRemoteDTO] {
        let trace = kbTrace("listFetch:")
        let t0 = CFAbsoluteTimeGetCurrent()
        
        KBLog.sync.kbInfo("[\(trace)] fetchTodoLists START familyId=\(familyId) childId=\(childId) query=isDeleted==false")
        
        let snap = try await db.collection("families")
            .document(familyId)
            .collection("todoLists")
            .whereField("childId", isEqualTo: childId)
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        
        let out = snap.documents.compactMap { doc -> TodoListRemoteDTO? in
            let d = doc.data()
            guard let name = d["name"] as? String,
                  let cid = d["childId"] as? String else {
                KBLog.sync.kbInfo("[\(trace)] fetchTodoLists decode FAIL docId=\(doc.documentID)")
                return nil
            }
            return TodoListRemoteDTO(
                id: doc.documentID,
                familyId: familyId,
                childId: cid,
                name: name,
                isDeleted: d["isDeleted"] as? Bool ?? false,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue()
            )
        }
        
        KBLog.sync.kbInfo("[\(trace)] fetchTodoLists OK docs=\(snap.documents.count) decoded=\(out.count) ms=\(kbMsSince(t0))")
        return out
    }
}

// MARK: - Realtime listener (Todos)

extension TodoRemoteStore {
    
    func listenTodos(
        familyId: String,
        childId: String,
        onChange: @escaping ([TodoRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        
        let trace = kbTrace("todoListen:")
        KBLog.sync.kbInfo("[\(trace)] TodoRemoteStore.listenTodos ATTACH familyId=\(familyId) childId=\(childId) query=childId==\(childId)")
        
        let db = Firestore.firestore()
        
        return db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("childId", isEqualTo: childId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[\(trace)] Todos listener ERROR familyId=\(familyId) childId=\(childId) err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("[\(trace)] Todos listener snapshot nil familyId=\(familyId) childId=\(childId)")
                    return
                }
                
                KBLog.sync.kbDebug("""
    [TodosListener] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count)
    fromCache=\(snap.metadata.isFromCache) pendingWrites=\(snap.metadata.hasPendingWrites)
    familyId=\(familyId) childId=\(childId)
    """)
                KBLog.sync.kbInfo("[TodosListener] fromCache=\(snap.metadata.isFromCache) pendingWrites=\(snap.metadata.hasPendingWrites) docs=\(snap.documents.count) changes=\(snap.documentChanges.count)")
                let meta = snap.metadata
                KBLog.sync.kbDebug("[\(trace)] Todos snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(kbBool(meta.isFromCache)) pendingWrites=\(kbBool(meta.hasPendingWrites))")
                
                var added = 0, modified = 0, removed = 0
                
                let changes: [TodoRemoteChange] = snap.documentChanges.compactMap { diff in
                    switch diff.type {
                    case .added: added += 1
                    case .modified: modified += 1
                    case .removed: removed += 1
                    }
                    
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
                    
                    if dto.childId.isEmpty {
                        KBLog.sync.kbInfo("[\(trace)] Todos decode WARN: missing childId docId=\(dto.id)")
                    }
                    
                    let isDel = data["isDeleted"] as? Bool ?? false
                    let ua = (data["updatedAt"] as? Timestamp)?.dateValue()
                    
                    KBLog.sync.kbDebug("[TodosListener] change=\(diff.type) id=\(doc.documentID) isDeleted=\(isDel) updatedAt=\(ua?.description ?? "nil")")
                    
                    // ⚠️ non loggare title/notes
                    KBLog.sync.kbDebug("[\(trace)] Todos change type=\(diff.type.rawValue) id=\(dto.id) listId=\(kbOptStr(dto.listId)) isDeleted=\(kbBool(dto.isDeleted)) isDone=\(kbBool(dto.isDone)) updatedAt=\(kbOptDate(dto.updatedAt))")
                    
                    switch diff.type {
                    case .added, .modified:
                        return .upsert(dto)
                    case .removed:
                        return .remove(doc.documentID)
                    }
                }
                
                KBLog.sync.kbInfo("[\(trace)] Todos snapshot summary added=\(added) modified=\(modified) removed=\(removed) emitting=\(changes.count)")
                
                if !changes.isEmpty {
                    onChange(changes)
                }
            }
    }
}
