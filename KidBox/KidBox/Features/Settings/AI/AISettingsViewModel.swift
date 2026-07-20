//
//  AISettingsViewModel.swift
//  KidBox
//
//  Created by vscocca on 05/03/26.
//


import Foundation
import Combine
import OSLog

/// ViewModel for `AISettingsView`.
///
/// Stesso pattern di `SettingsViewModel`:
/// - Legge la cache locale (UserDefaults) immediatamente all'init
/// - Sincronizza con Firestore via `NotificationManager` in background
/// - Aggiornamento ottimistico: UI si aggiorna subito, poi persiste
@MainActor
final class AISettingsViewModel: ObservableObject {
    
    // MARK: - Published
    
    @Published var aiEnabled:     Bool    = false
    @Published var consentGiven:  Bool    = false
    @Published var consentDate:   Date?   = nil
    @Published var isLoading:     Bool    = false
    @Published var infoText:      String? = nil
    @Published var usage:         AIResponse? = nil
    @Published var loadingUsage:  Bool    = false
    @Published var healthContextSendPreference: HealthContextSendPreference = .askEachTime
    
    // MARK: - Dependencies
    
    private let notifications = NotificationManager.shared
    private let aiSettings    = AISettings.shared
    
    // MARK: - Local cache keys
    
    private enum LocalKeys {
        static let aiEnabled    = "kb_ai_is_enabled"
        static let consentGiven = "kb_ai_consent_given"
        static let consentDate  = "kb_ai_consent_date"
    }
    
    // MARK: - Init
    
    private var usageObserver: NSObjectProtocol?

    init() {
        // Leggi cache locale immediatamente (UX istantanea)
        self.aiEnabled    = UserDefaults.standard.bool(forKey: LocalKeys.aiEnabled)
        self.consentGiven = UserDefaults.standard.bool(forKey: LocalKeys.consentGiven)
        self.consentDate  = UserDefaults.standard.object(forKey: LocalKeys.consentDate) as? Date
        self.healthContextSendPreference = aiSettings.healthContextSendPreference
        KBLog.settings.kbDebug("AISettingsVM init cached aiEnabled=\(self.aiEnabled)")

        usageObserver = NotificationCenter.default.addObserver(
            forName: .aiUsageDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let usageToday = note.userInfo?["usageToday"] as? Int,
                  let dailyLimit = note.userInfo?["dailyLimit"] as? Int else { return }
            Task { @MainActor in
                self.usage = AIResponse(reply: "", usageToday: usageToday, dailyLimit: dailyLimit)
            }
        }
    }

    deinit {
        if let usageObserver {
            NotificationCenter.default.removeObserver(usageObserver)
        }
    }
    
    // MARK: - Load (sync con Firestore)
    
    func load() {
        KBLog.settings.kbDebug("AISettingsVM load requested")
        
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            
            let remote = await notifications.fetchAIEnabledPreference()
            if aiEnabled != remote { aiEnabled = remote }
            UserDefaults.standard.set(remote, forKey: LocalKeys.aiEnabled)
            aiSettings.isEnabled = remote

            let healthPref = await notifications.fetchHealthContextSendPreference()
            if healthContextSendPreference != healthPref {
                healthContextSendPreference = healthPref
            }
            aiSettings.healthContextSendPreference = healthPref
            
            KBLog.settings.kbInfo("AISettingsVM remote aiEnabled=\(remote) healthContext=\(healthPref.rawValue)")
        }
    }
    
    // MARK: - Toggle AI
    
    func toggleAIEnabled(_ enabled: Bool) {
        KBLog.settings.kbInfo("AISettingsVM toggleAIEnabled=\(enabled)")
        infoText = nil
        
        // Se vuole attivare ma non ha ancora dato consenso → blocca
        // Il consenso viene richiesto da AIConsentSheet in AISettingsView
        guard enabled == false || consentGiven else {
            // Non attiviamo — la view mostrerà il consent sheet
            return
        }
        
        aiEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.aiEnabled)
        aiSettings.isEnabled = enabled
        
        Task { @MainActor in
            do {
                try await notifications.setAIEnabled(enabled)
                infoText = enabled ? NSLocalizedString("Assistente AI attivato.", comment: "") : NSLocalizedString("Assistente AI disattivato.", comment: "")
            } catch {
                // Rollback
                aiEnabled = !enabled
                UserDefaults.standard.set(!enabled, forKey: LocalKeys.aiEnabled)
                aiSettings.isEnabled = !enabled
                infoText = error.localizedDescription
                KBLog.settings.kbError("AISettingsVM setAIEnabled failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Consenso
    
    func recordConsent() {
        let now = Date()
        consentGiven = true
        consentDate  = now
        UserDefaults.standard.set(true, forKey: LocalKeys.consentGiven)
        UserDefaults.standard.set(now,  forKey: LocalKeys.consentDate)
        aiSettings.recordConsent()
        
        // Dopo il consenso, attiva automaticamente
        toggleAIEnabled(true)
        KBLog.settings.kbInfo("AISettingsVM consent recorded")
    }
    
    func revokeConsent() {
        consentGiven = false
        consentDate  = nil
        UserDefaults.standard.set(false, forKey: LocalKeys.consentGiven)
        UserDefaults.standard.removeObject(forKey: LocalKeys.consentDate)
        aiSettings.resetAll()
        toggleAIEnabled(false)
        KBLog.settings.kbInfo("AISettingsVM consent revoked")
    }
    
    func setHealthContextSendPreference(_ preference: HealthContextSendPreference) {
        healthContextSendPreference = preference
        aiSettings.healthContextSendPreference = preference
        KBLog.settings.kbInfo("AISettingsVM healthContextSendPreference=\(preference.rawValue)")
        Task {
            do {
                try await notifications.setHealthContextSendPreference(preference)
            } catch {
                infoText = error.localizedDescription
                KBLog.settings.kbError("AISettingsVM healthContext sync failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Usage
    
    func loadUsage() async {
        loadingUsage = true
        defer { loadingUsage = false }
        usage = try? await AIService.shared.fetchUsage()
    }
}
