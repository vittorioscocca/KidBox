//
//  KBTreatment.swift
//  KidBox
//
//  Created by vscocca on 04/03/26.
//

import Foundation
import SwiftData

@Model
final class KBTreatment {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    /// Se non vuoto, cura legata a un animale (`KBPet.id`); `childId` resta vuoto per queste righe.
    var petId: String = ""

    var drugName: String
    var activeIngredient: String?
    
    var dosageValue: Double
    var dosageUnit: String
    
    var isLongTerm: Bool
    var durationDays: Int
    var startDate: Date
    var endDate: Date?
    
    var dailyFrequency: Int
    /// Se `> 0`, una sola dose ogni N giorni (calendario da `startDate`), solo al primo orario in `scheduleTimes`. Se `0`, frequenza classica `dailyFrequency` volte al giorno.
    var intervalBetweenDosesDays: Int = 0
    var scheduleTimesData: String   // stored: "08:00,14:00,20:00"
    
    var isActive: Bool
    var notes: String?
    var reminderEnabled: Bool
    var isDeleted: Bool
    
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String?
    var createdBy: String?
    var syncStatus: Int             // stored: KBSyncState.rawValue
    var lastSyncError: String?
    var syncStateRaw: Int
    
    /// Visita che ha prescritto la cura (collegamento da modulo visita).
    var prescribingVisitId: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        petId: String = "",
        drugName: String,
        activeIngredient: String? = nil,
        dosageValue: Double = 0,
        dosageUnit: String = "ml",
        isLongTerm: Bool = false,
        durationDays: Int = 5,
        startDate: Date = Date(),
        endDate: Date? = nil,
        dailyFrequency: Int = 1,
        intervalBetweenDosesDays: Int = 0,
        scheduleTimes: [String] = ["08:00"],
        isActive: Bool = true,
        notes: String? = nil,
        reminderEnabled: Bool = false,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil,
        prescribingVisitId: String? = nil
    ) {
        self.id               = id
        self.familyId         = familyId
        self.childId          = childId
        self.petId            = petId
        self.drugName         = drugName
        self.activeIngredient = activeIngredient
        self.dosageValue      = dosageValue
        self.dosageUnit       = dosageUnit
        self.isLongTerm       = isLongTerm
        self.durationDays     = durationDays
        self.startDate        = startDate
        self.endDate          = endDate
        self.dailyFrequency   = dailyFrequency
        self.intervalBetweenDosesDays = max(0, intervalBetweenDosesDays)
        self.scheduleTimesData = scheduleTimes.joined(separator: ",")
        self.isActive         = isActive
        self.notes            = notes
        self.reminderEnabled  = reminderEnabled
        self.isDeleted        = isDeleted
        self.createdAt        = createdAt
        self.updatedAt        = updatedAt
        self.updatedBy        = updatedBy
        self.createdBy        = createdBy
        self.syncStatus       = KBSyncState.synced.rawValue
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
        self.prescribingVisitId = prescribingVisitId
    }
}

// MARK: - Computed wrappers (in extension: il macro @Model non le tocca)

extension KBTreatment {
    
    var scheduleTimes: [String] {
        get { scheduleTimesData.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { scheduleTimesData = newValue.joined(separator: ",") }
    }
    
    var totalDoses: Int {
        if isLongTerm { return -1 }
        if intervalBetweenDosesDays > 0 {
            let n = intervalBetweenDosesDays
            return max(1, (durationDays + n - 1) / n)
        }
        return dailyFrequency * durationDays
    }

    /// Frequenza non giornaliera (es. ogni 15 giorni).
    var usesIntervalSchedule: Bool { intervalBetweenDosesDays > 0 }

    /// `offset` = giorni da `startDate` (0 = primo giorno).
    func isScheduledDoseDay(calendarDayOffsetFromStart offset: Int) -> Bool {
        guard usesIntervalSchedule else { return true }
        let n = intervalBetweenDosesDays
        guard n > 0 else { return true }
        return offset >= 0 && offset % n == 0
    }

    /// Testo riassuntivo per UI (lista cure, dettaglio, ecc.).
    var frequencyDisplayLabel: String {
        if intervalBetweenDosesDays > 0 {
            return "Ogni \(intervalBetweenDosesDays) giorni"
        }
        return "\(dailyFrequency) volt\(dailyFrequency == 1 ? "a" : "e") al giorno"
    }
    
    var currentDay: Int? {
        guard isActive, !isLongTerm else { return nil }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        let day  = days + 1
        return (1...durationDays).contains(day) ? day : nil
    }
}
