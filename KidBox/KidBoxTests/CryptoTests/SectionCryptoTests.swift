//
//  SectionCryptoTests.swift
//  KidBoxTests
//
//  Regola di lettura e round trip del blob `secure` delle sezioni
//  (`internal/cifratura-sezioni.md`). Chiave iniettata nel Keychain, niente Firestore.
//

import XCTest
import CryptoKit
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
}
