//
//  KBRoutine.swift.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// A recurring daily task associated with a child.
///
/// Examples: prepare milk, vitamins, daycare bag, wash bottles.
/// Routines are typically shown in the Home "Today" summary and can be checked off daily.
///
/// - Note: Completion is not stored on the routine itself; it is tracked via `KBRoutineCheck` events.
@Model
final class KBRoutine {
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    var title: String
    var isActive: Bool
    var sortOrder: Int
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        title: String,
        isActive: Bool = true,
        sortOrder: Int = 0,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.title = title
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
