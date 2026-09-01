//
//  FitnessPlanRemoteStore.swift
//  KidBox
//
//  Sync del piano fitness su Firestore: lo stesso utente ritrova piano e stato
//  delle sedute su un altro device, e l'eliminazione vale ovunque.
//
//  Percorso: users/{uid}/fitnessPlans/{childId}
//
//  Sta sotto `users` e non sotto `families` per lo stesso motivo del piano
//  alimentare: contiene peso, infortuni e adattamenti clinici di chi lo genera.
//
//  Il documento viaggia come JSON in un singolo campo `payload`: la struttura
//  (settimane, sedute, esercizi, stati) è annidata e non guadagna nulla a essere
//  esplosa in campi Firestore, che nessuna query interroga.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum FitnessPlanRemoteStore {

    /// Il documento remoto, già risolto: `nil` quando non esiste, `deleted`
    /// quando un altro device l'ha eliminato (serve per svuotare la copia locale).
    enum Remote {
        case none
        case deleted
        case plan(FitnessPlanDocument)
    }

    private static var db: Firestore { Firestore.firestore() }

    private static func ref(childId: String) -> DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("FitnessPlan remote: not authenticated")
            return nil
        }
        return db.collection("users").document(uid)
            .collection("fitnessPlans").document(childId)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - OUTBOUND

    static func upsert(_ document: FitnessPlanDocument, childId: String) async {
        guard let ref = ref(childId: childId) else { return }
        guard
            let data = try? encoder.encode(document),
            let payload = String(data: data, encoding: .utf8)
        else {
            KBLog.sync.kbError("FitnessPlan remote upsert: encode failed childId=\(childId)")
            return
        }
        do {
            try await ref.setData([
                "childId": childId,
                "subjectName": document.subjectName,
                "payload": payload,
                "generatedAt": Timestamp(date: document.generatedAt),
                "startDate": Timestamp(date: document.startDate),
                "messageUnitsConsumed": document.messageUnitsConsumed,
                "isDeleted": false,
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
            KBLog.sync.kbInfo(
                "FitnessPlan remote upsert OK childId=\(childId) sessions=\(document.allSessions.count)"
            )
        } catch {
            KBLog.sync.kbError("FitnessPlan remote upsert failed: \(error.localizedDescription)")
        }
    }

    /// Soft-delete: gli altri device devono poter distinguere "mai sincronizzato"
    /// da "eliminato altrove", e un documento cancellato davvero non lo permette.
    static func delete(childId: String) async {
        guard let ref = ref(childId: childId) else { return }
        do {
            try await ref.setData([
                "childId": childId,
                "isDeleted": true,
                "payload": "",
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
            KBLog.sync.kbInfo("FitnessPlan remote delete OK childId=\(childId)")
        } catch {
            KBLog.sync.kbError("FitnessPlan remote delete failed: \(error.localizedDescription)")
        }
    }

    // MARK: - INBOUND

    static func fetch(childId: String) async -> Remote {
        guard let ref = ref(childId: childId) else { return .none }
        do {
            let snap = try await ref.getDocument()
            guard let data = snap.data() else { return .none }
            if data["isDeleted"] as? Bool == true { return .deleted }
            guard
                let payload = data["payload"] as? String, !payload.isEmpty,
                let raw = payload.data(using: .utf8),
                let document = try? decoder.decode(FitnessPlanDocument.self, from: raw)
            else { return .none }
            return .plan(document)
        } catch {
            KBLog.sync.kbError("FitnessPlan remote fetch failed: \(error.localizedDescription)")
            return .none
        }
    }
}
