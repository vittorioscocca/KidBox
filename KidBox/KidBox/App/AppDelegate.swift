//
//  AppDelegate.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import UIKit
import CoreLocation
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import OSLog
import FirebaseStorage
import Firebase
import FBSDKCoreKit

/// UIApplication delegate for KidBox.
///
/// Responsibilities:
/// - Configure Firebase at launch
/// - Bridge APNs token to Firebase Messaging (FCM)
/// - Receive FCM token updates (registration token refresh)
/// - Handle user interaction with notifications (tap)
/// - Present notifications while app is in foreground
/// - Handle background location relaunch (significant location changes)
///
/// Notes:
/// - Avoid logging sensitive notification payload data (could contain PII).
/// - Avoid logging full FCM tokens (treat as sensitive).
final class AppDelegate: NSObject,
                         UIApplicationDelegate,
                         UNUserNotificationCenterDelegate,
                         MessagingDelegate,
                         CLLocationManagerDelegate {
    
    // MARK: - Background location manager
    
    /// Location manager dedicato al relaunch — separato da quello del ViewModel.
    /// Serve solo per ricevere il primo evento di significant change che sveglia l'app
    /// dopo che è stata terminata dall'utente, poi il ViewModel prende il controllo.
    private var backgroundLocationManager: CLLocationManager?
    
    // MARK: - App lifecycle
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        KBLog.app.kbInfo("App didFinishLaunching")
        
        FirebaseApp.configure()
        KBLog.app.kbInfo("Firebase configured")
        
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
        KBLog.app.kbInfo("Facebook SDK configured")
        
        let opts = FirebaseApp.app()?.options
        KBLog.app.kbInfo("✅ PROJECT:\(opts?.projectID ?? "nil")" )
        KBLog.app.kbInfo("✅ STORAGE_BUCKET:\(opts?.storageBucket ?? "nil")")
        KBLog.app.kbInfo("✅ STORAGE via Storage.storage:\(Storage.storage().app.options.storageBucket ?? "nil")")
        // 🔔 Notifications delegate
        UNUserNotificationCenter.current().delegate = self
        KBLog.app.kbDebug("UNUserNotificationCenter delegate set")
        
        // 📩 FCM delegate
        Messaging.messaging().delegate = self
        KBLog.app.kbDebug("Messaging delegate set")
        
        configureMediaURLCache()
        KBLog.app.kbDebug("Cache configured")
        
        // 📍 Background location relaunch
        // iOS rilancia l'app con .location nelle launchOptions quando c'è
        // un significant location change pendente mentre l'app era terminata.
        // Nota: .location è deprecata in iOS 26 ma funziona ancora —
        // migreremo a CLLocationUpdate/CLMonitor quando iOS 26 sarà GA.
        if wasRelauchedForLocation(launchOptions: launchOptions) {
            KBLog.app.kbInfo("App relaunched by iOS for background location event")
            setupBackgroundLocationManager()
        }
        
        return true
    }
    
    func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        guard let urlContext = URLContexts.first else { return }
        
        let url = urlContext.url
        let options = urlContext.options
        
        ApplicationDelegate.shared.application(
            UIApplication.shared,
            open: url,
            sourceApplication: options.sourceApplication,
            annotation: options.annotation
        )
        
        KBLog.app.kbDebug("Facebook openURL handled via UIScene")
    }

    private func setupBackgroundLocationManager() {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        backgroundLocationManager = manager
        manager.startMonitoringSignificantLocationChanges()
    }
    
    /// Controlla se l'app è stata rilanciata da iOS per un location event.
    /// Usa la raw key string per evitare il warning di deprecazione di .location su iOS 26+.
    private func wasRelauchedForLocation(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let key = UIApplication.LaunchOptionsKey(rawValue: "UIApplicationLaunchOptionsLocationKey")
        return launchOptions?[key] != nil
    }
    
    func configureMediaURLCache() {
        let memory = 100 * 1024 * 1024   // 100 MB
        let disk   = 300 * 1024 * 1024   // 300 MB
        URLCache.shared = URLCache(memoryCapacity: memory, diskCapacity: disk, diskPath: "kidbox-media-cache")
    }
    
    // MARK: - CLLocationManagerDelegate (background relaunch)
    
    /// Riceve la posizione quando l'app viene rilanciata in background da iOS.
    /// In questo momento la UI non è ancora costruita, quindi scriviamo
    /// direttamente su Firestore tramite LocationRemoteStore.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        KBLog.app.kbInfo("Background location received lat=\(location.coordinate.latitude) lon=\(location.coordinate.longitude)")
        
        // Leggi uid/familyId/displayName da UserDefaults
        // (salvati dal FamilyLocationViewModel quando l'utente attiva la condivisione)
        let defaults = UserDefaults.standard
        guard
            let uid         = defaults.string(forKey: KBLocationDefaults.uid),
            let familyId    = defaults.string(forKey: KBLocationDefaults.familyId),
            let displayName = defaults.string(forKey: KBLocationDefaults.displayName),
            defaults.bool(forKey: KBLocationDefaults.isSharing)
        else {
            KBLog.app.kbDebug("Background location: no active sharing session, skipping")
            return
        }
        
        let store = LocationRemoteStore()
        Task {
            await store.updateLocation(
                familyId: familyId,
                uid: uid,
                location: location,
                displayName: displayName
            )
            KBLog.app.kbInfo("Background location: Firestore update sent uid=\(uid)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        KBLog.app.kbError("Background location error: \(error.localizedDescription)")
    }
    
    // MARK: - Notification tap handling
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        KBLog.auth.kbInfo("Notification tapped (didReceive response)")
        
        let userInfo = response.notification.request.content.userInfo
        
        await MainActor.run {
            NotificationManager.shared.handleNotificationUserInfo(userInfo)
        }
    }
    
    // MARK: - APNs registration
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        KBLog.auth.kbInfo("APNs token received bytes=\(deviceToken.count)")
        
        Task { @MainActor in
            await NotificationManager.shared.handleAPNSToken(deviceToken)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        KBLog.auth.kbError("APNs registration failed: \(error.localizedDescription)")
    }
    
    // MARK: - FCM registration token
    
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
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        KBLog.auth.kbDebug("Notification received in foreground (suppressed)")
        return []   // ✅ niente banner, niente suono, niente badge in foreground
    }
}
