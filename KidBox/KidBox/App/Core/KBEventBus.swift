//
//  KBEventBus.swift
//  KidBox
//
//  Bus eventi globale — le feature emettono eventi,
//  le altre feature ascoltano senza dipendenze dirette.
//

import Combine
import Foundation

// MARK: - Eventi

enum KBAppEvent {
    // Cure
    case treatmentAttachmentPending(
        urls:        [URL],
        treatmentId: String,
        familyId:    String,
        childId:     String
    )
    case visitAttachmentPending(
        urls:     [URL],
        visitId:  String,
        familyId: String,
        childId:  String
    )
    // Spese
    case expenseAttachmentPending(
        urls:         [URL],
        expenseId:    String,
        expenseTitle: String,
        familyId:     String
    )
    case vehicleAttachmentPending(
        urls: [URL],
        vehicleId: String,
        familyId: String
    )
    case vehicleEventAttachmentPending(
        urls: [URL],
        eventId: String,
        familyId: String
    )
    /// Casa — elementi (elettrodomestici, impianti, …)
    case homeItemAttachmentPending(
        urls: [URL],
        homeItemId: String,
        familyId: String
    )
    /// Casa — scadenze & pagamenti
    case housePaymentAttachmentPending(
        urls: [URL],
        paymentId: String,
        familyId: String
    )
    /// Animali — evento (vaccino, visita, …)
    case petEventAttachmentPending(
        urls: [URL],
        eventId: String,
        familyId: String
    )
}

// MARK: - Bus

final class KBEventBus {
    static let shared = KBEventBus()
    private init() {}
    
    private let subject = PassthroughSubject<KBAppEvent, Never>()
    
    var stream: AnyPublisher<KBAppEvent, Never> {
        subject.eraseToAnyPublisher()
    }
    
    func emit(_ event: KBAppEvent) {
        subject.send(event)
    }
}
