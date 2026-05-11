//
//  HomeItemRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTOs

struct HomeItemRemoteDTO {
    let id: String
    let familyId: String
    let name: String
    let categoryRaw: String
    let brand: String?
    let model: String?
    let serialNumber: String?
    let purchaseDate: Date?
    let warrantyExpiryDate: Date?
    let nextServiceDate: Date?
    let servicePeriodMonths: Int?
    let notes: String?
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let updatedBy: String?
    let reminderEnabled: Bool
}

enum HomeItemRemoteChange {
    case upsert(HomeItemRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class HomeItemRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, itemId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("homeItems")
            .document(itemId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("homeItems")
    }

    // MARK: - Upsert

    func upsert(item: KBHomeItem) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: item.familyId, itemId: item.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "name": item.name,
            "categoryRaw": item.categoryRaw,
            "isDeleted": false,
            "reminderEnabled": item.reminderEnabled,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }

        data["brand"] = item.brand as Any
        data["model"] = item.model as Any
        data["serialNumber"] = item.serialNumber as Any
        data["purchaseDate"] = item.purchaseDate.map { Timestamp(date: $0) } as Any
        data["warrantyExpiryDate"] = item.warrantyExpiryDate.map { Timestamp(date: $0) } as Any
        data["nextServiceDate"] = item.nextServiceDate.map { Timestamp(date: $0) } as Any
        data["servicePeriodMonths"] = item.servicePeriodMonths as Any
        data["notes"] = item.notes as Any

        if isNew { data["createdBy"] = item.createdBy.isEmpty ? uid : item.createdBy }

        try await ref(familyId: item.familyId, itemId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[HomeItemRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
    }

    // MARK: - Soft delete

    func softDelete(itemId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, itemId: itemId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[HomeItemRemote] softDelete OK id=\(itemId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenHomeItems(
        familyId: String,
        onChange: @escaping ([HomeItemRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[HomeItemRemote] listenHomeItems ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[HomeItemRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[HomeItemRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [HomeItemRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    guard let name = d["name"] as? String, !name.isEmpty else {
                        KBLog.sync.kbDebug("[HomeItemRemote] decode FAIL docId=\(doc.documentID)")
                        return nil
                    }

                    let categoryRaw = (d["categoryRaw"] as? String) ?? "other"

                    let servicePeriodMonths: Int? = {
                        if let i = d["servicePeriodMonths"] as? Int { return i }
                        if let n = d["servicePeriodMonths"] as? NSNumber { return n.intValue }
                        return nil
                    }()

                    let dto = HomeItemRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        name: name,
                        categoryRaw: categoryRaw,
                        brand: d["brand"] as? String,
                        model: d["model"] as? String,
                        serialNumber: d["serialNumber"] as? String,
                        purchaseDate: (d["purchaseDate"] as? Timestamp)?.dateValue(),
                        warrantyExpiryDate: (d["warrantyExpiryDate"] as? Timestamp)?.dateValue(),
                        nextServiceDate: (d["nextServiceDate"] as? Timestamp)?.dateValue(),
                        servicePeriodMonths: servicePeriodMonths,
                        notes: d["notes"] as? String,
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
