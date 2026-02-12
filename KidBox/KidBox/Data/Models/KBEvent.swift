//
//  KBEvent.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// A dated commitment in the child's life.
///
/// Examples: daycare, pediatric visit, courses, birthdays.
/// Events power the Home "Calendar" card and the dedicated Calendar view.
///
/// `type` is a lightweight classification (string) in the MVP.
@Model
final class KBEvent {
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    var type: String   // "nido" | "visita" | "corso" | "compleanno" | "altro"
    var title: String
    var startAt: Date
    var endAt: Date?
    var notes: String?
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        type: String,
        title: String,
        startAt: Date,
        endAt: Date? = nil,
        notes: String? = nil,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.type = type
        self.title = title
        self.startAt = startAt
        self.endAt = endAt
        self.notes = notes
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}

extension KBEvent: HasFamilyId {}
