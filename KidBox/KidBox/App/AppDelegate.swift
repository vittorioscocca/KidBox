//
//  AppDelegate.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import OSLog

/// UIApplication delegate for KidBox.
///
/// Responsibilities:
/// - Configure Firebase at launch
/// - Bridge APNs token to Firebase Messaging (FCM)
/// - Receive FCM token updates (registration token refresh)
/// - Handle user interaction with notifications (tap)
/// - Present notifications while app is in foreground
///
/// Notes:
/// - Avoid logging sensitive notification payload data (could contain PII).
/// - Avoid logging full FCM tokens (treat as sensitive).
final class AppDelegate: NSObject,
                         UIApplicationDelegate,
                         UNUserNotificationCenterDelegate,
                         MessagingDelegate {
    
    // MARK: - App lifecycle
    
    /// Called when the app finishes launching.
    ///
    /// Configures Firebase and sets delegates for:
    /// - `UNUserNotificationCenter` (foreground presentation + tap handling)
    /// - `Messaging` (FCM token refresh)
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        KBLog.app.kbInfo("App didFinishLaunching")
        
        FirebaseApp.configure()
        KBLog.app.kbInfo("Firebase configured")
        
        // 🔔 Notifications delegate (allows banner even in foreground)
        UNUserNotificationCenter.current().delegate = self
        KBLog.app.kbDebug("UNUserNotificationCenter delegate set")
        
        // 📩 FCM delegate (token refresh)
        Messaging.messaging().delegate = self
        KBLog.app.kbDebug("Messaging delegate set")
        
        return true
    }
    
    // MARK: - Notification tap handling
    
    /// Called when the user interacts with a notification (e.g. taps it).
    ///
    /// Forwards the notification payload to `NotificationManager` on MainActor.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        KBLog.auth.kbInfo("Notification tapped (didReceive response)")
        
        let userInfo = response.notification.request.content.userInfo
        
        // Forward payload to app-level notification manager.
        await MainActor.run {
            NotificationManager.shared.handleNotificationUserInfo(userInfo)
        }
    }
    
    // MARK: - APNs registration
    
    /// Called when APNs successfully registers and provides the device token.
    ///
    /// Bridges the APNs token to Firebase Messaging by forwarding it to `NotificationManager`,
    /// which will set `Messaging.messaging().apnsToken` and (if available) persist the FCM token.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        KBLog.auth.kbInfo("APNs token received bytes=\(deviceToken.count)")
        
        Task { @MainActor in
            await NotificationManager.shared.handleAPNSToken(deviceToken)
        }
    }
    
    /// Called when APNs registration fails.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        KBLog.auth.kbError("APNs registration failed: \(error.localizedDescription)")
    }
    
    // MARK: - FCM registration token
    
    /// Called when Firebase Messaging refreshes or generates a new FCM registration token.
    ///
    /// - Important: Do not log the full token.
    ///   Treat it as sensitive and only log non-sensitive metadata (e.g. length).
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let token = fcmToken, !token.isEmpty else {
            KBLog.auth.kbDebug("FCM token refresh received but token was empty")
            return
        }
        
        KBLog.auth.kbInfo("FCM token received length=\(token.count)")
        
        Task { @MainActor in
            await NotificationManager.shared.handleFCMToken(token)
        }
    }
    
    // MARK: - Foreground presentation
    
    /// Called when a notification arrives while the app is in the foreground.
    ///
    /// Returning `.banner` ensures the user still sees the notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        KBLog.auth.kbDebug("Notification received in foreground (willPresent)")
        return [.banner, .sound, .badge]
    }
}
