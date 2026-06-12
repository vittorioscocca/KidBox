//
//  DocumentIntelligenceModels.swift
//  KidBox
//
//  Modelli per "Document Intelligence": l'AI legge un documento importato e
//  propone azioni cross-feature (spese, eventi, scadenze, salute) che l'utente
//  conferma prima dell'esecuzione.
//

import Foundation

/// Una singola azione proposta dall'AI a partire dal documento analizzato.
/// `id` è locale (UI), non decodificato dalla risposta del modello.
struct DocIntelAction: Decodable, Identifiable {
    let id = UUID()

    /// Tipo azione: expense_add, event_add, todo_add, health_reminder,
    /// note_add, vehicle_event, medical_visit, vaccine_add, rename_document.
    let type: String
    /// Descrizione breve mostrata all'utente nella sheet di conferma.
    let summary: String?

    // Campi generici (presenti a seconda del tipo).
    let title: String?
    let body: String?
    let notes: String?
    let category: String?
    let amount: Double?
    let date: String?        // ISO8601
    let endDate: String?     // ISO8601
    let isAllDay: Bool?
    let childId: String?
    let vehicleId: String?
    let vehicleEventType: String?
    let doctorName: String?
    let vaccineType: String?
    let renameTo: String?

    private enum CodingKeys: String, CodingKey {
        case type, summary, title, body, notes, category, amount, date, endDate
        case isAllDay, childId, vehicleId, vehicleEventType, doctorName, vaccineType, renameTo
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
        case "vaccine_add":    return "syringe"
        case "rename_document":return "character.cursor.ibeam"
        default:               return "sparkles"
        }
    }

    var humanTypeLabel: String {
        switch type {
        case "expense_add":    return "Spesa"
        case "event_add":      return "Evento calendario"
        case "todo_add":       return "Promemoria"
        case "health_reminder":return "Promemoria salute"
        case "note_add":       return "Nota"
        case "vehicle_event":  return "Scadenza veicolo"
        case "medical_visit":  return "Visita medica"
        case "vaccine_add":    return "Vaccino"
        case "rename_document":return "Rinomina documento"
        default:               return "Azione"
        }
    }
}

/// Risultato completo dell'analisi di un documento.
struct DocIntelResult: Decodable {
    /// Tipo di documento riconosciuto (es. "referto medico", "fattura").
    let documentType: String?
    /// Titolo pulito suggerito per il documento.
    let suggestedTitle: String?
    let actions: [DocIntelAction]
}
