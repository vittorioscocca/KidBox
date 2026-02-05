//
//  FamilyReadRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import FirebaseFirestore

struct RemoteFamilyRead {
    let id: String
    let name: String
    let ownerUid: String
}

struct RemoteChildRead {
    let id: String
    let name: String
    let birthDate: Date?
}

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

final class FamilyReadRemoteStore {
    private var db: Firestore { Firestore.firestore() }
    
    func fetchFamily(familyId: String) async throws -> RemoteFamilyRead {
        let snap = try await db.collection("families").document(familyId).getDocument()
        guard let data = snap.data(),
              let name = data["name"] as? String,
              let ownerUid = data["ownerUid"] as? String
        else { throw NSError(domain: "KidBox", code: -10) }
        
        return .init(id: familyId, name: name, ownerUid: ownerUid)
    }
    
    func fetchChildren(familyId: String) async throws -> [RemoteChildRead] {
        let qs = try await db.collection("families").document(familyId).collection("children").getDocuments()
        return qs.documents.compactMap { doc in
            let d = doc.data()
            guard let name = d["name"] as? String else { return nil }
            let birth = (d["birthDate"] as? Timestamp)?.dateValue()
            return .init(id: doc.documentID, name: name, birthDate: birth)
        }
    }
    
    func fetchRoutines(familyId: String) async throws -> [RemoteRoutineRead] {
        let qs = try await db.collection("families").document(familyId).collection("routines").getDocuments()
        return qs.documents.compactMap { doc in
            let d = doc.data()
            guard
                let childId = d["childId"] as? String,
                let title = d["title"] as? String
            else { return nil }
            
            return .init(
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
    }
    
    func fetchTodos(familyId: String) async throws -> [RemoteTodoRead] {
        let qs = try await db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("isDeleted", isEqualTo: false)
            .getDocuments()
        
        return qs.documents.compactMap { doc in
            let d = doc.data()
            guard
                let childId = d["childId"] as? String,
                let title = d["title"] as? String
            else { return nil }
            
            return .init(
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
    }
    
    func fetchEvents(familyId: String) async throws -> [RemoteEventRead] {
        let qs = try await db.collection("families").document(familyId).collection("events").getDocuments()
        return qs.documents.compactMap { doc in
            let d = doc.data()
            guard
                let childId = d["childId"] as? String,
                let type = d["type"] as? String,
                let title = d["title"] as? String,
                let startAt = (d["startAt"] as? Timestamp)?.dateValue()
            else { return nil }
            
            return .init(
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
    }
}
