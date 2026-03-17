//
//  NotificationManager.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
//

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
        case chat(familyId: String)
        case familyLocation(familyId: String)
        case todo(familyId: String, childId: String, listId: String, todoId: String)
        case groceryItem(familyId: String, itemId: String)
        case note(familyId: String, noteId: String)
        case calendarEvent(familyId: String, eventId: String)
        case pediatricVisit(familyId: String, childId: String, visitId: String)
        case treatmentReminder(familyId: String, childId: String, treatmentId: String)
        case examReminder(familyId: String, childId: String, examId: String)
    }
    
    // MARK: - Deep Link Handling
    
    /// Parses FCM payload (o userInfo di notifica locale) e imposta il pending deep link.
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
            
        } else if type == "new_chat_message" {
            guard let familyId = userInfo["familyId"] as? String else { return }
            pendingDeepLink = .chat(familyId: familyId)
            
        } else if type == "location_sharing_started" || type == "location_sharing_stopped" {
            guard let familyId = userInfo["familyId"] as? String else {
                KBLog.auth.kbError("Invalid location payload (missing familyId)")
                return
            }
            pendingDeepLink = .familyLocation(familyId: familyId)
            KBLog.auth.kbInfo("DeepLink set for familyLocation familyId=\(familyId)")
            
        } else if type == "todo_assigned" || type == "todo_reassigned" || type == "todo_due_changed" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let childId  = userInfo["childId"]  as? String,
                let listId   = userInfo["listId"]   as? String,
                let todoId   = userInfo["todoId"]   as? String
            else {
                KBLog.auth.kbError("Invalid todo payload (missing ids)")
                return
            }
            pendingDeepLink = .todo(familyId: familyId, childId: childId, listId: listId, todoId: todoId)
            KBLog.auth.kbInfo("DeepLink set for todo familyId=\(familyId) listId=\(listId) todoId=\(todoId)")
            
        } else if type == "new_grocery_item" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let itemId   = userInfo["itemId"]   as? String
            else {
                KBLog.auth.kbError("Invalid new_grocery_item payload")
                return
            }
            pendingDeepLink = .groceryItem(familyId: familyId, itemId: itemId)
            KBLog.auth.kbInfo("DeepLink set for groceryItem familyId=\(familyId) itemId=\(itemId)")
            
        } else if type == "new_note" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let noteId   = userInfo["noteId"]   as? String
            else {
                KBLog.auth.kbError("Invalid new_note payload")
                return
            }
            pendingDeepLink = .note(familyId: familyId, noteId: noteId)
            KBLog.auth.kbInfo("DeepLink set for note familyId=\(familyId) noteId=\(noteId)")
            
        } else if type == "new_calendar_event" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let eventId  = userInfo["eventId"]  as? String
            else {
                KBLog.auth.kbError("Invalid new_calendar_event payload")
                return
            }
            pendingDeepLink = .calendarEvent(familyId: familyId, eventId: eventId)
            KBLog.auth.kbInfo("DeepLink set for calendarEvent familyId=\(familyId) eventId=\(eventId)")
            
        } else if type == "visit_reminder" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let childId  = userInfo["childId"]  as? String,
                let visitId  = userInfo["visitId"]  as? String
            else {
                KBLog.auth.kbError("Invalid visit_reminder payload")
                return
            }
            pendingDeepLink = .pediatricVisit(familyId: familyId, childId: childId, visitId: visitId)
            KBLog.auth.kbInfo("DeepLink set for pediatricVisit visitId=\(visitId)")
            
        } else if type == "treatment_reminder" {
            guard
                let familyId    = userInfo["familyId"]    as? String,
                let childId     = userInfo["childId"]     as? String,
                let treatmentId = userInfo["treatmentId"] as? String
            else {
                KBLog.auth.kbError("Invalid treatment_reminder payload")
                return
            }
            pendingDeepLink = .treatmentReminder(familyId: familyId, childId: childId, treatmentId: treatmentId)
            KBLog.auth.kbInfo("DeepLink set for treatmentReminder treatmentId=\(treatmentId)")
            
        } else if type == "exam_reminder" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let childId  = userInfo["childId"]  as? String,
                let examId   = userInfo["examId"]   as? String
            else {
                KBLog.auth.kbError("Invalid exam_reminder payload")
                return
            }
            pendingDeepLink = .examReminder(familyId: familyId, childId: childId, examId: examId)
            KBLog.auth.kbInfo("DeepLink set for examReminder examId=\(examId)")
        }
    }
    
    func fetchNotifyOnTodoAssignedPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnTodoAssigned"] as? Bool {
                return v
            }
            return true
        } catch {
            return true
        }
    }
    
    func setNotifyOnTodoAssigned(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnTodoAssigned": enabled]
        ], merge: true)
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }
    
    // MARK: - Shopping notification preference
    
    func fetchNotifyOnNewGroceryItemPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewGroceryItem"] as? Bool {
                return v
            }
            return true   // default ON
        } catch {
            return true
        }
    }
    
    func setNotifyOnNewGroceryItem(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnNewGroceryItem": enabled]
        ], merge: true)
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }
    
    // MARK: - Notes notification preference
    
    func fetchNotifyOnNewNotePreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewNote"] as? Bool {
                return v
            }
            return true   // default ON
        } catch {
            return true
        }
    }
    
    func setNotifyOnNewNote(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnNewNote": enabled]
        ], merge: true)
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }
    
    
    // MARK: - Calendar notification preference
    
    func fetchNotifyOnNewCalendarEventPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewCalendarEvent"] as? Bool {
                return v
            }
            return true   // default ON
        } catch {
            return true
        }
    }
    
    func setNotifyOnNewCalendarEvent(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnNewCalendarEvent": enabled]
        ], merge: true)
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }
    
    // MARK: - Existing preferences (unchanged)
    
    /// Clears current deep link after navigation is handled.
    func consumeDeepLink() {
        KBLog.auth.kbDebug("Consuming deep link")
        pendingDeepLink = nil
    }
    
    /// Imposta direttamente un deep link (es. da notifiche locali).
    /// Usato dall'AppDelegate dopo aver letto lo userInfo della notifica locale.
    func setDeepLink(_ link: DeepLink) {
        pendingDeepLink = link
    }
    
    // MARK: - Authorization
    
    func refreshAuthorizationStatus() async {
        KBLog.auth.kbDebug("Refreshing authorization status")
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    // MARK: - Preferences (existing)
    
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
    
    func fetchNotifyOnNewMessagesPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewMessages"] as? Bool {
                return v
            }
            return true
        } catch {
            return true
        }
    }
    
    func setNotifyOnNewMessages(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnNewMessages": enabled]
        ], merge: true)
    }
    
    func fetchNotifyOnLocationSharingPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnLocationSharing"] as? Bool {
                return v
            }
            return false
        } catch {
            return false
        }
    }
    
    func setNotifyOnLocationSharing(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnLocationSharing": enabled]
        ], merge: true)
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }
    
    // MARK: - APNs
    
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

// MARK: - NotificationManager+AI.swift
//  KidBox
//
//  Estensione di NotificationManager per la preferenza AI.
//  Stesso pattern di notifyOnNewDocs / notifyOnNewNote.
//
//  Firestore path: users/{uid}
//  Campo:          notificationPrefs.aiEnabled  (Bool, default false)
//

extension NotificationManager {
    
    // MARK: - Fetch
    
    func fetchAIEnabledPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["aiEnabled"] as? Bool {
                return v
            }
            return false // default OFF — l'utente deve attivare esplicitamente
        } catch {
            return false
        }
    }
    
    // MARK: - Set
    
    func setAIEnabled(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["aiEnabled": enabled]
        ], merge: true)
        
        KBLog.settings.kbInfo("AI enabled preference saved to Firestore: \(enabled)")
    }
}
