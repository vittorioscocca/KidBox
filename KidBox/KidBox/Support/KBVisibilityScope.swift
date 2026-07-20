//
//  KBVisibilityScope.swift
//  KidBox
//

import Foundation

/// Stored on Firestore/SwiftData as raw strings `"family"` | `"members"` | `"private"`.
enum KBVisibilityScope {
    static let family = "family"
    static let members = "members"
    /// Stored value is `"private"` (creator-only).
    static let onlyCreator = "private"

    /// SwiftData migrazioni / valori legacy: `nil` o sconosciuto → `family`.
    static func normalized(_ scope: String?) -> String {
        guard let scope, !scope.isEmpty else { return family }
        switch scope {
        case members: return members
        case onlyCreator: return onlyCreator
        default: return family
        }
    }

    static func chipLabel(for scope: String) -> String {
        switch scope {
        case members:
            return "👥 " + NSLocalizedString("Membri selezionati", comment: "Visibility: selected members")
        case onlyCreator:
            return "🔒 " + NSLocalizedString("Solo io", comment: "Visibility: only me")
        default:
            return "👨‍👩‍👧 " + NSLocalizedString("Tutta la famiglia", comment: "Visibility: whole family")
        }
    }

    /// `createdBy` is the owner's uid (`KBNote.createdBy`, `KBTodoItem.createdBy`).
    static func isVisible(
        scope: String?,
        memberIds: [String],
        createdBy: String?,
        currentUid: String?
    ) -> Bool {
        guard let currentUid, !currentUid.isEmpty else { return false }
        let s = normalized(scope)
        switch s {
        case family:
            return true
        case members:
            if createdBy == currentUid { return true }
            return memberIds.contains(currentUid)
        case onlyCreator:
            return createdBy == currentUid
        default:
            return true
        }
    }
}
