//
//  KBMedicalVisit.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData

@Model
final class KBMedicalVisit {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    // MARK: - Contenuto
    var date: Date
    var doctorName: String?
    var reason: String          // motivo della visita
    var diagnosis: String?
    var notes: String?
    var nextVisitDate: Date?
    
    // MARK: - Soft delete
    var isDeleted: Bool
    
    // MARK: - Sync
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String?
    var createdBy: String?
    var syncStateRaw: Int
    var lastSyncError: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        date: Date = Date(),
        doctorName: String? = nil,
        reason: String = "",
        diagnosis: String? = nil,
        notes: String? = nil,
        nextVisitDate: Date? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id            = id
        self.familyId      = familyId
        self.childId       = childId
        self.date          = date
        self.doctorName    = doctorName
        self.reason        = reason
        self.diagnosis     = diagnosis
        self.notes         = notes
        self.nextVisitDate = nextVisitDate
        self.isDeleted     = isDeleted
        self.createdAt     = createdAt
        self.updatedAt     = updatedAt
        self.updatedBy     = updatedBy
        self.createdBy     = createdBy
        self.syncStateRaw  = KBSyncState.synced.rawValue
    }
}
