//
//  PetEventRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTOs

struct PetEventRemoteDTO {
    let id: String
    let familyId: String
    let petId: String
    let title: String
    let eventTypeRaw: String
    let date: Date
    let nextDueDate: Date?
    let notes: String?
    let vetName: String?
    let cost: Double?
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let updatedBy: String?
    let reminderEnabled: Bool
}

enum PetEventRemoteChange {
    case upsert(PetEventRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class PetEventRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, eventId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("petEvents")
            .document(eventId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("petEvents")
    }

    // MARK: - Upsert

    func upsert(item: KBPetEvent) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: item.familyId, eventId: item.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "petId": item.petId,
            "title": item.title,
            "eventTypeRaw": item.eventTypeRaw,
            "date": Timestamp(date: item.date),
            "isDeleted": false,
            "reminderEnabled": item.reminderEnabled,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }

        data["nextDueDate"] = item.nextDueDate.map { Timestamp(date: $0) } as Any
        data["notes"] = item.notes as Any
        data["vetName"] = item.vetName as Any
        data["cost"] = item.cost as Any

        if isNew { data["createdBy"] = item.createdBy.isEmpty ? uid : item.createdBy }

        try await ref(familyId: item.familyId, eventId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[PetEventRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
    }

    // MARK: - Soft delete

    func softDelete(eventId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, eventId: eventId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[PetEventRemote] softDelete OK id=\(eventId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenPetEvents(
        familyId: String,
        onChange: @escaping ([PetEventRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[PetEventRemote] listenPetEvents ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[PetEventRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[PetEventRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [PetEventRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    guard let title = d["title"] as? String, !title.isEmpty else {
                        KBLog.sync.kbDebug("[PetEventRemote] decode FAIL docId=\(doc.documentID)")
                        return nil
                    }

                    let petId = (d["petId"] as? String) ?? ""
                    guard !petId.isEmpty else {
                        KBLog.sync.kbDebug("[PetEventRemote] decode FAIL missing petId docId=\(doc.documentID)")
                        return nil
                    }

                    let eventTypeRaw = (d["eventTypeRaw"] as? String) ?? "other"
                    let date = (d["date"] as? Timestamp)?.dateValue() ?? Date()

                    let cost: Double? = {
                        if let x = d["cost"] as? Double { return x }
                        if let n = d["cost"] as? NSNumber { return n.doubleValue }
                        return nil
                    }()

                    let dto = PetEventRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        petId: petId,
                        title: title,
                        eventTypeRaw: eventTypeRaw,
                        date: date,
                        nextDueDate: (d["nextDueDate"] as? Timestamp)?.dateValue(),
                        notes: d["notes"] as? String,
                        vetName: d["vetName"] as? String,
                        cost: cost,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        createdBy: d["createdBy"] as? String,
                        updatedBy: d["updatedBy"] as? String,
                        reminderEnabled: d["reminderEnabled"] as? Bool ?? false
                    )

                    switch diff.type {
                    case .added, .modified: return .upsert(dto)
                    case .removed: return .remove(doc.documentID)
                    }
                }

                if !changes.isEmpty { onChange(changes) }
            }
    }
}
