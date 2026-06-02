//
//  KBLocationDefaults.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import Foundation

/// UserDefaults keys used to persist the active location sharing session.
///
/// Written by `FamilyLocationViewModel` when the user starts/stops sharing.
/// Read by `AppDelegate` when iOS relaunches the app in background
/// after a significant location change.
enum KBLocationDefaults {
    static let uid         = "kb_location_uid"
    static let familyId    = "kb_location_familyId"
    static let displayName = "kb_location_displayName"
    static let isSharing   = "kb_location_isSharing"
    static let expiresAt   = "kb_location_expiresAt"

    /// Sessione geofence: persistita INDIPENDENTEMENTE dalla condivisione live, così
    /// `GeofenceMonitorService` può attribuire (uid/familyId/displayName) gli eventi
    /// region ricevuti dopo un relaunch in background, anche con sharing spento.
    static let geofenceUid         = "kb_geofence_uid"
    static let geofenceFamilyId    = "kb_geofence_familyId"
    static let geofenceDisplayName = "kb_geofence_displayName"
}
