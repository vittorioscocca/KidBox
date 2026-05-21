//
//  GeofenceRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import OSLog

// MARK: - DTO

struct GeofenceRemoteDTO {
    let id: String
    let familyId: String
    let name: String
    let emoji: String?
    let latitude: Double
    let longitude: Double
    let radius: Double
    let notifyOnArrive: Bool
    let notifyOnLeave: Bool
    let notifyMembers: [String]
    let monitoredMemberIds: [String]
    let isActive: Bool
    let createdBy: String?
    let createdAt: Date?
    let updatedAt: Date?
    let isDeleted: Bool

    /// Decodifica un documento Firestore in DTO.
    init?(id: String, familyId: String, data: [String: Any]) {
        guard let name = data["name"] as? String, !name.isEmpty else { return nil }

        let latitude = Self.doubleValue(data["latitude"]) ?? Self.doubleValue(data["lat"])
        let longitude = Self.longitudeValue(data) ?? Self.doubleValue(data["lon"])
        guard let latitude, let longitude else { return nil }

        let radius = Self.doubleValue(data["radius"]) ?? 200

        self.id = id
        self.familyId = familyId
        self.name = name
        self.emoji = data["emoji"] as? String
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.notifyOnArrive = data["notifyOnArrive"] as? Bool ?? true
        self.notifyOnLeave = data["notifyOnLeave"] as? Bool ?? false
        self.notifyMembers = Self.stringArray(data["notifyMembers"])
        self.monitoredMemberIds = Self.stringArray(data["monitoredMemberIds"])
        self.isActive = data["isActive"] as? Bool ?? true
        self.createdBy = data["createdBy"] as? String
        self.createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        self.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        self.isDeleted = data["isDeleted"] as? Bool ?? false
    }

    /// Payload Firestore per upsert.
    static func firestoreData(
        from geofence: KBGeofence,
        updatedBy uid: String,
        isNew: Bool
    ) -> [String: Any] {
        var data: [String: Any] = [
            "name": geofence.name,
            "latitude": geofence.latitude,
            "longitude": geofence.longitude,
            "radius": geofence.radius,
            "notifyOnArrive": geofence.notifyOnArrive,
            "notifyOnLeave": geofence.notifyOnLeave,
            "notifyMembers": geofence.notifyMembers,
            "monitoredMemberIds": geofence.monitoredMemberIds,
            "isActive": geofence.isActive,
            "isDeleted": false,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if isNew {
            data["createdAt"] = FieldValue.serverTimestamp()
            data["createdBy"] = geofence.createdBy.isEmpty ? uid : geofence.createdBy
        }

        if let emoji = geofence.emoji, !emoji.isEmpty {
            data["emoji"] = emoji
        } else {
            data["emoji"] = FieldValue.delete()
        }

        return data
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func longitudeValue(_ data: [String: Any]) -> Double? {
        doubleValue(data["longitude"]) ?? doubleValue(data["lng"])
    }

    private static func stringArray(_ any: Any?) -> [String] {
        if let a = any as? [String] { return a }
        return []
    }
}

// MARK: - Changes

enum GeofenceRemoteChange {
    case upsert(GeofenceRemoteDTO)
    case remove(String)
}

// MARK: - Remote store

/// Firestore CRUD per zone di arrivo sotto `families/{familyId}/geofences`.
final class GeofenceRemoteStore {

    private var db: Firestore { Firestore.firestore() }

    private func ref(familyId: String, geofenceId: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("geofences")
            .document(geofenceId)
    }

    private func col(familyId: String) -> CollectionReference {
        db.collection("families")
            .document(familyId)
            .collection("geofences")
    }

    // MARK: - Realtime listener

    func listen(
        familyId: String,
        onChange: @escaping ([GeofenceRemoteChange]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {

        KBLog.sync.kbInfo("[GeofenceRemote] listen ATTACH familyId=\(familyId)")

        return col(familyId: familyId)
            .whereField("isDeleted", isEqualTo: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err {
                    KBLog.sync.kbError("[GeofenceRemote] listener ERROR err=\(err.localizedDescription)")
                    onError(err)
                    return
                }
                guard let snap else {
                    KBLog.sync.kbDebug("[GeofenceRemote] listener snapshot nil")
                    return
                }

                KBLog.sync.kbDebug(
                    "[GeofenceRemote] snapshot docs=\(snap.documents.count) changes=\(snap.documentChanges.count) fromCache=\(snap.metadata.isFromCache)"
                )

                let changes: [GeofenceRemoteChange] = snap.documentChanges.compactMap { diff in
                    let doc = diff.document
                    let d = doc.data()

                    switch diff.type {
                    case .added, .modified:
                        guard let dto = GeofenceRemoteDTO(
                            id: doc.documentID,
                            familyId: familyId,
                            data: d
                        ) else {
                            KBLog.sync.kbDebug("[GeofenceRemote] decode FAIL docId=\(doc.documentID)")
                            return nil
                        }
                        return .upsert(dto)
                    case .removed:
                        return .remove(doc.documentID)
                    }
                }

                if !changes.isEmpty {
                    onChange(changes)
                }
            }
    }

    // MARK: - Upsert

    func upsert(_ geofence: KBGeofence) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[GeofenceRemote] upsert failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }

        let snap = try await ref(familyId: geofence.familyId, geofenceId: geofence.id).getDocument()
        let isNew = !snap.exists

        let data = GeofenceRemoteDTO.firestoreData(
            from: geofence,
            updatedBy: uid,
            isNew: isNew
        )

        try await ref(familyId: geofence.familyId, geofenceId: geofence.id).setData(data, merge: true)
        KBLog.sync.kbInfo("[GeofenceRemote] upsert OK id=\(geofence.id) familyId=\(geofence.familyId)")
    }

    // MARK: - Delete (soft)

    func delete(id: String, familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("[GeofenceRemote] delete failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }

        try await ref(familyId: familyId, geofenceId: id).setData([
            "isDeleted": true,
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid
        ], merge: true)

        KBLog.sync.kbInfo("[GeofenceRemote] delete OK id=\(id) familyId=\(familyId)")
    }
}
