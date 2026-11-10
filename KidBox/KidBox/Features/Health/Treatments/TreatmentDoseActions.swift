//
//  TreatmentDoseActions.swift
//  KidBox
//
//  Registrazione di una dose (presa / saltata / annullata), condivisa fra la
//  scheda della singola cura e la vista a calendario di tutte le cure.
//  Un solo punto che scrive i `KBDoseLog`: l'id è stabile
//  (`KBDoseLog.stableDocumentId`), così lo stesso slot è lo stesso documento
//  su tutti i dispositivi.
//

import Foundation
import SwiftData
import FirebaseAuth

enum TreatmentDoseActions {

    /// Il giorno terapeutico `dayNumber` (1 = primo giorno) cade dopo oggi?
    static func isFuture(treatment: KBTreatment, dayNumber: Int) -> Bool {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayNumber - 1, to: cal.startOfDay(for: treatment.startDate))
            ?? treatment.startDate
        return cal.startOfDay(for: day) > cal.startOfDay(for: Date())
    }

    private static func sameSlotLogs(
        treatmentId: String, dayNumber: Int, slotIndex: Int, context: ModelContext
    ) -> [KBDoseLog] {
        let tid = treatmentId
        let descriptor = FetchDescriptor<KBDoseLog>(predicate: #Predicate<KBDoseLog> {
            $0.treatmentId == tid && $0.dayNumber == dayNumber && $0.slotIndex == slotIndex && $0.isDeleted == false
        })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Segna la dose come presa all'istante `takenAt`.
    static func markTaken(
        treatment: KBTreatment, dayNumber: Int, slotIndex: Int, scheduledTime: String,
        takenAt: Date, modelContext: ModelContext
    ) {
        guard !isFuture(treatment: treatment, dayNumber: dayNumber) else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let stable = KBDoseLog.stableDocumentId(treatmentId: treatment.id, dayNumber: dayNumber, slotIndex: slotIndex)
        let sameSlot = sameSlotLogs(treatmentId: treatment.id, dayNumber: dayNumber, slotIndex: slotIndex, context: modelContext)
        let stableRow = sameSlot.first { $0.id == stable }
        for log in sameSlot where log.id != stable {
            SyncCenter.shared.enqueueDoseLogDelete(logId: log.id, familyId: treatment.familyId, modelContext: modelContext)
            modelContext.delete(log)
        }
        if let row = stableRow {
            row.taken = true
            row.takenAt = takenAt
            row.updatedAt = now
            row.updatedBy = uid
        } else {
            modelContext.insert(KBDoseLog(
                id: stable,
                familyId: treatment.familyId, childId: treatment.childId,
                treatmentId: treatment.id,
                dayNumber: dayNumber, slotIndex: slotIndex,
                scheduledTime: scheduledTime,
                takenAt: takenAt, taken: true, updatedBy: uid
            ))
        }
        try? modelContext.save()
        SyncCenter.shared.enqueueDoseLogUpsert(logId: stable, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)

        // Cancella la notifica pendente (e quella già consegnata) per questo slot:
        // vale anche se la dose viene registrata prima dell'orario programmato.
        TreatmentNotificationManager.cancelSlot(
            treatmentId: treatment.id, dayOffset: dayNumber - 1, slotIndex: slotIndex
        )
    }

    /// Segna la dose come saltata.
    static func markSkipped(
        treatment: KBTreatment, dayNumber: Int, slotIndex: Int, scheduledTime: String,
        modelContext: ModelContext
    ) {
        guard !isFuture(treatment: treatment, dayNumber: dayNumber) else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let stable = KBDoseLog.stableDocumentId(treatmentId: treatment.id, dayNumber: dayNumber, slotIndex: slotIndex)
        let sameSlot = sameSlotLogs(treatmentId: treatment.id, dayNumber: dayNumber, slotIndex: slotIndex, context: modelContext)
        let stableRow = sameSlot.first { $0.id == stable }
        for log in sameSlot where log.id != stable {
            SyncCenter.shared.enqueueDoseLogDelete(logId: log.id, familyId: treatment.familyId, modelContext: modelContext)
            modelContext.delete(log)
        }
        if let row = stableRow {
            row.taken = false
            row.takenAt = nil
            row.updatedAt = now
            row.updatedBy = uid
        } else {
            modelContext.insert(KBDoseLog(
                id: stable,
                familyId: treatment.familyId, childId: treatment.childId,
                treatmentId: treatment.id,
                dayNumber: dayNumber, slotIndex: slotIndex,
                scheduledTime: scheduledTime,
                takenAt: nil, taken: false, updatedBy: uid
            ))
        }
        try? modelContext.save()
        SyncCenter.shared.enqueueDoseLogUpsert(logId: stable, familyId: treatment.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    /// Toglie la registrazione (la dose torna «da prendere»).
    static func undo(
        treatment: KBTreatment, dayNumber: Int, slotIndex: Int, modelContext: ModelContext
    ) {
        let sameSlot = sameSlotLogs(treatmentId: treatment.id, dayNumber: dayNumber, slotIndex: slotIndex, context: modelContext)
        guard !sameSlot.isEmpty else { return }
        for log in sameSlot {
            SyncCenter.shared.enqueueDoseLogDelete(logId: log.id, familyId: treatment.familyId, modelContext: modelContext)
            modelContext.delete(log)
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}
