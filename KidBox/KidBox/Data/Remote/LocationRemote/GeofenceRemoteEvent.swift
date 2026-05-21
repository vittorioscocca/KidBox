//
//  GeofenceRemoteEvent.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import Foundation
import FirebaseFirestore
import OSLog

/// Tipo transizione geofence scritta su Firestore.
enum GeofenceTransitionType: String {
    case arrive
    case leave
}

/// Scrive eventi di ingresso/uscita zona su `families/{familyId}/geofenceEvents`.
final class GeofenceRemoteEvent {

    private var db: Firestore { Firestore.firestore() }

    /// Registra un evento arrive/leave triggerato da `CLLocationManager`.
    func writeEvent(
        familyId: String,
        geofenceId: String,
        uid: String,
        displayName: String,
        type: GeofenceTransitionType
    ) async {
        let eventId = UUID().uuidString

        let data: [String: Any] = [
            "geofenceId": geofenceId,
            "uid": uid,
            "displayName": displayName,
            "type": type.rawValue,
            "timestamp": FieldValue.serverTimestamp()
        ]

        do {
            try await db.collection("families")
                .document(familyId)
                .collection("geofenceEvents")
                .document(eventId)
                .setData(data)

            KBLog.sync.kbInfo(
                "[GeofenceRemoteEvent] write OK eventId=\(eventId) familyId=\(familyId) geofenceId=\(geofenceId) type=\(type.rawValue)"
            )
        } catch {
            KBLog.sync.kbError(
                "[GeofenceRemoteEvent] write failed familyId=\(familyId) geofenceId=\(geofenceId): \(error.localizedDescription)"
            )
        }
    }
}
