import Foundation
import SwiftUI
import MapKit
import CoreLocation
import Combine
internal import os
import FirebaseAuth
import FirebaseFirestore

/// Stato della schermata Posizione: mappa della famiglia, zone, e lo stato
/// della propria condivisione **letto** da `LocationSharingService`.
///
/// La condivisione non vive più qui: questo ViewModel è uno `@StateObject` di
/// una rotta push, e quando teneva il `CLLocationManager` tornare indietro
/// bastava a fermare gli invii (vedi `LocationSharingService`).
@MainActor
final class FamilyLocationViewModel: ObservableObject {

    // MARK: - Published

    @Published var sharedUsers: [SharedUserLocation] = []

    /// Stato della condivisione di questo dispositivo **in questa famiglia**:
    /// il servizio può condividere in un'altra.
    @Published private(set) var isSharing: Bool = false
    @Published private(set) var myMode: ShareMode?
    @Published private(set) var myExpiresAt: Date?
    @Published private(set) var myCurrentAddress: String? = nil

    @Published var geofences: [KBGeofence] = []

    // MARK: - Private

    private let remote = LocationRemoteStore()
    private var listener: ListenerRegistration?

    private var geofenceListener: ListenerRegistration?
    private let geofenceRemote = GeofenceRemoteStore()

    private let sharing = LocationSharingService.shared
    private let familyId: String
    private var cancellables = Set<AnyCancellable>()

    /// Reverse geocoding per l'indirizzo nella card: solo con la schermata
    /// aperta, e non a ogni fix. Prima partiva a ogni posizione, anche in
    /// background e prima di ogni filtro, e `CLGeocoder` è limitato da Apple:
    /// in macchina le richieste venivano rifiutate.
    private let geocoder = CLGeocoder()
    private var lastGeocodedLocation: CLLocation?
    private var lastGeocodeDate: Date?
    private static let geocodeMinDistance: CLLocationDistance = 50
    private static let geocodeMinInterval: TimeInterval = 30

    /// Nome canonico (SwiftData) passato dalla View. Il self-healing avviene
    /// in `healRemoteDisplayNameIfNeeded()`, guidato dal listener: prima veniva
    /// riscritto a ogni fix GPS dentro `updateLocation`, ma quella scrittura
    /// finiva sul documento di stato e faceva scattare
    /// `notifyLocationSharingChanged` ogni pochi secondi.
    private(set) var myCurrentDisplayName: String = "Utente"

    // MARK: - Init

    init(familyId: String) {
        self.familyId = familyId

        Publishers.CombineLatest4(sharing.$isSharing, sharing.$familyId, sharing.$mode, sharing.$expiresAt)
            .sink { [weak self] active, sharingFamilyId, mode, expiresAt in
                guard let self else { return }
                let here = active && sharingFamilyId == self.familyId
                self.isSharing = here
                self.myMode = here ? mode : nil
                self.myExpiresAt = here ? expiresAt : nil
                if !here {
                    self.myCurrentAddress = nil
                    self.lastGeocodedLocation = nil
                }
            }
            .store(in: &cancellables)

        sharing.$lastLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.updateAddressIfNeeded(for: location)
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        listen()
        listenGeofences()
        sharing.requestAuthorizationIfNeeded()
        syncGeofenceMonitor()
    }

    func stop() {
        listener?.remove()
        listener = nil

        geofenceListener?.remove()
        geofenceListener = nil
        // NON si fermano né il monitoraggio geofence né la condivisione: vivono
        // nei singleton `GeofenceMonitorService` e `LocationSharingService`.
        geocoder.cancelGeocode()
    }

    // MARK: - Firestore listen

    private func listen() {
        listener = remote.listen(familyId: familyId) { [weak self] users in
            Task { @MainActor in
                guard let self else { return }
                self.sharedUsers = users
                self.healRemoteDisplayNameIfNeeded()
            }
        }
    }

    private func listenGeofences() {
        geofenceListener?.remove()
        geofenceListener = geofenceRemote.listen(
            familyId: familyId,
            onChange: { [weak self] changes in
                Task { @MainActor in
                    guard let self else { return }
                    self.applyGeofenceChanges(changes)
                }
            },
            onError: { error in
                KBLog.sync.kbError("FamilyLocation geofence listener: \(error.localizedDescription)")
            }
        )
    }

    private func applyGeofenceChanges(_ changes: [GeofenceRemoteChange]) {
        guard !changes.isEmpty else { return }

        var byId = Dictionary(uniqueKeysWithValues: geofences.map { ($0.id, $0) })

        for change in changes {
            switch change {
            case .upsert(let dto):
                if dto.isDeleted {
                    byId.removeValue(forKey: dto.id)
                } else {
                    byId[dto.id] = geofence(from: dto)
                }
            case .remove(let id):
                byId.removeValue(forKey: id)
            }
        }

        geofences = byId.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        syncGeofenceMonitor()
    }

    private func geofence(from dto: GeofenceRemoteDTO) -> KBGeofence {
        KBGeofence(
            id: dto.id,
            familyId: dto.familyId,
            name: dto.name,
            emoji: dto.emoji,
            latitude: dto.latitude,
            longitude: dto.longitude,
            radius: dto.radius,
            notifyOnArrive: dto.notifyOnArrive,
            notifyOnLeave: dto.notifyOnLeave,
            notifyMembers: dto.notifyMembers,
            monitoredMemberIds: dto.monitoredMemberIds,
            isActive: dto.isActive,
            createdBy: dto.createdBy ?? "",
            createdAt: dto.createdAt ?? Date(),
            updatedAt: dto.updatedAt ?? Date(),
            isDeleted: dto.isDeleted
        )
    }

    // MARK: - Geofence monitoring

    /// La zona si applica al telefono dell'utente corrente se `monitoredMemberIds` è vuoto o contiene il suo uid.
    private func geofenceAppliesToCurrentUser(_ geofence: KBGeofence) -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return false }
        let monitored = geofence.monitoredMemberIds
        if monitored.isEmpty { return true }
        return monitored.contains(uid)
    }

    /// Monitoraggio geofence INDIPENDENTE dalla condivisione live: una zona applicata a una
    /// persona deve generare arrivo/uscita anche con lo sharing spento. Usa il singleton
    /// `GeofenceMonitorService.shared` (un solo CLLocationManager a vita-app).
    private func syncGeofenceMonitor() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let active = geofences.filter { geofence in
            geofence.isActive && !geofence.isDeleted && geofenceAppliesToCurrentUser(geofence)
        }
        guard !uid.isEmpty, !active.isEmpty else {
            GeofenceMonitorService.shared.stopMonitoring()
            return
        }
        GeofenceMonitorService.shared.configure(
            familyId: familyId,
            uid: uid,
            displayName: myCurrentDisplayName
        )
        GeofenceMonitorService.shared.startMonitoring(geofences: active)
    }

    /// Riallinea il nome su Firestore se è rimasto indietro rispetto a quello
    /// canonico locale (es. profilo rinominato mentre la condivisione era già
    /// attiva su un altro device). È una scrittura sul documento di STATO,
    /// quindi fa scattare il trigger server: si esegue solo quando i due nomi
    /// divergono davvero, non a ogni aggiornamento di posizione.
    private func healRemoteDisplayNameIfNeeded() {
        guard isSharing, myCurrentDisplayName != "Utente",
              let uid = Auth.auth().currentUser?.uid, !uid.isEmpty,
              let me = sharedUsers.first(where: { $0.id == uid }),
              me.name != myCurrentDisplayName
        else { return }

        Task {
            await remote.updateDisplayName(
                familyId: familyId,
                uid: uid,
                displayName: myCurrentDisplayName
            )
        }
    }

    // MARK: - Actions

    func startRealtime(displayName: String) async {
        myCurrentDisplayName = displayName
        await sharing.start(familyId: familyId, displayName: displayName, mode: .realtime, expiresAt: nil)
        syncGeofenceMonitor()
    }

    func startTemporary(hours: Int, displayName: String) async {
        myCurrentDisplayName = displayName
        let expires = Date().addingTimeInterval(Double(hours) * 3600)
        await sharing.start(familyId: familyId, displayName: displayName, mode: .temporary, expiresAt: expires)
        syncGeofenceMonitor()
    }

    func stopSharing() async {
        guard isSharing else { return }
        await sharing.stopSharing()
        syncGeofenceMonitor()
    }

    // MARK: - FIX: aggiorna il nome mentre la condivisione è attiva

    /// Chiama questo ogni volta che il profilo viene salvato o la view appare,
    /// così il nome su Firestore e su tutti i device è sempre quello corretto.
    func updateDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Utente" else { return }
        guard trimmed != myCurrentDisplayName else { return } // nessun cambiamento, evita write inutile

        myCurrentDisplayName = trimmed
        KBLog.app.kbDebug("FamilyLocation updateDisplayName -> \(trimmed)")

        // Si riscrive solo se il nome sul server è davvero diverso. La View lo
        // chiama a ogni apertura, e ora `isSharing` è vero fin da subito (lo
        // stato viene dal servizio, non più dal primo snapshot): scrivendo
        // sempre, ogni apertura della mappa riscriveva il documento di stato e
        // accendeva `notifyLocationSharingChanged` per niente.
        healRemoteDisplayNameIfNeeded()
    }

    // MARK: - Indirizzo nella card

    private func updateAddressIfNeeded(for location: CLLocation) {
        guard isSharing else { return }
        if let last = lastGeocodedLocation,
           location.distance(from: last) < Self.geocodeMinDistance {
            return
        }
        if let lastDate = lastGeocodeDate,
           Date().timeIntervalSince(lastDate) < Self.geocodeMinInterval {
            return
        }
        guard !geocoder.isGeocoding else { return }

        lastGeocodedLocation = location
        lastGeocodeDate = Date()
        Task {
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return }
            let street = placemark.thoroughfare ?? ""
            let number = placemark.subThoroughfare ?? ""
            let city   = placemark.locality ?? ""
            let parts  = [street, number, city].filter { !$0.isEmpty }
            guard isSharing else { return }
            myCurrentAddress = parts.isEmpty ? nil : parts.joined(separator: " ")
        }
    }
}
