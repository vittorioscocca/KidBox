//
//  AutoFillSnapshotAndTOTPTests.swift
//  KidBoxTests
//

import CryptoKit
import XCTest
@testable import KidBox

final class AutoFillSnapshotAndTOTPTests: XCTestCase {

    // MARK: - TOTP / HOTP (RFC 4226 counter 0 vector via OTPService → TOTPCodeGenerator)

    func test_totp_atEpoch0_matchesRFC4226_HOTP_counter0() {
        let secretBase32 = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let t0 = Date(timeIntervalSince1970: 0)
        let viaGenerator = TOTPCodeGenerator.currentCode(
            secretBase32: secretBase32,
            digits: 6,
            period: 30,
            algorithm: "SHA1",
            referenceDate: t0,
        )
        XCTAssertEqual(viaGenerator, "755224")

        let payload = PasswordOtpPayload(secret: secretBase32, digits: 6, period: 30, algorithm: "SHA1")
        let viaService = OTPService.currentTotpCode(payload: payload, at: t0)
        XCTAssertEqual(viaService, "755224")
    }

    func test_totp_invalidAlgorithm_returnsNil() {
        let t0 = Date(timeIntervalSince1970: 0)
        let code = TOTPCodeGenerator.currentCode(
            secretBase32: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            algorithm: "SHA256",
            referenceDate: t0,
        )
        XCTAssertNil(code)
    }

    func test_base32Validation_sharedWithOTPService() {
        XCTAssertTrue(TOTPCodeGenerator.isValidSecretBase32("JBSWY3DPEHPK3PXP"))
        XCTAssertTrue(OTPService.isValidOtpSecret("  JBSWY3DPEHPK3PXP  "))
        XCTAssertFalse(OTPService.isValidOtpSecret("!!!"))
    }

    // MARK: - AutoFillWebsiteHost

    func test_normalizedHost_stripsSchemeWwwPortPath() {
        XCTAssertEqual(AutoFillWebsiteHost.normalizedHost(from: "HTTPS://WWW.Example.COM:8443/foo"), "example.com")
        XCTAssertEqual(AutoFillWebsiteHost.normalizedHost(from: "sub.APP.io"), "sub.app.io")
        XCTAssertNil(AutoFillWebsiteHost.normalizedHost(from: "   "))
    }

    func test_hostMatching_subdomainAndEquality() {
        XCTAssertTrue(AutoFillWebsiteHost.host("login.example.com", matchesRequest: "example.com"))
        XCTAssertTrue(AutoFillWebsiteHost.host("example.com", matchesRequest: "login.example.com"))
        XCTAssertTrue(AutoFillWebsiteHost.host("example.com", matchesRequest: "example.com"))
        XCTAssertFalse(AutoFillWebsiteHost.host("evil-example.com", matchesRequest: "example.com"))
        XCTAssertFalse(AutoFillWebsiteHost.host(nil, matchesRequest: "a.com"))
    }

    // MARK: - AutoFillSnapshot AES-GCM round-trip

    func test_autoFillSnapshot_encryptDecrypt_roundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let original = AutoFillSnapshot(
            version: 1,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            items: [
                .init(
                    id: "1",
                    title: "Test",
                    username: "u",
                    password: "p",
                    website: "example.com",
                    visibility: "family",
                    owner: "uid",
                    otp: AutoFillOtpPayload(secret: "JBSWY3DPEHPK3PXP", digits: 6, period: 30, algorithm: "SHA1"),
                ),
            ],
        )
        let blob = try original.encryptedBlob(using: key)
        let decoded = try AutoFillSnapshot.decrypt(fromCombined: blob, using: key)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertEqual(decoded.items.count, original.items.count)
        XCTAssertEqual(decoded.items.first?.id, "1")
        XCTAssertEqual(decoded.items.first?.otp?.secret, "JBSWY3DPEHPK3PXP")
    }
}
