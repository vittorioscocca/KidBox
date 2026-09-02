//
//  FitnessHealthSyncTests.swift
//  KidBoxTests
//
//  Riproduce il caso reale del 2 settembre: una corsa registrata dall'orologio
//  in un giorno che prevedeva bici e corpo libero. La vecchia euristica chiudeva
//  entrambe le sedute; qui si verifica che non succeda più e che l'attività
//  svolta resti visibile.
//

import XCTest
@testable import KidBox

final class FitnessHealthSyncTests: XCTestCase {

    private let day = Calendar.current.startOfDay(for: Date())

    private func session(
        title: String,
        type: String,
        status: FitnessSessionStatus = .planned
    ) -> FitnessSession {
        FitnessSession(
            id: UUID().uuidString,
            date: day,
            weekIndex: 1,
            title: title,
            activityType: type,
            durationMinutes: 45,
            intensity: "media",
            status: status
        )
    }

    private func plan(_ sessions: [FitnessSession]) -> FitnessPlanDocument {
        FitnessPlanDocument(
            subjectName: "Test",
            input: FitnessPlanInput(),
            startDate: day,
            summary: "",
            safetyNotes: [],
            weeks: [FitnessWeek(index: 1, focus: "", sessions: sessions)],
            generatedAt: day,
            messageUnitsConsumed: 0
        )
    }

    private func run(_ title: String, minutes: Int = 32) -> KBHealthWorkoutEntry {
        KBHealthWorkoutEntry(
            id: "workout-run",
            title: title,
            startedAt: day.addingTimeInterval(9 * 3600),
            durationMinutes: minutes,
            activeEnergyKcal: 280
        )
    }

    func testCorsaNonChiudeBiciNeCorpoLibero() {
        let bici = session(title: "Ciclismo + tonificazione", type: "cardio")
        let corpoLibero = session(title: "Esercizi a corpo libero", type: "forza")
        let result = FitnessHealthSync.reconcile(
            plan: plan([bici, corpoLibero]),
            workouts: [run("Corsa all'aperto")]
        )

        XCTAssertTrue(result.matchedSessions.isEmpty, "nessuna seduta deve chiudersi")
        XCTAssertEqual(result.plan.session(id: bici.id)?.status, .planned)
        XCTAssertEqual(result.plan.session(id: corpoLibero.id)?.status, .planned)
    }

    func testLaCorsaSvoltaFinisceNelRegistro() {
        let bici = session(title: "Ciclismo + tonificazione", type: "cardio")
        let result = FitnessHealthSync.reconcile(
            plan: plan([bici]),
            workouts: [run("Corsa all'aperto")]
        )

        XCTAssertEqual(result.loggedWorkouts.count, 1)
        XCTAssertEqual(result.loggedWorkouts.first?.title, "Corsa all'aperto")
        XCTAssertEqual(result.plan.loggedWorkouts(on: day).count, 1)
        XCTAssertTrue(result.didChange)
    }

    func testUnaCorsaChiudeLaSedutaDiCorsa() {
        let corsa = session(title: "Corsa progressiva", type: "corsa")
        let result = FitnessHealthSync.reconcile(
            plan: plan([corsa]),
            workouts: [run("Corsa all'aperto")]
        )

        XCTAssertEqual(result.matchedSessions.count, 1)
        let closed = result.plan.session(id: corsa.id)
        XCTAssertEqual(closed?.status, .done)
        XCTAssertEqual(closed?.actualActivityTitle, "Corsa all'aperto")
        XCTAssertFalse(closed?.wasSubstituted ?? true, "stessa disciplina: non è una sostituzione")
        XCTAssertTrue(result.loggedWorkouts.isEmpty, "l'allenamento è stato usato, non va nel registro")
    }

    func testRiapreLeSeduteChiuseDallaVecchiaEuristica() {
        // Dato preesistente: la bici risulta chiusa dalla corsa, senza nome
        // dell'attività — è esattamente ciò che la vecchia versione salvava.
        var bici = session(title: "Ciclismo + tonificazione", type: "cardio", status: .done)
        bici.completionSource = .healthKit
        bici.matchedWorkoutId = "workout-run"
        bici.actualMinutes = 32

        let result = FitnessHealthSync.reconcile(
            plan: plan([bici]),
            workouts: [run("Corsa all'aperto")]
        )

        XCTAssertEqual(result.repairedSessions, 1)
        let repaired = result.plan.session(id: bici.id)
        XCTAssertEqual(repaired?.status, .planned)
        XCTAssertNil(repaired?.matchedWorkoutId)
        XCTAssertEqual(result.plan.loggedWorkouts(on: day).count, 1, "la corsa torna disponibile")
    }

    func testPulisceIResiduiSuSeduteNonChiuse() {
        var seduta = session(title: "Ciclismo", type: "cardio")
        seduta.matchedWorkoutId = "vecchio"
        seduta.actualMinutes = 64

        let result = FitnessHealthSync.reconcile(
            plan: plan([seduta]),
            workouts: [run("Corsa all'aperto")]
        )

        let cleaned = result.plan.session(id: seduta.id)
        XCTAssertNil(cleaned?.matchedWorkoutId)
        XCTAssertNil(cleaned?.actualMinutes)
    }
}
