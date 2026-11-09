//
//  FamilyKeyVaultTests.swift
//  KidBoxTests
//
//  La cassaforte v2 deve aprire ciò che scrive la web app (e viceversa).
//  Il vettore qui sotto è stato SCRITTO dalla web app (familyKeyVault.js) il
//  09/11/2026: se un test fallisce, una costante di FamilyKeyVaultCrypto non è
//  più identica al web e ad Android. Non correggere il vettore: correggere il codice.
//

import XCTest
import CryptoKit
@testable import KidBox

final class FamilyKeyVaultTests: XCTestCase {

    typealias C = FamilyKeyVaultCrypto

    // Vettore della web app
    let uid = "MeSf31GHULiGLS7KDyJleKMPSrZp"
    let familyId = "4A3DC5FF-2036-43E0-93AA-E81C7083D875"
    let code = "S62Z-TC4J-G5QR-F8W7-EWBJ-HH1C"
    let familyKeyB64 = "HCb/oTP5dnV/7a6FzxnpyHMru4zA6XfjempmUyeohqY="
    let rkId = "QjXYkcyX6Mgty8b86_NKjQ"
    let slotSalt = "tZNue8zZv4R320I9beHVMA=="
    let slot = C.Sealed(cipher: "JueafNLfYA9ZsjlHcN21c5uh02a+rWk70rQYdSY+4Io=",
                        nonce: "iWBNJdq4RvPVM6yK", tag: "vx7npyQiM+gFYcOUFsY+zQ==")
    let v2 = C.Sealed(cipher: "oTfoQwQX36GN6S1yNIGDMDY570RaePneyGL+TN2YeYQ=",
                      nonce: "F+/PfljfjEYPM8QM", tag: "qseWI3nQQERDTMWwUhSzAw==")

    private func openWebRK() throws -> Data {
        try C.openRecoverySlot(uid: uid, code: code, salt: slotSalt, sealed: slot, rkId: rkId)
    }

    func testOpensWebSlotWithRecoveryCode() throws {
        let rk = try openWebRK()
        XCTAssertEqual(rk.count, 32)
        XCTAssertEqual(C.rkId(rk), rkId)
    }

    func testOpensWebV2FamilyKey() throws {
        let rk = try openWebRK()
        let fk = C.openFamilyKeyV2(uid: uid, familyId: familyId, sealed: v2, rk: rk)
        XCTAssertEqual(fk?.base64EncodedString(), familyKeyB64)
    }

    func testCodeIsNormalized() throws {
        // minuscole, spazi e trattini, L al posto di 1
        XCTAssertEqual(C.normalizeRecoveryCode(" s62z tc4j-g5qr f8w7 ewbj hhLc "), "S62ZTC4JG5QRF8W7EWBJHH1C")
        // O→0, I/L→1
        XCTAssertEqual(C.normalizeRecoveryCode("OOOO-IIII-LLLL-0000-1111-2222"), "000011111111000011112222")
        XCTAssertNil(C.normalizeRecoveryCode("UUUU-UUUU-UUUU-UUUU-UUUU-UUUU"))
        XCTAssertNoThrow(try C.openRecoverySlot(uid: uid, code: "s62z tc4j g5qr f8w7 ewbj hhLc",
                                                salt: slotSalt, sealed: slot, rkId: rkId))
    }

    func testWrongCodeIsRejected() {
        XCTAssertThrowsError(try C.openRecoverySlot(uid: uid, code: "S62Z-TC4J-G5QR-F8W7-EWBJ-HH1D",
                                                    salt: slotSalt, sealed: slot, rkId: rkId))
        XCTAssertThrowsError(try C.openRecoverySlot(uid: uid, code: "troppo corto",
                                                    salt: slotSalt, sealed: slot, rkId: rkId))
    }

    func testAADBindsUidAndFamily() throws {
        let rk = try openWebRK()
        XCTAssertThrowsError(try C.openRecoverySlot(uid: "altro", code: code, salt: slotSalt, sealed: slot, rkId: nil))
        XCTAssertNil(C.openFamilyKeyV2(uid: uid, familyId: "altra-famiglia", sealed: v2, rk: rk))
        XCTAssertNil(C.openFamilyKeyV2(uid: "altro", familyId: familyId, sealed: v2, rk: rk))
    }

    func testRoundTrip() throws {
        let newCode = C.generateRecoveryCode()
        XCTAssertEqual(newCode.count, 29)
        XCTAssertNotNil(C.normalizeRecoveryCode(newCode))
        let rk = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let (salt, sealed) = try C.sealRecoverySlot(uid: uid, code: newCode, rk: rk)
        XCTAssertEqual(try C.openRecoverySlot(uid: uid, code: newCode, salt: salt, sealed: sealed, rkId: C.rkId(rk)), rk)

        let fk = Data(base64Encoded: familyKeyB64)!
        let s = try C.sealFamilyKeyV2(uid: uid, familyId: familyId, familyKey: fk, rk: rk)
        XCTAssertEqual(C.openFamilyKeyV2(uid: uid, familyId: familyId, sealed: s, rk: rk), fk)
    }
}
