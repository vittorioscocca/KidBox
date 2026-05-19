//
//  AISettings.swift
//  KidBox
//
//  Semplice store per le preferenze AI dell'utente.
//  Non gestisce più API key — tutto è lato server.
//

import Foundation
import Combine
import OSLog

final class AISettings: ObservableObject {
    
    static let shared = AISettings()
    
    private let log = Logger(subsystem: "com.kidbox", category: "ai_settings")
    
    private enum UDKey {
        static let isEnabled    = "kb_ai_is_enabled"
        static let consentGiven = "kb_ai_consent_given"
        static let consentDate  = "kb_ai_consent_date"
        static let healthContextSendPreference = "kb_ai_health_context_send_preference"
    }
    
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: UDKey.isEnabled) }
    }
    
    @Published var consentGiven: Bool {
        didSet { UserDefaults.standard.set(consentGiven, forKey: UDKey.consentGiven) }
    }
    
    @Published var consentDate: Date? {
        didSet { UserDefaults.standard.set(consentDate, forKey: UDKey.consentDate) }
    }

    @Published var healthContextSendPreference: HealthContextSendPreference {
        didSet {
            UserDefaults.standard.set(healthContextSendPreference.rawValue, forKey: UDKey.healthContextSendPreference)
        }
    }
    
    private init() {
        self.isEnabled    = UserDefaults.standard.bool(forKey: UDKey.isEnabled)
        self.consentGiven = UserDefaults.standard.bool(forKey: UDKey.consentGiven)
        self.consentDate  = UserDefaults.standard.object(forKey: UDKey.consentDate) as? Date
        let prefRaw = UserDefaults.standard.string(forKey: UDKey.healthContextSendPreference)
        self.healthContextSendPreference = prefRaw
            .flatMap(HealthContextSendPreference.init(rawValue:))
            ?? .askEachTime
    }
    
    func recordConsent() {
        consentGiven = true
        consentDate  = Date()
        isEnabled    = true
        log.info("AISettings: consent recorded")
    }
    
    func resetAll() {
        isEnabled    = false
        consentGiven = false
        consentDate  = nil
        log.info("AISettings: reset")
    }
}
