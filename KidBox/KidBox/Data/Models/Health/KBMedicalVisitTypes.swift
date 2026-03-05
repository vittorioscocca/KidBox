//
//  KBMedicalVisitTypes.swift
//  KidBox
//

import Foundation

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
