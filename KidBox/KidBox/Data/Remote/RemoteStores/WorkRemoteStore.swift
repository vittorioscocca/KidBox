//
//  WorkRemoteStore.swift
//  KidBox
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTO

struct WorkProfileDTO {
    let id: String
    let familyId: String
    let employerEnc: String?
    let visibilityScope: String?
    let visibilityMemberIds: [String]
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let createdByName: String?
    let updatedBy: String?
    let updatedByName: String?
}

struct WorkRecordDTO {
    let id: String
    let familyId: String
    let ownerUid: String
    let kind: String
    let referenceDate: Date?
    let fieldsEnc: String?
    let attachmentDocumentId: String?
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let createdByName: String?
    let updatedBy: String?
    let updatedByName: String?
}

enum WorkProfileRemoteChange {
    case upsert(WorkProfileDTO)
    case remove(String)
}

enum WorkRecordRemoteChange {
    case upsert(WorkRecordDTO)
    case remove(String)
}

// MARK: - Store

/// Path Firestore: `families/{familyId}/workProfiles/{ownerUid}` e
/// `families/{familyId}/workRecords/{recordId}`.
///
/// Le rules hanno una regola dedicata (`/rules-change`): il proprietario scrive,
/// un altro adulto legge solo se è in `visibilityMemberIds`. Una LIST non filtra,
/// quindi le query sono SEMPRE vincolate: le schede condivise con me con
/// `array-contains` sul mio uid, i documenti con `ownerUid ==`.
final class WorkRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func profiles(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("workProfiles")
    }

    private func records(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("workRecords")
    }

    private func requireUid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        return uid
    }

    // MARK: Upsert

    func upsert(profile: KBWorkProfile) async throws {
        let uid = try requireUid()
        let ref = profiles(familyId: profile.familyId).document(profile.id)
        let isNew = !(try await ref.getDocument()).exists
        let scope = KBWorkProfile.normalizedScope(profile.visibilityScope)

        var data: [String: Any] = [
            "schemaVersion": 1,
            "ownerUid": profile.id,
            "employerEnc": profile.employerEnc as Any,
            "visibilityScope": scope,
            // Autorevole per le rules: tornando privata la lista si svuota.
            "visibilityMemberIds": scope == KBVisibilityScope.members ? profile.visibilityMemberIds : [],
            "isDeleted": false,
            "updatedBy": uid,
            "updatedByName": profile.updatedByName,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
            data["createdBy"] = uid
            data["createdByName"] = profile.createdByName
        }
        try await ref.setData(data, merge: true)
        KBLog.sync.kbInfo("[WorkRemote] profile upsert OK id=\(profile.id)")
    }

    func upsert(record: KBWorkRecord) async throws {
        let uid = try requireUid()
        let ref = records(familyId: record.familyId).document(record.id)
        let isNew = !(try await ref.getDocument()).exists

        var data: [String: Any] = [
            "schemaVersion": 1,
            "ownerUid": record.ownerUid,
            "kind": record.kind,
            "referenceDate": Timestamp(date: record.referenceDate),
            "fieldsEnc": record.fieldsEnc as Any,
            "attachmentDocumentId": record.attachmentDocumentId as Any,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedByName": record.updatedByName,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
            data["createdBy"] = uid
            data["createdByName"] = record.createdByName
        }
        try await ref.setData(data, merge: true)
        KBLog.sync.kbInfo("[WorkRemote] record upsert OK id=\(record.id)")
    }

    /// Il tombstone svuota i campi cifrati: un documento cancellato non deve
    /// portarsi dietro i valori, nemmeno cifrati.
    func softDelete(recordId: String, familyId: String) async throws {
        let uid = try requireUid()
        try await records(familyId: familyId).document(recordId).setData([
            "isDeleted": true,
            "fieldsEnc": FieldValue.delete(),
            "attachmentDocumentId": FieldValue.delete(),
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        KBLog.sync.kbInfo("[WorkRemote] record softDelete OK id=\(recordId)")
    }

    // MARK: Listeners

    /// La propria scheda (documento singolo: id = uid).
    func listenOwnProfile(
        familyId: String,
        uid: String,
        onChange: @escaping ([WorkProfileRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        profiles(familyId: familyId).document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err { onError(err); return }
                guard let snap, snap.exists else { return }
                onChange([.upsert(Self.profileDTO(snap, familyId: familyId))])
            }
    }

    /// Le schede che altri adulti hanno condiviso con me.
    func listenSharedProfiles(
        familyId: String,
        uid: String,
        onChange: @escaping ([WorkProfileRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        profiles(familyId: familyId)
            .whereField("visibilityMemberIds", arrayContains: uid)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [WorkProfileRemoteChange] = snap.documentChanges.map { diff in
                    switch diff.type {
                    case .added, .modified: return .upsert(Self.profileDTO(diff.document, familyId: familyId))
                    case .removed:          return .remove(diff.document.documentID)
                    }
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }

    /// I documenti di un proprietario di cui posso leggere la scheda.
    func listenRecords(
        familyId: String,
        ownerUid: String,
        onChange: @escaping ([WorkRecordRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        records(familyId: familyId)
            .whereField("ownerUid", isEqualTo: ownerUid)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err { onError(err); return }
                guard let snap else { return }
                let changes: [WorkRecordRemoteChange] = snap.documentChanges.map { diff in
                    switch diff.type {
                    case .added, .modified: return .upsert(Self.recordDTO(diff.document, familyId: familyId))
                    case .removed:          return .remove(diff.document.documentID)
                    }
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }

    // MARK: Mapping

    private static func profileDTO(_ doc: DocumentSnapshot, familyId: String) -> WorkProfileDTO {
        let d = doc.data() ?? [:]
        func str(_ k: String) -> String? { (d[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return WorkProfileDTO(
            id: doc.documentID,
            familyId: familyId,
            employerEnc: str("employerEnc"),
            visibilityScope: str("visibilityScope"),
            visibilityMemberIds: (d["visibilityMemberIds"] as? [Any])?.compactMap { $0 as? String } ?? [],
            isDeleted: d["isDeleted"] as? Bool ?? false,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
            createdBy: str("createdBy"), createdByName: str("createdByName"),
            updatedBy: str("updatedBy"), updatedByName: str("updatedByName")
        )
    }

    private static func recordDTO(_ doc: DocumentSnapshot, familyId: String) -> WorkRecordDTO {
        let d = doc.data() ?? [:]
        func str(_ k: String) -> String? { (d[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        return WorkRecordDTO(
            id: doc.documentID,
            familyId: familyId,
            ownerUid: str("ownerUid") ?? "",
            kind: str("kind") ?? WorkRecordKind.payslip,
            referenceDate: (d["referenceDate"] as? Timestamp)?.dateValue(),
            fieldsEnc: str("fieldsEnc"),
            attachmentDocumentId: str("attachmentDocumentId"),
            isDeleted: d["isDeleted"] as? Bool ?? false,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
            createdBy: str("createdBy"), createdByName: str("createdByName"),
            updatedBy: str("updatedBy"), updatedByName: str("updatedByName")
        )
    }
}
