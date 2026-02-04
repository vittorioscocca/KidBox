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
    
    var createdAt: Date
    var updatedAt: Date
    var createdBy: String
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        name: String,
        createdBy: String,
        updatedBy: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdBy = createdBy
        self.updatedBy = updatedBy ?? createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
