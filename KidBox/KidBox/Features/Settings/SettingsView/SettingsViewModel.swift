//
//  SettingsViewModel.swift
//  KidBox
//

import Foundation
import Combine
import FirebaseAuth
import OSLog

/// ViewModel for `SettingsView`.
///
/// Responsibilities:
/// - Provide a stable UX by reading cached preferences immediately.
/// - Sync preferences with a remote source of truth via `NotificationManager`.
/// - Persist the latest known value locally in `UserDefaults`.
@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: - Published UI state
    // Tutte le preferenze di notifica nascono ATTIVE, coerenti con il server
    // (`getUserTokensIfEnabled`: preferenza assente = attiva). Un default a
    // `false` qui mostrerebbe spento ciò che invece sta arrivando.
    @Published var notifyOnNewDocs: Bool = true
    @Published var infoText: String? = nil
    @Published var isLoading: Bool = false
    @Published var notifyOnNewMessages: Bool = true
    @Published var notifyOnLocationSharing: Bool = true
    @Published var notifyOnTodos: Bool = true
    @Published var notifyOnNewGroceryItem: Bool = true
    @Published var notifyOnNewNote: Bool = true
    @Published var notifyOnNewExpense: Bool = true
    @Published var notifyOnNewWalletTicket: Bool = true
    @Published var notifyOnWalletReminder: Bool = true
    @Published var audioTranscriptionEnabled: Bool = true
    @Published var appearanceMode: AppearanceMode = .system
    
    // MARK: - Dependencies
    private let notifications = NotificationManager.shared
    
    // MARK: - Local cache keys
    private enum LocalKeys {
        static let notifyOnNewDocs          = "kb_notifyOnNewDocs"
        static let notifyOnNewMessages      = "kb_notifyOnNewMessages"
        static let notifyOnLocationSharing  = "kb_notifyOnLocationSharing"
        static let notifyOnTodos            = "kb_notifyOnTodos"
        static let notifyOnNewGroceryItem   = "kb_notifyOnNewGroceryItem"
        static let notifyOnNewNote          = "kb_notifyOnNewNote"
        static let notifyOnNewExpense       = "kb_notifyOnNewExpense"
        static let notifyOnNewWalletTicket  = "kb_notifyOnNewWalletTicket"
        static let notifyOnWalletReminder   = "kb_notifyOnWalletReminder"
        static let audioTranscriptionEnabled = "kb_audioTranscriptionEnabled"
        static let appearanceMode           = "kb_appearanceMode"
    }
    
    // MARK: - Init
    init() {
        // `bool(forKey:)` non distingue "mai scritta" da "false": userebbe
        // sempre `false` alla prima installazione. `object(forKey:)` sì.
        let cached = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewDocs) as? Bool ?? true
        self.notifyOnNewDocs = cached
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnNewDocs=\(cached)")
        
        let cachedChat = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewMessages) as? Bool ?? true
        self.notifyOnNewMessages = cachedChat
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnNewMessages=\(cachedChat)")
        
        let cachedLoc = UserDefaults.standard.object(forKey: LocalKeys.notifyOnLocationSharing) as? Bool ?? true
        self.notifyOnLocationSharing = cachedLoc
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnLocationSharing=\(cachedLoc)")
        
        let cachedTodos = UserDefaults.standard.object(forKey: LocalKeys.notifyOnTodos) as? Bool ?? true
        self.notifyOnTodos = cachedTodos
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnTodos=\(cachedTodos)")
        
        let cachedGrocery = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewGroceryItem) as? Bool ?? true
        self.notifyOnNewGroceryItem = cachedGrocery
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnNewGroceryItem=\(cachedGrocery)")
        
        let cachedNote = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewNote) as? Bool ?? true
        self.notifyOnNewNote = cachedNote
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnNewNote=\(cachedNote)")
        
        let cachedExpense = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewExpense) as? Bool ?? true
        self.notifyOnNewExpense = cachedExpense
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnNewExpense=\(cachedExpense)")

        let cachedWalletNew = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewWalletTicket) as? Bool ?? true
        self.notifyOnNewWalletTicket = cachedWalletNew
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnNewWalletTicket=\(cachedWalletNew)")

        let cachedWalletReminder = UserDefaults.standard.object(forKey: LocalKeys.notifyOnWalletReminder) as? Bool ?? true
        self.notifyOnWalletReminder = cachedWalletReminder
        KBLog.settings.kbDebug("SettingsVM init cached notifyOnWalletReminder=\(cachedWalletReminder)")

        let cachedTranscription = UserDefaults.standard.object(forKey: LocalKeys.audioTranscriptionEnabled) as? Bool ?? true
        self.audioTranscriptionEnabled = cachedTranscription
        KBLog.settings.kbDebug("SettingsVM init cached audioTranscriptionEnabled=\(cachedTranscription)")
        
        let rawAppearance = UserDefaults.standard.string(forKey: LocalKeys.appearanceMode) ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: rawAppearance) ?? .system
        KBLog.settings.kbDebug("SettingsVM init cached appearanceMode=\(rawAppearance)")
    }
    
    // MARK: - Load
    func load() {
        KBLog.settings.kbDebug("SettingsVM load requested")
        
        let cached = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewDocs) as? Bool ?? true
        if notifyOnNewDocs != cached { notifyOnNewDocs = cached }
        
        let cachedTranscription = UserDefaults.standard.object(forKey: LocalKeys.audioTranscriptionEnabled) as? Bool ?? true
        if audioTranscriptionEnabled != cachedTranscription { audioTranscriptionEnabled = cachedTranscription }
        
        let rawAppearance = UserDefaults.standard.string(forKey: LocalKeys.appearanceMode) ?? AppearanceMode.system.rawValue
        let cachedAppearance = AppearanceMode(rawValue: rawAppearance) ?? .system
        if appearanceMode != cachedAppearance { appearanceMode = cachedAppearance }
        
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            
            infoText = nil
            
            await notifications.refreshAuthorizationStatus()
            
            let remoteValue = await notifications.fetchNotifyOnNewDocsPreference()
            if notifyOnNewDocs != remoteValue { notifyOnNewDocs = remoteValue }
            UserDefaults.standard.set(remoteValue, forKey: LocalKeys.notifyOnNewDocs)
            
            let remoteChat = await notifications.fetchNotifyOnNewMessagesPreference()
            if notifyOnNewMessages != remoteChat { notifyOnNewMessages = remoteChat }
            UserDefaults.standard.set(remoteChat, forKey: LocalKeys.notifyOnNewMessages)
            
            let remoteTodo = await notifications.fetchNotifyOnTodoAssignedPreference()
            if notifyOnTodos != remoteTodo { notifyOnTodos = remoteTodo }
            UserDefaults.standard.set(remoteTodo, forKey: LocalKeys.notifyOnTodos)
            
            let remoteGrocery = await notifications.fetchNotifyOnNewGroceryItemPreference()
            KBLog.settings.kbInfo("SettingsVM fetch remote grocery pref=\(remoteGrocery)")
            if notifyOnNewGroceryItem != remoteGrocery { notifyOnNewGroceryItem = remoteGrocery }
            UserDefaults.standard.set(remoteGrocery, forKey: LocalKeys.notifyOnNewGroceryItem)
            
            let remoteNote = await notifications.fetchNotifyOnNewNotePreference()
            KBLog.settings.kbInfo("SettingsVM fetch remote note pref=\(remoteNote)")
            if notifyOnNewNote != remoteNote { notifyOnNewNote = remoteNote }
            UserDefaults.standard.set(remoteNote, forKey: LocalKeys.notifyOnNewNote)
            
            let remoteExpense = await notifications.fetchNotifyOnNewExpensePreference()
            KBLog.settings.kbInfo("SettingsVM fetch remote expense pref=\(remoteExpense)")
            if notifyOnNewExpense != remoteExpense { notifyOnNewExpense = remoteExpense }
            UserDefaults.standard.set(remoteExpense, forKey: LocalKeys.notifyOnNewExpense)

            let remoteWalletNew = await notifications.fetchNotifyOnNewWalletTicketPreference()
            KBLog.settings.kbInfo("SettingsVM fetch remote walletNew pref=\(remoteWalletNew)")
            if notifyOnNewWalletTicket != remoteWalletNew { notifyOnNewWalletTicket = remoteWalletNew }
            UserDefaults.standard.set(remoteWalletNew, forKey: LocalKeys.notifyOnNewWalletTicket)

            let remoteWalletReminder = await notifications.fetchNotifyOnWalletReminderPreference()
            KBLog.settings.kbInfo("SettingsVM fetch remote walletReminder pref=\(remoteWalletReminder)")
            if notifyOnWalletReminder != remoteWalletReminder { notifyOnWalletReminder = remoteWalletReminder }
            UserDefaults.standard.set(remoteWalletReminder, forKey: LocalKeys.notifyOnWalletReminder)
        }
    }
    
    // MARK: - User actions
    
    func toggleNotifyOnNewDocs(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleNotifyOnNewDocs enabled=\(enabled)")
        infoText = nil
        notifyOnNewDocs = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewDocs)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewDocs(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche attive.", comment: "") : NSLocalizedString("Notifiche disattivate.", comment: "")
            } catch {
                notifyOnNewDocs = false
                UserDefaults.standard.set(false, forKey: LocalKeys.notifyOnNewDocs)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnNewDocs failed: \(error.localizedDescription)")
            }
        }
    }
    
    func toggleNotifyOnNewMessages(_ enabled: Bool) {
        notifyOnNewMessages = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewMessages)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewMessages(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche chat attive.", comment: "") : NSLocalizedString("Notifiche chat disattivate.", comment: "")
            } catch {
                notifyOnNewMessages = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewMessages)
                infoText = error.localizedDescription
            }
        }
    }
    
    func toggleNotifyOnLocationSharing(_ enabled: Bool) {
        notifyOnLocationSharing = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnLocationSharing)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnLocationSharing(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche posizione attive.", comment: "") : NSLocalizedString("Notifiche posizione disattivate.", comment: "")
            } catch {
                notifyOnLocationSharing = false
                UserDefaults.standard.set(false, forKey: LocalKeys.notifyOnLocationSharing)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnLocationSharing failed: \(error.localizedDescription)")
            }
        }
    }
    
    func toggleNotifyOnTodos(_ enabled: Bool) {
        notifyOnTodos = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnTodos)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnTodoAssigned(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche Todo attive.", comment: "") : NSLocalizedString("Notifiche Todo disattivate.", comment: "")
            } catch {
                notifyOnTodos = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnTodos)
                infoText = error.localizedDescription
            }
        }
    }
    
    // MARK: - Shopping toggle
    
    func toggleNotifyOnNewGroceryItem(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleNotifyOnNewGroceryItem enabled=\(enabled)")
        notifyOnNewGroceryItem = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewGroceryItem)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewGroceryItem(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche spesa attive.", comment: "") : NSLocalizedString("Notifiche spesa disattivate.", comment: "")
            } catch {
                notifyOnNewGroceryItem = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewGroceryItem)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnNewGroceryItem failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Notes toggle
    
    func toggleNotifyOnNewNote(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleNotifyOnNewNote enabled=\(enabled)")
        notifyOnNewNote = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewNote)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewNote(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche note attive.", comment: "") : NSLocalizedString("Notifiche note disattivate.", comment: "")
            } catch {
                notifyOnNewNote = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewNote)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnNewNote failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Expense toggle
    
    func toggleNotifyOnNewExpense(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleNotifyOnNewExpense enabled=\(enabled)")
        notifyOnNewExpense = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewExpense)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewExpense(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche spese attive.", comment: "") : NSLocalizedString("Notifiche spese disattivate.", comment: "")
            } catch {
                notifyOnNewExpense = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewExpense)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnNewExpense failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Wallet toggles

    func toggleNotifyOnNewWalletTicket(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleNotifyOnNewWalletTicket enabled=\(enabled)")
        notifyOnNewWalletTicket = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewWalletTicket)

        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewWalletTicket(enabled)
                infoText = enabled ? NSLocalizedString("Notifiche Wallet attive.", comment: "") : NSLocalizedString("Notifiche Wallet disattivate.", comment: "")
            } catch {
                notifyOnNewWalletTicket = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewWalletTicket)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnNewWalletTicket failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleNotifyOnWalletReminder(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleNotifyOnWalletReminder enabled=\(enabled)")
        notifyOnWalletReminder = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnWalletReminder)

        Task { @MainActor in
            do {
                try await notifications.setNotifyOnWalletReminder(enabled)
                infoText = enabled ? NSLocalizedString("Promemoria Wallet attivi.", comment: "") : NSLocalizedString("Promemoria Wallet disattivati.", comment: "")

                // Disabilitato → cancella anche le notifiche locali già schedulate.
                // (Le push schedulate dalla CF rispettano già la preferenza remota.)
                if !enabled {
                    await WalletReminderService.shared.cancelAllReminders()
                }
            } catch {
                notifyOnWalletReminder = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnWalletReminder)
                infoText = error.localizedDescription
                KBLog.settings.kbError("SettingsVM setNotifyOnWalletReminder failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Audio transcription toggle
    
    /// Salva la preferenza solo in locale (UserDefaults).
    /// Non richiede chiamate di rete — la preferenza è letta direttamente
    /// da `ChatViewModel` prima di avviare la trascrizione.
    func toggleAudioTranscription(_ enabled: Bool) {
        KBLog.settings.kbInfo("SettingsVM toggleAudioTranscription enabled=\(enabled)")
        audioTranscriptionEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.audioTranscriptionEnabled)
        infoText = enabled ? NSLocalizedString("Trascrizione vocale attiva.", comment: "") : NSLocalizedString("Trascrizione vocale disattivata.", comment: "")
    }
    
    // MARK: - Appearance toggle
    
    /// Salva il tema scelto in UserDefaults e lo propaga al coordinator
    /// che applica `.preferredColorScheme` alla root dell'app.
    func setAppearanceMode(_ mode: AppearanceMode, coordinator: AppCoordinator) {
        KBLog.settings.kbInfo("SettingsVM setAppearanceMode mode=\(mode.rawValue)")
        appearanceMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: LocalKeys.appearanceMode)
        coordinator.setAppearanceMode(mode)
        infoText = String(format: NSLocalizedString("Tema impostato su %@.", comment: "Theme changed info"), mode.label)
    }
}
