//
//  KBInsightTests.swift
//  KidBox
//

import XCTest
import SwiftData
@testable import KidBox

final class KBInsightTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeInsight(entityId: String = "todo-1") -> KBInsight {
        KBInsight(
            familyId: "fam-1",
            recipientUid: "uid-1",
            type: .todoUnassignedDueSoon,
            entityId: entityId,
            priority: .normal,
            fireAt: t0.addingTimeInterval(3600),
            now: t0
        )
    }

    func testIdIsDeterministicKey() {
        let a = makeInsight()
        let b = makeInsight()
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.id, "fam-1|todo_unassigned_due_soon|todo-1")
        XCTAssertNotEqual(a.id, makeInsight(entityId: "todo-2").id)
    }

    func testNewInsightStartsOpen() {
        let i = makeInsight()
        XCTAssertEqual(i.state, .new)
        XCTAssertTrue(i.state.isOpen)
        XCTAssertNil(i.stateChangedAt)
        XCTAssertEqual(i.type, .todoUnassignedDueSoon)
    }

    func testUnknownRawValuesFallBack() {
        let i = makeInsight()
        i.typeRaw = "from_a_newer_build"
        i.stateRaw = "?"
        i.priorityRaw = 99
        XCTAssertNil(i.type)
        XCTAssertEqual(i.state, .dismissed)
        XCTAssertEqual(i.priority, .low)
    }

    func testRefreshUpdatesScheduleButKeepsState() {
        let i = makeInsight()
        i.mark(.dismissed, now: t0)
        let later = t0.addingTimeInterval(60)
        i.refresh(priority: .high, fireAt: t0.addingTimeInterval(7200), now: later)
        XCTAssertEqual(i.priority, .high)
        XCTAssertEqual(i.fireAt, t0.addingTimeInterval(7200))
        XCTAssertEqual(i.updatedAt, later)
        XCTAssertEqual(i.state, .dismissed)
    }

    func testRefreshWithSameValuesDoesNotTouchUpdatedAt() {
        let i = makeInsight()
        i.refresh(priority: .normal, fireAt: t0.addingTimeInterval(3600), now: t0.addingTimeInterval(60))
        XCTAssertEqual(i.updatedAt, t0)
    }

    func testMarkRecordsTransitionOnce() {
        let i = makeInsight()
        let seenAt = t0.addingTimeInterval(10)
        i.mark(.seen, now: seenAt)
        i.mark(.seen, now: seenAt.addingTimeInterval(10))
        XCTAssertEqual(i.state, .seen)
        XCTAssertTrue(i.state.isOpen)
        XCTAssertEqual(i.stateChangedAt, seenAt)

        i.mark(.done, now: seenAt.addingTimeInterval(20))
        XCTAssertFalse(i.state.isOpen)
        XCTAssertFalse(KBInsightState.dismissed.isOpen)
    }

    func testPriorityOrdering() {
        XCTAssertLessThan(KBInsightPriority.low, .normal)
        XCTAssertLessThan(KBInsightPriority.normal, .high)
    }

    @MainActor
    func testPersistsInAppSchemaAndFetchesByKey() throws {
        let container = ModelContainerProvider.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(makeInsight())
        try context.save()

        let key = KBInsight.key(familyId: "fam-1", type: .todoUnassignedDueSoon, entityId: "todo-1")
        let fetched = try context.fetch(FetchDescriptor<KBInsight>(predicate: #Predicate { $0.id == key }))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.recipientUid, "uid-1")
    }
}
