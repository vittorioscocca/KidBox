//
//  KBActiveFamilyRemoteStore.swift
//  KidBox
//
//  Famiglia attiva ricordata sull'account, non sul dispositivo.
//
//  Il logout fa piazza pulita in locale — ed è giusto, altrimenti i dati di un
//  account resterebbero nella sessione del successivo. Ma così si perdeva anche
//  "stavo nella famiglia B": al rientro l'app ripartiva dalla prima famiglia che
//  rispondeva, di solito la più vecchia.
//
//  Il posto giusto per questa informazione è `users/{uid}.activeFamilyId`: è del
//  conto, non del telefono, sopravvive a logout e reinstallazioni e segue
//  l'utente anche fra iOS e Android.
//
//  Le rules lo consentono: `users/{uid}` è aggiornabile dal proprietario purché
//  non tocchi i campi del piano (`keepsPlanFields()`).
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum KBActiveFamilyRemoteStore {

    /// Scrive la famiglia attiva sull'account. Fire-and-forget: un errore di
    /// rete non deve impedire lo switch, la prossima scrittura riallinea.
    static func save(_ familyId: String?) async {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }
        do {
            var payload: [String: Any] = [
                "activeFamilyUpdatedAt": FieldValue.serverTimestamp()
            ]
            payload["activeFamilyId"] = familyId ?? FieldValue.delete()
            try await Firestore.firestore().collection("users").document(uid)
                .setData(payload, merge: true)
            KBLog.sync.kbDebug("ActiveFamily: salvata sull'account familyId=\(familyId ?? "nil")")
        } catch {
            KBLog.sync.kbDebug("ActiveFamily: salvataggio fallito \(error.localizedDescription)")
        }
    }

    /// Ultima famiglia aperta con questo account, da qualunque dispositivo.
    static func load() async -> String? {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return nil }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let id = (snap.data()?["activeFamilyId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (id?.isEmpty == false) ? id : nil
        } catch {
            KBLog.sync.kbDebug("ActiveFamily: lettura fallita \(error.localizedDescription)")
            return nil
        }
    }
}
