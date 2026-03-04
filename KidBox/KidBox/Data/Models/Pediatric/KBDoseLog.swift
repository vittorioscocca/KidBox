//
//  KBDoseLog.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

import Foundation
import SwiftData

@Model
final class KBDoseLog {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId:  String
    var treatmentId: String
    
    /// Giorno della cura (1-based)
    var dayNumber: Int
    
    /// Slot orario (0 = mattina, 1 = pranzo, ...)
    var slotIndex: Int
    
    /// Orario schedulato (es. "08:00")
    var scheduledTime: String
    
    /// Data/ora in cui è stata effettivamente somministrata
    var takenAt: Date?
    
    /// true = presa, false = saltata
    var taken: Bool
    
    // Sync
    var createdAt:  Date
    var updatedAt:  Date
    var updatedBy:  String?
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        treatmentId: String,
        dayNumber: Int,
        slotIndex: Int,
        scheduledTime: String,
        takenAt: Date? = nil,
        taken: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil
    ) {
        self.id            = id
        self.familyId      = familyId
        self.childId       = childId
        self.treatmentId   = treatmentId
        self.dayNumber     = dayNumber
        self.slotIndex     = slotIndex
        self.scheduledTime = scheduledTime
        self.takenAt       = takenAt
        self.taken         = taken
        self.createdAt     = createdAt
        self.updatedAt     = updatedAt
        self.updatedBy     = updatedBy
    }
}
