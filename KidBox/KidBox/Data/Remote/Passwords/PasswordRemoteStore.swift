//
//  PasswordRemoteStore.swift
//  KidBox
//
//  Firestore: `families/{familyId}/passwords/{id}` e `families/{familyId}/passwordGroups/{id}`.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import OSLog

// MARK: - DTO

struct PasswordEntryDTO {
    let id: String
    let familyId: String
    let createdBy: String
    let visibility: String
    let visibilityMemberIds: [String]
    let groupId: String?
    let titleCipherB64: String?
    let usernameCipherB64: String?
    let passwordCipherB64: String?
    let websiteCipherB64: String?
    let notesCipherB64: String?
    let otpConfigCipherB64: String?
    let iconURL: String?
    let lastUsedAt: Date?
    let passwordUpdatedAt: Date?
    let expiresAt: Date?
    let pwnedCount: Int?
    let pwnedCheckedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
    let isFavorite: Bool
}

struct PasswordGroupDTO {
    let id: String
    let familyId: String
    let nameCipherB64: String?
    let icon: String?
    let color: String?
    let visibility: String
    let visibilityMemberIds: [String]
    let createdBy: String
    let isSystem: Bool
    let sortIndex: Int
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
}

enum PasswordRemoteChange {
    case upsertEntry(PasswordEntryDTO)
    case removeEntry(String)
    case upsertGroup(PasswordGroupDTO)
    case removeGroup(String)
}

// MARK: - Store

final class PasswordRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func passwordsCol(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("passwords")
    }

    private func groupsCol(familyId: String) -> CollectionReference {
        db.collection("families").document(familyId).collection("passwordGroups")
    }

    private func b64(_ data: Data) -> String { data.base64EncodedString() }

    private func dataFromB64(_ s: String?) -> Data? {
        guard let s, !s.isEmpty, let d = Data(base64Encoded: s) else { return nil }
        return d
    }

    // MARK: - Upsert

    func upsert(entry: PasswordEntry) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let ref = passwordsCol(familyId: entry.familyId).document(entry.id)
        let snap = try await ref.getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "schemaVersion": 1,
            "familyId": entry.familyId,
            "createdBy": entry.createdBy,
            "visibility": PasswordEntry.normalizedPasswordVisibility(entry.visibility),
            "visibilityMemberIds": entry.visibilityMemberIds,
            "titleCipherB64": b64(entry.titleCipher),
            "passwordCipherB64": b64(entry.passwordCipher),
            "passwordUpdatedAt": Timestamp(date: entry.passwordUpdatedAt),
            "createdAt": Timestamp(date: entry.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid,
        ]
        if let gid = entry.groupId, !gid.isEmpty { data["groupId"] = gid }
        if let u = entry.usernameCipher { data["usernameCipherB64"] = b64(u) }
        if let w = entry.websiteCipher { data["websiteCipherB64"] = b64(w) }
        if let n = entry.notesCipher { data["notesCipherB64"] = b64(n) }
        if let o = entry.otpConfigCipher { data["otpConfigCipherB64"] = b64(o) }
        if let icon = entry.iconURL, !icon.isEmpty { data["iconURL"] = icon }
        if let lu = entry.lastUsedAt { data["lastUsedAt"] = Timestamp(date: lu) }
        if let ex = entry.expiresAt { data["expiresAt"] = Timestamp(date: ex) }
        if let pwned = entry.pwnedCount { data["pwnedCount"] = pwned }
        if let checked = entry.pwnedCheckedAt { data["pwnedCheckedAt"] = Timestamp(date: checked) }
        if let del = entry.deletedAt { data["deletedAt"] = Timestamp(date: del) }
        data["isFavorite"] = entry.isFavorite

        if isNew {
            data["createdBy"] = entry.createdBy.isEmpty ? uid : entry.createdBy
        }

        try await ref.setData(data, merge: true)
        KBLog.sync.kbDebug("[PasswordRemote] upsert entry id=\(entry.id)")
    }

    func upsert(group: PasswordGroup) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        let ref = groupsCol(familyId: group.familyId).document(group.id)
        let snap = try await ref.getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "schemaVersion": 1,
            "familyId": group.familyId,
            "createdBy": group.createdBy,
            "visibility": PasswordEntry.normalizedPasswordVisibility(group.visibility),
            "visibilityMemberIds": group.visibilityMemberIds,
            "nameCipherB64": b64(group.nameCipher),
            "icon": group.icon,
            "color": group.color,
            "isSystem": group.isSystem,
            "sortIndex": group.sortIndex,
            "createdAt": Timestamp(date: group.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid,
        ]
        if let del = group.deletedAt { data["deletedAt"] = Timestamp(date: del) }

        if isNew {
            data["createdBy"] = group.createdBy.isEmpty ? uid : group.createdBy
        }

        try await ref.setData(data, merge: true)
        KBLog.sync.kbDebug("[PasswordRemote] upsert group id=\(group.id)")
    }

    func softDeleteEntry(entryId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        try await passwordsCol(familyId: familyId).document(entryId).setData([
            "deletedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid,
        ], merge: true)
    }

    func softDeleteGroup(groupId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        try await groupsCol(familyId: familyId).document(groupId).setData([
            "deletedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid,
        ], merge: true)
    }

    // MARK: - Parsing

    private func parseEntryDoc(_ doc: DocumentSnapshot, familyId: String) -> PasswordEntryDTO? {
        guard let d = doc.data() else { return nil }
        return PasswordEntryDTO(
            id: doc.documentID,
            familyId: familyId,
            createdBy: d["createdBy"] as? String ?? "",
            visibility: d["visibility"] as? String ?? KBVisibilityScope.family,
            visibilityMemberIds: d["visibilityMemberIds"] as? [String] ?? [],
            groupId: d["groupId"] as? String,
            titleCipherB64: d["titleCipherB64"] as? String,
            usernameCipherB64: d["usernameCipherB64"] as? String,
            passwordCipherB64: d["passwordCipherB64"] as? String,
            websiteCipherB64: d["websiteCipherB64"] as? String,
            notesCipherB64: d["notesCipherB64"] as? String,
            otpConfigCipherB64: d["otpConfigCipherB64"] as? String,
            iconURL: d["iconURL"] as? String,
            lastUsedAt: (d["lastUsedAt"] as? Timestamp)?.dateValue(),
            passwordUpdatedAt: (d["passwordUpdatedAt"] as? Timestamp)?.dateValue(),
            expiresAt: (d["expiresAt"] as? Timestamp)?.dateValue(),
            pwnedCount: d["pwnedCount"] as? Int,
            pwnedCheckedAt: (d["pwnedCheckedAt"] as? Timestamp)?.dateValue(),
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
            deletedAt: (d["deletedAt"] as? Timestamp)?.dateValue(),
            isFavorite: d["isFavorite"] as? Bool ?? false
        )
    }

    private func parseGroupDoc(_ doc: DocumentSnapshot, familyId: String) -> PasswordGroupDTO? {
        guard let d = doc.data() else { return nil }
        return PasswordGroupDTO(
            id: doc.documentID,
            familyId: familyId,
            nameCipherB64: d["nameCipherB64"] as? String,
            icon: d["icon"] as? String,
            color: d["color"] as? String,
            visibility: d["visibility"] as? String ?? KBVisibilityScope.family,
            visibilityMemberIds: d["visibilityMemberIds"] as? [String] ?? [],
            createdBy: d["createdBy"] as? String ?? "",
            isSystem: d["isSystem"] as? Bool ?? false,
            sortIndex: d["sortIndex"] as? Int ?? 0,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue(),
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue(),
            deletedAt: (d["deletedAt"] as? Timestamp)?.dateValue()
        )
    }

    // MARK: - Listeners

    func listenPasswordEntries(
        familyId: String,
        onChange: @escaping ([PasswordRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        passwordsCol(familyId: familyId)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    onError(err)
                    return
                }
                guard let snap else { return }
                let changes: [PasswordRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    switch diff.type {
                    case .added, .modified:
                        guard let dto = self.parseEntryDoc(doc, familyId: familyId) else { return nil }
                        return .upsertEntry(dto)
                    case .removed:
                        return .removeEntry(doc.documentID)
                    }
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }

    func listenPasswordGroups(
        familyId: String,
        onChange: @escaping ([PasswordRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        groupsCol(familyId: familyId)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    onError(err)
                    return
                }
                guard let snap else { return }
                let changes: [PasswordRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    switch diff.type {
                    case .added, .modified:
                        guard let dto = self.parseGroupDoc(doc, familyId: familyId) else { return nil }
                        return .upsertGroup(dto)
                    case .removed:
                        return .removeGroup(doc.documentID)
                    }
                }
                if !changes.isEmpty { onChange(changes) }
            }
    }
}
