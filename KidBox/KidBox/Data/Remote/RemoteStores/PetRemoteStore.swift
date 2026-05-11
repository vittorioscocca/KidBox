//
//  PetRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTOs

struct PetRemoteDTO {
    let id: String
    let familyId: String
    let name: String
    let species: String
    let breed: String?
    let birthDate: Date?
    let color: String?
    let chipCode: String?
    let notes: String?
    let photoURL: String?
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let updatedBy: String?
}

enum PetRemoteChange {
    case upsert(PetRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class PetRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, petId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("pets")
            .document(petId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("pets")
    }

    // MARK: - Upsert

    func upsert(item: KBPet) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: item.familyId, petId: item.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "name": item.name,
            "species": item.species,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }

        data["breed"] = item.breed as Any
        data["birthDate"] = item.birthDate.map { Timestamp(date: $0) } as Any
        data["color"] = item.color as Any
        data["chipCode"] = item.chipCode as Any
        data["notes"] = item.notes as Any
        data["photoURL"] = item.photoURL as Any

        if isNew { data["createdBy"] = item.createdBy.isEmpty ? uid : item.createdBy }

        try await ref(familyId: item.familyId, petId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[PetRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
    }

    // MARK: - Soft delete

    func softDelete(petId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, petId: petId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[PetRemote] softDelete OK id=\(petId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenPets(
        familyId: String,
        onChange: @escaping ([PetRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[PetRemote] listenPets ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[PetRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[PetRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [PetRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    guard let name = d["name"] as? String, !name.isEmpty else {
                        KBLog.sync.kbDebug("[PetRemote] decode FAIL docId=\(doc.documentID)")
                        return nil
                    }

                    let species = (d["species"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !species.isEmpty else {
                        KBLog.sync.kbDebug("[PetRemote] decode FAIL missing species docId=\(doc.documentID)")
                        return nil
                    }

                    let dto = PetRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        name: name,
                        species: species,
                        breed: d["breed"] as? String,
                        birthDate: (d["birthDate"] as? Timestamp)?.dateValue(),
                        color: d["color"] as? String,
                        chipCode: d["chipCode"] as? String,
                        notes: d["notes"] as? String,
                        photoURL: d["photoURL"] as? String,
                        isDeleted: d["isDeleted"] as? Bool ?? false,
                        createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
                        updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
                        createdBy: d["createdBy"] as? String,
                        updatedBy: d["updatedBy"] as? String
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
