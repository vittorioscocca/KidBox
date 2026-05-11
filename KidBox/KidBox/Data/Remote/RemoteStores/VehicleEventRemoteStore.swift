//
//  VehicleEventRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTOs

struct VehicleEventRemoteDTO {
    let id: String
    let familyId: String
    let vehicleId: String
    let title: String
    let eventTypeRaw: String
    let date: Date
    let km: Int?
    let cost: Double?
    let garageName: String?
    let notes: String?
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let updatedBy: String?
}

enum VehicleEventRemoteChange {
    case upsert(VehicleEventRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class VehicleEventRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, eventId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("vehicleEvents")
            .document(eventId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("vehicleEvents")
    }

    // MARK: - Upsert

    func upsert(item: KBVehicleEvent) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: item.familyId, eventId: item.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "vehicleId": item.vehicleId,
            "title": item.title,
            "eventTypeRaw": item.eventTypeRaw,
            "date": Timestamp(date: item.date),
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }

        data["km"] = item.km as Any
        data["cost"] = item.cost as Any
        data["garageName"] = item.garageName as Any
        data["notes"] = item.notes as Any

        if isNew { data["createdBy"] = item.createdBy.isEmpty ? uid : item.createdBy }

        try await ref(familyId: item.familyId, eventId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[VehicleEventRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
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

        KBLog.sync.kbInfo("[VehicleEventRemote] softDelete OK id=\(eventId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenVehicleEvents(
        familyId: String,
        onChange: @escaping ([VehicleEventRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[VehicleEventRemote] listenVehicleEvents ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[VehicleEventRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[VehicleEventRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [VehicleEventRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    guard let title = d["title"] as? String, !title.isEmpty else {
                        KBLog.sync.kbDebug("[VehicleEventRemote] decode FAIL docId=\(doc.documentID)")
                        return nil
                    }

                    let vehicleId = (d["vehicleId"] as? String) ?? ""
                    guard !vehicleId.isEmpty else {
                        KBLog.sync.kbDebug("[VehicleEventRemote] decode FAIL missing vehicleId docId=\(doc.documentID)")
                        return nil
                    }

                    let eventTypeRaw = (d["eventTypeRaw"] as? String) ?? "other"
                    let date = (d["date"] as? Timestamp)?.dateValue() ?? Date()

                    let km: Int? = {
                        if let i = d["km"] as? Int { return i }
                        if let n = d["km"] as? NSNumber { return n.intValue }
                        return nil
                    }()

                    let cost: Double? = {
                        if let x = d["cost"] as? Double { return x }
                        if let n = d["cost"] as? NSNumber { return n.doubleValue }
                        return nil
                    }()

                    let dto = VehicleEventRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        vehicleId: vehicleId,
                        title: title,
                        eventTypeRaw: eventTypeRaw,
                        date: date,
                        km: km,
                        cost: cost,
                        garageName: d["garageName"] as? String,
                        notes: d["notes"] as? String,
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
