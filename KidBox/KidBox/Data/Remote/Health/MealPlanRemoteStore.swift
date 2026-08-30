//
//  MealPlanRemoteStore.swift
//  KidBox
//
//  Sync del piano alimentare su Firestore: lo stesso utente ritrova il piano
//  su un altro device, e l'eliminazione vale ovunque.
//
//  Percorso: users/{uid}/mealPlans/{childId}
//
//  Sta sotto `users` e non sotto `families` di proposito: il piano contiene
//  peso, obiettivo e abitudini alimentari di chi lo genera, e sotto `families`
//  il wildcard delle rules lo renderebbe leggibile a tutta la famiglia.
//
//  A differenza degli altri store di Salute non c'è listener realtime né
//  integrazione con SwiftData: il piano è un singolo documento che si legge
//  all'apertura della schermata e si riscrive solo quando viene rigenerato.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

enum MealPlanRemoteStore {

    /// Il documento remoto, già risolto: `nil` quando non esiste, `deleted`
    /// quando un altro device l'ha eliminato (serve per svuotare la copia locale).
    enum Remote {
        case none
        case deleted
        case plan(MealPlanDocument)
    }

    private static var db: Firestore { Firestore.firestore() }

    private static func ref(childId: String) -> DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("MealPlan remote: not authenticated")
            return nil
        }
        return db.collection("users").document(uid)
            .collection("mealPlans").document(childId)
    }

    // MARK: - OUTBOUND

    static func upsert(_ document: MealPlanDocument, childId: String) async {
        guard let ref = ref(childId: childId) else { return }
        let input = document.input
        let data: [String: Any] = [
            "childId": childId,
            "subjectName": document.subjectName,
            "text": document.text,
            "generatedAt": Timestamp(date: document.generatedAt),
            "messageUnitsConsumed": document.messageUnitsConsumed,
            "goal": input.goal.rawValue,
            "activityLevel": input.activityLevel.rawValue,
            "preferredFoods": input.preferredFoods,
            "avoidedFoods": input.avoidedFoods,
            "notes": input.notes,
            "manualAgeYears": input.manualAgeYears,
            "manualWeightKg": input.manualWeightKg,
            "manualHeightCm": input.manualHeightCm,
            "isDeleted": false,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        do {
            try await ref.setData(data, merge: true)
            KBLog.sync.kbInfo("MealPlan remote upsert OK childId=\(childId) chars=\(document.text.count)")
        } catch {
            KBLog.sync.kbError("MealPlan remote upsert failed: \(error.localizedDescription)")
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
                "text": "",
                "updatedAt": FieldValue.serverTimestamp(),
            ], merge: true)
            KBLog.sync.kbInfo("MealPlan remote delete OK childId=\(childId)")
        } catch {
            KBLog.sync.kbError("MealPlan remote delete failed: \(error.localizedDescription)")
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
                let text = data["text"] as? String, !text.isEmpty,
                let generatedAt = (data["generatedAt"] as? Timestamp)?.dateValue()
            else { return .none }

            var input = MealPlanInput()
            if let raw = data["goal"] as? String, let goal = MealPlanGoal(rawValue: raw) {
                input.goal = goal
            }
            if let raw = data["activityLevel"] as? String,
               let level = MealPlanActivityLevel(rawValue: raw) {
                input.activityLevel = level
            }
            input.preferredFoods = data["preferredFoods"] as? String ?? ""
            input.avoidedFoods = data["avoidedFoods"] as? String ?? ""
            input.notes = data["notes"] as? String ?? ""
            input.manualAgeYears = data["manualAgeYears"] as? String ?? ""
            input.manualWeightKg = data["manualWeightKg"] as? String ?? ""
            input.manualHeightCm = data["manualHeightCm"] as? String ?? ""

            return .plan(
                MealPlanDocument(
                    subjectName: data["subjectName"] as? String ?? "",
                    input: input,
                    text: text,
                    generatedAt: generatedAt,
                    messageUnitsConsumed: data["messageUnitsConsumed"] as? Int ?? 0
                )
            )
        } catch {
            KBLog.sync.kbError("MealPlan remote fetch failed: \(error.localizedDescription)")
            return .none
        }
    }
}
