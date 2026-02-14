//
//  FamilyReadRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore
import OSLog

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
    let notes: String?
    let dueAt: Date?
    let isDone: Bool
    let doneAt: Date?
    let doneBy: String?
    let updatedAt: Date?
    let updatedBy: String?
    let isDeleted: Bool
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
    
    /// Fetches the family root document.
    ///
    /// - Throws: If the document does not exist or required fields are missing.
    func fetchFamily(familyId: String) async throws -> RemoteFamilyRead {
        KBLog.sync.kbInfo("fetchFamily started familyId=\(familyId)")
        
        let snap = try await db.collection("families")
            .document(familyId)
            .getDocument()
        
        guard let data = snap.data(),
              let name = data["name"] as? String,
              let ownerUid = data["ownerUid"] as? String
        else {
            KBLog.sync.kbError("fetchFamily failed: missing fields familyId=\(familyId)")
            throw NSError(domain: "KidBox", code: -10)
        }
        
        KBLog.sync.kbInfo("fetchFamily completed familyId=\(familyId)")
        return .init(id: familyId, name: name, ownerUid: ownerUid)
    }
    
    /// Fetches all children documents under a family.
    ///
    /// - Returns: Array of decoded children. Invalid rows are skipped.
    func fetchChildren(familyId: String) async throws -> [RemoteChildRead] {
        KBLog.sync.kbInfo("fetchChildren started familyId=\(familyId)")
        
        let qs = try await db.collection("families")
            .document(familyId)
            .collection("children")
            .getDocuments()
        
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
        
        KBLog.sync.kbInfo("fetchChildren completed familyId=\(familyId) count=\(items.count)")
        return items
    }
    
    /// Fetches all routines documents under a family.
    ///
    /// - Returns: Array of decoded routines. Invalid rows are skipped.
    func fetchRoutines(familyId: String) async throws -> [RemoteRoutineRead] {
        KBLog.sync.kbInfo("fetchRoutines started familyId=\(familyId)")
        
        let qs = try await db.collection("families")
            .document(familyId)
            .collection("routines")
            .getDocuments()
        
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
        
        KBLog.sync.kbInfo("fetchRoutines completed familyId=\(familyId) count=\(items.count)")
        return items
    }
    
    /// Fetches todos documents under a family where `isDeleted == false`.
    ///
    /// - Returns: Array of decoded todos. Invalid rows are skipped.
    func fetchTodos(familyId: String) async throws -> [RemoteTodoRead] {
        KBLog.sync.kbInfo("fetchTodos started familyId=\(familyId)")
        
        let qs = try await db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        
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
                notes: d["notes"] as? String,
                dueAt: (d["dueAt"] as? Timestamp)?.dateValue(),
                isDone: (d["isDone"] as? Bool) ?? false,
                doneAt: (d["doneAt"] as? Timestamp)?.dateValue(),
                doneBy: d["doneBy"] as? String,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                updatedBy: d["updatedBy"] as? String,
                isDeleted: (d["isDeleted"] as? Bool) ?? false
            )
        }
        
        KBLog.sync.kbInfo("fetchTodos completed familyId=\(familyId) count=\(items.count)")
        return items
    }
    
    /// Fetches all events documents under a family.
    ///
    /// - Returns: Array of decoded events. Invalid rows are skipped.
    func fetchEvents(familyId: String) async throws -> [RemoteEventRead] {
        KBLog.sync.kbInfo("fetchEvents started familyId=\(familyId)")
        
        let qs = try await db.collection("families")
            .document(familyId)
            .collection("events")
            .getDocuments()
        
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
        
        KBLog.sync.kbInfo("fetchEvents completed familyId=\(familyId) count=\(items.count)")
        return items
    }
}
