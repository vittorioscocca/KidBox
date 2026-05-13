//
//  PasswordCypherTests.swift
//  KidBoxTests
//

import CryptoKit
import XCTest
@testable import KidBox

final class PasswordCypherTests: XCTestCase {

    private func injectKey(familyId: String = "pw-test-family", userId: String = "pw-test-user") throws -> (String, String) {
        let key = SymmetricKey(size: .bits256)
        try FamilyKeychainStore.saveFamilyKey(key, familyId: familyId, userId: userId)
        return (familyId, userId)
    }

    override func tearDown() {
        super.tearDown()
        let dummy = SymmetricKey(size: .bits256)
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: "pw-test-family", userId: "pw-test-user")
    }

    func test_roundTrip_familyVisibility() throws {
        let (familyId, uid) = try injectKey()
        let plain = "Segreto super-mario-64!"
        let cipher = try PasswordCypher.encrypt(
            plain,
            familyId: familyId,
            visibility: KBVisibilityScope.family,
            createdBy: uid,
            familyKeyUserId: uid
        )
        let out = try PasswordCypher.decrypt(
            cipher,
            familyId: familyId,
            visibility: KBVisibilityScope.family,
            createdBy: uid,
            familyKeyUserId: uid
        )
        XCTAssertEqual(out, plain)
    }

    func test_roundTrip_onlyCreator_sameCreator() throws {
        let (familyId, uid) = try injectKey()
        let plain = "TOTP-seed-or-password"
        let cipher = try PasswordCypher.encrypt(
            plain,
            familyId: familyId,
            visibility: KBVisibilityScope.onlyCreator,
            createdBy: uid,
            familyKeyUserId: uid
        )
        let out = try PasswordCypher.decrypt(
            cipher,
            familyId: familyId,
            visibility: KBVisibilityScope.onlyCreator,
            createdBy: uid,
            familyKeyUserId: uid
        )
        XCTAssertEqual(out, plain)
    }

    func test_onlyCreator_decryptDeniedForOtherUser() throws {
        let (familyId, creator) = try injectKey()
        let other = "pw-other-user"
        try FamilyKeychainStore.saveFamilyKey(SymmetricKey(size: .bits256), familyId: familyId, userId: other)

        let plain = "solo-io"
        let cipher = try PasswordCypher.encrypt(
            plain,
            familyId: familyId,
            visibility: KBVisibilityScope.onlyCreator,
            createdBy: creator,
            familyKeyUserId: creator
        )

        XCTAssertThrowsError(
            try PasswordCypher.decrypt(
                cipher,
                familyId: familyId,
                visibility: KBVisibilityScope.onlyCreator,
                createdBy: creator,
                familyKeyUserId: other
            )
        ) { err in
            guard let cryptoErr = err as? PasswordCypher.PasswordCryptoError,
                  case .notCreatorForPrivateEntry = cryptoErr else {
                XCTFail("Expected notCreatorForPrivateEntry, got \(err)")
                return
            }
        }
    }
}
