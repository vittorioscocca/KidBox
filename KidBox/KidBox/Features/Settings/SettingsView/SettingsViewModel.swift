//
//  SettingsViewModel.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
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
    @Published var notifyOnNewDocs: Bool = false
    @Published var infoText: String? = nil
    @Published var isLoading: Bool = false
    @Published var notifyOnNewMessages: Bool = true
    @Published var notifyOnLocationSharing: Bool = false
    @Published var notifyOnTodos: Bool = true
    @Published var notifyOnNewGroceryItem: Bool = true   // ← NEW
    @Published var notifyOnNewNote: Bool = true          // ← NEW
    
    // MARK: - Dependencies
    private let notifications = NotificationManager.shared
    
    // MARK: - Local cache keys
    private enum LocalKeys {
        static let notifyOnNewDocs          = "kb_notifyOnNewDocs"
        static let notifyOnNewMessages      = "kb_notifyOnNewMessages"
        static let notifyOnLocationSharing  = "kb_notifyOnLocationSharing"
        static let notifyOnTodos            = "kb_notifyOnTodos"
        static let notifyOnNewGroceryItem   = "kb_notifyOnNewGroceryItem"   // ← NEW
        static let notifyOnNewNote          = "kb_notifyOnNewNote"          // ← NEW
    }
    
    // MARK: - Init
    init() {
        let cached = UserDefaults.standard.bool(forKey: LocalKeys.notifyOnNewDocs)
        self.notifyOnNewDocs = cached
        KBLog.settings.debug("SettingsVM init cached notifyOnNewDocs=\(cached, privacy: .public)")
        
        let cachedChat = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewMessages) as? Bool ?? true
        self.notifyOnNewMessages = cachedChat
        KBLog.settings.debug("SettingsVM init cached notifyOnNewMessages=\(cachedChat, privacy: .public)")
        
        let cachedLoc = UserDefaults.standard.object(forKey: LocalKeys.notifyOnLocationSharing) as? Bool ?? false
        self.notifyOnLocationSharing = cachedLoc
        KBLog.settings.debug("SettingsVM init cached notifyOnLocationSharing=\(cachedLoc, privacy: .public)")
        
        let cachedTodos = UserDefaults.standard.object(forKey: LocalKeys.notifyOnTodos) as? Bool ?? true
        self.notifyOnTodos = cachedTodos
        KBLog.settings.debug("SettingsVM init cached notifyOnTodos=\(cachedTodos, privacy: .public)")
        
        // ← NEW
        let cachedGrocery = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewGroceryItem) as? Bool ?? true
        self.notifyOnNewGroceryItem = cachedGrocery
        KBLog.settings.debug("SettingsVM init cached notifyOnNewGroceryItem=\(cachedGrocery, privacy: .public)")
        
        let cachedNote = UserDefaults.standard.object(forKey: LocalKeys.notifyOnNewNote) as? Bool ?? true
        self.notifyOnNewNote = cachedNote
        KBLog.settings.debug("SettingsVM init cached notifyOnNewNote=\(cachedNote, privacy: .public)")
    }
    
    // MARK: - Load
    func load() {
        KBLog.settings.debug("SettingsVM load requested")
        
        let cached = UserDefaults.standard.bool(forKey: LocalKeys.notifyOnNewDocs)
        if notifyOnNewDocs != cached {
            notifyOnNewDocs = cached
        }
        
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            
            infoText = nil
            
            await notifications.refreshAuthorizationStatus()
            
            // Docs
            let remoteValue = await notifications.fetchNotifyOnNewDocsPreference()
            if notifyOnNewDocs != remoteValue { notifyOnNewDocs = remoteValue }
            UserDefaults.standard.set(remoteValue, forKey: LocalKeys.notifyOnNewDocs)
            
            // Chat
            let remoteChat = await notifications.fetchNotifyOnNewMessagesPreference()
            if notifyOnNewMessages != remoteChat { notifyOnNewMessages = remoteChat }
            UserDefaults.standard.set(remoteChat, forKey: LocalKeys.notifyOnNewMessages)
            
            // Todos
            let remoteTodo = await notifications.fetchNotifyOnTodoAssignedPreference()
            if notifyOnTodos != remoteTodo { notifyOnTodos = remoteTodo }
            UserDefaults.standard.set(remoteTodo, forKey: LocalKeys.notifyOnTodos)
            
            // Shopping  ← NEW
            let remoteGrocery = await notifications.fetchNotifyOnNewGroceryItemPreference()
            KBLog.settings.info("SettingsVM fetch remote grocery pref=\(remoteGrocery, privacy: .public)")
            if notifyOnNewGroceryItem != remoteGrocery { notifyOnNewGroceryItem = remoteGrocery }
            UserDefaults.standard.set(remoteGrocery, forKey: LocalKeys.notifyOnNewGroceryItem)
            
            // Notes  ← NEW
            let remoteNote = await notifications.fetchNotifyOnNewNotePreference()
            KBLog.settings.info("SettingsVM fetch remote note pref=\(remoteNote, privacy: .public)")
            if notifyOnNewNote != remoteNote { notifyOnNewNote = remoteNote }
            UserDefaults.standard.set(remoteNote, forKey: LocalKeys.notifyOnNewNote)
        }
    }
    
    // MARK: - User actions (existing)
    
    func toggleNotifyOnNewDocs(_ enabled: Bool) {
        KBLog.settings.info("SettingsVM toggleNotifyOnNewDocs enabled=\(enabled, privacy: .public)")
        infoText = nil
        notifyOnNewDocs = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewDocs)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewDocs(enabled)
                infoText = enabled ? "Notifiche attive." : "Notifiche disattivate."
            } catch {
                notifyOnNewDocs = false
                UserDefaults.standard.set(false, forKey: LocalKeys.notifyOnNewDocs)
                infoText = error.localizedDescription
                KBLog.settings.error("SettingsVM setNotifyOnNewDocs failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func toggleNotifyOnNewMessages(_ enabled: Bool) {
        notifyOnNewMessages = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewMessages)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewMessages(enabled)
                infoText = enabled ? "Notifiche chat attive." : "Notifiche chat disattivate."
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
                infoText = enabled ? "Notifiche posizione attive." : "Notifiche posizione disattivate."
            } catch {
                notifyOnLocationSharing = false
                UserDefaults.standard.set(false, forKey: LocalKeys.notifyOnLocationSharing)
                infoText = error.localizedDescription
                KBLog.settings.error("SettingsVM setNotifyOnLocationSharing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func toggleNotifyOnTodos(_ enabled: Bool) {
        notifyOnTodos = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnTodos)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnTodoAssigned(enabled)
                infoText = enabled ? "Notifiche Todo attive." : "Notifiche Todo disattivate."
            } catch {
                notifyOnTodos = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnTodos)
                infoText = error.localizedDescription
            }
        }
    }
    
    // MARK: - Shopping toggle  ← NEW
    
    func toggleNotifyOnNewGroceryItem(_ enabled: Bool) {
        KBLog.settings.info("SettingsVM toggleNotifyOnNewGroceryItem enabled=\(enabled, privacy: .public)")
        notifyOnNewGroceryItem = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewGroceryItem)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewGroceryItem(enabled)
                infoText = enabled ? "Notifiche spesa attive." : "Notifiche spesa disattivate."
            } catch {
                notifyOnNewGroceryItem = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewGroceryItem)
                infoText = error.localizedDescription
                KBLog.settings.error("SettingsVM setNotifyOnNewGroceryItem failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    // MARK: - Notes toggle  ← NEW
    
    func toggleNotifyOnNewNote(_ enabled: Bool) {
        KBLog.settings.info("SettingsVM toggleNotifyOnNewNote enabled=\(enabled, privacy: .public)")
        notifyOnNewNote = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewNote)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewNote(enabled)
                infoText = enabled ? "Notifiche note attive." : "Notifiche note disattivate."
            } catch {
                notifyOnNewNote = true
                UserDefaults.standard.set(true, forKey: LocalKeys.notifyOnNewNote)
                infoText = error.localizedDescription
                KBLog.settings.error("SettingsVM setNotifyOnNewNote failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
