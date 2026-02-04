//
//  KBRoutineCheck.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// An append-only event that marks a routine as completed for a given day.
///
/// We model completion as events (instead of a boolean on the routine) to:
/// - avoid sync conflicts between two parents
/// - support offline-first usage
///
/// `dayKey` is a normalized "YYYY-MM-DD" key in the user's current calendar/timezone.
@Model
final class KBRoutineCheck {
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    var routineId: String
    
    /// "YYYY-MM-DD" computed at creation time (local calendar)
    var dayKey: String
    var checkedAt: Date
    var checkedBy: String
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        routineId: String,
        dayKey: String,
        checkedAt: Date = Date(),
        checkedBy: String,
        updatedBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.routineId = routineId
        self.dayKey = dayKey
        self.checkedAt = checkedAt
        self.checkedBy = checkedBy
        self.updatedBy = updatedBy ?? checkedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
