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
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        createdBy: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.createdBy = createdBy
    }
}
