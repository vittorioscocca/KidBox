//
//  NotificationManager.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
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
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private let db = Firestore.firestore()
    
    // MARK: - Deep Link (tap su push)
    enum DeepLink: Equatable {
        case document(familyId: String, docId: String)
    }
    
    @Published var pendingDeepLink: DeepLink? = nil
    
    func handleNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        // payload FCM: data.* finisce in userInfo direttamente
        let type = userInfo["type"] as? String
        
        if type == "new_document" {
            guard
                let familyId = userInfo["familyId"] as? String,
                let docId = userInfo["docId"] as? String
            else { return }
            
            pendingDeepLink = .document(familyId: familyId, docId: docId)
        }
    }
    
    /// chiamalo dopo che hai navigato, così non lo riesegue
    func consumeDeepLink() {
        pendingDeepLink = nil
    }
    
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    func fetchNotifyOnNewDocsPreference() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("🔔 prefs: no user logged in -> false")
            return false
        }
        
        print("🔔 prefs: reading users/\(uid) ...")
        
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            
            print("🔔 prefs: exists=\(snap.exists)")
            print("🔔 prefs: data =", snap.data() ?? [:])
            
            // A) formato corretto: notificationPrefs: { notifyOnNewDocs: true }
            if let prefs = snap.get("notificationPrefs") as? [String: Any],
               let v = prefs["notifyOnNewDocs"] as? Bool {
                print("🔔 prefs: read from MAP =", v)
                return v
            }
            
            // B) prova field-path annidato (se esiste come map)
            if let v = snap.get("notificationPrefs.notifyOnNewDocs") as? Bool {
                print("🔔 prefs: read from field-path =", v)
                return v
            }
            
            // C) compat: campo “piatto” che si chiama letteralmente "notificationPrefs.notifyOnNewDocs"
            // (cioè il dot fa parte del nome del campo)
            if let v = snap.get(FieldPath(["notificationPrefs.notifyOnNewDocs"])) as? Bool {
                print("🔔 prefs: read from literal-dot field =", v)
                return v
            }
            
            print("🔔 prefs: not found -> false")
            return false
            
        } catch {
            print("❌ prefs: read failed:", error.localizedDescription)
            return false
        }
    }
    
    @MainActor
    func handleAPNSToken(_ deviceToken: Data) async {
        // collega APNs a Firebase Messaging
        Messaging.messaging().apnsToken = deviceToken
        
        // opzionale: se il token FCM esiste già, persistilo
        if let fcm = Messaging.messaging().fcmToken, !fcm.isEmpty {
            do {
                try await persistFCMToken(fcm)
            } catch {
                print("⚠️ persistFCMToken after APNs failed:", error.localizedDescription)
            }
        }
    }
    
    // MARK: - Toggle
    func setNotifyOnNewDocs(_ enabled: Bool) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // 1️⃣ Scrittura CORRETTA (mappa annidata)
        try await db.collection("users").document(uid).setData([
            "notificationPrefs": [
                "notifyOnNewDocs": enabled
            ]
        ], merge: true)
        
        // 2️⃣ 🔥 PULIZIA del vecchio campo sbagliato (se esiste)
        // (campo letterale "notificationPrefs.notifyOnNewDocs")
        try? await db.collection("users").document(uid).updateData([
            FieldPath(["notificationPrefs.notifyOnNewDocs"]): FieldValue.delete()
        ])
        
        // 3️⃣ Comportamento notifiche
        if enabled {
            try await enablePushNotificationsForCurrentUser()
        } else {
            try await disablePushNotificationsForCurrentUser()
        }
    }
    
    
    // MARK: - Enable
    func enablePushNotificationsForCurrentUser() async throws {
        let center = UNUserNotificationCenter.current()
        
        let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        await refreshAuthorizationStatus()
        
        guard granted else {
            throw NSError(domain: "KidBox", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Permesso notifiche negato"
            ])
        }
        
        // registra APNs (necessario per avere FCM token su iOS)
        UIApplication.shared.registerForRemoteNotifications()
        print("✅ registerForRemoteNotifications() called")
        
        // se il token FCM è già pronto, salvalo subito
        try await persistFCMTokenIfAvailable()
    }
    
    // MARK: - Disable
    func disablePushNotificationsForCurrentUser() async throws {
        print("notifica disabilitata dall'utente")
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // pref già messa a false sopra, ma lasciamola robusta
        try await db.collection("users").document(uid)
            .setData(["notificationPrefs.notifyOnNewDocs": false], merge: true)
        
        // opzionale: se vuoi essere SICURO di non ricevere più push,
        // puoi cancellare i token dal db (io lo lascerei, ma visto che tu vuoi “0 push” lo teniamo)
        let tokensRef = db.collection("users").document(uid).collection("fcmTokens")
        let snap = try await tokensRef.getDocuments()
        for d in snap.documents {
            try await d.reference.delete()
        }
    }
    
    // MARK: - Token
    func persistFCMToken(_ token: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        let ref = db.collection("users").document(uid)
            .collection("fcmTokens").document(token)
        
        try await ref.setData([
            "token": token,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    func handleFCMToken(_ token: String) async {
        do {
            try await persistFCMToken(token)
        } catch {
            print("⚠️ persistFCMToken failed:", error.localizedDescription)
        }
    }
    
    private func persistFCMTokenIfAvailable() async throws {
        if let token = Messaging.messaging().fcmToken, !token.isEmpty {
            try await persistFCMToken(token)
        }
    }
}
