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
@MainActor
final class GeofenceMonitorService: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Published

    @Published private(set) var monitoredGeofenceIds: Set<String> = []

    // MARK: - Dependencies

    private let remoteEvent = GeofenceRemoteEvent()
    private let locationManager = CLLocationManager()

    private let familyId: String
    private let uid: String
    private let displayName: String

    /// Metadati locale per regioni attive (identifier = geofence.id).
    private var monitoredGeofences: [String: MonitoredGeofenceState] = [:]

    // MARK: - Init

    init(familyId: String, uid: String, displayName: String) {
        self.familyId = familyId
        self.uid = uid
        self.displayName = displayName
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.pausesLocationUpdatesAutomatically = false
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
        let requested = geofence.radius > 0 ? geofence.radius : 200
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
        guard let state = monitoredGeofences[geofenceId] else {
            KBLog.app.kbDebug("GeofenceMonitorService: unknown region id=\(geofenceId)")
            return
        }

        switch type {
        case .arrive:
            guard state.notifyOnArrive else { return }
        case .leave:
            guard state.notifyOnLeave else { return }
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
