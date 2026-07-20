//
//  KBVaccine.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData

enum VaccineStatus: String, Codable {
    case administered   = "administered"    // Somministrato
    case scheduled      = "scheduled"       // Appuntamento fissato
    case planned        = "planned"         // Da programmare
}

enum VaccineType: String, Codable, CaseIterable {
    case esavalente     = "esavalente"
    case pneumococco    = "pneumococco"
    case meningococcoB  = "meningococcoB"
    case mpr            = "mpr"
    case varicella      = "varicella"
    case meningococcoACWY = "meningococcoACWY"
    case hpv            = "hpv"
    case influenza      = "influenza"
    case altro          = "altro"
    
    /// `String` (non `LocalizedStringKey`): usato in coalescenza con `commercialName`
    /// (`String` dinamico) e in interpolazioni per notifiche/contesto AI, quindi
    /// passa da NSLocalizedString.
    var displayName: String {
        switch self {
        case .esavalente:       return NSLocalizedString("Esavalente", comment: "Vaccine type")
        case .pneumococco:      return NSLocalizedString("Pneumococco", comment: "Vaccine type")
        case .meningococcoB:    return NSLocalizedString("Meningococco B", comment: "Vaccine type")
        case .mpr:              return NSLocalizedString("MPR", comment: "Vaccine type")
        case .varicella:        return NSLocalizedString("Varicella", comment: "Vaccine type")
        case .meningococcoACWY: return NSLocalizedString("Meningococco ACWY", comment: "Vaccine type")
        case .hpv:              return NSLocalizedString("HPV", comment: "Vaccine type")
        case .influenza:        return NSLocalizedString("Influenza", comment: "Vaccine type")
        case .altro:            return NSLocalizedString("Altro", comment: "Vaccine type")
        }
    }
    
    var systemImage: String {
        switch self {
        case .esavalente, .influenza, .hpv: return "syringe"
        case .pneumococco, .meningococcoB, .meningococcoACWY: return "brain.head.profile"
        case .mpr:              return "pills"
        case .varicella:        return "allergens"
        case .altro:            return "cross.vial"
        }
    }
}

@Model
final class KBVaccine {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    // MARK: - Contenuto
    var vaccineTypeRaw: String          // VaccineType.rawValue
    var statusRaw: String               // VaccineStatus.rawValue
    var commercialName: String?
    var doseNumber: Int
    var totalDoses: Int
    var administeredDate: Date?
    var scheduledDate: Date?
    var lotNumber: String?
    var administeredBy: String?
    var administrationSiteRaw: String?  // "braccio_sx", "braccio_dx", ecc.
    var notes: String?
    
    /// Promemoria locale (notifica) solo quando `status == .planned`.
    /// Opzionale per migrazione SwiftData: i record senza colonna storica restano `nil` (= spento).
    var reminderOn: Bool?
    /// Data prevista del richiamo (usata per il promemoria «giorno prima»).
    var nextDoseDate: Date?
    
    // MARK: - Soft delete
    var isDeleted: Bool
    
    // MARK: - Sync
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String?
    var createdBy: String?
    var syncStateRaw: Int
    var lastSyncError: String?
    
    // MARK: - Computed
    var vaccineType: VaccineType {
        get { VaccineType(rawValue: vaccineTypeRaw) ?? .altro }
        set { vaccineTypeRaw = newValue.rawValue }
    }
    
    var status: VaccineStatus {
        get { VaccineStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        vaccineType: VaccineType = .altro,
        status: VaccineStatus = .administered,
        commercialName: String? = nil,
        doseNumber: Int = 1,
        totalDoses: Int = 1,
        administeredDate: Date? = nil,
        scheduledDate: Date? = nil,
        lotNumber: String? = nil,
        administeredBy: String? = nil,
        administrationSiteRaw: String? = nil,
        notes: String? = nil,
        reminderOn: Bool? = false,
        nextDoseDate: Date? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id                    = id
        self.familyId              = familyId
        self.childId               = childId
        self.vaccineTypeRaw        = vaccineType.rawValue
        self.statusRaw             = status.rawValue
        self.commercialName        = commercialName
        self.doseNumber            = doseNumber
        self.totalDoses            = totalDoses
        self.administeredDate      = administeredDate
        self.scheduledDate         = scheduledDate
        self.lotNumber             = lotNumber
        self.administeredBy        = administeredBy
        self.administrationSiteRaw = administrationSiteRaw
        self.notes                 = notes
        self.reminderOn            = reminderOn
        self.nextDoseDate          = nextDoseDate
        self.isDeleted             = isDeleted
        self.createdAt             = createdAt
        self.updatedAt             = updatedAt
        self.updatedBy             = updatedBy
        self.createdBy             = createdBy
        self.syncStateRaw          = KBSyncState.synced.rawValue
    }
}
