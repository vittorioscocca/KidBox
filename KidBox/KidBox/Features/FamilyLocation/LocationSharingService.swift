//
//  LocationSharingService.swift
//  KidBox
//
//  Created by vscocca on 30/09/26.
//

import Foundation
import UIKit
import CoreLocation
import Combine
import UserNotifications
internal import os
import FirebaseAuth
import FirebaseFirestore

/// Motore della condivisione posizione live di QUESTO dispositivo.
///
/// È un **singleton a vita-app**, come `GeofenceMonitorService`. Prima il
/// `CLLocationManager` viveva nel ViewModel della schermata Posizione, uno
/// `@StateObject` di una rotta push: tornando indietro SwiftUI lo rilasciava e
/// gli invii si fermavano, mentre la Home continuava a dire «condivisione
/// attiva» e gli altri vedevano il pin fermo. Il 30/09/2026 le due condivisioni
/// iOS attive avevano l'ultima posizione nell'istante in cui erano state
/// accese, 33 e 2,8 giorni prima.
///
/// Qui vive tutto ciò che deve sopravvivere alla schermata:
/// - lo stato persistito in `KBLocationDefaults` (lo legge anche la Home);
/// - la scrittura delle coordinate su `live/current`, con i due filtri;
/// - la scadenza della condivisione temporanea;
/// - la ripresa a ogni avvio dell'app, anche quando iOS la rilancia in
///   background per un significant location change: quell'evento arriva al
///   `CLLocationManager` di questa istanza, creata in `didFinishLaunching`.
///
/// La condivisione appartiene al dispositivo che l'ha avviata. Aprire la mappa
/// su un altro dispositivo dello stesso utente non la riprende da lì: prima
/// succedeva, e due dispositivi scrivevano la stessa posizione a turno.
@MainActor
final class LocationSharingService: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationSharingService()

    // MARK: - Stato (letto dalla schermata Posizione)

    @Published private(set) var isSharing = false
    @Published private(set) var mode: ShareMode?
    @Published private(set) var expiresAt: Date?
    /// Famiglia in cui questo dispositivo sta condividendo.
    @Published private(set) var familyId: String?
    /// Ultimo fix affidabile ricevuto, scritto o no: serve alla UI (indirizzo).
    @Published private(set) var lastLocation: CLLocation?

    // MARK: - Filtri

    /// Una scrittura al massimo ogni 45 s, qualunque sia il ritmo dei fix.
    private static let uploadInterval: TimeInterval = 45

    /// Distanza minima dall'ultima posizione **scritta** (non dall'ultimo fix
    /// consegnato, come fa `distanceFilter`): con il jitter GPS da fermo un
    /// telefono appoggiato sul tavolo continuerebbe a scrivere. Stesso gate di
    /// `LocationSharingService` su Android.
    private static let minUploadDistance: CLLocationDistance = 10

    /// Oltre questa precisione il fix non si usa: è una cella telefonica o
    /// peggio (il 30/09 sul server ce n'era uno da 50 km).
    private static let maxAccuracy: CLLocationAccuracy = 2000

    /// Un fix grossolano (celle, Wi-Fi) non sostituisce una posizione precisa
    /// scritta da poco: farebbe saltare il pin di centinaia di metri.
    private static let coarseAccuracy: CLLocationAccuracy = 200
    private static let preciseFixValidity: TimeInterval = 5 * 60

    /// Un fix più vecchio di così è la cache di CoreLocation, non dove sei ora.
    private static let maxFixAge: TimeInterval = 120

    /// Anche da fermi una scrittura almeno ogni 15 minuti, come su Android: chi
    /// guarda la mappa legge «aggiornata X fa», e senza battito un telefono
    /// fermo e uno che ha smesso di inviare sarebbero indistinguibili.
    private static let heartbeatInterval: TimeInterval = 15 * 60

    // MARK: - Risparmio batteria

    /// In movimento il GPS; da fermi la posizione da Wi-Fi e celle, che costa
    /// una frazione. Prima il GPS restava alla massima precisione anche col
    /// telefono sul tavolo, per una scrittura ogni 45 secondi al più.
    private enum PowerMode { case moving, stationary }
    private var powerMode: PowerMode = .moving

    /// Ultimo punto in cui ci si è mossi davvero, e quando.
    private var movementAnchor: CLLocation?
    private var lastMovementAt = Date()

    /// Sotto questo raggio un fix nuovo è ancora «lì»: il jitter da fermi.
    private static let movementRadius: CLLocationDistance = 30
    /// Da fermi da così tanto si spegne il GPS.
    private static let stationaryAfter: TimeInterval = 5 * 60
    /// Da fermi, quanto deve spostarsi un fix grossolano (oltre la sua
    /// imprecisione) perché si riaccenda il GPS.
    private static let wakeUpDistance: CLLocationDistance = 100

    // MARK: - Private

    private let remote = LocationRemoteStore()
    private let locationManager = CLLocationManager()

    private var uid: String?
    private var displayName = "Utente"

    private var lastUploadDate: Date?
    private var lastUploadedLocation: CLLocation?

    /// Le coordinate si scrivono solo dopo che il server ha confermato la
    /// condivisione accesa. Alla ripresa da `UserDefaults` il server potrebbe
    /// averla già spenta (scadenza, stop da un altro dispositivo): scrivere
    /// subito lascerebbe una posizione orfana che nessuno cancella.
    private var remoteConfirmed = false

    private var waitingForAuthorization = false
    private var expiryTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var statusListener: ListenerRegistration?
    private var statusRetryDelay: TimeInterval = 60

    /// Cambia a ogni avvio e a ogni stop: un `start` la cui scrittura arriva
    /// dopo uno stop sa di essere vecchio.
    private var session = 0

    // MARK: - Init

    private override init() {
        super.init()
        locationManager.delegate = self
        applyPowerMode(.moving)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Avvio app

    /// Riprende la condivisione se questo dispositivo la stava facendo.
    /// Chiamato da `AppDelegate` a ogni avvio, anche in background.
    func restoreFromDefaults() {
        let defaults = UserDefaults.standard
        guard
            !isSharing,
            defaults.bool(forKey: KBLocationDefaults.isSharing),
            let uid = defaults.string(forKey: KBLocationDefaults.uid), !uid.isEmpty,
            let familyId = defaults.string(forKey: KBLocationDefaults.familyId), !familyId.isEmpty
        else { return }

        // Un altro account su questo dispositivo: la condivisione del vecchio
        // non si riprende. Senza account (`nil`) invece si riprende lo stesso:
        // dopo un riavvio, a telefono ancora bloccato, iOS può rilanciare l'app
        // prima che il portachiavi sia leggibile.
        if let current = Auth.auth().currentUser?.uid, current != uid {
            KBLog.app.kbInfo("LocationSharing: account diverso da quello che condivideva → non riprende")
            clearDefaults()
            return
        }

        let expiresTimestamp = defaults.double(forKey: KBLocationDefaults.expiresAt)
        let expires = expiresTimestamp > 0 ? Date(timeIntervalSince1970: expiresTimestamp) : nil

        self.uid = uid
        self.familyId = familyId
        self.displayName = defaults.string(forKey: KBLocationDefaults.displayName) ?? "Utente"
        self.mode = expires == nil ? .realtime : .temporary
        self.expiresAt = expires
        self.isSharing = true

        if let expires, expires <= Date() {
            KBLog.app.kbInfo("LocationSharing: temporanea scaduta mentre l'app era chiusa → stop")
            Task { await stopSharing() }
            return
        }

        KBLog.app.kbInfo("LocationSharing: ripresa all'avvio familyId=\(familyId)")
        remoteConfirmed = false
        activate(promptForAuthorization: false)
    }

    // MARK: - Azioni

    /// Avvia la condivisione in `familyId`. `false` se la scrittura dello stato
    /// su Firestore fallisce (lo stato locale torna com'era prima).
    @discardableResult
    func start(familyId: String, displayName: String, mode: ShareMode, expiresAt: Date?) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return false }

        // Finché il server non conferma, niente coordinate: i fix che arrivano
        // durante il cambio finirebbero ancora nella sessione precedente.
        remoteConfirmed = false

        // Una condivisione sola per dispositivo: se era attiva in un'altra
        // famiglia, lì si chiude, o gli altri membri vedrebbero un pin fermo.
        if isSharing, let oldFamilyId = self.familyId, oldFamilyId != familyId, let oldUid = self.uid {
            await remote.stopSharing(familyId: oldFamilyId, uid: oldUid)
        }

        self.uid = uid
        self.familyId = familyId
        self.displayName = displayName
        self.mode = mode
        self.expiresAt = expiresAt
        self.isSharing = true
        persist()

        session += 1
        let startedSession = session

        do {
            try await remote.startSharing(
                familyId: familyId,
                uid: uid,
                name: displayName,
                mode: mode,
                expiresAt: expiresAt
            )
        } catch {
            KBLog.app.kbError("LocationSharing start failed: \(error.localizedDescription)")
            if session == startedSession { deactivate() }
            return false
        }

        // La scrittura può restare in volo a lungo (offline aspetta il server):
        // se nel frattempo l'utente ha fermato o riavviato, questa non riparte.
        guard session == startedSession, isSharing else { return false }

        // Il primo fix di una condivisione nuova parte subito, senza ereditare
        // i filtri della sessione precedente: da fermi verrebbe scartato e gli
        // altri resterebbero senza posizione.
        lastUploadDate = nil
        lastUploadedLocation = nil
        remoteConfirmed = true
        activate(promptForAuthorization: true)
        return true
    }

    /// Ferma la condivisione di questo dispositivo, localmente e su Firestore.
    func stopSharing() async {
        let familyId = self.familyId
        let uid = self.uid
        deactivate()
        if let familyId, let uid {
            await remote.stopSharing(familyId: familyId, uid: uid)
        }
    }

    /// Chiede il permesso posizione se manca (da chiamare con l'app in primo
    /// piano: all'apertura della schermata Posizione).
    func requestAuthorizationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Senza «Sempre» niente significant location changes: a app
            // terminata iOS non la rilancerebbe per riprendere la condivisione.
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - Ciclo di vita della sessione

    private func activate(promptForAuthorization: Bool) {
        // Ogni sessione parte col GPS: il primo fix deve essere preciso.
        movementAnchor = nil
        lastMovementAt = Date()
        applyPowerMode(.moving)
        scheduleExpiry()
        startHeartbeat()
        listenOwnStatus()
        setBadge(active: true)
        startUpdates(promptForAuthorization: promptForAuthorization)
    }

    /// Torna allo stato «non condivido» solo in locale: niente scritture.
    private func deactivate() {
        session += 1
        isSharing = false
        mode = nil
        expiresAt = nil
        familyId = nil
        uid = nil
        lastLocation = nil
        lastUploadDate = nil
        lastUploadedLocation = nil
        remoteConfirmed = false
        waitingForAuthorization = false

        expiryTask?.cancel()
        expiryTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        statusListener?.remove()
        statusListener = nil

        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        movementAnchor = nil
        applyPowerMode(.moving)

        clearDefaults()
        setBadge(active: false)
    }

    private func applyPowerMode(_ newMode: PowerMode) {
        powerMode = newMode
        switch newMode {
        case .moving:
            // «10 metri» e non «massima»: per una scrittura ogni 45 s basta, e
            // consuma meno. Il filtro dei 10 m resta quello di sempre.
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 10
        case .stationary:
            // Wi-Fi e celle: il GPS si spegne. I fix che arrivano servono solo
            // a capire se ci si è mossi (vedi `handle`), non si scrivono.
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager.distanceFilter = 50
        }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        guard mode == .temporary, let expiresAt else { return }

        let seconds = expiresAt.timeIntervalSinceNow
        guard seconds > 0 else {
            Task { await stopSharing() }
            return
        }
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return // cancellato
            }
            KBLog.app.kbInfo("LocationSharing: condivisione temporanea scaduta → stop")
            await self?.stopSharing()
        }
    }

    /// Da fermi `distanceFilter` non consegna fix, quindi il battito non può
    /// dipendere da loro: un controllo al minuto riscrive l'ultima posizione
    /// buona quando l'ultima scrittura ha più di 15 minuti. Con gli
    /// aggiornamenti di posizione attivi l'app resta viva in background, e il
    /// ciclo con lei.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                self.heartbeatIfDue()
            }
        }
    }

    private func heartbeatIfDue() {
        guard isSharing else { return }

        // Fermi da 5 minuti: si spegne il GPS. Il controllo sta qui e non in
        // `handle` perché da fermi `distanceFilter` non consegna fix che lo
        // facciano scattare.
        // Serve un punto di riferimento preciso: senza, da fermi non si
        // saprebbe più dire quando ci si è mossi.
        if powerMode == .moving, movementAnchor != nil,
           Date().timeIntervalSince(lastMovementAt) >= Self.stationaryAfter {
            KBLog.app.kbInfo("LocationSharing: fermi da 5 minuti → GPS spento, Wi-Fi e celle")
            applyPowerMode(.stationary)
        }

        // Dovuto anche quando in questa sessione non si è ancora scritto niente:
        // dopo una ripresa il primo fix può arrivare prima della conferma del
        // server, e da fermi non ne arrivano altri (prova del 30/09/2026: un
        // iPhone ripartito da `restoreFromDefaults` non ha più scritto nulla).
        let due = lastUploadDate.map { Date().timeIntervalSince($0) >= Self.heartbeatInterval } ?? true
        // L'ultima posizione SCRITTA prima dell'ultimo fix: da fermi i fix
        // sono grossolani, e riscriverli farebbe saltare il pin.
        guard due, let location = lastUploadedLocation ?? lastLocation else { return }

        if let expiresAt, expiresAt <= Date() {
            Task { await stopSharing() }
            return
        }
        upload(location)
    }

    /// Scrive `location` se il server ha confermato la condivisione e
    /// l'account è ancora quello che l'ha avviata.
    private func upload(_ location: CLLocation) {
        guard remoteConfirmed, let familyId, let uid,
              Auth.auth().currentUser?.uid == uid
        else { return }
        lastUploadDate = Date()
        lastUploadedLocation = location
        Task {
            await remote.updateLocation(familyId: familyId, uid: uid, location: location)
        }
    }

    /// Ascolta il proprio documento di stato: se la condivisione viene spenta
    /// altrove (scadenza lato server, stop da un altro dispositivo, famiglia o
    /// account cancellati) questo dispositivo smette di inviare.
    private func listenOwnStatus() {
        statusListener?.remove()
        statusListener = nil
        guard let familyId, let uid else { return }

        // `includeMetadataChanges: true` è indispensabile: se il documento in
        // cache è identico a quello del server, senza di esso Firestore non
        // manda l'aggiornamento «ora viene dal server» e la conferma non arriva
        // mai. Prova dal vivo del 30/09/2026: dopo ogni ripresa (reinstallazione,
        // riavvio) l'iPhone condivideva senza scrivere niente.
        statusListener = Firestore.firestore()
            .collection("families").document(familyId)
            .collection("locations").document(uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
                if let error {
                    let denied = (error as NSError).code == FirestoreErrorCode.permissionDenied.rawValue
                    Task { @MainActor in
                        KBLog.app.kbError("LocationSharing status listener: \(error.localizedDescription)")
                        guard let self, self.isSharing, self.familyId == familyId else { return }
                        // Negato con l'account giusto = non più membro di quella
                        // famiglia: le scritture verrebbero negate comunque, e il
                        // GPS resterebbe acceso per niente. Negato senza account
                        // (riavvio a telefono bloccato) o per rete: si riprova.
                        if denied, Auth.auth().currentUser?.uid == uid {
                            self.deactivate()
                        } else {
                            self.retryStatusListener()
                        }
                    }
                    return
                }
                // Solo la parola del server: una cache vuota o una nostra
                // scrittura non ancora confermata non dicono niente.
                guard let snap, !snap.metadata.isFromCache, !snap.metadata.hasPendingWrites else { return }
                let sharingOnServer = snap.data()?["isSharing"] as? Bool ?? false
                Task { @MainActor in
                    guard let self, self.isSharing, self.familyId == familyId else { return }
                    self.statusRetryDelay = 60
                    if sharingOnServer {
                        self.remoteConfirmed = true
                        // Il fix arrivato prima della conferma parte adesso: da
                        // fermi potrebbe non arrivarne un altro.
                        if self.lastUploadDate == nil, let pending = self.lastLocation {
                            self.upload(pending)
                        }
                    } else {
                        KBLog.app.kbInfo("LocationSharing: spenta sul server → stop locale")
                        self.deactivate()
                    }
                }
            }
    }

    /// Un listener Firestore andato in errore non si riprende da solo: senza
    /// questo, dopo un errore la conferma del server non arriverebbe più e le
    /// coordinate non partirebbero fino al prossimo avvio. L'attesa raddoppia
    /// fino a 15 minuti: senza account leggibile ogni tentativo è una lettura
    /// negata, e non deve diventarne una al minuto per sempre.
    private func retryStatusListener() {
        statusListener?.remove()
        statusListener = nil
        let delay = statusRetryDelay
        statusRetryDelay = min(statusRetryDelay * 2, 15 * 60)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isSharing, self.statusListener == nil else { return }
            self.listenOwnStatus()
        }
    }

    // MARK: - Aggiornamenti di posizione

    private func startUpdates(promptForAuthorization: Bool) {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            waitingForAuthorization = false
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
            // Rilancia l'app anche dopo che è stata terminata: funziona solo con «Sempre».
            if status == .authorizedAlways {
                locationManager.startMonitoringSignificantLocationChanges()
            } else if promptForAuthorization {
                locationManager.requestAlwaysAuthorization()
            }
        case .notDetermined:
            waitingForAuthorization = true
            if promptForAuthorization {
                locationManager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            waitingForAuthorization = false
            KBLog.app.kbError("LocationSharing: permesso posizione negato")
        @unknown default:
            waitingForAuthorization = false
        }
    }

    private func handle(_ location: CLLocation) {
        guard isSharing, familyId != nil, let uid else { return }

        if let expiresAt, expiresAt <= Date() {
            Task { await stopSharing() }
            return
        }

        // Con «Posizione esatta» spenta ogni fix è approssimativo per scelta
        // dell'utente (chilometri): i due filtri sulla precisione lo
        // scarterebbero sempre, e quel telefono non scriverebbe più niente.
        let approximateOnly = locationManager.accuracyAuthorization == .reducedAccuracy

        guard
            location.horizontalAccuracy >= 0,
            approximateOnly || location.horizontalAccuracy <= Self.maxAccuracy,
            abs(location.timestamp.timeIntervalSinceNow) <= Self.maxFixAge
        else { return }

        if !approximateOnly,
           location.horizontalAccuracy > Self.coarseAccuracy,
           let lastUploaded = lastUploadedLocation,
           lastUploaded.horizontalAccuracy <= Self.coarseAccuracy,
           location.timestamp.timeIntervalSince(lastUploaded.timestamp) < Self.preciseFixValidity {
            return
        }

        if powerMode == .stationary {
            // Da fermi arrivano fix da Wi-Fi e celle: dicono solo se ci si è
            // mossi. Scritti, farebbero saltare il pin; il battito riscrive
            // l'ultima posizione precisa. Se ci si è allontanati davvero (oltre
            // l'imprecisione del fix), si riaccende il GPS e si scrive il
            // prossimo fix preciso.
            if let anchor = movementAnchor,
               location.distance(from: anchor) > Self.wakeUpDistance + location.horizontalAccuracy {
                KBLog.app.kbInfo("LocationSharing: di nuovo in movimento → GPS")
                movementAnchor = nil
                lastMovementAt = Date()
                applyPowerMode(.moving)
            }
            return
        }

        // Uno spostamento più piccolo dell'imprecisione del fix è rumore, non
        // movimento: vale per capire se si è fermi e per decidere se scrivere.
        let noise = max(Self.movementRadius, location.horizontalAccuracy)
        if let anchor = movementAnchor, location.distance(from: anchor) < noise {
            // Ancora lì: il jitter da fermi non conta come movimento.
        } else {
            movementAnchor = location
            lastMovementAt = Date()
        }

        lastLocation = location

        // Prima della conferma del server il fix resta in `lastLocation` e parte
        // alla conferma (vedi `listenOwnStatus`). Account cambiato su questo
        // dispositivo senza passare dallo stop: niente.
        guard remoteConfirmed, Auth.auth().currentUser?.uid == uid else { return }

        let now = Date()
        if let last = lastUploadDate, now.timeIntervalSince(last) < Self.uploadInterval {
            return
        }
        // Volutamente senza toccare `lastUploadDate`: da fermi non si scrive,
        // ma il fix successivo rivaluta subito la distanza invece di aspettare
        // altri 45 s, così appena ci si muove la posizione parte.
        // Oltre i 10 m, e anche oltre l'imprecisione del fix: al chiuso un
        // iPhone fermo con fix da ±12 m scriveva ogni pochi minuti (prova del
        // 30/09). In movimento vero lo spostamento supera l'imprecisione, e il
        // fix si scrive anche se grossolano: in macchina il pin non si ferma.
        if let lastUploaded = lastUploadedLocation,
           location.distance(from: lastUploaded) < max(Self.minUploadDistance, location.horizontalAccuracy) {
            return
        }

        upload(location)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.handle(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            KBLog.app.kbError("LocationSharing update failed: \(error.localizedDescription)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.isSharing else { return }
            switch self.locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                // Anche il passaggio a «Sempre» a condivisione già attiva:
                // riavvia per accendere i significant location changes.
                let foreground = UIApplication.shared.applicationState == .active
                self.startUpdates(promptForAuthorization: foreground)
            case .denied, .restricted:
                KBLog.app.kbError("LocationSharing: permesso posizione revocato")
            default:
                break
            }
        }
    }

    // MARK: - Persistenza (letta dalla Home e alla ripresa)

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(uid, forKey: KBLocationDefaults.uid)
        defaults.set(familyId, forKey: KBLocationDefaults.familyId)
        defaults.set(displayName, forKey: KBLocationDefaults.displayName)
        defaults.set(true, forKey: KBLocationDefaults.isSharing)
        if let expiresAt {
            defaults.set(expiresAt.timeIntervalSince1970, forKey: KBLocationDefaults.expiresAt)
        } else {
            defaults.removeObject(forKey: KBLocationDefaults.expiresAt)
        }
        NotificationCenter.default.post(name: .kbLocationSharingStateChanged, object: nil)
    }

    private func clearDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: KBLocationDefaults.uid)
        defaults.removeObject(forKey: KBLocationDefaults.familyId)
        defaults.removeObject(forKey: KBLocationDefaults.displayName)
        defaults.removeObject(forKey: KBLocationDefaults.expiresAt)
        defaults.set(false, forKey: KBLocationDefaults.isSharing)
        NotificationCenter.default.post(name: .kbLocationSharingStateChanged, object: nil)
    }

    /// Badge 1 sull'icona mentre la condivisione è attiva.
    private func setBadge(active: Bool) {
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(active ? 1 : 0)
            } catch {
                KBLog.app.kbError("LocationSharing setBadge failed: \(error.localizedDescription)")
            }
        }
    }
}
