//
//  Route.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

/// Represents a navigation destination in KidBox.
///
/// Routes are resolved by `AppCoordinator` and used by the root `NavigationStack`.
/// This enum defines all high-level screens reachable in the app.
///
/// - Note: Routes are intentionally coarse-grained; feature-specific sub-flows
///   can be handled by dedicated coordinators later.
import Foundation

enum Route: Hashable {
    case home
    case today
    case calendar
    case todo
    case settings
    
    case profile
    case familySettings
    case inviteCode
    case joinFamily
    
    case setupFamily               // create
    case editFamily(familyId: String, childId: String) // edit
}
