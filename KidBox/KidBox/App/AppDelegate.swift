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

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        
        FirebaseApp.configure()
        
        // 🔔 Delegate notifiche (banner anche in foreground)
        UNUserNotificationCenter.current().delegate = self
        
        // 📩 Delegate FCM (token refresh)
        Messaging.messaging().delegate = self
        
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            NotificationManager.shared.handleNotificationUserInfo(userInfo)
        }
    }
    
    // APNs token (necessario per FCM -> token)
    func application(_ application: UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        print("✅ APNs token received, size=\(deviceToken.count)")
        Task { @MainActor in
            await NotificationManager.shared.handleAPNSToken(deviceToken)
        }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("❌ APNs register failed:", error.localizedDescription)
    }
    
    // ✅ Token FCM aggiornato/rigenerato
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        print("📩 FCM TOKEN =", token)
        Task { @MainActor in
            await NotificationManager.shared.handleFCMToken(token)
        }
    }
    
    // ✅ Mostra banner anche quando app è aperta
    func userNotificationCenter(_ center: UNUserNotificationCenter,willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
}
