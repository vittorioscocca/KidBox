//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

@Model
final class KBUserProfile {
    
    @Attribute(.unique) var uid: String
    
    // Already existing
    var email: String?
    var displayName: String?
    var createdAt: Date
    var updatedAt: Date
    
    // NEW FIELDS (safe additions)
    var firstName: String?
    var lastName: String?
    var familyAddress: String?
    var avatarData: Data?
    var lastLoginAt: Date?
    
    init(
        uid: String,
        email: String? = nil,
        displayName: String? = nil
    ) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
