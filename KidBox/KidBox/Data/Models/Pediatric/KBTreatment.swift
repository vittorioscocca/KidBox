//
//  KBTreatment.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation
import SwiftData

/// Una cura farmacologica: farmaco + dosaggio + frequenza giornaliera + durata.
@Model
final class KBTreatment {
    
    @Attribute(.unique) var id: String
    var familyId: String
    var childId: String
    
    // MARK: - Farmaco
    var drugName: String            // es. "Tachipirina"
    var activeIngredient: String?   // es. "Paracetamolo"
    
    // MARK: - Dosaggio
    var dosageValue: Double         // es. 10
    var dosageUnit: String          // es. "ml", "mg", "gocce", "compresse"
    
    // MARK: - Durata
    var isLongTerm: Bool            // cura a lungo termine (senza fine)
    var durationDays: Int           // giorni (ignorato se isLongTerm)
    var startDate: Date
    var endDate: Date?              // calcolato: startDate + durationDays
    
    // MARK: - Frequenza (numero di dosi/giorno)
    var dailyFrequency: Int         // 1, 2, 3, 4 …
    
    /// Orari delle dosi serializzati come "HH:mm,HH:mm,HH:mm"
    var scheduleTimesRaw: String
    
    var scheduleTimes: [String] {
        get {
            scheduleTimesRaw.split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        set {
            scheduleTimesRaw = newValue.joined(separator: ",")
        }
    }
    
    // MARK: - Stato
    var isActive: Bool
    var notes: String?
    
    // MARK: - Soft delete
    var isDeleted: Bool
    
    // MARK: - Sync
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String?
    var createdBy: String?
    var syncStateRaw: Int
    var lastSyncError: String?
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    // MARK: - Computed helpers
    
    /// Dosi totali = frequenza × durata
    var totalDoses: Int {
        isLongTerm ? -1 : dailyFrequency * durationDays
    }
    
    /// Giorno corrente della cura (1-based), nil se terminata o non ancora iniziata
    var currentDay: Int? {
        guard isActive, !isLongTerm else { return nil }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        let day = days + 1
        return (1...durationDays).contains(day) ? day : nil
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        childId: String,
        drugName: String,
        activeIngredient: String? = nil,
        dosageValue: Double = 0,
        dosageUnit: String = "ml",
        isLongTerm: Bool = false,
        durationDays: Int = 5,
        startDate: Date = Date(),
        endDate: Date? = nil,
        dailyFrequency: Int = 1,
        scheduleTimes: [String] = ["08:00"],
        isActive: Bool = true,
        notes: String? = nil,
        isDeleted: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        updatedBy: String? = nil,
        createdBy: String? = nil
    ) {
        self.id               = id
        self.familyId         = familyId
        self.childId          = childId
        self.drugName         = drugName
        self.activeIngredient = activeIngredient
        self.dosageValue      = dosageValue
        self.dosageUnit       = dosageUnit
        self.isLongTerm       = isLongTerm
        self.durationDays     = durationDays
        self.startDate        = startDate
        self.endDate          = endDate
        self.dailyFrequency   = dailyFrequency
        self.scheduleTimesRaw = scheduleTimes.joined(separator: ",")
        self.isActive         = isActive
        self.notes            = notes
        self.isDeleted        = isDeleted
        self.createdAt        = createdAt
        self.updatedAt        = updatedAt
        self.updatedBy        = updatedBy
        self.createdBy        = createdBy
        self.syncStateRaw     = KBSyncState.synced.rawValue
    }
}
