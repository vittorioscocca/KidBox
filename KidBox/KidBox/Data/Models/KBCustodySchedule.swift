//
//  KBCustodySchedule.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// A base weekly template describing who has the child on each day.
///
/// This model supports:
/// - a clear "who has the child today/this week" view
/// - simple planning for co-parenting scenarios
///
/// - Note: Change requests / overrides (swap days, proposals) are planned for a later version.
@Model
final class KBCustodySchedule {
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    var pattern: String // "weekly"
    var weekTemplateJSON: String // mapping dayOfWeek -> userId
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        pattern: String = "weekly",
        weekTemplateJSON: String,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.pattern = pattern
        self.weekTemplateJSON = weekTemplateJSON
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

extension KBCustodySchedule: HasFamilyId {}
