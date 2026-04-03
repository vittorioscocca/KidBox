//
//  SyncCenterNotesTests.swift
//  KidBox
//
//  Created by vscocca on 02/04/26.
//

//
//  SyncCenterNoteExpenseTests.swift
//  KidBoxTests
//
//  Testa la logica LWW (Last-Write-Wins) di:
//  - applyNotesInbound   (SyncCenter+Notes)
//  - applyExpensesInbound (SyncCenter+Expenses)
//
//  Approccio black-box identico a SyncCenterPhotosTests:
//  - ModelContainer in-memory con schema minimale
//  - DTO mock costruiti direttamente
//  - Verifica dell'effetto osservabile su SwiftData
//
//  NOTA: applyNotesInbound usa Auth.auth().currentUser?.uid per la
//  decrittografia. Nei test uid sarà "" → il codice usa il fallback
//  "titlePlain/bodyPlain" invece di titleEnc/bodyEnc.
//  I DTO di test popolano titlePlain/bodyPlain di conseguenza.
//

import XCTest
import SwiftData
@testable import KidBox

// MARK: - RemoteNoteDTO mock builder

private func makeNoteDTO(
    id: String = UUID().uuidString,
    familyId: String = "fam-note-test",
    titlePlain: String = "Titolo",
    bodyPlain: String = "Corpo",
    updatedAt: Date = Date(),
    isDeleted: Bool = false
) -> NoteDTO {
    NoteDTO(
        id: id,
        familyId: familyId,
        titleEnc: nil,
        bodyEnc: nil,
        titlePlain: titlePlain,
        bodyPlain: bodyPlain,
        isDeleted: isDeleted,
        createdAt: Date(),
        updatedAt: updatedAt,
        createdBy: "user-1",
        createdByName: "Mario",
        updatedBy: "user-1",
        updatedByName: "Mario"
    )
}

// MARK: - RemoteExpenseDTO mock builder

private func makeExpenseDTO(
    id: String = UUID().uuidString,
    familyId: String = "fam-exp-test",
    title: String = "Spesa test",
    amount: Double = 42.0,
    updatedAt: Date = Date(),
    isDeleted: Bool = false
) -> RemoteExpenseDTO {
    RemoteExpenseDTO(
        id: id,
        familyId: familyId,
        title: title,
        amount: amount,
        date: Date(),
        categoryId: nil,
        notes: nil,
        attachedDocumentId: nil,
        isDeleted: isDeleted,
        createdByUid: "user-1",
        updatedBy: "user-1",
        createdAt: Date(),
        updatedAt: updatedAt
    )
}

// MARK: - SyncCenterNotesTests

@MainActor
final class SyncCenterNotesTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    private let familyId = "fam-note-test"
    
    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: KBNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }
    
    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func fetchNote(id: String) throws -> KBNote? {
        let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == id })
        return try context.fetch(desc).first
    }
    
    private func applyNotes(_ changes: [NoteRemoteChange]) {
        SyncCenter.shared.applyNotesInbound(
            changes: changes,
            familyId: familyId,
            modelContext: context
        )
    }
    
    // MARK: - Create
    
    func test_notes_upsertNew_createsLocal() throws {
        let dto = makeNoteDTO(id: "n1", titlePlain: "Visita pediatra")
        applyNotes([.upsert(dto)])
        
        let note = try fetchNote(id: "n1")
        XCTAssertNotNil(note, "La nota deve essere creata localmente")
        XCTAssertEqual(note?.title, "Visita pediatra")
    }
    
    func test_notes_upsertMultiple_createsAll() throws {
        let dtos = (1...3).map { makeNoteDTO(id: "n\($0)", titlePlain: "Nota \($0)") }
        applyNotes(dtos.map { .upsert($0) })
        
        for i in 1...3 {
            let note = try fetchNote(id: "n\(i)")
            XCTAssertNotNil(note, "Nota n\(i) deve esistere")
        }
    }
    
    // MARK: - Update (LWW)
    
    func test_notes_remoteNewer_updatesLocal() throws {
        // Creo prima una nota locale
        let old = Date().addingTimeInterval(-60)
        let dto1 = makeNoteDTO(id: "n-lww", titlePlain: "Vecchio", updatedAt: old)
        applyNotes([.upsert(dto1)])
        
        // Remote più recente → deve aggiornare
        let dto2 = makeNoteDTO(id: "n-lww", titlePlain: "Aggiornato", updatedAt: Date())
        applyNotes([.upsert(dto2)])
        
        let note = try fetchNote(id: "n-lww")
        XCTAssertEqual(note?.title, "Aggiornato", "Il remote più recente deve vincere (LWW)")
    }
    
    func test_notes_remoteOlder_doesNotOverrideLocal() throws {
        // Prima la versione "nuova"
        let now = Date()
        let dto1 = makeNoteDTO(id: "n-stale", titlePlain: "Recente", updatedAt: now)
        applyNotes([.upsert(dto1)])
        
        // Poi una versione stale (più vecchia)
        let old = now.addingTimeInterval(-120)
        let dto2 = makeNoteDTO(id: "n-stale", titlePlain: "Stale", updatedAt: old)
        applyNotes([.upsert(dto2)])
        
        let note = try fetchNote(id: "n-stale")
        XCTAssertEqual(note?.title, "Recente", "Il remoto più vecchio NON deve sovrascrivere il locale più recente")
    }
    
    // MARK: - isDeleted
    
    func test_notes_remoteIsDeleted_deletesLocal() throws {
        let dto = makeNoteDTO(id: "n-del", titlePlain: "Da cancellare")
        applyNotes([.upsert(dto)])
        XCTAssertNotNil(try fetchNote(id: "n-del"))
        
        let deletedDTO = makeNoteDTO(id: "n-del", isDeleted: true)
        applyNotes([.upsert(deletedDTO)])
        XCTAssertNil(try fetchNote(id: "n-del"), "La nota eliminata remotamente deve essere rimossa localmente")
    }
    
    func test_notes_upsertIsDeleted_notCreated() throws {
        // DTO già isDeleted: non deve creare nulla
        let dto = makeNoteDTO(id: "n-ghost", isDeleted: true)
        applyNotes([.upsert(dto)])
        XCTAssertNil(try fetchNote(id: "n-ghost"), "Una nota già eliminata non deve essere creata")
    }
    
    // MARK: - Remove
    
    func test_notes_remove_deletesExistingLocal() throws {
        let dto = makeNoteDTO(id: "n-rem")
        applyNotes([.upsert(dto)])
        XCTAssertNotNil(try fetchNote(id: "n-rem"))
        
        applyNotes([.remove("n-rem")])
        XCTAssertNil(try fetchNote(id: "n-rem"), ".remove deve eliminare la nota locale")
    }
    
    func test_notes_remove_nonExistent_doesNotCrash() throws {
        // Non deve crashare se la nota non esiste
        applyNotes([.remove("n-missing")])
        // Nessun assert — basta non crashare
    }
    
    // MARK: - Body
    
    func test_notes_body_preservedCorrectly() throws {
        let dto = makeNoteDTO(id: "n-body", titlePlain: "Titolo", bodyPlain: "Corpo lungo con emoji 🏥")
        applyNotes([.upsert(dto)])
        
        let note = try fetchNote(id: "n-body")
        XCTAssertEqual(note?.body, "Corpo lungo con emoji 🏥")
    }
}

// MARK: - SyncCenterExpensesTests

@MainActor
final class SyncCenterExpensesTests: XCTestCase {
    
    private var container: ModelContainer!
    private var context: ModelContext!
    private let familyId = "fam-exp-test"
    
    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(
            for: KBExpense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
    }
    
    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func fetchExpense(id: String) throws -> KBExpense? {
        let desc = FetchDescriptor<KBExpense>(predicate: #Predicate { $0.id == id })
        return try context.fetch(desc).first
    }
    
    private func applyExpenses(_ changes: [ExpenseRemoteChange]) {
        SyncCenter.shared.applyExpensesInbound(
            changes: changes,
            modelContext: context
        )
    }
    
    // MARK: - Create
    
    func test_expenses_upsertNew_createsLocal() throws {
        let dto = makeExpenseDTO(id: "e1", title: "Farmacia", amount: 15.50)
        applyExpenses([.upsert(dto)])
        
        let exp = try fetchExpense(id: "e1")
        XCTAssertNotNil(exp)
        XCTAssertEqual(exp!.title, "Farmacia")
        XCTAssertEqual(exp!.amount, 15.50, accuracy: 0.001)
    }
    
    func test_expenses_upsertMultiple_createsAll() throws {
        let dtos = (1...4).map { makeExpenseDTO(id: "e\($0)", title: "Spesa \($0)", amount: Double($0) * 10) }
        applyExpenses(dtos.map { .upsert($0) })
        
        for i in 1...4 {
            XCTAssertNotNil(try fetchExpense(id: "e\(i)"), "Spesa e\(i) deve esistere")
        }
    }
    
    // MARK: - Update (LWW)
    
    func test_expenses_remoteNewer_updatesAmount() throws {
        let old = Date().addingTimeInterval(-60)
        let dto1 = makeExpenseDTO(id: "e-lww", title: "Originale", amount: 10.0, updatedAt: old)
        applyExpenses([.upsert(dto1)])
        
        let dto2 = makeExpenseDTO(id: "e-lww", title: "Aggiornata", amount: 99.0, updatedAt: Date())
        applyExpenses([.upsert(dto2)])
        
        let exp = try fetchExpense(id: "e-lww")
        XCTAssertNotNil(exp)
        XCTAssertEqual(exp!.title, "Aggiornata")
        XCTAssertEqual(exp!.amount, 99.0, accuracy: 0.001)
    }
    
    func test_expenses_remoteOlder_doesNotOverride() throws {
        let now = Date()
        let dto1 = makeExpenseDTO(id: "e-stale", title: "Recente", amount: 50.0, updatedAt: now)
        applyExpenses([.upsert(dto1)])
        
        let old = now.addingTimeInterval(-120)
        let dto2 = makeExpenseDTO(id: "e-stale", title: "Stale", amount: 1.0, updatedAt: old)
        applyExpenses([.upsert(dto2)])
        
        let exp = try fetchExpense(id: "e-stale")
        XCTAssertNotNil(exp)
        XCTAssertEqual(exp!.title, "Recente", "Il remoto più vecchio NON deve sovrascrivere")
        XCTAssertEqual(exp!.amount, 50.0, accuracy: 0.001)
    }
    
    // MARK: - isDeleted
    
    func test_expenses_remoteIsDeleted_deletesLocal() throws {
        let dto = makeExpenseDTO(id: "e-del", title: "Da rimuovere")
        applyExpenses([.upsert(dto)])
        XCTAssertNotNil(try fetchExpense(id: "e-del"))
        
        let deletedDTO = makeExpenseDTO(id: "e-del", isDeleted: true)
        applyExpenses([.upsert(deletedDTO)])
        XCTAssertNil(try fetchExpense(id: "e-del"), "Spesa eliminata remotamente deve sparire")
    }
    
    func test_expenses_upsertIsDeleted_notCreated() throws {
        let dto = makeExpenseDTO(id: "e-ghost", isDeleted: true)
        applyExpenses([.upsert(dto)])
        XCTAssertNil(try fetchExpense(id: "e-ghost"), "Non deve creare una spesa già eliminata")
    }
    
    // MARK: - Remove
    
    func test_expenses_remove_deletesLocal() throws {
        let dto = makeExpenseDTO(id: "e-rem")
        applyExpenses([.upsert(dto)])
        XCTAssertNotNil(try fetchExpense(id: "e-rem"))
        
        applyExpenses([.remove("e-rem")])
        XCTAssertNil(try fetchExpense(id: "e-rem"))
    }
    
    func test_expenses_remove_nonExistent_doesNotCrash() {
        applyExpenses([.remove("e-missing")])
    }
    
    // MARK: - Anti-resurrect
    
    func test_expenses_antiResurrect_pendingDeleteNotOverridden() throws {
        let dto = makeExpenseDTO(id: "e-resurrect", title: "Originale", amount: 42.0)
        applyExpenses([.upsert(dto)])
        
        // Forza pendingDelete direttamente sul raw value
        let local = try XCTUnwrap(fetchExpense(id: "e-resurrect"))
        local.syncStateRaw = KBSyncState.pendingDelete.rawValue
        try context.save()
        
        // Remote più recente con titolo diverso → anti-resurrect deve bloccarla
        let remoteDTO = makeExpenseDTO(id: "e-resurrect", title: "Ritornata", amount: 999.0, updatedAt: Date())
        applyExpenses([.upsert(remoteDTO)])
        
        // Se anti-resurrect ha funzionato, il titolo e l'importo NON devono essere cambiati
        let after = try XCTUnwrap(fetchExpense(id: "e-resurrect"))
        XCTAssertEqual(after.title, "Originale", "Anti-resurrect: il titolo non deve essere sovrascritto")
        XCTAssertEqual(after.amount, 42.0, accuracy: 0.001, "Anti-resurrect: l'importo non deve essere sovrascritto")
        XCTAssertEqual(after.syncStateRaw, KBSyncState.pendingDelete.rawValue, "Anti-resurrect: syncState deve restare pendingDelete")
    }
}
