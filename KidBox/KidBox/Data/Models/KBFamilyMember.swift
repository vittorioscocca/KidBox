//
//  KBFamilyMember.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Links a user to a family with a role.
///
/// A family can have multiple members (e.g. two parents). Membership is used for:
/// - authorization (who can read/write family data)
/// - future features (invites, permissions)
///
/// `role` is intentionally simple in MVP ("admin" | "member") and can be expanded later.
@Model
final class KBFamilyMember {
    @Attribute(.unique) var id: String
    var familyId: String
    var userId: String
    var role: String // "admin" | "member"
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        userId: String,
        role: String = "member",
        updatedBy: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.userId = userId
        self.role = role
        self.updatedBy = updatedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
