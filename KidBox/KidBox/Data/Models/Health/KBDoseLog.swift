//
//  KBDoseLog.swift
//  KidBox

import Foundation
import SwiftData

@Model
final class KBDoseLog {
    
    @Attribute(.unique) var id: String
    var familyId:    String
    var childId:     String
    var treatmentId: String
    
    var dayNumber:     Int
    var slotIndex:     Int
    var scheduledTime: String
    var takenAt:       Date?
    var taken:         Bool
    
    var isDeleted:     Bool
    var createdAt:     Date
    var updatedAt:     Date
    var updatedBy:     String?
    var syncStatus:    Int        // KBSyncState.rawValue
    var lastSyncError: String?
    
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
        isDeleted: Bool = false,
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
        self.isDeleted     = isDeleted
        self.createdAt     = createdAt
        self.updatedAt     = updatedAt
        self.updatedBy     = updatedBy
        self.syncStatus    = KBSyncState.synced.rawValue
    }
}

extension KBDoseLog {
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStatus) ?? .synced }
        set { syncStatus = newValue.rawValue }
    }
}
