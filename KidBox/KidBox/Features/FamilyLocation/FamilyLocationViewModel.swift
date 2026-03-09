import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine
import UserNotifications
internal import os
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class FamilyLocationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // MARK: - Published
    
    @Published var sharedUsers: [SharedUserLocation] = []
    
    @Published var isSharing: Bool = false
    @Published var myMode: ShareMode?
    @Published var myExpiresAt: Date?
    @Published var myCurrentAddress: String? = nil
    
    /// True appena l'utente attiva la condivisione (fix chicken-and-egg):
    /// consente di inviare lat/lon anche prima che il listener ci includa.
    @Published private(set) var sharingRequested: Bool = false
    
    // MARK: - Private
    
    private let remote = LocationRemoteStore()
    private var listener: ListenerRegistration?
    
    private let locationManager = CLLocationManager()
    private let familyId: String
    
    private var shouldStartLocationUpdates = false
    private var expiryTask: Task<Void, Never>?
    
    /// Manteniamo il nome canonico (SwiftData) passato dalla View,
    /// così lo riscriviamo anche durante updateLocation (self-healing).
    private(set) var myCurrentDisplayName: String = "Utente"
    
    // MARK: - Init
    
    init(familyId: String) {
        self.familyId = familyId
        super.init()
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }
    
    // MARK: - Lifecycle
    
    func start() {
        listen()
        requestAuthorizationIfNeeded()
        // Se l'app è stata rilanciata in background da significant location changes,
        // ripristina il tracking se eravamo in sharing
        resumeIfNeeded()
    }
    
    func stop() {
        listener?.remove()
        listener = nil
        
        expiryTask?.cancel()
        expiryTask = nil
        
        // NON fermiamo il location manager se stiamo condividendo —
        // l'app continua in background e significant changes rimane attivo
        if !sharingRequested {
            stopLocationUpdates()
        }
    }
    
    // MARK: - Firestore listen
    
    private func listen() {
        listener = remote.listen(familyId: familyId) { [weak self] users in
            Task { @MainActor in
                guard let self else { return }
                self.sharedUsers = users
                self.applyRemoteStateForMeIfNeeded()
            }
        }
    }
    
    /// Dopo relaunch (o quando non abbiamo appena premuto un bottone),
    /// riallinea lo stato UI in base a ciò che Firestore dice su "me".
    private func applyRemoteStateForMeIfNeeded() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        // Se l'utente ha appena premuto "condividi" in questa sessione,
        // non sovrascriviamo il suo stato locale col listener (evita flicker).
        if sharingRequested { return }
        
        guard let me = sharedUsers.first(where: { $0.id == uid }) else {
            // Non risulto in sharing lato remote
            isSharing = false
            myMode = nil
            myExpiresAt = nil
            
            expiryTask?.cancel()
            expiryTask = nil
            return
        }
        
        // Risulto in sharing lato remote
        isSharing = true
        myMode = me.mode
        myExpiresAt = me.expiresAt
        
        // Se temporaneo scaduto → stop forzato
        if me.mode == .temporary, let exp = me.expiresAt, exp <= Date() {
            Task { await stopSharing() }
            return
        }
        
        // Ripristina updates e timer (anche dopo relaunch)
        sharingRequested = true
        if me.mode == .temporary {
            scheduleExpiryStopIfNeeded()
        } else {
            expiryTask?.cancel()
            expiryTask = nil
        }
        startLocationUpdatesIfPossible()
    }
    
    // MARK: - Actions
    
    func startRealtime(displayName: String) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        
        myCurrentDisplayName = displayName
        
        sharingRequested = true
        isSharing = true
        myMode = .realtime
        myExpiresAt = nil
        
        saveLocationDefaults(uid: uid, displayName: displayName)
        setBadge(active: true)
        
        expiryTask?.cancel()
        expiryTask = nil
        
        do {
            try await remote.startSharing(
                familyId: familyId,
                uid: uid,
                name: displayName,
                mode: .realtime,
                expiresAt: nil
            )
        } catch {
            KBLog.app.error("FamilyLocation startRealtime failed: \(error.localizedDescription, privacy: .public)")
            rollbackSharingUI()
            return
        }
        
        startLocationUpdatesIfPossible()
    }
    
    func startTemporary(hours: Int, displayName: String) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        
        myCurrentDisplayName = displayName
        
        let expires = Date().addingTimeInterval(Double(hours) * 3600)
        
        sharingRequested = true
        isSharing = true
        myMode = .temporary
        myExpiresAt = expires
        
        saveLocationDefaults(uid: uid, displayName: displayName)
        setBadge(active: true)
        
        do {
            try await remote.startSharing(
                familyId: familyId,
                uid: uid,
                name: displayName,
                mode: .temporary,
                expiresAt: expires
            )
        } catch {
            KBLog.app.error("FamilyLocation startTemporary failed: \(error.localizedDescription, privacy: .public)")
            rollbackSharingUI()
            return
        }
        
        scheduleExpiryStopIfNeeded()
        startLocationUpdatesIfPossible()
    }
    
    func stopSharing() async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        
        sharingRequested = false
        isSharing = false
        myMode = nil
        myExpiresAt = nil
        myCurrentAddress = nil
        
        expiryTask?.cancel()
        expiryTask = nil
        
        // Rimuovi da UserDefaults
        clearLocationDefaults()
        setBadge(active: false)
        
        await remote.stopSharing(familyId: familyId, uid: uid)
        
        stopLocationUpdates()
    }
    
    // MARK: - FIX: aggiorna il nome mentre la condivisione è attiva
    
    /// Chiama questo ogni volta che il profilo viene salvato o la view appare,
    /// così il nome su Firestore e su tutti i device è sempre quello corretto.
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Utente" else { return }
        guard trimmed != myCurrentDisplayName else { return } // nessun cambiamento, evita write inutile
        
        myCurrentDisplayName = trimmed
        KBLog.app.debug("FamilyLocation updateDisplayName -> \(trimmed, privacy: .public)")
        
        guard isSharing, let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        
        Task {
            await remote.updateDisplayName(familyId: familyId, uid: uid, displayName: trimmed)
        }
    }
    
    private func rollbackSharingUI() {
        sharingRequested = false
        isSharing = false
        myMode = nil
        myExpiresAt = nil
        
        expiryTask?.cancel()
        expiryTask = nil
        
        clearLocationDefaults()
        setBadge(active: false)
        stopLocationUpdates()
    }
    
    // MARK: - Temporary expiry timer
    
    private func scheduleExpiryStopIfNeeded() {
        expiryTask?.cancel()
        expiryTask = nil
        
        guard sharingRequested, myMode == .temporary, let expiresAt = myExpiresAt else { return }
        
        let seconds = expiresAt.timeIntervalSinceNow
        if seconds <= 0 {
            Task { await stopSharing() }
            return
        }
        
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return // cancellato
            }
            
            KBLog.app.error("FamilyLocation temporary sharing expired -> auto stop")
            await self?.stopSharing()
        }
    }
    
    // MARK: - Authorization & Location
    
    private func requestAuthorizationIfNeeded() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            // Prima chiediamo WhenInUse, poi upgrade ad Always
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Abbiamo WhenInUse, chiediamo upgrade ad Always per il background
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        case .restricted, .denied:
            KBLog.app.error("Location permission denied/restricted")
        @unknown default:
            break
        }
    }
    
    private func startLocationUpdatesIfPossible() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
            shouldStartLocationUpdates = false
            
            // Significant changes: risveglia l'app anche se terminata dall'utente
            // (funziona solo con authorizedAlways)
            if status == .authorizedAlways {
                locationManager.startMonitoringSignificantLocationChanges()
            }
            
            if status == .authorizedWhenInUse {
                locationManager.requestAlwaysAuthorization()
            }
            
        case .notDetermined:
            shouldStartLocationUpdates = true
            locationManager.requestWhenInUseAuthorization()
            
        case .restricted, .denied:
            shouldStartLocationUpdates = false
            KBLog.app.error("Cannot start location updates: permission denied")
            
        @unknown default:
            shouldStartLocationUpdates = false
        }
    }
    
    private func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        shouldStartLocationUpdates = false
    }
    
    /// Chiamato all'avvio: se Firestore dice che eravamo in sharing (es. app rilanciata
    /// da iOS dopo significant location change), riparte il tracking immediatamente.
    private func resumeIfNeeded() {
        // applyRemoteStateForMeIfNeeded() viene già chiamato dal listener Firestore
        // appena arriva il primo snapshot — non serve fare altro qui.
        // Il listener è già partito in start() → listen().
        KBLog.app.debug("FamilyLocation: resumeIfNeeded — listener will restore state")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        switch status {
        case .authorizedWhenInUse:
            // Upgrade ad Always appena possibile
            manager.requestAlwaysAuthorization()
            if shouldStartLocationUpdates, sharingRequested {
                startLocationUpdatesIfPossible()
            }
        case .authorizedAlways:
            if shouldStartLocationUpdates, sharingRequested {
                startLocationUpdatesIfPossible()
            }
        case .denied, .restricted:
            KBLog.app.error("Location authorization denied/restricted")
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard
            sharingRequested,
            let uid = Auth.auth().currentUser?.uid,
            let location = locations.last
        else { return }
        
        // Reverse geocoding per indirizzo nella card
        Task {
            let geocoder = CLGeocoder()
            if let placemark = try? await geocoder.reverseGeocodeLocation(location).first {
                let street = placemark.thoroughfare ?? ""
                let number = placemark.subThoroughfare ?? ""
                let city   = placemark.locality ?? ""
                let parts  = [street, number, city].filter { !$0.isEmpty }
                await MainActor.run {
                    myCurrentAddress = parts.isEmpty ? nil : parts.joined(separator: " ")
                }
            }
        }
        
        Task {
            await remote.updateLocation(
                familyId: familyId,
                uid: uid,
                location: location,
                displayName: myCurrentDisplayName
            )
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        KBLog.app.error("Location update failed: \(error.localizedDescription, privacy: .public)")
    }
    
    // MARK: - UserDefaults persistence (per AppDelegate background relaunch)
    
    private func saveLocationDefaults(uid: String, displayName: String) {
        let defaults = UserDefaults.standard
        defaults.set(uid, forKey: KBLocationDefaults.uid)
        defaults.set(familyId, forKey: KBLocationDefaults.familyId)
        defaults.set(displayName, forKey: KBLocationDefaults.displayName)
        defaults.set(true, forKey: KBLocationDefaults.isSharing)
        // Salva expiresAt se temporaneo, altrimenti rimuovi
        if let expires = myExpiresAt {
            defaults.set(expires.timeIntervalSince1970, forKey: KBLocationDefaults.expiresAt)
        } else {
            defaults.removeObject(forKey: KBLocationDefaults.expiresAt)
        }
        NotificationCenter.default.post(name: .kbLocationSharingStateChanged, object: nil)
    }
    
    private func clearLocationDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: KBLocationDefaults.uid)
        defaults.removeObject(forKey: KBLocationDefaults.familyId)
        defaults.removeObject(forKey: KBLocationDefaults.displayName)
        defaults.removeObject(forKey: KBLocationDefaults.expiresAt)   // ← NUOVO
        defaults.set(false, forKey: KBLocationDefaults.isSharing)
        NotificationCenter.default.post(name: .kbLocationSharingStateChanged, object: nil)
    }
    
    /// Mostra badge 1 sull'icona mentre la condivisione è attiva, lo rimuove quando si ferma.
    private func setBadge(active: Bool) {
        Task { @MainActor in
            do {
                try await UNUserNotificationCenter.current()
                    .setBadgeCount(active ? 1 : 0)
            } catch {
                KBLog.app.error("FamilyLocation setBadge failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
