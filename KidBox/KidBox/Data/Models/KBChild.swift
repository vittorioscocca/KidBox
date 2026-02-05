//
//  KBChild.swift.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Represents a child within a family.
///
/// A child is the center of KidBox: most entities (routines, events, todos, schedules)
/// reference a specific `childId`.
///
/// - Important: KidBox is child-centric: data is about the child, not about the parents.
@Model
final class KBChild {
    @Attribute(.unique) var id: String
    
    var name: String
    var birthDate: Date?
    
    // audit (i tuoi campi già esistenti)
    var createdBy: String
    var createdAt: Date
    
    /// Inverse relationship back to the family.
    var family: KBFamily?
    
    init(id: String, name: String, birthDate: Date?, createdBy: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}
