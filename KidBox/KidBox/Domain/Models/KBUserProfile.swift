//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Local user profile for the authenticated user.
/// It is updated from Firebase Auth claims (Apple) and used by the app session.
@Model
final class KBUserProfile {
    @Attribute(.unique) var uid: String
    var email: String?
    var displayName: String?
    var createdAt: Date
    var updatedAt: Date
    
    init(uid: String, email: String?, displayName: String?) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
