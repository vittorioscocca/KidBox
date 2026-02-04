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
    var familyId: String
    var name: String
    var birthDate: Date?
    var photoLocalRef: String? // placeholder locale
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        name: String,
        birthDate: Date? = nil,
        photoLocalRef: String? = nil,
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.name = name
        self.birthDate = birthDate
        self.photoLocalRef = photoLocalRef
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
