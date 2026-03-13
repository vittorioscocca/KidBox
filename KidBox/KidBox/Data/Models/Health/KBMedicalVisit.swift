//
//  KBMedicalVisit.swift
//  KidBox
//

import Foundation
import SwiftData

@Model
final class KBMedicalVisit {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    // MARK: Step 1 · Medico & Data
    var date: Date
    var doctorName: String?
    var doctorSpecializationRaw: String?
    var travelDetailsData: Data?
    var reason: String
    
    // MARK: Step 2 · Esito
    var diagnosis: String?
    var recommendations: String?
    
    // MARK: Step 3 · Prescrizioni
    var linkedTreatmentIds: [String]
    var linkedExamIds: [String] = []
    var asNeededDrugsData: Data?
    var therapyTypesRaw: [String]
    var prescribedExamsData: Data?
    
    // MARK: Step 4 · Foto & Appunti
    var photoURLs: [String]
    var notes: String?
    
    // MARK: Step 5 · Prossima visita
    var nextVisitDate: Date?
    var nextVisitReason: String?
    
    // MARK: Stato visita
    var visitStatusRaw: String?
    
    // MARK: Soft delete
    var isDeleted: Bool
    
    // MARK: Sync
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
    
    // MARK: - Computed helpers
    // Le chiamate a kbEncode/kbDecode usano tipi concreti — il compilatore
    // non deve soddisfare vincoli Sendable sui generici.
    
    var doctorSpecialization: KBDoctorSpecialization? {
        get { doctorSpecializationRaw.flatMap { KBDoctorSpecialization(rawValue: $0) } }
        set { doctorSpecializationRaw = newValue?.rawValue }
    }
    
    var prescribedExams: [KBPrescribedExam] {
        get { kbDecode([KBPrescribedExam].self, from: prescribedExamsData) ?? [] }
        set { prescribedExamsData = kbEncode(newValue) }
    }
    
    var asNeededDrugs: [KBAsNeededDrug] {
        get { kbDecode([KBAsNeededDrug].self, from: asNeededDrugsData) ?? [] }
        set { asNeededDrugsData = kbEncode(newValue) }
    }
    
    var travelDetails: KBTravelDetails? {
        get { kbDecode(KBTravelDetails.self, from: travelDetailsData) }
        set { travelDetailsData = newValue.flatMap { kbEncode($0) } }
    }
    
    var therapyTypes: [KBTherapyType] {
        get { therapyTypesRaw.compactMap { KBTherapyType(rawValue: $0) } }
        set { therapyTypesRaw = newValue.map { $0.rawValue } }
    }
    
    var visitStatus: KBVisitStatus? {
        get { visitStatusRaw.flatMap { KBVisitStatus(rawValue: $0) } }
        set { visitStatusRaw = newValue?.rawValue }
    }
    
    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        date: Date = Date(),
        doctorName: String? = nil,
        doctorSpecialization: KBDoctorSpecialization? = nil,
        travelDetails: KBTravelDetails? = nil,
        reason: String = "",
        diagnosis: String? = nil,
        recommendations: String? = nil,
        linkedTreatmentIds: [String] = [],
        linkedExamIds: [String] = [],
        asNeededDrugs: [KBAsNeededDrug] = [],
        therapyTypes: [KBTherapyType] = [],
        prescribedExams: [KBPrescribedExam] = [],
        photoURLs: [String] = [],
        notes: String? = nil,
        nextVisitDate: Date? = nil,
        nextVisitReason: String? = nil,
        visitStatus: KBVisitStatus? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id                      = id
        self.familyId                = familyId
        self.childId                 = childId
        self.date                    = date
        self.doctorName              = doctorName
        self.doctorSpecializationRaw = doctorSpecialization?.rawValue
        self.reason                  = reason
        self.diagnosis               = diagnosis
        self.recommendations         = recommendations
        self.linkedTreatmentIds      = linkedTreatmentIds
        self.linkedExamIds           = linkedExamIds
        self.therapyTypesRaw         = therapyTypes.map { $0.rawValue }
        self.photoURLs               = photoURLs
        self.notes                   = notes
        self.nextVisitDate           = nextVisitDate
        self.nextVisitReason         = nextVisitReason
        self.visitStatusRaw          = visitStatus?.rawValue
        self.isDeleted               = isDeleted
        self.createdAt               = createdAt
        self.updatedAt               = updatedAt
        self.updatedBy               = updatedBy
        self.createdBy               = createdBy
        self.syncStateRaw            = KBSyncState.synced.rawValue
        self.travelDetailsData       = travelDetails.flatMap { kbEncode($0) }
        self.asNeededDrugsData       = kbEncode(asNeededDrugs)
        self.prescribedExamsData     = kbEncode(prescribedExams)
    }
}
