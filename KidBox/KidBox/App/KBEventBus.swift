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
    // Espandibile in futuro:
    // case treatmentCreated(treatmentId: String, familyId: String)
    // case treatmentDoseTaken(treatmentId: String, dayNumber: Int, slotIndex: Int)
    // case treatmentCompleted(treatmentId: String, familyId: String)
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
