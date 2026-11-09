//
//  SectionCryptoTests.swift
//  KidBoxTests
//
//  Regola di lettura e round trip del blob `secure` delle sezioni
//  (`internal/cifratura-sezioni.md`). Chiave iniettata nel Keychain, niente Firestore.
//

import XCTest
import CryptoKit
import FirebaseFirestore
@testable import KidBox

final class SectionCryptoTests: XCTestCase {

    private let familyId = "test-family-sections"
    private let userId   = "test-user-sections"

    override func setUp() {
        super.setUp()
        try? FamilyKeychainStore.saveFamilyKey(SymmetricKey(size: .bits256), familyId: familyId, userId: userId)
    }

    private func encrypt(_ s: String) -> String? {
        try? NoteCryptoService.encryptString(s, familyId: familyId, userId: userId)
    }

    private func decrypt(_ s: String) -> String? {
        try? NoteCryptoService.decryptString(s, familyId: familyId, userId: userId)
    }

    private let fields = SectionCrypto.Section.vehicles.fields

    // MARK: - Round trip

    func test_sealThenResolve_roundTrip() throws {
        let data: [String: Any] = [
            "name": "Panda", "licensePlate": "AB123CD", "notes": Optional<String>.none as Any,
            "currentKm": 12000, "isDeleted": false
        ]
        let sealed = try XCTUnwrap(SectionCrypto.sealed(data, fields: fields, existing: nil, encrypt: encrypt))

        // Tutti i campi della tabella a "", il resto intatto.
        for f in fields { XCTAssertEqual(sealed[f] as? String, "") }
        XCTAssertEqual(sealed["currentKm"] as? Int, 12000)
        XCTAssertEqual(sealed[SectionCrypto.versionKey] as? Int, 1)
        XCTAssertTrue(SectionCrypto.isSealed(sealed))

        let opened = SectionCrypto.resolve(sealed, fields: fields, decrypt: decrypt)
        XCTAssertEqual(opened["name"] as? String, "Panda")
        XCTAssertEqual(opened["licensePlate"] as? String, "AB123CD")
        XCTAssertEqual(opened["notes"] as? String, "")
    }

    // MARK: - Regola di lettura

    func test_resolve_plainNonEmptyWins() throws {
        let sealed = try XCTUnwrap(SectionCrypto.sealed(["name": "Vecchio", "notes": "cifrata"],
                                                        fields: fields, existing: nil, encrypt: encrypt))
        var doc = sealed
        doc["name"] = "Nuovo"   // una build vecchia ha riscritto il chiaro
        let opened = SectionCrypto.resolve(doc, fields: fields, decrypt: decrypt)
        XCTAssertEqual(opened["name"] as? String, "Nuovo")
        XCTAssertEqual(opened["notes"] as? String, "cifrata")
    }

    func test_resolve_undecryptable_keepsPlain() {
        let doc: [String: Any] = ["name": "", "notes": "in chiaro", SectionCrypto.secureKey: "non-base64!!"]
        let opened = SectionCrypto.resolve(doc, fields: fields, decrypt: decrypt)
        XCTAssertEqual(opened["name"] as? String, "")
        XCTAssertEqual(opened["notes"] as? String, "in chiaro")
    }

    func test_resolve_withoutSecure_isUnchanged() {
        let doc: [String: Any] = ["name": "Panda", "brand": "Fiat"]
        let opened = SectionCrypto.resolve(doc, fields: fields, decrypt: decrypt)
        XCTAssertEqual(opened["name"] as? String, "Panda")
        XCTAssertEqual(opened["brand"] as? String, "Fiat")
        XCTAssertFalse(SectionCrypto.isSealed(doc))
    }

    // MARK: - Campi non riscritti

    func test_sealed_keepsExistingForMissingFields() throws {
        let existing: [String: Any] = ["name": "Panda", "vin": "ZFA123"]
        let sealed = try XCTUnwrap(SectionCrypto.sealed(["name": "Panda 4x4"], fields: fields,
                                                        existing: existing, encrypt: encrypt))
        let opened = SectionCrypto.resolve(sealed, fields: fields, decrypt: decrypt)
        XCTAssertEqual(opened["name"] as? String, "Panda 4x4")
        XCTAssertEqual(opened["vin"] as? String, "ZFA123")
    }

    func test_sealed_reencryptPayload_onlySecureAndEmptyFields() throws {
        let update = try XCTUnwrap(SectionCrypto.sealed([:], fields: fields,
                                                        existing: ["name": "Panda", "updatedAt": "x"],
                                                        encrypt: encrypt))
        XCTAssertEqual(Set(update.keys), Set(fields + [SectionCrypto.secureKey, SectionCrypto.versionKey]))
    }

    // MARK: - Secondo giro: campi «*» cancellati

    func test_sealed_starredFieldsAreDeleted() throws {
        let section = SectionCrypto.Section.medicalVisits
        let data: [String: Any] = ["reason": "Febbre", "travelDetailsData": "eyJhIjoxfQ==",
                                   "asNeededDrugsJson": "[]", "cost": 50]
        let sealed = try XCTUnwrap(SectionCrypto.sealed(data, fields: section.fields, deleted: section.deletedFields,
                                                        existing: nil, encrypt: encrypt))
        for f in section.fields {
            if section.deletedFields.contains(f) {
                XCTAssertTrue(sealed[f] is FieldValue, "\(f) dovrebbe essere FieldValue.delete()")
            } else {
                XCTAssertEqual(sealed[f] as? String, "", f)
            }
        }
        XCTAssertEqual(sealed["cost"] as? Int, 50)

        // In lettura il campo assente equivale a vuoto: il valore torna da `secure`.
        var stored = sealed
        for f in section.deletedFields { stored.removeValue(forKey: f) }
        let opened = SectionCrypto.resolve(stored, fields: section.fields, decrypt: decrypt)
        XCTAssertEqual(opened["travelDetailsData"] as? String, "eyJhIjoxfQ==")
        XCTAssertEqual(opened["asNeededDrugsJson"] as? String, "[]")
        XCTAssertEqual(opened["reason"] as? String, "Febbre")
    }

    func test_deletedFields_onlyInTable() {
        for section in SectionCrypto.Section.allCases {
            XCTAssertTrue(section.deletedFields.isSubset(of: Set(section.fields)), section.rawValue)
        }
    }

    // MARK: - Secondo giro: scritture parziali

    func test_sealed_partialWrite_keepsFieldsOtherClientsWrite() throws {
        // `name`, `doctorName`, `location` dei vaccini li scrive solo Android.
        let section = SectionCrypto.Section.vaccines
        let existing: [String: Any] = ["commercialName": "Hexyon", "name": "Esavalente",
                                       "doctorName": "Dr. Rossi", "location": "ASL"]
        let write: [String: Any] = ["commercialName": "Hexyon", "lotNumber": "L1", "notes": "ok"]
        let sealed = try XCTUnwrap(SectionCrypto.sealed(write, fields: section.fields, existing: existing,
                                                        encrypt: encrypt))
        let opened = SectionCrypto.resolve(sealed, fields: section.fields, decrypt: decrypt)
        XCTAssertEqual(opened["name"] as? String, "Esavalente")
        XCTAssertEqual(opened["doctorName"] as? String, "Dr. Rossi")
        XCTAssertEqual(opened["location"] as? String, "ASL")
        XCTAssertEqual(opened["lotNumber"] as? String, "L1")
    }

    func test_sealed_explicitClear_winsOverExisting() throws {
        // Un campo scritto nullo o cancellato è uno svuotamento voluto, non un campo mancante.
        let section = SectionCrypto.Section.calendarEvents
        let existing: [String: Any] = ["title": "Calcio", "notes": "porta la borraccia", "location": "Campo"]
        let write: [String: Any] = ["title": "Calcio", "notes": FieldValue.delete(), "location": NSNull()]
        let sealed = try XCTUnwrap(SectionCrypto.sealed(write, fields: section.fields, existing: existing,
                                                        encrypt: encrypt))
        let opened = SectionCrypto.resolve(sealed, fields: section.fields, decrypt: decrypt)
        XCTAssertEqual(opened["title"] as? String, "Calcio")
        XCTAssertEqual(opened["notes"] as? String, "")
        XCTAssertEqual(opened["location"] as? String, "")
    }

    func test_newTables() {
        XCTAssertEqual(SectionCrypto.Section.children.fields, ["name"])
        XCTAssertEqual(SectionCrypto.Section.todos.fields, ["title", "notes"])
        XCTAssertEqual(SectionCrypto.Section.todoLists.fields, ["name"])
        XCTAssertEqual(SectionCrypto.Section.calendarEvents.fields, ["title", "notes", "location"])
    }

    // MARK: - Calendario esportato: riapertura

    func test_reopened_writesPlainAndDeletesSecure() throws {
        let fields = SectionCrypto.Section.calendarEvents.fields
        let sealed = try XCTUnwrap(SectionCrypto.sealed(["title": "Dentista", "location": "Via Roma"],
                                                        fields: fields, existing: nil, encrypt: encrypt))
        let resolved = SectionCrypto.resolve(sealed, fields: fields, decrypt: decrypt)
        let update = SectionCrypto.reopened(resolved, fields: fields)
        XCTAssertEqual(update["title"] as? String, "Dentista")
        XCTAssertEqual(update["location"] as? String, "Via Roma")
        XCTAssertEqual(update["notes"] as? String, "")
        XCTAssertTrue(update[SectionCrypto.secureKey] is FieldValue)
        XCTAssertTrue(update[SectionCrypto.versionKey] is FieldValue)
        XCTAssertNil(update["updatedAt"])
        XCTAssertEqual(Set(update.keys), Set(fields + [SectionCrypto.secureKey, SectionCrypto.versionKey]))
    }

    // MARK: - Push: segnaposto

    func test_pushTemplate_fillsPlaceholders() throws {
        let sealed = try XCTUnwrap(SectionCrypto.sealed(["title": "Comprare il latte"],
                                                        fields: SectionCrypto.Section.todos.fields,
                                                        existing: nil, encrypt: encrypt))
        let json = try XCTUnwrap(decrypt(try XCTUnwrap(sealed[SectionCrypto.secureKey] as? String)))
        let values = try XCTUnwrap(SecurePushTemplate.values(fromJSON: json))
        let r = try XCTUnwrap(SecurePushTemplate.render(titleTemplate: "Nuovo to-do",
                                                        bodyTemplate: "Marco ti ha assegnato «{title}»",
                                                        values: values))
        XCTAssertEqual(r.title, "Nuovo to-do")
        XCTAssertEqual(r.body, "Marco ti ha assegnato «Comprare il latte»")
    }

    func test_pushTemplate_missingValue_keepsGeneric() {
        XCTAssertNil(SecurePushTemplate.fill("{title} alle {location}", values: ["title": "Calcio"]))
        XCTAssertNil(SecurePushTemplate.fill("{title}", values: ["title": ""]))
        XCTAssertNil(SecurePushTemplate.render(titleTemplate: "{title}", bodyTemplate: "{notes}",
                                               values: ["title": "Calcio"]))
        XCTAssertEqual(SecurePushTemplate.fill("Senza segnaposto", values: [:]), "Senza segnaposto")
        XCTAssertEqual(SecurePushTemplate.fill("{a}{b}!", values: ["a": "x", "b": "y"]), "xy!")
    }
}
