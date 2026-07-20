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
    
    // MARK: - Medico / pediatra di riferimento
    var doctorName: String?
    var doctorPhone: String?
    var doctorEmail: String?
    var doctorAddress: String?
    var doctorWebsite: String?
    var doctorOfficeHoursData: Data? = nil
    
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
        doctorEmail: String? = nil,
        doctorAddress: String? = nil,
        doctorWebsite: String? = nil,
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
        self.doctorEmail = doctorEmail
        self.doctorAddress = doctorAddress
        self.doctorWebsite = doctorWebsite
        self.updatedAt   = updatedAt
        self.updatedBy   = updatedBy
        self.syncStateRaw = KBSyncState.synced.rawValue
    }
}

/// Fascia oraria di ricevimento (giorno in italiano, dalle/alle in HH:mm).
struct KBDoctorOfficeHourSlot: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var weekday: String
    var fromTime: String
    var toTime: String
}

extension Array where Element == KBDoctorOfficeHourSlot {

    /// Es. `Lunedì: 08:30 – 10:30; 16:30 – 18:30` (fasce dello stesso giorno sulla stessa riga).
    var groupedOfficeHourDisplayLines: [String] {
        guard !isEmpty else { return [] }

        var byWeekday: [String: [KBDoctorOfficeHourSlot]] = [:]
        for slot in self {
            byWeekday[slot.weekday, default: []].append(slot)
        }

        var lines: [String] = []
        for day in KBItalianWeekday.allCases.map(\.rawValue) {
            guard let slots = byWeekday.removeValue(forKey: day), !slots.isEmpty else { continue }
            lines.append(Self.formatGroupedOfficeHourLine(weekday: day, slots: slots))
        }
        for day in byWeekday.keys.sorted() {
            guard let slots = byWeekday[day], !slots.isEmpty else { continue }
            lines.append(Self.formatGroupedOfficeHourLine(weekday: day, slots: slots))
        }
        return lines
    }

    private static func formatGroupedOfficeHourLine(
        weekday: String,
        slots: [KBDoctorOfficeHourSlot]
    ) -> String {
        let ranges = slots
            .map { "\($0.fromTime) – \($0.toTime)" }
            .joined(separator: "; ")
        return "\(weekday): \(ranges)"
    }
}

enum KBItalianWeekday: String, CaseIterable, Identifiable {
    case lunedi = "Lunedì"
    case martedi = "Martedì"
    case mercoledi = "Mercoledì"
    case giovedi = "Giovedì"
    case venerdi = "Venerdì"
    case sabato = "Sabato"
    case domenica = "Domenica"

    var id: String { rawValue }

    /// Etichetta per la UI. `rawValue` resta invariato (persistito come
    /// `KBDoctorOfficeHourSlot.weekday`) — non tradurlo.
    var uiLabel: String {
        switch self {
        case .lunedi:     return NSLocalizedString("Lunedì", comment: "Weekday")
        case .martedi:    return NSLocalizedString("Martedì", comment: "Weekday")
        case .mercoledi:  return NSLocalizedString("Mercoledì", comment: "Weekday")
        case .giovedi:    return NSLocalizedString("Giovedì", comment: "Weekday")
        case .venerdi:    return NSLocalizedString("Venerdì", comment: "Weekday")
        case .sabato:     return NSLocalizedString("Sabato", comment: "Weekday")
        case .domenica:   return NSLocalizedString("Domenica", comment: "Weekday")
        }
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

    var doctorOfficeHours: [KBDoctorOfficeHourSlot] {
        get {
            guard let data = doctorOfficeHoursData else { return [] }
            return (try? JSONDecoder().decode([KBDoctorOfficeHourSlot].self, from: data)) ?? []
        }
        set {
            doctorOfficeHoursData = newValue.isEmpty
                ? nil
                : try? JSONEncoder().encode(newValue)
        }
    }

    var hasReferenceDoctor: Bool {
        let name = doctorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty
    }
}
