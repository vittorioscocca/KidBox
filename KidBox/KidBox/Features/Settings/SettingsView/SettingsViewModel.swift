//
//  SettingsViewModel.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
//

import Foundation
import Combine
import FirebaseAuth

import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: - Published UI state
    @Published var notifyOnNewDocs: Bool = false
    @Published var infoText: String? = nil
    @Published var isLoading: Bool = false
    
    // MARK: - Dependencies
    private let notifications = NotificationManager.shared
    
    // MARK: - Local cache keys
    private enum LocalKeys {
        static let notifyOnNewDocs = "kb_notifyOnNewDocs"   // namespaced
    }
    
    // MARK: - Init
    init() {
        // ✅ inizializza subito da locale (UX stabile)
        self.notifyOnNewDocs = UserDefaults.standard.bool(forKey: LocalKeys.notifyOnNewDocs)
    }
    
    // MARK: - Load (call onAppear)
    func load() {
        // ✅ 1) subito da locale
        let cached = UserDefaults.standard.bool(forKey: LocalKeys.notifyOnNewDocs)
        if notifyOnNewDocs != cached {
            notifyOnNewDocs = cached
        }
        
        // ✅ 2) sync con remoto (source of truth)
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            
            infoText = nil
            await notifications.refreshAuthorizationStatus()
            
            let remoteValue = await notifications.fetchNotifyOnNewDocsPreference()
            
            // aggiorna UI solo se cambia davvero
            if notifyOnNewDocs != remoteValue {
                notifyOnNewDocs = remoteValue
            }
            
            // aggiorna cache
            UserDefaults.standard.set(remoteValue, forKey: LocalKeys.notifyOnNewDocs)
        }
    }
    
    // MARK: - User action
    func toggleNotifyOnNewDocs(_ enabled: Bool) {
        infoText = nil
        
        // ✅ UX immediata + cache locale immediata
        notifyOnNewDocs = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewDocs)
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewDocs(enabled)
                infoText = enabled ? "Notifiche attive." : "Notifiche disattivate."
            } catch {
                // ❌ rollback locale + UI
                notifyOnNewDocs = false
                UserDefaults.standard.set(false, forKey: LocalKeys.notifyOnNewDocs)
                infoText = error.localizedDescription
            }
        }
    }
}
