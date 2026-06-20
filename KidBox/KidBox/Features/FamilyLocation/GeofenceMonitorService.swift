//
//  GeofenceMonitorService.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import Foundation
import CoreLocation
import Combine

/// Monitora ingressi/uscite dalle zone di arrivo e scrive eventi su Firestore.
/// Le notifiche push ai membri sono gestite dalla Cloud Function `onGeofenceEvent`.
///
/// È un **singleton a vita-app**: un solo `CLLocationManager` il cui delegate resta vivo
/// anche dopo che iOS rilancia l'app in background per un attraversamento di zona. Le
/// regioni `CLCircularRegion` persistono a livello OS tra i lanci, quindi questa istanza
/// (ricreata all'avvio) riceve comunque gli eventi `didEnter/ExitRegion`.
/// Il contesto (familyId/uid/displayName) viene persistito su `UserDefaults` così l'evento
/// è attribuibile anche se la schermata Posizione non è mai stata aperta in questa sessione.
@MainActor
final class GeofenceMonitorService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = GeofenceMonitorService()

    /// Raggio minimo affidabile per il region monitoring (Apple raccomanda ≥100 m).
    static let minRadiusMeters: CLLocationDistance = 100
    /// Raggio usato quando la zona non ne specifica uno valido.
    static let defaultRadiusMeters: CLLocationDistance = 200

    // MARK: - Published

    @Published private(set) var monitoredGeofenceIds: Set<String> = []

    // MARK: - Dependencies

    private let remoteEvent = GeofenceRemoteEvent()
    private let locationManager = CLLocationManager()

    /// Contesto di attribuzione, mutabile e persistito (vedi [configure] / [restoreFromDefaults]).
    private var familyId: String = ""
    private var uid: String = ""
    private var displayName: String = "Utente"

    /// Metadati locale per regioni attive (identifier = geofence.id).
    private var monitoredGeofences: [String: MonitoredGeofenceState] = [:]

    // MARK: - Init

    private override init() {
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.pausesLocationUpdatesAutomatically = false

        restoreFromDefaults()
    }

    // MARK: - Context

    /// Imposta il contesto corrente e lo persiste, così l'AppDelegate (al relaunch) può
    /// attribuire gli eventi region anche con condivisione live spenta.
    func configure(familyId: String, uid: String, displayName: String) {
        self.familyId = familyId
        self.uid = uid
        self.displayName = displayName.isEmpty ? "Utente" : displayName

        let defaults = UserDefaults.standard
        defaults.set(familyId, forKey: KBLocationDefaults.geofenceFamilyId)
        defaults.set(uid, forKey: KBLocationDefaults.geofenceUid)
        defaults.set(self.displayName, forKey: KBLocationDefaults.geofenceDisplayName)
    }

    /// Carica il contesto da `UserDefaults` (chiamato all'init/avvio app).
    func restoreFromDefaults() {
        let defaults = UserDefaults.standard
        if let fid = defaults.string(forKey: KBLocationDefaults.geofenceFamilyId) { familyId = fid }
        if let u = defaults.string(forKey: KBLocationDefaults.geofenceUid) { uid = u }
        if let n = defaults.string(forKey: KBLocationDefaults.geofenceDisplayName), !n.isEmpty { displayName = n }
    }

    // MARK: - Monitoring control

    /// Sincronizza le regioni monitorate con l'elenco geofence attive (diff per identifier).
    func startMonitoring(geofences: [KBGeofence]) {
        guard hasAlwaysAuthorization else {
            KBLog.app.kbWarning(
                "GeofenceMonitorService: authorizedAlways required (status=\(authorizationStatusLabel))"
            )
            return
        }

        let active = geofences.filter {
            $0.familyId == familyId && $0.isActive && !$0.isDeleted
        }

        let targetIds = Set(active.map(\.id))
        let currentIds = Set(monitoredGeofences.keys)

        for id in currentIds.subtracting(targetIds) {
            stopMonitoring(geofenceId: id)
        }

        for geofence in active {
            if let existing = monitoredGeofences[geofence.id] {
                if !existing.matches(geofence) {
                    stopMonitoring(geofenceId: geofence.id)
                    startMonitoringRegion(for: geofence)
                }
            } else {
                startMonitoringRegion(for: geofence)
            }
        }

        monitoredGeofenceIds = Set(monitoredGeofences.keys)

        KBLog.app.kbInfo(
            "GeofenceMonitorService: monitoring count=\(monitoredGeofences.count) familyId=\(familyId)"
        )
    }

    /// Interrompe il monitoraggio di tutte le regioni.
    func stopMonitoring() {
        let ids = Array(monitoredGeofences.keys)
        for id in ids {
            stopMonitoring(geofenceId: id)
        }
        monitoredGeofenceIds = []
        KBLog.app.kbInfo("GeofenceMonitorService: stopped all regions familyId=\(familyId)")
    }

    /// Interrompe il monitoraggio di una singola geofence.
    func stopMonitoring(geofenceId: String) {
        guard let state = monitoredGeofences.removeValue(forKey: geofenceId) else { return }

        locationManager.stopMonitoring(for: state.region)
        monitoredGeofenceIds = Set(monitoredGeofences.keys)

        KBLog.app.kbDebug("GeofenceMonitorService: stopped region id=\(geofenceId)")
    }

    // MARK: - Private

    private var hasAlwaysAuthorization: Bool {
        locationManager.authorizationStatus == .authorizedAlways
    }

    private var authorizationStatusLabel: String {
        switch locationManager.authorizationStatus {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        @unknown default: return "unknown"
        }
    }

    private func effectiveRadius(for geofence: KBGeofence) -> CLLocationDistance {
        // Floor a 100 m: sotto questa soglia il region monitoring è inaffidabile
        // (falsi ingressi/uscite, eventi mancati). Parità col floor lato Android.
        let base = geofence.radius > 0 ? geofence.radius : Self.defaultRadiusMeters
        let requested = max(base, Self.minRadiusMeters)
        let maxAllowed = locationManager.maximumRegionMonitoringDistance
        return min(requested, maxAllowed)
    }

    private func startMonitoringRegion(for geofence: KBGeofence) {
        let center = CLLocationCoordinate2D(
            latitude: geofence.latitude,
            longitude: geofence.longitude
        )

        guard CLLocationCoordinate2DIsValid(center) else {
            KBLog.app.kbWarning("GeofenceMonitorService: invalid coordinates id=\(geofence.id)")
            return
        }

        let radius = effectiveRadius(for: geofence)
        let region = CLCircularRegion(
            center: center,
            radius: radius,
            identifier: geofence.id
        )
        region.notifyOnEntry = geofence.notifyOnArrive
        region.notifyOnExit = geofence.notifyOnLeave

        locationManager.startMonitoring(for: region)

        monitoredGeofences[geofence.id] = MonitoredGeofenceState(
            region: region,
            notifyOnArrive: geofence.notifyOnArrive,
            notifyOnLeave: geofence.notifyOnLeave,
            latitude: geofence.latitude,
            longitude: geofence.longitude,
            requestedRadius: geofence.radius > 0 ? geofence.radius : 200
        )

        KBLog.app.kbDebug(
            "GeofenceMonitorService: started region id=\(geofence.id) radius=\(Int(radius))m"
        )
    }

    private func handleRegionEvent(geofenceId: String, type: GeofenceTransitionType) {
        // Dopo un relaunch in background lo stato locale `monitoredGeofences` è vuoto
        // (le regioni sono però ancora registrate a livello OS). In quel caso ci fidiamo
        // di `notifyOnEntry/notifyOnExit` impostati sulla regione: iOS consegna solo le
        // transizioni richieste, e la Cloud Function ricontrolla comunque i flag sul doc.
        if let state = monitoredGeofences[geofenceId] {
            switch type {
            case .arrive:
                guard state.notifyOnArrive else { return }
            case .leave:
                guard state.notifyOnLeave else { return }
            }
        }

        if familyId.isEmpty || uid.isEmpty {
            restoreFromDefaults()
        }
        guard !familyId.isEmpty, !uid.isEmpty else {
            KBLog.app.kbDebug("GeofenceMonitorService: no context for region id=\(geofenceId), skip")
            return
        }

        KBLog.app.kbInfo(
            "GeofenceMonitorService: region \(type.rawValue) id=\(geofenceId) familyId=\(familyId)"
        )

        Task {
            await remoteEvent.writeEvent(
                familyId: familyId,
                geofenceId: geofenceId,
                uid: uid,
                displayName: displayName,
                type: type
            )
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        guard region is CLCircularRegion else { return }
        let geofenceId = region.identifier
        Task { @MainActor in
            handleRegionEvent(geofenceId: geofenceId, type: .arrive)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        guard region is CLCircularRegion else { return }
        let geofenceId = region.identifier
        Task { @MainActor in
            handleRegionEvent(geofenceId: geofenceId, type: .leave)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        let regionId = region?.identifier ?? "nil"
        Task { @MainActor in
            KBLog.app.kbError(
                "GeofenceMonitorService: monitoring failed region=\(regionId) err=\(error.localizedDescription)"
            )
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus != .authorizedAlways {
                KBLog.app.kbWarning(
                    "GeofenceMonitorService: authorizedAlways required (status=\(authorizationStatusLabel))"
                )
            }
        }
    }
}

// MARK: - Monitored state

private struct MonitoredGeofenceState {
    let region: CLCircularRegion
    let notifyOnArrive: Bool
    let notifyOnLeave: Bool
    let latitude: Double
    let longitude: Double
    let requestedRadius: Double

    func matches(_ geofence: KBGeofence) -> Bool {
        let radius = geofence.radius > 0 ? geofence.radius : 200
        return notifyOnArrive == geofence.notifyOnArrive &&
        notifyOnLeave == geofence.notifyOnLeave &&
        latitude == geofence.latitude &&
        longitude == geofence.longitude &&
        requestedRadius == radius
    }
}
