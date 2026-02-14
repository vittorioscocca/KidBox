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
///
/// Logging strategy:
/// - Log *events* (load start/end, remote fetch, user toggle, success/failure).
/// - Avoid noisy logs on every minor state assignment.
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
        // Initialize immediately from local cache for a stable UX.
        let cached = UserDefaults.standard.bool(forKey: LocalKeys.notifyOnNewDocs)
        self.notifyOnNewDocs = cached
        KBLog.settings.debug("SettingsVM init cached notifyOnNewDocs=\(cached, privacy: .public)")
    }
    
    // MARK: - Load (called by view .task / onAppear)
    func load() {
        KBLog.settings.debug("SettingsVM load requested")
        
        // 1) Refresh from local cache (cheap, immediate).
        let cached = UserDefaults.standard.bool(forKey: LocalKeys.notifyOnNewDocs)
        if notifyOnNewDocs != cached {
            notifyOnNewDocs = cached
            KBLog.settings.debug("SettingsVM applied cached notifyOnNewDocs=\(cached, privacy: .public)")
        }
        
        // 2) Sync with remote source of truth.
        Task { @MainActor in
            isLoading = true
            defer { isLoading = false }
            
            infoText = nil
            
            KBLog.settings.debug("SettingsVM refreshAuthorizationStatus start")
            await notifications.refreshAuthorizationStatus()
            KBLog.settings.debug("SettingsVM refreshAuthorizationStatus end")
            
            KBLog.settings.debug("SettingsVM fetch remote preference start")
            let remoteValue = await notifications.fetchNotifyOnNewDocsPreference()
            KBLog.settings.info("SettingsVM fetch remote preference done value=\(remoteValue, privacy: .public)")
            
            // Update UI only if it actually changed.
            if notifyOnNewDocs != remoteValue {
                notifyOnNewDocs = remoteValue
                KBLog.settings.debug("SettingsVM applied remote notifyOnNewDocs=\(remoteValue, privacy: .public)")
            }
            
            // Update local cache.
            UserDefaults.standard.set(remoteValue, forKey: LocalKeys.notifyOnNewDocs)
            KBLog.settings.debug("SettingsVM cached remote notifyOnNewDocs=\(remoteValue, privacy: .public)")
        }
    }
    
    // MARK: - User action
    func toggleNotifyOnNewDocs(_ enabled: Bool) {
        KBLog.settings.info("SettingsVM toggleNotifyOnNewDocs requested enabled=\(enabled, privacy: .public)")
        infoText = nil
        
        // Immediate UX + immediate local cache update.
        notifyOnNewDocs = enabled
        UserDefaults.standard.set(enabled, forKey: LocalKeys.notifyOnNewDocs)
        KBLog.settings.debug("SettingsVM optimistic set + cached enabled=\(enabled, privacy: .public)")
        
        Task { @MainActor in
            do {
                try await notifications.setNotifyOnNewDocs(enabled)
                infoText = enabled ? "Notifiche attive." : "Notifiche disattivate."
                KBLog.settings.info("SettingsVM setNotifyOnNewDocs OK enabled=\(enabled, privacy: .public)")
            } catch {
                // Rollback local + UI. (Keeps your existing logic: rollback to false)
                notifyOnNewDocs = false
                UserDefaults.standard.set(false, forKey: LocalKeys.notifyOnNewDocs)
                infoText = error.localizedDescription
                KBLog.settings.error("SettingsVM setNotifyOnNewDocs failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
