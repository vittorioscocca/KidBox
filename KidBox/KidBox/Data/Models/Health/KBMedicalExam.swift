//
//  KBMedicalExam.swift
//  KidBox
//

import Foundation
import SwiftData

// MARK: - Exam Status

enum KBExamStatus: String, Codable, CaseIterable {
    case pending   = "In attesa"
    case booked    = "Prenotato"
    case done      = "Eseguito"
    case resultIn  = "Risultato disponibile"
    
    var icon: String {
        switch self {
        case .pending:  return "clock"
        case .booked:   return "calendar.badge.checkmark"
        case .done:     return "checkmark.circle"
        case .resultIn: return "doc.text.magnifyingglass"
        }
    }
}

// MARK: - Model

@Model
final class KBMedicalExam {
    
    // Identity
    @Attribute(.unique) var id:       String
    var familyId:                     String
    var childId:                      String
    
    // Core fields
    var name:                         String
    var isUrgent:                     Bool
    var deadline:                     Date?
    var preparation:                  String?
    var notes:                        String?
    var location:                     String?   // ← NUOVO: luogo dell'esame
    
    // Status lifecycle
    var statusRaw:                    String
    var resultText:                   String?
    var resultDate:                   Date?
    
    // Link alla visita da cui è stato prescritto (opzionale)
    var prescribingVisitId:           String?
    
    // Sync / soft-delete
    var isDeleted:                    Bool
    var syncStateRaw:                 Int
    var lastSyncError:                String?
    var createdAt:                    Date
    var updatedAt:                    Date
    var updatedBy:                    String
    var createdBy:                    String
    
    // MARK: - Computed helpers
    
    var status: KBExamStatus {
        get { KBExamStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    // MARK: - Init
    
    init(
        id:                 String       = UUID().uuidString,
        familyId:           String,
        childId:            String,
        name:               String,
        isUrgent:           Bool         = false,
        deadline:           Date?        = nil,
        preparation:        String?      = nil,
        notes:              String?      = nil,
        location:           String?      = nil,   // ← NUOVO
        status:             KBExamStatus = .pending,
        resultText:         String?      = nil,
        resultDate:         Date?        = nil,
        prescribingVisitId: String?      = nil,
        createdAt:          Date         = Date(),
        updatedAt:          Date         = Date(),
        updatedBy:          String       = "",
        createdBy:          String       = ""
    ) {
        self.id                 = id
        self.familyId           = familyId
        self.childId            = childId
        self.name               = name
        self.isUrgent           = isUrgent
        self.deadline           = deadline
        self.preparation        = preparation
        self.notes              = notes
        self.location           = location
        self.statusRaw          = status.rawValue
        self.resultText         = resultText
        self.resultDate         = resultDate
        self.prescribingVisitId = prescribingVisitId
        self.isDeleted          = false
        self.syncStateRaw       = KBSyncState.pendingUpsert.rawValue
        self.createdAt          = createdAt
        self.updatedAt          = updatedAt
        self.updatedBy          = updatedBy
        self.createdBy          = createdBy
    }
}

// MARK: - DTO

struct KBMedicalExamDTO {
    let id:                 String
    let familyId:           String
    let childId:            String
    let name:               String
    let isUrgent:           Bool
    let deadline:           Date?
    let preparation:        String?
    let notes:              String?
    let location:           String?   // ← NUOVO
    let statusRaw:          String
    let resultText:         String?
    let resultDate:         Date?
    let prescribingVisitId: String?
    let isDeleted:          Bool
    let createdAt:          Date
    let updatedAt:          Date
    let updatedBy:          String
    let createdBy:          String
}

extension KBMedicalExam {
    func toDTO() -> KBMedicalExamDTO {
        KBMedicalExamDTO(
            id:                 id,
            familyId:           familyId,
            childId:            childId,
            name:               name,
            isUrgent:           isUrgent,
            deadline:           deadline,
            preparation:        preparation,
            notes:              notes,
            location:           location,
            statusRaw:          statusRaw,
            resultText:         resultText,
            resultDate:         resultDate,
            prescribingVisitId: prescribingVisitId,
            isDeleted:          isDeleted,
            createdAt:          createdAt,
            updatedAt:          updatedAt,
            updatedBy:          updatedBy,
            createdBy:          createdBy
        )
    }
}
