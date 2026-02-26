//
//  FamilyReadRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import OSLog
import FirebaseAuth

// MARK: - Remote read models

/// Minimal family snapshot read from Firestore.
struct RemoteFamilyRead {
    let id: String
    let name: String
    let ownerUid: String
}

/// Minimal child snapshot read from Firestore.
struct RemoteChildRead {
    let id: String
    let name: String
    let birthDate: Date?
}

/// Routine snapshot read from Firestore.
struct RemoteRoutineRead {
    let id: String
    let childId: String
    let title: String
    let isActive: Bool
    let sortOrder: Int
    let updatedAt: Date?
    let updatedBy: String?
    let isDeleted: Bool
}

/// Todo snapshot read from Firestore.
struct RemoteTodoRead {
    let id: String
    let childId: String
    let title: String
    let listId: String?
    let notes: String?
    let dueAt: Date?
    let isDone: Bool
    let doneAt: Date?
    let doneBy: String?
    let assignedTo: String?
    let createdBy: String?
    let priority: Int?
    let updatedAt: Date?
    let updatedBy: String?
    let isDeleted: Bool
}

/// TodoList snapshot read from Firestore.
struct RemoteTodoListRead {
    let id: String
    let childId: String
    let name: String
    let isDeleted: Bool
    let updatedAt: Date?
}

/// Event snapshot read from Firestore.
struct RemoteEventRead {
    let id: String
    let childId: String
    let type: String
    let title: String
    let startAt: Date
    let endAt: Date?
    let notes: String?
    let updatedAt: Date?
    let updatedBy: String?
    let isDeleted: Bool
}

// MARK: - Remote store

/// Read-only remote store for fetching a family's "bundle" from Firestore.
///
/// Responsibilities:
/// - Fetch the family root document
/// - Fetch children
/// - Fetch routines
/// - Fetch todos (filtered to `isDeleted == false`)
/// - Fetch events
///
/// Notes:
/// - This layer performs best-effort decoding:
///   rows missing required fields are skipped (`compactMap`) for collections.
/// - `fetchFamily` throws if required fields are missing (unchanged).
final class FamilyReadRemoteStore {
    
    private var db: Firestore { Firestore.firestore() }
    
    // MARK: - Logging helpers
    
    /// Short trace id to correlate logs for a single fetch call.
    private func traceId() -> String {
        String(UUID().uuidString.prefix(8))
    }
    
    /// Milliseconds elapsed since `start`.
    private func elapsedMs(since start: DispatchTime) -> Int {
        let end = DispatchTime.now().uptimeNanoseconds
        let begin = start.uptimeNanoseconds
        return Int((end - begin) / 1_000_000)
    }
    
    /// Fetches the family root document.
    ///
    /// - Throws: If the document does not exist or required fields are missing.
    func fetchFamily(familyId: String) async throws -> RemoteFamilyRead {
        let tid = traceId()
        let t0 = DispatchTime.now()
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchFamily start familyId=\(familyId)")
        
        var snap: DocumentSnapshot
        do {
            snap = try await db.collection("families")
                .document(familyId)
                .getDocument()
        } catch {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchFamily FAIL familyId=\(familyId) ms=\(elapsedMs(since: t0)) err=\(String(describing: error))")
            throw error
        }
        
        guard snap.exists else {
            KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchFamily missing doc familyId=\(familyId) ms=\(elapsedMs(since: t0))")
            // ✅ Fallback: crea un documento minimo
            let ownerUid = Auth.auth().currentUser?.uid ?? "unknown"
            try await db.collection("families").document(familyId).setData([
                "name": "Famiglia",
                "ownerUid": ownerUid,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
            
            KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchFamily created missing doc familyId=\(familyId) ms=\(elapsedMs(since: t0))")
            return .init(id: familyId, name: "Famiglia", ownerUid: ownerUid)
        }
        
        guard let data = snap.data(),
              let name = data["name"] as? String
        else {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchFamily missing required fields familyId=\(familyId) ms=\(elapsedMs(since: t0))")
            throw NSError(domain: "KidBox", code: -10)
        }
        
        let ownerUid = (data["ownerUid"] as? String) ?? ""
        
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchFamily done familyId=\(familyId) ms=\(elapsedMs(since: t0))")
        return .init(id: familyId, name: name, ownerUid: ownerUid)
    }
    
    /// Fetches all children documents under a family.
    ///
    /// - Returns: Array of decoded children. Invalid rows are skipped.
    func fetchChildren(familyId: String) async throws -> [RemoteChildRead] {
        let tid = traceId()
        let t0 = DispatchTime.now()
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchChildren start familyId=\(familyId)")
        
        var qs: QuerySnapshot
        do {
            qs = try await db.collection("families")
                .document(familyId)
                .collection("children")
                .getDocuments()
        } catch {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchChildren FAIL familyId=\(familyId) ms=\(elapsedMs(since: t0)) err=\(String(describing: error))")
            throw error
        }
        
        let items: [RemoteChildRead] = qs.documents.compactMap { doc in
            let d = doc.data()
            guard let name = d["name"] as? String else { return nil }
            let birth = (d["birthDate"] as? Timestamp)?.dateValue()
            
            return RemoteChildRead(
                id: doc.documentID,
                name: name,
                birthDate: birth
            )
        }
        
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchChildren done familyId=\(familyId) ms=\(elapsedMs(since: t0)) docs=\(qs.documents.count) decoded=\(items.count) skipped=\(max(0, qs.documents.count - items.count))")
        return items
    }
    
    /// Fetches all routines documents under a family.
    ///
    /// - Returns: Array of decoded routines. Invalid rows are skipped.
    func fetchRoutines(familyId: String) async throws -> [RemoteRoutineRead] {
        let tid = traceId()
        let t0 = DispatchTime.now()
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchRoutines start familyId=\(familyId)")
        
        var qs: QuerySnapshot
        do {
            qs = try await db.collection("families")
                .document(familyId)
                .collection("routines")
                .getDocuments()
        } catch {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchRoutines FAIL familyId=\(familyId) ms=\(elapsedMs(since: t0)) err=\(String(describing: error))")
            throw error
        }
        
        let items: [RemoteRoutineRead] = qs.documents.compactMap { doc in
            let d = doc.data()
            guard
                let childId = d["childId"] as? String,
                let title = d["title"] as? String
            else { return nil }
            
            return RemoteRoutineRead(
                id: doc.documentID,
                childId: childId,
                title: title,
                isActive: (d["isActive"] as? Bool) ?? true,
                sortOrder: (d["sortOrder"] as? Int) ?? 0,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                updatedBy: d["updatedBy"] as? String,
                isDeleted: (d["isDeleted"] as? Bool) ?? false
            )
        }
        
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchRoutines done familyId=\(familyId) ms=\(elapsedMs(since: t0)) docs=\(qs.documents.count) decoded=\(items.count) skipped=\(max(0, qs.documents.count - items.count))")
        return items
    }
    
    /// Fetches todos documents under a family where `isDeleted == false`.
    ///
    /// - Returns: Array of decoded todos. Invalid rows are skipped.
    func fetchTodos(familyId: String) async throws -> [RemoteTodoRead] {
        let tid = traceId()
        let t0 = DispatchTime.now()
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchTodos start familyId=\(familyId)")
        
        var qs: QuerySnapshot
        do {
            qs = try await db.collection("families")
                .document(familyId)
                .collection("todos")
                .whereField("isDeleted", isEqualTo: false)
                .getDocuments()
        } catch {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchTodos FAIL familyId=\(familyId) ms=\(elapsedMs(since: t0)) err=\(String(describing: error))")
            throw error
        }
        
        let items: [RemoteTodoRead] = qs.documents.compactMap { doc in
            let d = doc.data()
            
            guard
                let childId = d["childId"] as? String,
                let title = d["title"] as? String
            else { return nil }
            
            return RemoteTodoRead(
                id: doc.documentID,
                childId: childId,
                title: title,
                listId: d["listId"] as? String,
                notes: d["notes"] as? String,
                dueAt: (d["dueAt"] as? Timestamp)?.dateValue(),
                isDone: (d["isDone"] as? Bool) ?? false,
                doneAt: (d["doneAt"] as? Timestamp)?.dateValue(),
                doneBy: d["doneBy"] as? String,
                assignedTo: d["assignedTo"] as? String,
                createdBy: d["createdBy"] as? String,
                priority: d["priority"] as? Int,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                updatedBy: d["updatedBy"] as? String,
                isDeleted: (d["isDeleted"] as? Bool) ?? false
            )
        }
        
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchTodos done familyId=\(familyId) ms=\(elapsedMs(since: t0)) docs=\(qs.documents.count) decoded=\(items.count) skipped=\(max(0, qs.documents.count - items.count))")
        return items
    }
    
    /// Fetches all todoList documents under a family where `isDeleted == false`.
    ///
    /// - Returns: Array of decoded lists. Invalid rows are skipped.
    func fetchTodoLists(familyId: String) async throws -> [RemoteTodoListRead] {
        let tid = traceId()
        let t0 = DispatchTime.now()
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchTodoLists start familyId=\(familyId)")
        
        var qs: QuerySnapshot
        do {
            qs = try await db.collection("families")
                .document(familyId)
                .collection("todoLists")
                .whereField("isDeleted", isEqualTo: false)
                .getDocuments()
        } catch {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchTodoLists FAIL familyId=\(familyId) ms=\(elapsedMs(since: t0)) err=\(String(describing: error))")
            throw error
        }
        
        let items: [RemoteTodoListRead] = qs.documents.compactMap { doc in
            let d = doc.data()
            guard
                let childId = d["childId"] as? String,
                let name = d["name"] as? String
            else { return nil }
            
            return RemoteTodoListRead(
                id: doc.documentID,
                childId: childId,
                name: name,
                isDeleted: (d["isDeleted"] as? Bool) ?? false,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue()
            )
        }
        
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchTodoLists done familyId=\(familyId) ms=\(elapsedMs(since: t0)) docs=\(qs.documents.count) decoded=\(items.count) skipped=\(max(0, qs.documents.count - items.count))")
        return items
    }
    
    /// Fetches all events documents under a family.
    ///
    /// - Returns: Array of decoded events. Invalid rows are skipped.
    func fetchEvents(familyId: String) async throws -> [RemoteEventRead] {
        let tid = traceId()
        let t0 = DispatchTime.now()
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchEvents start familyId=\(familyId)")
        
        var qs: QuerySnapshot
        do {
            qs = try await db.collection("families")
                .document(familyId)
                .collection("events")
                .getDocuments()
        } catch {
            KBLog.sync.kbError("[FamilyReadRemoteStore][\(tid)] fetchEvents FAIL familyId=\(familyId) ms=\(elapsedMs(since: t0)) err=\(String(describing: error))")
            throw error
        }
        
        let items: [RemoteEventRead] = qs.documents.compactMap { doc in
            let d = doc.data()
            guard
                let childId = d["childId"] as? String,
                let type = d["type"] as? String,
                let title = d["title"] as? String,
                let startAt = (d["startAt"] as? Timestamp)?.dateValue()
            else { return nil }
            
            return RemoteEventRead(
                id: doc.documentID,
                childId: childId,
                type: type,
                title: title,
                startAt: startAt,
                endAt: (d["endAt"] as? Timestamp)?.dateValue(),
                notes: d["notes"] as? String,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                updatedBy: d["updatedBy"] as? String,
                isDeleted: (d["isDeleted"] as? Bool) ?? false
            )
        }
        
        KBLog.sync.kbInfo("[FamilyReadRemoteStore][\(tid)] fetchEvents done familyId=\(familyId) ms=\(elapsedMs(since: t0)) docs=\(qs.documents.count) decoded=\(items.count) skipped=\(max(0, qs.documents.count - items.count))")
        return items
    }
}

