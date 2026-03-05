//
//  Route.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Represents a navigation destination in KidBox.
///
/// Routes are resolved by `AppCoordinator` and used by the root `NavigationStack`.
/// This enum defines all high-level screens reachable in the app.
///
/// - Note: Routes are intentionally coarse-grained; feature-specific sub-flows
///   can be handled by dedicated coordinators later.

enum TodoSmartKind: String, Codable, Hashable {
    case today
    case all
    case assignedToMe
    case completed
    case notAssignedToMe
    case notCompleted
}

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
    case chat
    case shoppingList(familyId: String)
    case familyLocation(familyId: String)
    case todoList(familyId: String, childId: String, listId: String)
    case document
    case documentsHome
    case documentsCategory(familyId: String, categoryId: String, title: String)
    case todoSmart(familyId: String, childId: String, kind: TodoSmartKind)
    case editChild(familyId: String, childId: String)
    
    case setupFamily               // create
    case editFamily(familyId: String, childId: String) // edit
    
    /// MARK: - Pediatria
    case pediatricChildSelector(familyId: String)
    case pediatricHome(familyId: String, childId: String)
    case pediatricMedicalRecord(familyId: String, childId: String)
    case pediatricVisits(familyId: String, childId: String)
    case pediatricVisitDetail(familyId: String, childId: String, visitId: String)
    case pediatricVaccines(familyId: String, childId: String)
    case pediatricTreatments(familyId: String, childId: String)
    case pediatricTreatmentDetail(familyId: String, childId: String, treatmentId: String)
    
    // MARK: - Note
    case notesHome(familyId: String)
    case noteDetail(familyId: String, noteId: String)
}
