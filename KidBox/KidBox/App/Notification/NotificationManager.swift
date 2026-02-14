//
//  NotificationManager.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
//

//
//  NotificationManager.swift
//  KidBox
//
//  Centralized push notification manager.
//
//  Responsibilities:
//  - Manage notification authorization state
//  - Persist FCM tokens
//  - Handle APNs token bridging
//  - Read/write user notification preferences
//  - Handle deep link routing from push payload
//
//  NOTE:
//  - Runs on MainActor
//  - Avoid logging PII
//

import Foundation
import UserNotifications
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import Combine


@MainActor
final class NotificationManager: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = NotificationManager()
    
    // MARK: - Published State
    
    /// Current system notification authorization status.
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// Pending deep link triggered by push tap.
    @Published var pendingDeepLink: DeepLink? = nil
    
    // MARK: - Private
    
    private let db = Firestore.firestore()
    
    // MARK: - Deep Link
    
    /// Supported deep links triggered from push notifications.
    enum DeepLink: Equatable {
        case document(familyId: String, docId: String)
    }
    
    // MARK: - Deep Link Handling
    
    /// Parses FCM payload and sets pending deep link if needed.
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        KBLog.auth.kbDebug("Handling push userInfo")
        
        let type = userInfo["type"] as? String
        
        if type == "new_document" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let docId = userInfo["docId"] as? String
            else {
                KBLog.auth.kbError("Invalid new_document payload")
                return
            }
            
            pendingDeepLink = .document(familyId: familyId, docId: docId)
            KBLog.auth.kbInfo("DeepLink set for document")
        }
    }
    
    /// Clears current deep link after navigation is handled.
    func consumeDeepLink() {
        KBLog.auth.kbDebug("Consuming deep link")
        pendingDeepLink = nil
    }
    
    // MARK: - Authorization
    
    /// Refreshes notification authorization status from system settings.
    func refreshAuthorizationStatus() async {
        KBLog.auth.kbDebug("Refreshing authorization status")
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    // MARK: - Preferences
    
    /// Reads `notifyOnNewDocs` preference from Firestore.
    func fetchNotifyOnNewDocsPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbDebug("No authenticated user while reading prefs")
            return false
        }
        
        KBLog.auth.kbDebug("Reading notification prefs")
        
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewDocs"] as? Bool {
                KBLog.auth.kbInfo("Preference read from map")
                return v
            }
            
            if let v = snap.get("notificationPrefs.notifyOnNewDocs") as? Bool {
                KBLog.auth.kbInfo("Preference read via field path")
                return v
            }
            
            if let v = snap.get(FieldPath(["notificationPrefs.notifyOnNewDocs"])) as? Bool {
                KBLog.auth.kbInfo("Preference read via literal dot field")
                return v
            }
            
            KBLog.auth.kbDebug("Preference not found, default false")
            return false
            
        } catch {
            KBLog.auth.kbError("Failed reading notification prefs: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - APNs
    
    /// Links APNs token with Firebase Messaging and persists FCM if available.
    func handleAPNSToken(_ deviceToken: Data) async {
        KBLog.auth.kbDebug("Handling APNs token")
        
        Messaging.messaging().apnsToken = deviceToken
        
        if let fcm = Messaging.messaging().fcmToken, !fcm.isEmpty {
            do {
                try await persistFCMToken(fcm)
                KBLog.auth.kbInfo("FCM token persisted after APNs registration")
            } catch {
                KBLog.auth.kbError("Persist FCM after APNs failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Toggle
    
    /// Updates notifyOnNewDocs preference and enables/disables push.
    func setNotifyOnNewDocs(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        KBLog.auth.kbInfo("Updating notifyOnNewDocs = \(enabled)")
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": [
                "notifyOnNewDocs": enabled
            ]
        ], merge: true)
        
        try? await db.collection("users").document(uid).updateData([
            FieldPath(["notificationPrefs.notifyOnNewDocs"]): FieldValue.delete()
        ])
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        } else {
            try await disablePushNotificationsForCurrentUser()
        }
    }
    
    // MARK: - Enable
    
    /// Requests permission and registers for remote notifications.
    func enablePushNotificationsForCurrentUser() async throws {
        KBLog.auth.kbDebug("Enabling push notifications")
        
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        
        await refreshAuthorizationStatus()
        
        guard granted else {
            KBLog.auth.kbError("Notification permission denied")
            throw NSError(domain: "KidBox", code: 1)
        }
        
        UIApplication.shared.registerForRemoteNotifications()
        KBLog.auth.kbInfo("registerForRemoteNotifications called")
        
        try await persistFCMTokenIfAvailable()
    }
    
    // MARK: - Disable
    
    /// Disables push notifications and removes FCM tokens.
    func disablePushNotificationsForCurrentUser() async throws {
        KBLog.auth.kbInfo("User disabled notifications")
        
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid)
            .setData(["notificationPrefs.notifyOnNewDocs": false], merge: true)
        
        let tokensRef = db.collection("users").document(uid).collection("fcmTokens")
        let snap = try await tokensRef.getDocuments()
        
        for d in snap.documents {
            try await d.reference.delete()
        }
        
        KBLog.auth.kbInfo("All FCM tokens removed")
    }
    
    // MARK: - Token Persistence
    
    /// Persists FCM token under users/{uid}/fcmTokens/{token}
    func persistFCMToken(_ token: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let ref = db.collection("users").document(uid)
            .collection("fcmTokens").document(token)
        
        try await ref.setData([
            "token": token,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
        
        KBLog.auth.kbDebug("FCM token stored")
    }
    
    /// Handles FCM token refresh.
    func handleFCMToken(_ token: String) async {
        do {
            try await persistFCMToken(token)
        } catch {
            KBLog.auth.kbError("Persist FCM token failed: \(error.localizedDescription)")
        }
    }
    
    private func persistFCMTokenIfAvailable() async throws {
        if let token = Messaging.messaging().fcmToken, !token.isEmpty {
            try await persistFCMToken(token)
        }
    }
}
