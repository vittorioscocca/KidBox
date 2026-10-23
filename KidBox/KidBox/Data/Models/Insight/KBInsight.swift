//
//  KBInsight.swift
//  KidBox
//
//  Insight del motore proattivo: una cosa rimasta scoperta in famiglia
//  (to-do senza nessuno, dose non registrata…) vista da questo dispositivo
//  per il suo utente. Vive solo in locale e non si sincronizza: lo stato
//  (visto, fatto, scartato) è di chi ha il telefono, e il server non lo vede.
//
//  L'id è la chiave deterministica famiglia + tipo + entità: rivalutare la
//  stessa regola aggiorna la riga invece di crearne un'altra, e la stessa
//  chiave farà da identificativo della notifica locale.
//
//  Il testo non si salva: si compone alla consegna, nella lingua dell'utente,
//  leggendo l'entità per id (che intanto può aver cambiato titolo).
//

import Foundation
import SwiftData

/// Che cosa ha osservato il motore. Il valore grezzo finisce nella chiave e,
/// con il prefisso `insight_`, nel `type` della notifica locale: non cambiarlo.
enum KBInsightType: String, Codable, CaseIterable, Sendable {
    /// To-do senza assegnatario che scade entro 24 ore.
    case todoUnassignedDueSoon = "todo_unassigned_due_soon"
    /// Cura attiva senza dose registrata oggi.
    case treatmentDoseMissing = "treatment_dose_missing"
    /// Evento di domani senza promemoria.
    case eventTomorrowNoReminder = "event_tomorrow_no_reminder"
    /// Vaccino in scadenza.
    case vaccineDue = "vaccine_due"
    /// Lista della spesa ferma da giorni.
    case groceryStale = "grocery_stale"
    /// Pagamento di casa in scadenza per cui nessuno ha preso il to-do «Pagare: …».
    case housePaymentDue = "house_payment_due"
}

/// Quanto conta: decide il canale, non l'ordine delle notifiche di sistema.
enum KBInsightPriority: Int, Codable, Comparable, Sendable {
    /// Solo nel feed in Home.
    case low = 0
    /// Notifica locale, se le preferenze dell'utente la consentono.
    case normal = 1
    /// Notifica locale con una scadenza vicina: passa anche nel riepilogo serale.
    case high = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum KBInsightState: String, Codable, Sendable {
    case new
    case seen
    /// Risolto: dall'utente con «Fatto» o dal motore quando la regola non scatta più.
    case done
    /// «Non mi interessa» o ignorato fino alla scadenza.
    case dismissed

    /// Ancora da mostrare nel feed e da tenere programmato come notifica.
    var isOpen: Bool { self == .new || self == .seen }
}

@Model
final class KBInsight {
    @Attribute(.unique) var id: String
    var familyId: String
    /// L'utente di questo dispositivo a cui l'insight è rivolto.
    var recipientUid: String
    var typeRaw: String
    /// Id della voce osservata (to-do, cura, evento, vaccino, lista).
    var entityId: String
    var priorityRaw: Int
    var stateRaw: String
    /// Quando consegnarlo: l'orario della notifica locale.
    var fireAt: Date
    var createdAt: Date
    var updatedAt: Date
    var stateChangedAt: Date?
    /// Quando la notifica locale è stata (o sarà) consegnata. Se `fireAt` passa
    /// oltre, è un avviso nuovo (la dose della sera dopo quella del mattino).
    var notifiedAt: Date?
    /// Quando `insight_shown` è stato registrato: una volta sola per avviso.
    var shownReportedAt: Date?
    /// Quando `insight_acted` è stato registrato: chiedere agli altri conta
    /// già come azione, e la chiusura che arriva dopo non si conta due volte.
    var actedReportedAt: Date?

    /// `nil` per un tipo scritto da una build più recente: il motore lo salta.
    var type: KBInsightType? {
        KBInsightType(rawValue: typeRaw)
    }

    var priority: KBInsightPriority {
        get { KBInsightPriority(rawValue: priorityRaw) ?? .low }
        set { priorityRaw = newValue.rawValue }
    }

    var state: KBInsightState {
        get { KBInsightState(rawValue: stateRaw) ?? .dismissed }
        set { stateRaw = newValue.rawValue }
    }

    static func key(familyId: String, type: KBInsightType, entityId: String) -> String {
        "\(familyId)|\(type.rawValue)|\(entityId)"
    }

    init(
        familyId: String,
        recipientUid: String,
        type: KBInsightType,
        entityId: String,
        priority: KBInsightPriority,
        fireAt: Date,
        now: Date = Date()
    ) {
        self.id = Self.key(familyId: familyId, type: type, entityId: entityId)
        self.familyId = familyId
        self.recipientUid = recipientUid
        self.typeRaw = type.rawValue
        self.entityId = entityId
        self.priorityRaw = priority.rawValue
        self.stateRaw = KBInsightState.new.rawValue
        self.fireAt = fireAt
        self.createdAt = now
        self.updatedAt = now
        self.stateChangedAt = nil
        self.notifiedAt = nil
        self.shownReportedAt = nil
        self.actedReportedAt = nil
    }

    /// Nuova valutazione della stessa regola. Lo stato resta quello che l'utente
    /// ha scelto: un insight scartato non torna solo perché la regola scatta ancora.
    func refresh(priority: KBInsightPriority, fireAt: Date, now: Date = Date()) {
        guard self.priority != priority || self.fireAt != fireAt else { return }
        self.priority = priority
        self.fireAt = fireAt
        self.updatedAt = now
    }

    func mark(_ newState: KBInsightState, now: Date = Date()) {
        guard state != newState else { return }
        state = newState
        stateChangedAt = now
        updatedAt = now
    }
}
