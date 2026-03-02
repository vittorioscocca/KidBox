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
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.childId = childId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
