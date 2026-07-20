//
//  KBMedicalVisitTypes.swift
//  KidBox
//

import Foundation
import SwiftUI

enum KBDoctorSpecialization: String, Codable, CaseIterable {
    case pediatra            = "Pediatra"
    case medicoBase          = "Medico di Base"
    case dermatologo         = "Dermatologo"
    case ortopedico          = "Ortopedico"
    case otorinolaringoiatra = "Otorinolaringoiatra"
    case oculista            = "Oculista"
    case urologo             = "Urologo"
    case cardiologo          = "Cardiologo"
    case altro               = "Altro"

    /// Etichetta per la UI. `rawValue` resta invariato (persistito su SwiftData
    /// come `doctorSpecializationRaw`/`doc.spec`) — non tradurlo.
    var uiLabel: String {
        switch self {
        case .pediatra:             return NSLocalizedString("Pediatra", comment: "Doctor specialization")
        case .medicoBase:           return NSLocalizedString("Medico di Base", comment: "Doctor specialization")
        case .dermatologo:          return NSLocalizedString("Dermatologo", comment: "Doctor specialization")
        case .ortopedico:           return NSLocalizedString("Ortopedico", comment: "Doctor specialization")
        case .otorinolaringoiatra:  return NSLocalizedString("Otorinolaringoiatra", comment: "Doctor specialization")
        case .oculista:             return NSLocalizedString("Oculista", comment: "Doctor specialization")
        case .urologo:              return NSLocalizedString("Urologo", comment: "Doctor specialization")
        case .cardiologo:           return NSLocalizedString("Cardiologo", comment: "Doctor specialization")
        case .altro:                return NSLocalizedString("Altro", comment: "Doctor specialization: other")
        }
    }
}

struct KBPrescribedExam: Codable, Identifiable {
    var id: String           = UUID().uuidString
    var name: String
    var isUrgent: Bool       = false
    var deadline: Date?      = nil
    var preparation: String? = nil
}

struct KBAsNeededDrug: Codable, Identifiable {
    var id: String            = UUID().uuidString
    var drugName: String
    var dosageValue: Double
    var dosageUnit: String
    var instructions: String? = nil
}

enum KBTherapyType: String, Codable, CaseIterable {
    case riposo       = "Riposo"
    case fisioterapia = "Fisioterapia"
    case dieta        = "Dieta"
    case aerosol      = "Aerosol"
    case altro        = "Altro"

    /// Etichetta per la UI. `rawValue` resta invariato (persistito su SwiftData
    /// come `therapyTypesRaw`) — non tradurlo.
    var uiLabel: String {
        switch self {
        case .riposo:       return NSLocalizedString("Riposo", comment: "Therapy type: rest")
        case .fisioterapia: return NSLocalizedString("Fisioterapia", comment: "Therapy type: physiotherapy")
        case .dieta:        return NSLocalizedString("Dieta", comment: "Therapy type: diet")
        case .aerosol:      return NSLocalizedString("Aerosol", comment: "Therapy type: aerosol")
        case .altro:        return NSLocalizedString("Altro", comment: "Therapy type: other")
        }
    }
}

enum KBVisitStatus: String, Codable, CaseIterable {
    case pending           = "In attesa"
    case booked            = "Prenotata"
    case completed         = "Eseguita"
    case resultAvailable   = "Risultato disponibile"

    /// Etichetta da mostrare in UI. `rawValue` resta invariato (persistito su
    /// SwiftData/Firestore come `visitStatusRaw`) — non tradurlo, altrimenti i
    /// record esistenti non verrebbero più riconosciuti.
    var displayName: String {
        switch self {
        case .pending:         return NSLocalizedString("In attesa", comment: "Visit status: pending")
        case .booked:           return NSLocalizedString("Prenotata", comment: "Visit status: booked")
        case .completed:        return NSLocalizedString("Eseguita", comment: "Visit status: completed")
        case .resultAvailable:  return NSLocalizedString("Risultato disponibile", comment: "Visit status: result available")
        }
    }

    var icon: String {
        switch self {
        case .pending:         return "clock"
        case .booked:          return "calendar.badge.checkmark"
        case .completed:       return "checkmark.circle.fill"
        case .resultAvailable: return "doc.text.magnifyingglass"
        }
    }
    
    var color: Color {
        switch self {
        case .pending:         return .gray
        case .booked:          return .blue
        case .completed:       return .green
        case .resultAvailable: return .purple
        }
    }
}

struct KBTravelDetails: Codable {
    var transportMode: String? = nil
    var distanceKm: Double?    = nil
    var travelNotes: String?   = nil
}

// MARK: - JSON helpers
// Usano JSONEncoder/Decoder direttamente senza vincoli generici Sendable,
// evitando il problema di actor-isolated conformance in Swift 6.

func kbEncode<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder().encode(value)
}

func kbDecode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
    guard let data else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}
