//
//  VehicleRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 11/05/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - DTOs

struct VehicleRemoteDTO {
    let id: String
    let familyId: String
    let name: String
    let licensePlate: String?
    let brand: String?
    let model: String?
    let year: Int?
    let fuelTypeRaw: String?
    let color: String?
    let vin: String?
    let insuranceExpiryDate: Date?
    let revisionExpiryDate: Date?
    let taxExpiryDate: Date?
    let lastServiceDate: Date?
    let nextServiceDate: Date?
    let currentKm: Int?
    let notes: String?
    let photoURL: String?
    let isDeleted: Bool
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: String?
    let updatedBy: String?
    let reminderEnabled: Bool
}

enum VehicleRemoteChange {
    case upsert(VehicleRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

final class VehicleRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, vehicleId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("vehicles")
            .document(vehicleId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("vehicles")
    }

    // MARK: - Upsert

    func upsert(item: KBVehicle) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        let snap = try await ref(familyId: item.familyId, vehicleId: item.id).getDocument()
        let isNew = !snap.exists

        var data: [String: Any] = [
            "name": item.name,
            "isDeleted": false,
            "reminderEnabled": item.reminderEnabled,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew { data["createdAt"] = FieldValue.serverTimestamp() }

        data["licensePlate"] = item.licensePlate as Any
        data["brand"] = item.brand as Any
        data["model"] = item.model as Any
        data["year"] = item.year as Any
        data["fuelTypeRaw"] = item.fuelTypeRaw as Any
        data["color"] = item.color as Any
        data["vin"] = item.vin as Any
        data["insuranceExpiryDate"] = item.insuranceExpiryDate.map { Timestamp(date: $0) } as Any
        data["revisionExpiryDate"] = item.revisionExpiryDate.map { Timestamp(date: $0) } as Any
        data["taxExpiryDate"] = item.taxExpiryDate.map { Timestamp(date: $0) } as Any
        data["lastServiceDate"] = item.lastServiceDate.map { Timestamp(date: $0) } as Any
        data["nextServiceDate"] = item.nextServiceDate.map { Timestamp(date: $0) } as Any
        data["currentKm"] = item.currentKm as Any
        data["notes"] = item.notes as Any
        data["photoURL"] = item.photoURL as Any

        if isNew { data["createdBy"] = item.createdBy.isEmpty ? uid : item.createdBy }

        try await ref(familyId: item.familyId, vehicleId: item.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[VehicleRemote] upsert OK id=\(item.id) familyId=\(item.familyId)")
    }

    // MARK: - Soft delete

    func softDelete(vehicleId: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        try await ref(familyId: familyId, vehicleId: vehicleId).setData([
            "isDeleted": true,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        KBLog.sync.kbInfo("[VehicleRemote] softDelete OK id=\(vehicleId) familyId=\(familyId)")
    }

    // MARK: - Realtime listener

    func listenVehicles(
        familyId: String,
        onChange: @escaping ([VehicleRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[VehicleRemote] listenVehicles ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[VehicleRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else { return }

                KBLog.sync.kbDebug("[VehicleRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)")

                let changes: [VehicleRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    guard let name = d["name"] as? String, !name.isEmpty else {
                        KBLog.sync.kbDebug("[VehicleRemote] decode FAIL docId=\(doc.documentID)")
                        return nil
                    }

                    let year: Int? = {
                        if let i = d["year"] as? Int { return i }
                        if let n = d["year"] as? NSNumber { return n.intValue }
                        return nil
                    }()

                    let currentKm: Int? = {
                        if let i = d["currentKm"] as? Int { return i }
                        if let n = d["currentKm"] as? NSNumber { return n.intValue }
                        return nil
                    }()

                    let dto = VehicleRemoteDTO(
                        id: doc.documentID,
                        familyId: familyId,
                        name: name,
                        licensePlate: d["licensePlate"] as? String,
                        brand: d["brand"] as? String,
                        model: d["model"] as? String,
                        year: year,
                        fuelTypeRaw: d["fuelTypeRaw"] as? String,
                        color: d["color"] as? String,
                        vin: d["vin"] as? String,
                        insuranceExpiryDate: (d["insuranceExpiryDate"] as? Timestamp)?.dateValue(),
                        revisionExpiryDate: (d["revisionExpiryDate"] as? Timestamp)?.dateValue(),
                        taxExpiryDate: (d["taxExpiryDate"] as? Timestamp)?.dateValue(),
                        lastServiceDate: (d["lastServiceDate"] as? Timestamp)?.dateValue(),
                        nextServiceDate: (d["nextServiceDate"] as? Timestamp)?.dateValue(),
                        currentKm: currentKm,
                        notes: d["notes"] as? String,
                        photoURL: d["photoURL"] as? String,
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
