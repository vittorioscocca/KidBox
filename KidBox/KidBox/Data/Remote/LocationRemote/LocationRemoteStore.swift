//
//  LocationRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import FirebaseFirestore
import FirebaseAuth
import CoreLocation
internal import os

final class LocationRemoteStore {
    
    private let db = Firestore.firestore()
    
    func startSharing(
        familyId: String,
        uid: String,
        name: String,
        mode: ShareMode,
        expiresAt: Date?
    ) async throws {
        
        var data: [String: Any] = [
            "isSharing": true,
            "mode": mode.rawValue,
            "name": name,
            "startedAt": FieldValue.serverTimestamp(),
            "lastUpdateAt": FieldValue.serverTimestamp()
        ]
        
        if let expiresAt {
            data["expiresAt"] = expiresAt
        }
        
        try await db.collection("families")
            .document(familyId)
            .collection("locations")
            .document(uid)
            .setData(data, merge: true)
    }
    
    func updateLocation(
        familyId: String,
        uid: String,
        location: CLLocation,
        displayName: String
    ) async {
        do {
            try await db.collection("families")
                .document(familyId)
                .collection("locations")
                .document(uid)
                .setData([
                    "lat": location.coordinate.latitude,
                    "lon": location.coordinate.longitude,
                    "accuracy": location.horizontalAccuracy,
                    "name": displayName, // ✅ sempre aggiornato
                    "lastUpdateAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            KBLog.app.error("LocationRemoteStore updateLocation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func stopSharing(familyId: String, uid: String) async {
        try? await db.collection("families")
            .document(familyId)
            .collection("locations")
            .document(uid)
            .setData([
                "isSharing": false
            ], merge: true)
    }
    
    func updateDisplayName(familyId: String, uid: String, displayName: String) async {
        do {
            try await db.collection("families")
                .document(familyId)
                .collection("locations")
                .document(uid)
                .setData([
                    "name": displayName,
                    "lastUpdateAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            KBLog.app.error("LocationRemoteStore updateDisplayName failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func listen(
        familyId: String,
        onChange: @escaping ([SharedUserLocation]) -> Void
    ) -> ListenerRegistration {
        
        db.collection("families")
            .document(familyId)
            .collection("locations")
            .addSnapshotListener { snap, _ in
                
                guard let snap else { return }
                
                let users: [SharedUserLocation] = snap.documents.compactMap { doc in
                    
                    guard
                        doc.data()["isSharing"] as? Bool == true,
                        let lat = doc.data()["lat"] as? Double,
                        let lon = doc.data()["lon"] as? Double,
                        let name = doc.data()["name"] as? String,
                        let modeRaw = doc.data()["mode"] as? String,
                        let mode = ShareMode(rawValue: modeRaw)
                    else { return nil }
                    
                    let expires = (doc.data()["expiresAt"] as? Timestamp)?.dateValue()
                    
                    // scarta temporanei scaduti
                    if mode == .temporary,
                       let expires,
                       expires < Date() {
                        return nil
                    }
                    
                    return SharedUserLocation(
                        id: doc.documentID,
                        name: name,
                        latitude: lat,
                        longitude: lon,
                        mode: mode,
                        expiresAt: expires
                    )
                }
                
                onChange(users)
            }
    }
}
