//
//  KBTodoList.swift
//  KidBox
//
//  Created by vscocca on 25/02/26.
//

import Foundation
import SwiftData

@Model
final class KBTodoList {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    /// Chi ha creato la lista. Opzionale: le liste precedenti a questo campo non
    /// lo hanno, e `TodoListExposure` le tratta come pubbliche per non farle
    /// sparire a chi le usa già.
    var createdBy: String?
    /// Visibilità che prendono di default i to-do creati nella lista
    /// (`family` | `members` | `private`). `nil` = famiglia, come prima.
    var defaultVisibilityScope: String?
    var defaultVisibilityMemberIds: [String]?
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        createdBy: String? = nil,
        defaultVisibilityScope: String? = nil,
        defaultVisibilityMemberIds: [String]? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.createdBy = createdBy
        self.defaultVisibilityScope = defaultVisibilityScope
        self.defaultVisibilityMemberIds = defaultVisibilityMemberIds
    }

    /// Scope normalizzato da dare ai to-do nuovi.
    var resolvedDefaultScope: String { KBVisibilityScope.normalized(defaultVisibilityScope) }

    /// Membri da dare ai to-do nuovi (solo con scope `members`).
    var resolvedDefaultMemberIds: [String] {
        resolvedDefaultScope == KBVisibilityScope.members ? (defaultVisibilityMemberIds ?? []) : []
    }
}
