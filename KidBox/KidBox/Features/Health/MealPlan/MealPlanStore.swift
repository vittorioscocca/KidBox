//
//  MealPlanStore.swift
//  KidBox
//

import Foundation

/// Persistenza locale dell'ultimo piano alimentare generato per profilo (childId).
/// Stessa logica di `ClinicalRecordStore`: il piano costa messaggi AI, quindi
/// non va rigenerato a ogni apertura della schermata.
enum MealPlanStore {

    private static let prefix = "kidbox.mealplan."

    static func load(childId: String) -> MealPlanDocument? {
        guard let data = UserDefaults.standard.data(forKey: key(childId)) else { return nil }
        return try? JSONDecoder().decode(MealPlanDocument.self, from: data)
    }

    static func save(_ document: MealPlanDocument, childId: String) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        UserDefaults.standard.set(data, forKey: key(childId))
        KBLog.persistence.kbInfo("MealPlan saved childId=\(childId) chars=\(document.text.count)")
    }

    static func clear(childId: String) {
        UserDefaults.standard.removeObject(forKey: key(childId))
    }

    private static func key(_ childId: String) -> String { prefix + childId }
}
