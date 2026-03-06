//
//  KBCustomDrug.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import Foundation
import SwiftData

@Model
final class KBCustomDrug {
    @Attribute(.unique) var id: String
    
    var name: String
    var activeIngredient: String
    var category: String
    var form: String
    
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool
    
    init(
        id: String = UUID().uuidString,
        name: String,
        activeIngredient: String,
        category: String,
        form: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.activeIngredient = activeIngredient
        self.category = category
        self.form = form
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }
}
