//
//  Session.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation

/// Represents the authentication/session state of the current user.
///
/// In the MVP this is a lightweight placeholder.
/// It will later be expanded with authentication providers,
/// user profile data, and session lifecycle handling.
struct Session {
    
    /// Unique identifier of the authenticated user.
    var userId: String?
    
    /// Indicates whether the user is authenticated.
    var isAuthenticated: Bool {
        userId != nil
    }
    
    init(userId: String? = nil) {
        self.userId = userId
    }
}
