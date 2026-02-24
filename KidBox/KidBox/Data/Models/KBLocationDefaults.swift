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
}
