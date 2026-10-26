//
//  DocumentIntelligenceModels.swift
//  KidBox
//
//  Modelli per "Document Intelligence": l'AI legge un documento (importato in
//  Documenti o caricato col «+» dell'assistente), capisce cos'è e propone le
//  azioni nelle sezioni giuste (Casa, Salute, Spese, Calendario…) che l'utente
//  conferma, e può correggere, prima dell'esecuzione.
//

import Foundation

/// Una singola azione proposta dall'AI a partire dal documento analizzato.
/// `id` è locale (UI), non decodificato dalla risposta del modello. I campi
/// sono `var` perché la scheda di conferma li lascia correggere.
struct DocIntelAction: Decodable, Identifiable {
    var id = UUID()

    /// Tipo azione: expense_add, event_add, todo_add, health_reminder,
    /// note_add, vehicle_event, medical_visit, exam_add, treatment_add,
    /// house_payment, vaccine_add, rename_document.
    let type: String
    /// Descrizione breve mostrata all'utente nella sheet di conferma.
    var summary: String?

    // Campi generici (presenti a seconda del tipo).
    var title: String?
    var body: String?
    var notes: String?
    var category: String?
    var amount: Double?
    var date: String?        // ISO8601
    var endDate: String?     // ISO8601
    var isAllDay: Bool?
    /// Persona dei dati sanitari: `childId` di un figlio o `userId` di un adulto.
    var childId: String?
    var vehicleId: String?
    var vehicleEventType: String?
    var doctorName: String?
    var vaccineType: String?
    var renameTo: String?

    // Visita
    var diagnosis: String?
    var recommendations: String?
    // Esame / analisi
    var resultText: String?
    var location: String?
    // Cura
    var activeIngredient: String?
    var dosageValue: Double?
    var dosageUnit: String?
    var dailyFrequency: Int?
    var durationDays: Int?
    var isLongTerm: Bool?
    // Pagamento di Casa
    var paymentType: String?
    var subtype: String?
    var provider: String?

    private enum CodingKeys: String, CodingKey {
        case type, summary, title, body, notes, category, amount, date, endDate
        case isAllDay, childId, vehicleId, vehicleEventType, doctorName, vaccineType, renameTo
        case diagnosis, recommendations, resultText, location
        case activeIngredient, dosageValue, dosageUnit, dailyFrequency, durationDays, isLongTerm
        case paymentType, subtype, provider
    }

    /// Azioni che riguardano una persona (figlio o adulto) di Salute.
    var needsPerson: Bool {
        ["medical_visit", "exam_add", "treatment_add", "vaccine_add"].contains(type)
    }

    /// Azioni a cui l'originale del documento si allega come file.
    var takesAttachment: Bool {
        ["medical_visit", "exam_add", "treatment_add", "house_payment"].contains(type)
    }

    /// Etichetta per l'icona/categoria nella UI.
    var iconName: String {
        switch type {
        case "expense_add":    return "eurosign.circle"
        case "event_add":      return "calendar"
        case "todo_add":       return "checklist"
        case "health_reminder":return "bell.badge"
        case "note_add":       return "note.text"
        case "vehicle_event":  return "car"
        case "medical_visit":  return "stethoscope"
        case "exam_add":       return "testtube.2"
        case "treatment_add":  return "pills"
        case "house_payment":  return "house"
        case "vaccine_add":    return "syringe"
        case "rename_document":return "character.cursor.ibeam"
        default:               return "sparkles"
        }
    }

    var humanTypeLabel: String {
        switch type {
        case "expense_add":    return String(localized: "Spesa")
        case "event_add":      return String(localized: "Evento calendario")
        case "todo_add":       return String(localized: "Promemoria")
        case "health_reminder":return String(localized: "Promemoria salute")
        case "note_add":       return String(localized: "Nota")
        case "vehicle_event":  return String(localized: "Scadenza veicolo")
        case "medical_visit":  return String(localized: "Visita medica")
        case "exam_add":       return String(localized: "Esame / analisi")
        case "treatment_add":  return String(localized: "Cura")
        case "house_payment":  return String(localized: "Casa · Scadenze e pagamenti")
        case "vaccine_add":    return String(localized: "Vaccino")
        case "rename_document":return String(localized: "Rinomina documento")
        default:               return String(localized: "Azione")
        }
    }
}

/// Risultato completo dell'analisi di un documento.
struct DocIntelResult: Decodable {
    /// Tipo di documento riconosciuto (es. "referto medico", "fattura").
    let documentType: String?
    /// Classe del documento: bill, medical_report, lab_results, prescription,
    /// receipt, vehicle, school, insurance, other.
    let category: String?
    /// Titolo pulito suggerito per il documento.
    let suggestedTitle: String?
    var actions: [DocIntelAction]
}

/// Cosa serve alla scheda di conferma: il risultato, le persone e i veicoli
/// dati all'AI, e il documento (importato in Documenti) oppure il file
/// sorgente (caricato col «+» dell'assistente) da allegare.
struct DocIntelPayload: Identifiable {
    let id = UUID()
    let result: DocIntelResult
    var documentId: String? = nil
    var sourceFile: URL? = nil
    let children: [DocumentIntelligenceService.ChildRef]
    let vehicles: [DocumentIntelligenceService.VehicleRef]
}
