//
//  KBFamily.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Represents a family workspace in KidBox.
///
/// A `KBFamily` groups parents (members) and one or more children.
/// All shared data (routines, events, todos, schedules) is scoped to a `familyId`.
///
/// - Note: In the MVP we keep relationships as string identifiers (`familyId`, `childId`)
///   to simplify sync with the backend (e.g. Firestore).
@Model
final class KBFamily {
    @Attribute(.unique) var id: String
    var name: String
    
    var createdBy: String
    var updatedBy: String
    var createdAt: Date
    var updatedAt: Date
    
    // ✅ M3
    var lastSyncAt: Date?            // ultimo momento in cui abbiamo processato sync per questa family
    var lastSyncError: String?       // utile per debug/supporto
    
    @Relationship(deleteRule: .cascade, inverse: \KBChild.family)
    var children: [KBChild] = []
    
    init(id: String, name: String, createdBy: String, updatedBy: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
