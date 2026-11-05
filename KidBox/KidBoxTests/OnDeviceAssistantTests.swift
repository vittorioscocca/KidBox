//
//  OnDeviceAssistantTests.swift
//  KidBoxTests
//
//  Chi passa dal telefono e cosa entra nei 4.096 token del modello.
//

import XCTest
@testable import KidBox

@MainActor
final class OnDeviceAssistantTests: XCTestCase {

    private func file(_ name: String, _ title: String, _ body: String) -> AgentMemoryFile {
        AgentMemoryFile(name: name, title: title, summary: "", body: body)
    }

    private var book: AgentMemoryBook {
        AgentMemoryBook(files: [
            file("famiglia.md", "Famiglia", "Marco, 6 anni"),
            file("oggi.md", "Oggi", "Dentista alle 15"),
            file("casa.md", "Casa", "Bolletta Enel 70,86 euro"),
            file("veicoli.md", "Veicoli", "Revisione della Panda a marzo"),
            file("spesa.md", "Spesa", "Latte"),
            file("domanda.md", "Domanda", "testo scelto per Claude"),
        ])
    }

    func testRouting() {
        // Con la rete Claude: Pro, Max e il Free col bonus da usare.
        XCTAssertFalse(OnDeviceAI.prefersDevice(modelReady: true, bonusFinished: false, online: true))
        // Senza rete il telefono per tutti.
        XCTAssertTrue(OnDeviceAI.prefersDevice(modelReady: true, bonusFinished: false, online: false))
        // Bonus finito: il telefono, anche con la rete.
        XCTAssertTrue(OnDeviceAI.prefersDevice(modelReady: true, bonusFinished: true, online: true))
        // Telefono senza modello: resta com'era.
        XCTAssertFalse(OnDeviceAI.prefersDevice(modelReady: false, bonusFinished: true, online: false))
    }

    func testDocumentRouting() {
        // Il Free parte dal telefono anche col bonus intatto e con la rete.
        XCTAssertTrue(OnDeviceAI.prefersDeviceForDocument(modelReady: true, freePlan: true, online: true))
        // Pro e Max: Claude con la rete, telefono senza.
        XCTAssertFalse(OnDeviceAI.prefersDeviceForDocument(modelReady: true, freePlan: false, online: true))
        XCTAssertTrue(OnDeviceAI.prefersDeviceForDocument(modelReady: true, freePlan: false, online: false))
        // Telefono senza modello: resta com'era.
        XCTAssertFalse(OnDeviceAI.prefersDeviceForDocument(modelReady: false, freePlan: true, online: true))
    }

    func testContextPicksTheCardsOfTheQuestion() {
        let context = OnDeviceAssistant.context(book: book, focus: nil, question: "Quando scade la revisione?", budget: 5000)
        XCTAssertTrue(context.contains("Revisione della Panda"))
        XCTAssertTrue(context.contains("Marco, 6 anni"))
        XCTAssertTrue(context.contains("Latte"))
        XCTAssertFalse(context.contains("Bolletta Enel"))
        XCTAssertFalse(context.contains("testo scelto per Claude"))
    }

    func testContextStaysInsideTheBudget() {
        let long = (1...400).map { "Riga numero \($0) del quaderno" }.joined(separator: "\n")
        let big = AgentMemoryBook(files: [
            file("famiglia.md", "Famiglia", long),
            file("oggi.md", "Oggi", long),
            file("calendario.md", "Calendario", long),
            file("todo.md", "To-do", long),
        ])
        let budget = 5000
        let context = OnDeviceAssistant.context(book: big, focus: nil, question: "cosa c'è oggi", budget: budget)
        // Le righe dei titoli sono il solo extra.
        XCTAssertLessThanOrEqual(context.count, budget + 100)
        XCTAssertFalse(context.isEmpty)
    }

    func testClippingKeepsTheLinesOfTheQuestion() {
        let body = ((1...200).map { "Voce qualunque \($0)" } + ["Revisione Panda 12 marzo"]).joined(separator: "\n")
        let clipped = OnDeviceAssistant.clipped(body, terms: ["revisione"], limit: 300)
        XCTAssertLessThanOrEqual(clipped.count, 300)
        XCTAssertTrue(clipped.contains("Revisione Panda"))
        XCTAssertTrue(clipped.hasPrefix("Voce qualunque 1\n"))
        // Quello che ci sta non si tocca.
        XCTAssertEqual(OnDeviceAssistant.clipped("corto", terms: [], limit: 300), "corto")
    }
}
