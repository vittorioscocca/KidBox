//
//  LocationRemoteStore.swift
//  KidBox
//
//  Created by vscocca on 24/02/26.
//

import FirebaseFirestore
import FirebaseAuth
import CoreLocation
internal import os

final class LocationRemoteStore {

    private let db = Firestore.firestore()

    func startSharing(
        familyId: String,
        uid: String,
        name: String,
        mode: ShareMode,
        expiresAt: Date?
    ) async throws {

        var data: [String: Any] = [
            "isSharing": true,
            "mode": mode.rawValue,
            "name": name,
            "startedAt": FieldValue.serverTimestamp(),
            "lastUpdateAt": FieldValue.serverTimestamp()
        ]

        if let expiresAt {
            data["expiresAt"] = expiresAt
        }

        try await db.collection("families")
            .document(familyId)
            .collection("locations")
            .document(uid)
            .setData(data, merge: true)
    }

    /// Aggiorna solo le coordinate, su un documento SEPARATO da quello di stato
    /// (`locations/{uid}`). Il fix GPS arriva ogni pochi metri — se scrivesse
    /// sullo stesso documento di `startSharing`/`stopSharing`, ogni singolo
    /// aggiornamento farebbe scattare `notifyLocationSharingChanged` lato
    /// server (che osserva quel documento): con la condivisione attiva era
    /// arrivata a essere il 94% di tutte le invocazioni Cloud Functions del
    /// progetto. Scrivendo altrove, il trigger dello stato smette di vedere
    /// questi aggiornamenti — non serve toccare `index.js`.
    func updateLocation(
        familyId: String,
        uid: String,
        location: CLLocation
    ) async {
        // La batteria viaggia dentro questa stessa scrittura: nessun documento
        // nuovo, nessuna scrittura in più, nessun tocco al documento di stato
        // (che è quello osservato dalle Cloud Functions).
        let battery = await DeviceBattery.snapshot()

        var payload: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "lastUpdateAt": FieldValue.serverTimestamp()
        ]
        // Il campo si omette quando il livello non è noto: scrivere un valore
        // finto farebbe apparire in mappa una percentuale inventata.
        if let percentage = battery.percentage {
            payload["battery"] = percentage
            payload["batteryCharging"] = battery.isCharging
        }

        do {
            try await liveLocationRef(familyId: familyId, uid: uid)
                .setData(payload, merge: true)
        } catch {
            KBLog.app.kbError("LocationRemoteStore updateLocation failed: \(error.localizedDescription)")
        }
    }

    func stopSharing(familyId: String, uid: String) async {
        try? await db.collection("families")
            .document(familyId)
            .collection("locations")
            .document(uid)
            .setData([
                "isSharing": false
            ], merge: true)
    }

    func updateDisplayName(familyId: String, uid: String, displayName: String) async {
        do {
            try await db.collection("families")
                .document(familyId)
                .collection("locations")
                .document(uid)
                .setData([
                    "name": displayName,
                    "lastUpdateAt": FieldValue.serverTimestamp()
                ], merge: true)
        } catch {
            KBLog.app.kbError("LocationRemoteStore updateDisplayName failed: \(error.localizedDescription)")
        }
    }

    /// Ascolta lo stato condivisione di tutta la famiglia (`locations/{uid}`,
    /// scritture rare) e apre/chiude in fan-out un listener di coordinate per
    /// ogni utente attualmente in sharing (`locations/{uid}/live/current`,
    /// scritture frequenti). I due stream vengono uniti a ogni cambiamento
    /// dell'uno o dell'altro: `SharedUserLocation` esce solo per chi ha sia
    /// stato "in sharing" sia una coordinata nota — stesso contratto di prima,
    /// quando tutto viveva in un unico documento.
    func listen(
        familyId: String,
        onChange: @escaping ([SharedUserLocation]) -> Void
    ) -> ListenerRegistration {

        struct Status {
            let name: String
            let mode: ShareMode
            let expiresAt: Date?
            let avatarURL: String?
        }

        var statusByUid: [String: Status] = [:]
        var coordListeners: [String: ListenerRegistration] = [:]
        var coordByUid: [String: (lat: Double, lon: Double, battery: Int?, charging: Bool)] = [:]

        // Riferimenti catturati come valori: le closure dei listener vivono
        // finché non si chiama `remove()`, e catturare `self` terrebbe in vita
        // lo store per tutto quel tempo.
        let locationsRef = db.collection("families")
            .document(familyId)
            .collection("locations")
        let liveRef: (String) -> DocumentReference = { uid in
            locationsRef.document(uid).collection("live").document("current")
        }

        func emit() {
            let users: [SharedUserLocation] = statusByUid.compactMap { uid, status in
                guard let coord = coordByUid[uid] else { return nil }
                return SharedUserLocation(
                    id: uid,
                    name: status.name,
                    latitude: coord.lat,
                    longitude: coord.lon,
                    mode: status.mode,
                    expiresAt: status.expiresAt,
                    avatarURL: status.avatarURL,
                    batteryLevel: coord.battery,
                    isCharging: coord.charging
                )
            }
            onChange(users)
        }

        func syncCoordListeners() {
            let wanted = Set(statusByUid.keys)

            // `Array(...)` non è cosmetico: iterare `coordListeners.keys`
            // mentre si rimuove dallo stesso dizionario itera su una copia
            // implicita (CoW), quindi il ciclo lavorerebbe su uno stato già
            // stantio. Si fa una fotografia esplicita delle chiavi.
            for uid in Array(coordListeners.keys) where !wanted.contains(uid) {
                coordListeners[uid]?.remove()
                coordListeners.removeValue(forKey: uid)
                coordByUid.removeValue(forKey: uid)
            }

            for uid in wanted where coordListeners[uid] == nil {
                let reg = liveRef(uid)
                    .addSnapshotListener { snap, _ in
                        guard
                            let data = snap?.data(),
                            let lat = data["lat"] as? Double,
                            let lon = data["lon"] as? Double
                        else {
                            coordByUid.removeValue(forKey: uid)
                            emit()
                            return
                        }
                        // `as? Int` da solo non basta: il numero arriva come
                        // `NSNumber`, e a seconda di come l'ha scritto il
                        // dispositivo che condivide (iOS o Android) il cast
                        // diretto può non riuscire.
                        let battery = (data["battery"] as? NSNumber)?.intValue
                            ?? (data["battery"] as? Int)

                        coordByUid[uid] = (
                            lat,
                            lon,
                            battery,
                            (data["batteryCharging"] as? NSNumber)?.boolValue
                                ?? (data["batteryCharging"] as? Bool)
                                ?? false
                        )
                        emit()
                    }
                coordListeners[uid] = reg
            }
        }

        let statusReg = locationsRef
            .addSnapshotListener { snap, _ in

                guard let snap else { return }

                var newStatus: [String: Status] = [:]

                for doc in snap.documents {
                    let data = doc.data()

                    guard
                        data["isSharing"] as? Bool == true,
                        let name = data["name"] as? String,
                        let modeRaw = data["mode"] as? String,
                        let mode = ShareMode(rawValue: modeRaw)
                    else { continue }

                    let expires = (data["expiresAt"] as? Timestamp)?.dateValue()

                    // Scarta temporanei scaduti
                    if mode == .temporary,
                       let expires,
                       expires < Date() {
                        continue
                    }

                    let avatarURL = data["avatarURL"] as? String

                    newStatus[doc.documentID] = Status(
                        name: name,
                        mode: mode,
                        expiresAt: expires,
                        avatarURL: avatarURL
                    )
                }

                statusByUid = newStatus
                syncCoordListeners()
                emit()
            }

        return FanOutRegistration {
            statusReg.remove()
            for (_, reg) in coordListeners { reg.remove() }
            coordListeners.removeAll()
        }
    }

    private func liveLocationRef(familyId: String, uid: String) -> DocumentReference {
        db.collection("families")
            .document(familyId)
            .collection("locations")
            .document(uid)
            .collection("live")
            .document("current")
    }
}

/// `ListenerRegistration` composito: alla `remove()` chiude sia il listener
/// principale sia tutti quelli aperti in fan-out, così il chiamante continua a
/// vedere un singolo handle da tenere e rilasciare (come prima dello split).
private final class FanOutRegistration: NSObject, ListenerRegistration {
    private let onRemove: () -> Void
    private var removed = false

    init(onRemove: @escaping () -> Void) {
        self.onRemove = onRemove
    }

    func remove() {
        guard !removed else { return }
        removed = true
        onRemove()
    }
}
