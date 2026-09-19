//
//  KBDeviceSessionRegistry.swift
//  KidBox
//
//  Registro dei dispositivi collegati all'account, e leva del logout remoto.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit

/// Un documento per dispositivo in `users/{uid}/sessions/{sessionId}`.
///
/// Firebase Auth non sa niente dei dispositivi: ogni device ha un suo refresh
/// token, ma lato server non esiste un elenco delle sessioni aperte né un modo
/// di revocarne una sola — `revokeRefreshTokens` vale per tutto l'account.
/// Questo registro è quell'elenco, tenuto da noi.
///
/// Il logout remoto che ne deriva è **cooperativo**: ogni client ascolta il
/// proprio documento e, quando lo vede sparire, si slogga da sé. Copre il caso
/// reale — il vecchio portatile, il tablet di casa — ma non un'app modificata
/// che decidesse di ignorarlo. Per quello c'è `signOutAllDevices`, che revoca
/// davvero lato Firebase.
@MainActor
final class KBDeviceSessionRegistry {

    static let shared = KBDeviceSessionRegistry()
    private init() {}

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var activeUid: String?
    private var onRevoked: (() -> Void)?

    // MARK: - Identità del dispositivo

    private static let installIdKey = "kb_installId"

    /// Identificatore di QUESTA installazione, stabile finché l'app non viene
    /// disinstallata. Non è l'identificatore del telefono — non ne esiste uno
    /// lecito e persistente su iOS — e non serve che lo sia: basta distinguere
    /// una riga dall'altra nell'elenco.
    ///
    /// Il documento vive sotto l'uid, quindi stessa installazione e account
    /// diversi restano sessioni diverse. È quello che serve: se sul telefono si
    /// logga un altro familiare, non deve ereditare la sessione di chi c'era.
    static var installId: String {
        if let existing = UserDefaults.standard.string(forKey: installIdKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: installIdKey)
        return fresh
    }

    /// Nome mostrato nell'elenco. Volutamente grossolano: da iOS 16 il nome che
    /// l'utente ha dato al telefono non è più leggibile senza entitlement, e il
    /// codice modello (`iPhone15,3`) andrebbe tradotto con una tabella che
    /// invecchia a ogni uscita Apple. «iPhone» e la versione di sistema bastano
    /// a farsi riconoscere in una lista di due o tre righe.
    static var deviceName: String {
        #if targetEnvironment(macCatalyst)
        return "Mac"
        #else
        return UIDevice.current.model
        #endif
    }

    private static var osVersion: String {
        "iOS \(UIDevice.current.systemVersion)"
    }

    private static var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    // MARK: - Ciclo di vita

    /// Registra questa sessione e comincia ad ascoltarla.
    ///
    /// `onRevoked` scatta quando il documento viene cancellato da un altro
    /// dispositivo: tocca al chiamante eseguire il logout vero e proprio, che
    /// qui dentro non si può fare (serve il `ModelContext` per ripulire i dati
    /// locali, e questo oggetto non deve saperne niente).
    func start(uid: String, onRevoked: @escaping () -> Void) {
        guard activeUid != uid else { return }
        stop()
        activeUid = uid
        self.onRevoked = onRevoked

        let ref = db.collection("users").document(uid)
            .collection("sessions").document(Self.installId)

        Task {
            do {
                try await ref.setData([
                    "platform": "ios",
                    "deviceName": Self.deviceName,
                    "osVersion": Self.osVersion,
                    "appVersion": Self.appVersion,
                    "lastSeenAt": FieldValue.serverTimestamp(),
                ], merge: true)
                KBLog.auth.kbInfo("Sessione registrata")
            } catch {
                KBLog.auth.kbError("Registrazione sessione fallita: \(error.localizedDescription)")
            }
            // L'ascolto parte comunque, anche se la scrittura è fallita: se il
            // documento non c'è perché non siamo riusciti a crearlo, la
            // condizione qui sotto NON slogga — richiede una conferma dal
            // server di un documento che prima esisteva.
            self.observe(ref)
        }
    }

    private func observe(_ ref: DocumentReference) {
        var sawDocument = false

        listener = ref.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, error in
            guard let self, let snap else {
                if let error {
                    KBLog.auth.kbError("Listener sessione: \(error.localizedDescription)")
                }
                return
            }

            // Solo dal server. Offline, o all'avvio senza rete, Firestore
            // risponde dalla cache: un documento cancellato altrove risulta
            // ancora presente (e quindi non si slogga nessuno per sbaglio), ma
            // soprattutto un'assenza dalla cache non è una prova di
            // cancellazione — sloggherebbe chi apre l'app in aereo.
            guard !snap.metadata.isFromCache else { return }

            if snap.exists {
                sawDocument = true
                return
            }

            // Assente sul server. Se non l'abbiamo mai visto esistere, è la
            // registrazione che non è andata a buon fine: non è una revoca.
            guard sawDocument else { return }

            KBLog.auth.kbInfo("Sessione revocata da un altro dispositivo — logout")
            Task { @MainActor in
                // La chiusura va presa PRIMA di `stop()`, che azzera
                // `onRevoked` insieme al listener: invertendo i due, qui si
                // chiamava un riferimento ormai nil e il logout non avveniva
                // mai — il log diceva «revocata» e l'app restava dentro.
                let callback = self.onRevoked
                self.stop()
                callback?()
            }
        }
    }

    /// Smette di ascoltare. Non tocca il documento: si usa quando l'utente
    /// cambia, o quando il logout è già stato deciso altrove.
    func stop() {
        listener?.remove()
        listener = nil
        activeUid = nil
        onRevoked = nil
    }

    /// Logout volontario da questo dispositivo: il documento va tolto, o la
    /// sessione resterebbe nell'elenco degli altri dispositivi per sempre.
    ///
    /// Va chiamato PRIMA di `Auth.signOut()`: dopo, le rules non lascerebbero
    /// più scrivere.
    func stopAndRemove() async {
        guard let uid = activeUid ?? Auth.auth().currentUser?.uid else {
            stop()
            return
        }
        let ref = db.collection("users").document(uid)
            .collection("sessions").document(Self.installId)
        stop()
        do {
            try await ref.delete()
        } catch {
            KBLog.auth.kbError("Rimozione sessione fallita: \(error.localizedDescription)")
        }
    }
}
