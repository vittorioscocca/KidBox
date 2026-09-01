//
//  FitnessPlanStore.swift
//  KidBox
//
//  Persistenza locale del piano fitness per profilo (childId).
//  Stessa logica di `MealPlanStore`: generare il piano costa messaggi AI,
//  quindi non va rigenerato a ogni apertura della schermata. Qui però il
//  documento cambia spesso (stati delle sedute, spostamenti), quindi si
//  riscrive a ogni modifica.
//

import Foundation

enum FitnessPlanStore {

    private static let planPrefix = "kidbox.fitnessplan."
    private static let reviewedWeeksPrefix = "kidbox.fitnessplan.reviewedWeeks."
    private static let lastHealthSyncPrefix = "kidbox.fitnessplan.lastHealthSync."

    // MARK: - Piano

    static func load(childId: String) -> FitnessPlanDocument? {
        guard let data = UserDefaults.standard.data(forKey: planPrefix + childId) else { return nil }
        return try? JSONDecoder().decode(FitnessPlanDocument.self, from: data)
    }

    static func save(_ document: FitnessPlanDocument, childId: String) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        UserDefaults.standard.set(data, forKey: planPrefix + childId)
        KBLog.persistence.kbInfo(
            "FitnessPlan saved childId=\(childId) sessions=\(document.allSessions.count)"
        )
    }

    static func clear(childId: String) {
        UserDefaults.standard.removeObject(forKey: planPrefix + childId)
        UserDefaults.standard.removeObject(forKey: reviewedWeeksPrefix + childId)
        UserDefaults.standard.removeObject(forKey: lastHealthSyncPrefix + childId)
    }

    // MARK: - Report settimanali già visti

    /// Settimane per cui l'utente ha già chiuso il report: evita di riproporlo.
    static func reviewedWeeks(childId: String) -> Set<Int> {
        let raw = UserDefaults.standard.array(forKey: reviewedWeeksPrefix + childId) as? [Int] ?? []
        return Set(raw)
    }

    static func markWeekReviewed(_ weekIndex: Int, childId: String) {
        var weeks = reviewedWeeks(childId: childId)
        weeks.insert(weekIndex)
        UserDefaults.standard.set(Array(weeks), forKey: reviewedWeeksPrefix + childId)
    }

    // MARK: - Ultima riconciliazione con Apple Salute

    static func lastHealthSync(childId: String) -> Date? {
        UserDefaults.standard.object(forKey: lastHealthSyncPrefix + childId) as? Date
    }

    static func setLastHealthSync(_ date: Date, childId: String) {
        UserDefaults.standard.set(date, forKey: lastHealthSyncPrefix + childId)
    }
}
