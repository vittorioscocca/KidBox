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

    /// Testo briefing da mostrare come primo messaggio in PlanningAIChatView (tap notifica daily/weekly).
    private(set) var pendingPlanningInitialMessage: String?

    // MARK: - Private
    
    private let db = Firestore.firestore()
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var observedUid: String?

    override init() {
        super.init()
        observedUid = Auth.auth().currentUser?.uid
        startAuthStateObserver()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
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
        case expense(familyId: String, expenseId: String)
        case walletTicket(familyId: String, ticketId: String)
        /// Apre PlanningAIChatView — usato dalla sintesi settimanale AI
        case askExpert
        /// Notifica locale promemoria scadenza password (T-30 / T-7 / T-1).
        case passwordExpiry(familyId: String, entryId: String)
        /// Notifica locale aggregata dopo scan sicurezza password.
        case passwordSecurity(familyId: String)
    }

    // MARK: - Auth / FCM token ownership

    /// Keeps FCM token ownership aligned with the currently authenticated user.
    /// Without this, after account switch the same iOS device token can remain
    /// stored under the previous user and still receive pushes for old families.
    private func startAuthStateObserver() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let newUid = user?.uid
            Task { @MainActor in
                await self.handleAuthUserChange(newUid: newUid)
            }
        }
    }

    private func handleAuthUserChange(newUid: String?) async {
        let oldUid = observedUid
        guard oldUid != newUid else { return }
        observedUid = newUid

        KBLog.auth.kbInfo("NotificationManager auth change oldUid=\(oldUid ?? "nil") newUid=\(newUid ?? "nil")")

        let currentToken = Messaging.messaging().fcmToken
        if let oldUid, let token = currentToken, !token.isEmpty {
            do {
                try await removeFCMToken(token, forUid: oldUid)
                KBLog.auth.kbInfo("Removed current FCM token from previous user")
            } catch {
                KBLog.auth.kbError("Failed removing old user FCM token: \(error.localizedDescription)")
            }
        }

        // Force token rotation on account switch/logout so old-account delivery stops.
        do {
            try await deleteCurrentFCMToken()
            KBLog.auth.kbInfo("FCM token deleted for account switch")
        } catch {
            KBLog.auth.kbError("FCM token deletion failed on account switch: \(error.localizedDescription)")
        }

        guard newUid != nil else { return }

        do {
            let freshToken = try await requestFCMToken()
            try await persistFCMToken(freshToken)
            KBLog.auth.kbInfo("Fresh FCM token persisted for new user")
        } catch {
            KBLog.auth.kbError("Failed to persist fresh FCM token for new user: \(error.localizedDescription)")
        }
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
            
        } else if type == "todo_reminder" || type == "todo_assigned" || type == "todo_reassigned" || type == "todo_due_changed" {
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
            
        } else if type == "new_expense" {
            guard
                let familyId  = userInfo["familyId"]  as? String,
                let expenseId = userInfo["expenseId"] as? String
            else {
                KBLog.auth.kbError("Invalid new_expense payload")
                return
            }
            pendingDeepLink = .expense(familyId: familyId, expenseId: expenseId)
            KBLog.auth.kbInfo("DeepLink set for expense familyId=\(familyId) expenseId=\(expenseId)")
            
        } else if type == "weekly_summary" {
            pendingPlanningInitialMessage = (userInfo["fullText"] as? String)
                ?? WeeklySummaryService.shared.lastSummaryText
            pendingDeepLink = .askExpert
            KBLog.auth.kbInfo("DeepLink set for weeklySummary → askExpert")

        } else if type == "daily_briefing" {
            pendingPlanningInitialMessage = (userInfo["fullText"] as? String)
                ?? DailyBriefingService.shared.lastBriefingText
            pendingDeepLink = .askExpert
            KBLog.auth.kbInfo("DeepLink set for dailyBriefing → askExpert")

        } else if type == "health_pattern" {
            pendingPlanningInitialMessage = (userInfo["fullText"] as? String)
                ?? HealthPatternAnalyzerService.shared.lastInsightText
            pendingDeepLink = .askExpert
            KBLog.auth.kbInfo("DeepLink set for healthPattern → askExpert")

        } else if type == "new_wallet_ticket" || type == "wallet_ticket_reminder" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let ticketId = userInfo["ticketId"] as? String
            else {
                KBLog.auth.kbError("Invalid wallet ticket payload (missing ids)")
                return
            }
            pendingDeepLink = .walletTicket(familyId: familyId, ticketId: ticketId)
            KBLog.auth.kbInfo("DeepLink set for walletTicket familyId=\(familyId) ticketId=\(ticketId)")

        } else if type == "password_expiry_reminder" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let entryId = userInfo["entryId"] as? String
            else {
                KBLog.auth.kbError("Invalid password_expiry_reminder payload")
                return
            }
            pendingDeepLink = .passwordExpiry(familyId: familyId, entryId: entryId)
            KBLog.auth.kbInfo("DeepLink set for passwordExpiry entryId=\(entryId)")
        } else if type == "password_security_summary" {
            guard let familyId = userInfo["familyId"] as? String else {
                KBLog.auth.kbError("Invalid password_security_summary payload")
                return
            }
            pendingDeepLink = .passwordSecurity(familyId: familyId)
            KBLog.auth.kbInfo("DeepLink set for passwordSecurity familyId=\(familyId)")
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
    
    
    // MARK: - Expense notification preference
    
    func fetchNotifyOnNewExpensePreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewExpense"] as? Bool {
                return v
            }
            return true   // default ON
        } catch {
            return true
        }
    }
    
    func setNotifyOnNewExpense(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnNewExpense": enabled]
        ], merge: true)
        
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }
    
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

    // MARK: - Wallet notification preferences

    /// "Nuovo biglietto Wallet aggiunto": push triggerata dalla CF
    /// `notifyNewWalletTicket`. Default ON.
    func fetchNotifyOnNewWalletTicketPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewWalletTicket"] as? Bool {
                return v
            }
            return true   // default ON
        } catch {
            return true
        }
    }

    func setNotifyOnNewWalletTicket(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnNewWalletTicket": enabled]
        ], merge: true)

        if enabled {
            try await enablePushNotificationsForCurrentUser()
        }
    }

    /// Promemoria Wallet (T-24h, T-2h, ecc.) — sia push (CF schedulata
    /// `notifyUpcomingWalletTickets`) sia notifiche locali schedulate da
    /// `WalletReminderService`. Default ON.
    func fetchNotifyOnWalletReminderPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return true }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnWalletReminder"] as? Bool {
                return v
            }
            return true   // default ON
        } catch {
            return true
        }
    }

    func setNotifyOnWalletReminder(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try await db.collection("users").document(uid).setData([
            "notificationPrefs": ["notifyOnWalletReminder": enabled]
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

    /// Restituisce e azzera il briefing da iniettare in PlanningAIChatView.
    func takePendingPlanningInitialMessage() -> String? {
        defer { pendingPlanningInitialMessage = nil }
        let trimmed = pendingPlanningInitialMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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

    private func removeFCMToken(_ token: String, forUid uid: String) async throws {
        let ref = db.collection("users").document(uid)
            .collection("fcmTokens").document(token)
        try await ref.delete()
    }

    private func requestFCMToken() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Messaging.messaging().token { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: NSError(domain: "KidBox", code: 2))
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    private func deleteCurrentFCMToken() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Messaging.messaging().deleteToken { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
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

    // MARK: - Health context send preference (chat Salute)

    func fetchHealthContextSendPreference() async -> HealthContextSendPreference {
        guard let uid = Auth.auth().currentUser?.uid else { return .askEachTime }
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let aiPrefs = snap.get("aiPrefs") as? [String: Any],
               let raw = aiPrefs["healthContextSendPreference"] as? String {
                return HealthContextSendPreference.fromFirestoreValue(raw)
            }
            return .askEachTime
        } catch {
            KBLog.settings.kbError("fetchHealthContextSendPreference failed: \(error.localizedDescription)")
            return .askEachTime
        }
    }

    func setHealthContextSendPreference(_ preference: HealthContextSendPreference) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        try await db.collection("users").document(uid).setData([
            "aiPrefs": [
                "healthContextSendPreference": preference.firestoreValue,
                "healthContextSendPreferenceUpdatedAt": FieldValue.serverTimestamp(),
            ],
        ], merge: true)

        KBLog.settings.kbInfo("healthContextSendPreference saved: \(preference.firestoreValue)")
    }
}

//
//  NotificationManager+WeeklySummary.swift
//  KidBox
//
//  Estensione di NotificationManager per la sintesi settimanale AI.
//  Aggiunge il case `.askExpert` all'enum DeepLink e gestisce il
//  payload `type == "weekly_summary"` in handleNotificationUserInfo.
//
//  INTEGRAZIONE RICHIESTA in NotificationManager.swift:
//  1. Aggiungere `.askExpert` all'enum DeepLink:
//       case askExpert
//  2. Aggiungere il branch `weekly_summary` in handleNotificationUserInfo:
//       } else if type == "weekly_summary" {
//           pendingDeepLink = .askExpert
//           KBLog.auth.kbInfo("DeepLink set for weeklySummary → askExpert")
//       }
//  3. Aggiungere il case in AppCoordinator.handleDeepLink:
//       case .askExpert:
//           navigate(to: .askExpert)
//
//  Il file esistente non viene toccato — queste istruzioni documentano
//  le modifiche manuali da fare.
//

// MARK: - Weekly summary notification preference

extension NotificationManager {
    
    private enum WeeklySummaryPrefKey {
        static let enabled = "kb_weeklySummaryEnabled"
    }
    
    /// Preferenza locale (UserDefaults) per abilitare la sintesi settimanale.
    var weeklySummaryEnabled: Bool {
        get { UserDefaults.standard.object(forKey: WeeklySummaryPrefKey.enabled) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: WeeklySummaryPrefKey.enabled)
            if !newValue {
                // Rimuove la notifica schedulata se l'utente disabilita
                UNUserNotificationCenter.current()
                    .removePendingNotificationRequests(withIdentifiers: ["kb-weekly-summary"])
                KBLog.ai.kbInfo("NotificationManager: weekly summary disabled, notification removed")
            }
        }
    }
}

// MARK: - Password expiry (local reminders T-30 / T-7 / T-1)

extension NotificationManager {

    private static func passwordExpiryIdPrefix(entryId: String) -> String {
        "kb.password.expiry.\(entryId)."
    }

    /// Rimuove tutte le richieste locali KidBox per una voce password (logout / delete / sync).
    func cancelPasswordExpiryNotifications(forEntryId entryId: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = Self.passwordExpiryIdPrefix(entryId: entryId)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        KBLog.auth.kbDebug("[PasswordExpiry] cancelled pending count=\(ids.count) entryId=\(entryId)")
    }

    /// Cancella i precedenti e ripianifica fino a tre notifiche locali: **30 / 7 / 1 giorni prima** della scadenza, alle **09:00** (stesso schema di `HousePaymentReminderService` / vaccini).
    func syncPasswordExpiryNotifications(for entry: PasswordEntry) async {
        await cancelPasswordExpiryNotifications(forEntryId: entry.id)

        guard entry.deletedAt == nil,
              let expiry = entry.expiresAt
        else { return }

        let cal = Calendar.current
        if cal.startOfDay(for: expiry) < cal.startOfDay(for: Date()) { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            KBLog.auth.kbDebug("[PasswordExpiry] not authorized — skip entry=\(entry.id)")
            return
        }

        let titlePlain = (try? entry.decryptTitle())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Password"
        let displayTitle = titlePlain.isEmpty ? "Password" : titlePlain

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = kbDeviceLocale()
        let expiryStr = formatter.string(from: expiry)

        for days in [30, 7, 1] {
            guard let fireDate = Self.fireDateNineAM(daysBeforeExpiry: days, expiry: expiry) else { continue }
            guard fireDate > Date().addingTimeInterval(5) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Password in scadenza"
            switch days {
            case 1:
                content.body = "«\(displayTitle)» scade domani (\(expiryStr))."
            case 7:
                content.body = "«\(displayTitle)» scade il \(expiryStr). Mancano 7 giorni."
            default:
                content.body = "«\(displayTitle)» scade il \(expiryStr). Mancano 30 giorni."
            }
            content.sound = .default
            content.threadIdentifier = "kidbox.passwords"
            content.userInfo = [
                "type": "password_expiry_reminder",
                "familyId": entry.familyId,
                "entryId": entry.id,
                "daysBefore": days,
            ]

            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            comps.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let identifier = "\(Self.passwordExpiryIdPrefix(entryId: entry.id))d\(days)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                KBLog.auth.kbInfo("[PasswordExpiry] scheduled id=\(identifier) fire=\(fireDate)")
            } catch {
                KBLog.auth.kbError("[PasswordExpiry] schedule failed: \(error.localizedDescription)")
            }
        }
    }

    private static func fireDateNineAM(daysBeforeExpiry: Int, expiry: Date) -> Date? {
        let cal = Calendar.current
        let expiryStart = cal.startOfDay(for: expiry)
        guard let targetDay = cal.date(byAdding: .day, value: -daysBeforeExpiry, to: expiryStart) else { return nil }
        var c = cal.dateComponents([.year, .month, .day], from: targetDay)
        c.hour = 9
        c.minute = 0
        c.second = 0
        return cal.date(from: c)
    }

    /// Notifica locale unica (raggruppata) quando uno scan rileva nuove password compromesse.
    func schedulePasswordSecuritySummaryNotification(familyId: String, newlyCompromised: Int) async {
        guard newlyCompromised > 0 else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let id = "kb.password.security.summary.\(familyId)"
        let content = UNMutableNotificationContent()
        content.title = "Sicurezza password"
        content.body = newlyCompromised == 1
            ? "Abbiamo trovato 1 nuova password compromessa."
            : "Abbiamo trovato \(newlyCompromised) nuove password compromesse."
        content.sound = .default
        content.threadIdentifier = "kidbox.passwords.security"
        content.userInfo = [
            "type": "password_security_summary",
            "familyId": familyId,
            "newlyCompromised": newlyCompromised
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        do {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            try await center.add(request)
            KBLog.auth.kbInfo("[PasswordSecurity] summary notification scheduled newly=\(newlyCompromised)")
        } catch {
            KBLog.auth.kbError("[PasswordSecurity] schedule summary failed: \(error.localizedDescription)")
        }
    }
}

