//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//


import Foundation
import SwiftData

/// Scheda medica del bambino: gruppo sanguigno, allergie, pediatra di riferimento.
/// One-per-child: id == childId per semplicità.
@Model
final class KBPediatricProfile {
    
    @Attribute(.unique) var id: String   // == childId
    var familyId: String
    var childId: String
    
    var emergencyContactsData: Data? = nil
    
    // MARK: - Scheda medica
    var bloodGroup: String?              // "A+", "B-", "0+", …
    var allergies: String?               // testo libero
    var medicalNotes: String?
    
    // MARK: - Pediatra
    var doctorName: String?
    var doctorPhone: String?
    
    // MARK: - Sync
    var updatedAt: Date
    var updatedBy: String?
    var syncStateRaw: Int
    var lastSyncError: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    init(
        childId: String,
        familyId: String,
        bloodGroup: String? = nil,
        allergies: String? = nil,
        medicalNotes: String? = nil,
        doctorName: String? = nil,
        doctorPhone: String? = nil,
        updatedAt: Date = Date(),
        updatedBy: String? = nil
    ) {
        self.id          = childId
        self.childId     = childId
        self.familyId    = familyId
        self.bloodGroup  = bloodGroup
        self.allergies   = allergies
        self.medicalNotes = medicalNotes
        self.doctorName  = doctorName
        self.doctorPhone = doctorPhone
        self.updatedAt   = updatedAt
        self.updatedBy   = updatedBy
        self.syncStateRaw = KBSyncState.synced.rawValue
    }
}

/// Contatto di emergenza associato a un bambino.
/// Salvato come array JSON embedded in KBPediatricProfile.emergencyContactsData.
struct KBEmergencyContact: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var relation: String   // es. "Nonna", "Papà", "Babysitter"
    var phone: String
}

// MARK: - KBPediatricProfile + emergencyContacts

extension KBPediatricProfile {
    
    /// Array decodificato dei contatti emergenza.
    /// Getter: decodifica da emergencyContactsData (nil → [])
    /// Setter: ri-codifica e salva in emergencyContactsData
    var emergencyContacts: [KBEmergencyContact] {
        get {
            guard let data = emergencyContactsData else { return [] }
            return (try? JSONDecoder().decode([KBEmergencyContact].self, from: data)) ?? []
        }
        set {
            emergencyContactsData = try? JSONEncoder().encode(newValue)
        }
    }
}
