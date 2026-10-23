//
//  KBInsightEngineTests.swift
//  KidBox
//

import XCTest
import SwiftData
@testable import KidBox

final class KBInsightEngineTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Rome")!
        return c
    }()

    /// Venerdì 23 ottobre 2026, 12:00 a Roma.
    private var now: Date { at(2026, 10, 23, 12, 0) }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func todo(
        _ id: String = "t1",
        dueAt: Date?,
        hasDueTime: Bool = true,
        isDone: Bool = false,
        isTaken: Bool = false,
        visible: Bool = true
    ) -> KBInsightSnapshot.Todo {
        .init(id: id, dueAt: dueAt, hasDueTime: hasDueTime, isDone: isDone, isDeleted: false,
              isTaken: isTaken, isVisibleToUser: visible)
    }

    private func treatment(
        _ id: String = "c1",
        start: Date? = nil,
        days: Int = 5,
        longTerm: Bool = false,
        interval: Int = 0,
        times: [String] = ["08:00", "20:00"]
    ) -> KBInsightSnapshot.Treatment {
        .init(id: id, isActive: true, isDeleted: false, isLongTerm: longTerm, durationDays: days,
              startDate: start ?? at(2026, 10, 21, 9, 0), endDate: nil,
              intervalBetweenDosesDays: interval, scheduleTimes: times)
    }

    private func evaluate(_ s: KBInsightSnapshot) -> [KBInsightCandidate] {
        KBInsightEngine.evaluate(s, now: now, calendar: cal)
    }

    // MARK: - To-do

    func testUnassignedTodoDueTomorrowFiresTwentyFourHoursBefore() {
        let due = at(2026, 10, 25, 9, 0)
        let c = evaluate(KBInsightSnapshot(todos: [todo(dueAt: due)]))
        XCTAssertEqual(c, [KBInsightCandidate(type: .todoUnassignedDueSoon, entityId: "t1",
                                              priority: .normal, fireAt: at(2026, 10, 24, 9, 0))])
    }

    func testUnassignedTodoWithinTwentyFourHoursFiresNow() {
        let c = evaluate(KBInsightSnapshot(todos: [todo(dueAt: at(2026, 10, 23, 20, 0))]))
        XCTAssertEqual(c.first?.fireAt, now)
        XCTAssertEqual(c.first?.priority, .normal)
    }

    func testUnassignedTodoWithinSixHoursIsHigh() {
        let c = evaluate(KBInsightSnapshot(todos: [todo(dueAt: at(2026, 10, 23, 17, 0))]))
        XCTAssertEqual(c.first?.priority, .high)
    }

    func testTodoWithoutTimeDueAtEndOfDay() {
        // Scade oggi senza orario: fine giornata, fra 12 ore.
        let c = evaluate(KBInsightSnapshot(todos: [todo(dueAt: at(2026, 10, 23, 0, 0), hasDueTime: false)]))
        XCTAssertEqual(c.first?.fireAt, now)
        XCTAssertEqual(c.first?.priority, .normal)
    }

    func testTodoSkippedWhenTakenDoneHiddenPastOrFar() {
        let s = KBInsightSnapshot(todos: [
            todo("taken", dueAt: at(2026, 10, 24, 9, 0), isTaken: true),
            todo("done", dueAt: at(2026, 10, 24, 9, 0), isDone: true),
            todo("hidden", dueAt: at(2026, 10, 24, 9, 0), visible: false),
            todo("past", dueAt: at(2026, 10, 23, 11, 0)),
            todo("far", dueAt: at(2026, 11, 5, 9, 0)),
            todo("nodate", dueAt: nil),
        ])
        XCTAssertEqual(evaluate(s), [])
    }

    // MARK: - Dosi

    func testMissingMorningDoseFiresAfterGrace() {
        let c = evaluate(KBInsightSnapshot(treatments: [treatment()]))
        XCTAssertEqual(c, [KBInsightCandidate(type: .treatmentDoseMissing, entityId: "c1@2026-10-23",
                                              priority: .high, fireAt: now)])
    }

    func testTakenMorningDoseSchedulesEveningCheck() {
        // Cura iniziata il 21: oggi è il giorno 3.
        let s = KBInsightSnapshot(
            treatments: [treatment()],
            doseLogs: [.init(treatmentId: "c1", dayNumber: 3, slotIndex: 0, taken: true, isDeleted: false)]
        )
        XCTAssertEqual(evaluate(s).first?.fireAt, at(2026, 10, 23, 21, 0))
    }

    func testAllDosesTakenGivesNothing() {
        let s = KBInsightSnapshot(
            treatments: [treatment()],
            doseLogs: [
                .init(treatmentId: "c1", dayNumber: 3, slotIndex: 0, taken: true, isDeleted: false),
                .init(treatmentId: "c1", dayNumber: 3, slotIndex: 1, taken: true, isDeleted: false),
            ]
        )
        XCTAssertEqual(evaluate(s), [])
    }

    func testDeletedOrSkippedLogDoesNotCount() {
        let s = KBInsightSnapshot(
            treatments: [treatment(times: ["08:00"])],
            doseLogs: [
                .init(treatmentId: "c1", dayNumber: 3, slotIndex: 0, taken: true, isDeleted: true),
                .init(treatmentId: "c1", dayNumber: 3, slotIndex: 0, taken: false, isDeleted: false),
            ]
        )
        XCTAssertEqual(evaluate(s).count, 1)
    }

    func testTreatmentOutsideItsDaysGivesNothing() {
        let ended = treatment(start: at(2026, 10, 10, 9, 0), days: 5)
        let future = treatment("c2", start: at(2026, 10, 25, 9, 0))
        // Ogni 2 giorni dal 20: oggi (offset 3) non è giorno di dose.
        let skipDay = treatment("c3", start: at(2026, 10, 20, 9, 0), days: 10, interval: 2)
        XCTAssertEqual(evaluate(KBInsightSnapshot(treatments: [ended, future, skipDay])), [])
    }

    func testLongTermTreatmentKeepsGoing() {
        let t = treatment(start: at(2026, 1, 1, 9, 0), days: 0, longTerm: true, times: ["08:00"])
        XCTAssertEqual(evaluate(KBInsightSnapshot(treatments: [t])).count, 1)
    }

    // MARK: - Riconciliazione

    @MainActor
    func testReconcileOpensRefreshesAndResolves() throws {
        let context = ModelContext(ModelContainerProvider.makeContainer(inMemory: true))
        let a = KBInsightCandidate(type: .todoUnassignedDueSoon, entityId: "t1", priority: .normal, fireAt: now)
        let b = KBInsightCandidate(type: .treatmentDoseMissing, entityId: "c1@2026-10-23", priority: .high, fireAt: now)

        var changes = try KBInsightStore.reconcile([a, b], familyId: "f", uid: "u", now: now, context: context)
        XCTAssertEqual(Set(changes.opened), ["f|todo_unassigned_due_soon|t1", "f|treatment_dose_missing|c1@2026-10-23"])

        // Stessa valutazione: niente da fare.
        changes = try KBInsightStore.reconcile([a, b], familyId: "f", uid: "u", now: now, context: context)
        XCTAssertTrue(changes.isEmpty)

        // La dose è stata registrata e il to-do si sposta più avanti.
        let later = KBInsightCandidate(type: .todoUnassignedDueSoon, entityId: "t1", priority: .high,
                                       fireAt: now.addingTimeInterval(60))
        changes = try KBInsightStore.reconcile([later], familyId: "f", uid: "u", now: now, context: context)
        XCTAssertEqual(changes.rescheduled, ["f|todo_unassigned_due_soon|t1"])
        XCTAssertEqual(changes.resolved, ["f|treatment_dose_missing|c1@2026-10-23"])

        let rows = try context.fetch(FetchDescriptor<KBInsight>())
        XCTAssertEqual(rows.first { $0.entityId == "c1@2026-10-23" }?.state, .done)
        XCTAssertEqual(rows.first { $0.entityId == "t1" }?.priority, .high)
    }

    @MainActor
    func testReconcileReopensResolvedButKeepsDismissed() throws {
        let context = ModelContext(ModelContainerProvider.makeContainer(inMemory: true))
        let a = KBInsightCandidate(type: .todoUnassignedDueSoon, entityId: "t1", priority: .normal, fireAt: now)
        let b = KBInsightCandidate(type: .todoUnassignedDueSoon, entityId: "t2", priority: .normal, fireAt: now)
        try KBInsightStore.reconcile([a, b], familyId: "f", uid: "u", now: now, context: context)

        let rows = try context.fetch(FetchDescriptor<KBInsight>())
        rows.first { $0.entityId == "t2" }?.mark(.dismissed, now: now)
        try KBInsightStore.reconcile([], familyId: "f", uid: "u", now: now, context: context)

        // Il to-do t1 torna senza nessuno: si riapre. t2 era stato scartato: resta così.
        let changes = try KBInsightStore.reconcile([a, b], familyId: "f", uid: "u", now: now, context: context)
        XCTAssertEqual(changes.opened, ["f|todo_unassigned_due_soon|t1"])
        let after = try context.fetch(FetchDescriptor<KBInsight>())
        XCTAssertEqual(after.first { $0.entityId == "t2" }?.state, .dismissed)
        XCTAssertEqual(after.first { $0.entityId == "t1" }?.state, .new)
    }

    @MainActor
    func testSnapshotLoadsFromSwiftData() throws {
        let context = ModelContext(ModelContainerProvider.makeContainer(inMemory: true))
        let free = KBTodoItem(familyId: "f", childId: "", title: "Regalo maestra", listId: nil,
                              dueAt: at(2026, 10, 24, 9, 0), updatedBy: "u")
        free.createdBy = "u"
        let taken = KBTodoItem(familyId: "f", childId: "", title: "Gita", listId: nil,
                               dueAt: at(2026, 10, 24, 9, 0), updatedBy: "u")
        taken.assignedTo = "other"
        let otherFamily = KBTodoItem(familyId: "g", childId: "", title: "Altro", listId: nil,
                                     dueAt: at(2026, 10, 24, 9, 0), updatedBy: "u")
        context.insert(free)
        context.insert(taken)
        context.insert(otherFamily)
        context.insert(KBTreatment(id: "c1", familyId: "f", childId: "k", drugName: "Amoxicillina",
                                   startDate: at(2026, 10, 21, 9, 0), scheduleTimes: ["08:00"]))
        context.insert(KBDoseLog(familyId: "f", childId: "k", treatmentId: "c1", dayNumber: 3,
                                 slotIndex: 0, scheduledTime: "08:00", taken: true))
        try context.save()

        let snapshot = try KBInsightSnapshot.load(familyId: "f", uid: "u", context: context)
        XCTAssertEqual(snapshot.todos.count, 2)
        XCTAssertEqual(snapshot.todos.first { $0.id == taken.id }?.isTaken, true)
        XCTAssertEqual(snapshot.doseLogs.count, 1)

        let c = KBInsightEngine.evaluate(snapshot, now: now, calendar: cal)
        XCTAssertEqual(c.map(\.entityId), [free.id])
    }
}
