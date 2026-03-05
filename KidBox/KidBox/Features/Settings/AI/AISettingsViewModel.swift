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
    
    init() {
        // Leggi cache locale immediatamente (UX istantanea)
        self.aiEnabled    = UserDefaults.standard.bool(forKey: LocalKeys.aiEnabled)
        self.consentGiven = UserDefaults.standard.bool(forKey: LocalKeys.consentGiven)
        self.consentDate  = UserDefaults.standard.object(forKey: LocalKeys.consentDate) as? Date
        KBLog.settings.kbDebug("AISettingsVM init cached aiEnabled=\(self.aiEnabled)")
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
            
            KBLog.settings.kbInfo("AISettingsVM remote aiEnabled=\(remote)")
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
                infoText = enabled ? "Assistente AI attivato." : "Assistente AI disattivato."
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
    
    // MARK: - Usage
    
    func loadUsage() async {
        loadingUsage = true
        defer { loadingUsage = false }
        usage = try? await AIService.shared.fetchUsage()
    }
}
