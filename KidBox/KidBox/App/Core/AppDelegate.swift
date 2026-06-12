//
//  AppDelegate.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import UIKit
import CoreLocation
import BackgroundTasks
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import OSLog
import FirebaseStorage
import Firebase
import FBSDKCoreKit
import FirebaseAuth
import SwiftData

/// UIApplication delegate for KidBox.
///
/// Responsibilities:
/// - Configure Firebase at launch
/// - Bridge APNs token to Firebase Messaging (FCM)
/// - Receive FCM token updates (registration token refresh)
/// - Handle user interaction with notifications (tap)
/// - Handle quick actions on treatment dose notifications (Assunto / Saltato)
/// - Present notifications while app is in foreground
/// - Handle background location relaunch (significant location changes)
///
/// Notes:
/// - Avoid logging sensitive notification payload data (could contain PII).
/// - Avoid logging full FCM tokens (treat as sensitive).
/// - `modelContainer` viene iniettato da `KidBoxApp.init()` prima che qualsiasi
///   notifica possa arrivare, quindi è sempre disponibile quando serve.
final class AppDelegate: NSObject,
                         UIApplicationDelegate,
                         UNUserNotificationCenterDelegate,
                         MessagingDelegate,
                         CLLocationManagerDelegate {
    
    // MARK: - SwiftData container (iniettato da KidBoxApp)
    
    /// Iniettato da `KidBoxApp.init()` subito dopo la costruzione del container.
    /// Usato da `TreatmentDoseActionHandler` per aggiornare i `KBDoseLog`
    /// direttamente dalla quick action senza aprire l'app.
    var modelContainer: ModelContainer?
    
    // MARK: - Background location manager
    
    /// Location manager dedicato al relaunch — separato da quello del ViewModel.
    /// Serve solo per ricevere il primo evento di significant change che sveglia l'app
    /// dopo che è stata terminata dall'utente, poi il ViewModel prende il controllo.
    private var backgroundLocationManager: CLLocationManager?
    private static let passwordSecurityRefreshTaskId = "it.vittorioscocca.kidbox.password-security-refresh"

    // MARK: - Orientation

    /// Maschera orientamenti supportati, dinamica. L'app è portrait-only su iPhone, ma
    /// l'anteprima documenti/PDF (QuickLook / PDFKit) la imposta temporaneamente a `.all`
    /// così il documento ruota con il dispositivo, poi `AppOrientation.reset()` ripristina.
    static var supportedOrientations: UIInterfaceOrientationMask =
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.supportedOrientations
    }
    
    // MARK: - App lifecycle
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        KBLog.app.kbInfo("App didFinishLaunching")
        
        FirebaseApp.configure()
        KBLog.app.kbInfo("Firebase configured")

        // ── Mac Catalyst: rimuove il background ovale automatico dai BarButtonItem ──
        // Su Mac Catalyst i ToolbarItem SwiftUI vengono bridgati a UIBarButtonItem
        // e UIKit aggiunge automaticamente un background pillola. Impostiamo
        // backgroundImage vuota via UIBarButtonItemAppearance per rimuoverlo.
        #if targetEnvironment(macCatalyst)
        configureMacCatalystButtonAppearance()
        #endif
        // ─────────────────────────────────────────────────────────────────────────

        // ── Registra le categorie di notifica con azioni rapide ────────────
        // Deve essere chiamato il prima possibile, prima di impostare il delegate,
        // così iOS conosce già le categorie quando arriva la prima notifica.
        TreatmentNotificationCategory.register()
        KBLog.app.kbDebug("Notification categories registered")
        // ──────────────────────────────────────────────────────────────────
        
        // Condividi la sessione Auth con la Share Extension tramite Keychain sharing.
        // Richiede "Keychain Sharing" capability con gruppo "it.vittorioscocca.kidbox"
        // attivato su ENTRAMBI i target in Xcode → Signing & Capabilities.
        do {
            let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KEYCHAIN_ACCESS_GROUP") as? String ?? ""
            try Auth.auth().useUserAccessGroup(accessGroup)
            KBLog.auth.kbInfo("Auth Keychain access group set")
        } catch {
            KBLog.auth.kbError("Auth useUserAccessGroup failed: \(error.localizedDescription)")
        }
        
        // Imposta App ID / client token prima dell’SDK Facebook: `ApplicationDelegate` valida subito la config.
        configureFacebookFromInfoPlistIfNeeded()
        ApplicationDelegate.shared.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )
        KBLog.app.kbInfo("Facebook SDK configured")
        
        let opts = FirebaseApp.app()?.options
        KBLog.app.kbInfo("✅ PROJECT:\(opts?.projectID ?? "nil")")
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
        registerBackgroundTasks()
        schedulePasswordSecurityRefresh()
        
        // 📍 Background location relaunch
        // iOS rilancia l'app con .location nelle launchOptions quando c'è
        // un significant location change pendente mentre l'app era terminata.
        // Nota: .location è deprecata in iOS 26 ma funziona ancora —
        // migreremo a CLLocationUpdate/CLMonitor quando iOS 26 sarà GA.
        if wasRelauchedForLocation(launchOptions: launchOptions) {
            KBLog.app.kbInfo("App relaunched by iOS for background location event")
            setupBackgroundLocationManager()
        }

        // 📍 Geofence: istanzia il singleton così il suo CLLocationManager delegate è vivo
        // ad ogni avvio e riceve gli eventi didEnter/ExitRegion delle regioni già registrate
        // a livello OS (che persistono tra i lanci), anche senza aprire la schermata Posizione.
        MainActor.assumeIsolated {
            GeofenceMonitorService.shared.restoreFromDefaults()
        }

        return true
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.passwordSecurityRefreshTaskId,
            using: nil
        ) { [weak self] task in
            guard let appRefresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handlePasswordSecurityRefresh(task: appRefresh)
        }
    }

    private func schedulePasswordSecurityRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.passwordSecurityRefreshTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            KBLog.app.kbError("Failed scheduling password security BG refresh: \(error.localizedDescription)")
        }
    }

    private func handlePasswordSecurityRefresh(task: BGAppRefreshTask) {
        schedulePasswordSecurityRefresh()
        guard let container = modelContainer else {
            task.setTaskCompleted(success: false)
            return
        }
        let familyId = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?.string(forKey: "activeFamilyId") ?? ""
        guard !familyId.isEmpty else {
            task.setTaskCompleted(success: true)
            return
        }
        guard PasswordsSecurityScanner.shouldRunWeeklyAutoScan(familyId: familyId) else {
            task.setTaskCompleted(success: true)
            return
        }
        let context = container.mainContext
        let work = Task { @MainActor in
            _ = await PasswordsSecurityScanner(modelContext: context, familyId: familyId).runFullSecurityScan()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Assicura App ID / Client Token letti dal plist risolto (xcconfig). Se restano `$(...)`, il token Graph è invalido → Firebase 190.
    private func configureFacebookFromInfoPlistIfNeeded() {
        guard let info = Bundle.main.infoDictionary else { return }
        let rawAppID = info["FacebookAppID"] as? String ?? ""
        let rawClient = info["FacebookClientToken"] as? String ?? ""
        if rawAppID.contains("$(") || rawAppID.isEmpty {
            KBLog.app.kbError(
                "FacebookAppID non risolto nel plist — verifica che il target Xcode includa Facebook.xcconfig / Facebook.local.xcconfig"
            )
            return
        }
        Settings.shared.appID = rawAppID
        if !rawClient.isEmpty && !rawClient.contains("$(") {
            Settings.shared.clientToken = rawClient
        }
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
    
    // MARK: - Notification response handling
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        KBLog.auth.kbInfo("Notification response received actionId=\(response.actionIdentifier)")
        
        let userInfo = response.notification.request.content.userInfo
        
        // ── Quick action: Assunto / Saltato ────────────────────────────────
        // Se l'utente ha toccato una delle azioni rapide della notifica dose,
        // registriamo il KBDoseLog direttamente senza aprire l'app.
        // TreatmentDoseActionHandler.handle() restituisce `true` solo per le
        // due azioni rapide; per il tap normale (UNNotificationDefaultActionIdentifier)
        // restituisce `false` e proseguiamo con il deep link.
        if let container = modelContainer {
            let handled = await MainActor.run {
                TreatmentDoseActionHandler.handle(
                    response:     response,
                    modelContext: container.mainContext
                )
            }
            if handled {
                KBLog.auth.kbInfo("Treatment dose quick action handled — skipping deep link")
                return
            }
        } else {
            KBLog.auth.kbError("AppDelegate.modelContainer is nil — quick actions unavailable")
        }
        // ──────────────────────────────────────────────────────────────────
        
        // ── Tap normale sulla notifica → deep link ─────────────────────────
        let notifType = userInfo["type"] as? String ?? "unknown"
        let notifKeys = userInfo.keys.map { "\($0)" }.sorted().joined(separator: ",")
        KBLog.auth.kbInfo("[AppDelegate] didReceive tap: notifId=\(response.notification.request.identifier) type=\(notifType) keys=[\(notifKeys)]")
        await MainActor.run {
            NotificationManager.shared.handleNotificationUserInfo(userInfo)
        }
    }
    
    // MARK: - Foreground presentation
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let type = notification.request.content.userInfo["type"] as? String
        switch type {
        case "visit_reminder", "treatment_reminder", "todo_reminder":
            // Mostra banner + suono anche con l'app aperta in foreground
            KBLog.auth.kbDebug("Notification in foreground: \(type ?? "") → show banner")
            return [.banner, .sound, .badge]
        default:
            KBLog.auth.kbDebug("Notification received in foreground (suppressed) type=\(type ?? "nil")")
            return []
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
    
    // MARK: - Mac Catalyst appearance

    #if targetEnvironment(macCatalyst)
    private func configureMacCatalystButtonAppearance() {
        // Rimuove il background pillola/ovale dai UIBarButtonItem in tutte
        // le navigation bar. Usiamo un'immagine vuota come background per
        // ogni stato: questo azzera il rendering automatico del rettangolo
        // arrotondato che Mac Catalyst aggiunge di default.
        let noImage = UIImage()
        let itemAppearance = UIBarButtonItemAppearance(style: .plain)
        itemAppearance.normal.backgroundImage           = noImage
        itemAppearance.highlighted.backgroundImage      = noImage
        itemAppearance.disabled.backgroundImage         = noImage
        itemAppearance.focused.backgroundImage          = noImage

        let doneAppearance = UIBarButtonItemAppearance(style: .done)
        doneAppearance.normal.backgroundImage           = noImage
        doneAppearance.highlighted.backgroundImage      = noImage
        doneAppearance.disabled.backgroundImage         = noImage
        doneAppearance.focused.backgroundImage          = noImage

        // Applica a tutte le varianti di UINavigationBarAppearance
        for appearance in [
            UINavigationBar.appearance().standardAppearance,
            UINavigationBar.appearance().compactAppearance,
            UINavigationBar.appearance().scrollEdgeAppearance
        ].compactMap({ $0 }) {
            appearance.buttonAppearance     = itemAppearance
            appearance.doneButtonAppearance = doneAppearance
            appearance.backButtonAppearance = itemAppearance
        }

        // Configura anche le appearance di default usate quando non è stata
        // impostata esplicitamente una scrollEdge/compact appearance.
        let defaultAppearance = UINavigationBarAppearance()
        defaultAppearance.configureWithDefaultBackground()
        defaultAppearance.buttonAppearance     = itemAppearance
        defaultAppearance.doneButtonAppearance = doneAppearance
        defaultAppearance.backButtonAppearance = itemAppearance
        UINavigationBar.appearance().standardAppearance    = defaultAppearance
        UINavigationBar.appearance().compactAppearance     = defaultAppearance
        UINavigationBar.appearance().scrollEdgeAppearance  = defaultAppearance
    }
    #endif

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
        print("🔑 FCM TOKEN: \(token)")
        Task { @MainActor in
            await NotificationManager.shared.handleFCMToken(token)
        }
    }
}
