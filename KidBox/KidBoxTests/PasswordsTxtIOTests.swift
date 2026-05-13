import XCTest
import SwiftData
import CryptoKit
@testable import KidBox

@MainActor
final class PasswordsTxtIOTests: XCTestCase {
    private let familyId = "pw-io-family"
    private let uid = "pw-io-user"

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PasswordEntry.self, PasswordGroup.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func seedFamilyKey() throws {
        try FamilyKeychainStore.saveFamilyKey(SymmetricKey(size: .bits256), familyId: familyId, userId: uid)
    }

    private func writeTemp(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kbpw-test-\(UUID().uuidString).txt")
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(content.utf8))
        try data.write(to: url)
        return url
    }

    func test_roundTrip_export_parse_commit_keepsRecord() async throws {
        try seedFamilyKey()
        let exportGroupName = "Personale"
        let groupCipher = try PasswordCypher.encrypt(exportGroupName, familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid)
        let group = PasswordGroup(familyId: familyId, nameCipher: groupCipher, visibility: KBVisibilityScope.family, createdBy: uid)

        let entry = PasswordEntry(
            familyId: familyId,
            createdBy: uid,
            visibility: KBVisibilityScope.family,
            groupId: group.id,
            titleCipher: try PasswordCypher.encrypt("Gmail", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid),
            usernameCipher: try PasswordCypher.encrypt("mario@example.com", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid),
            passwordCipher: try PasswordCypher.encrypt("secret", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid),
            websiteCipher: try PasswordCypher.encrypt("https://mail.google.com", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid),
            notesCipher: try PasswordCypher.encrypt("nota", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid)
        )

        let exporter = PasswordsTxtExporter(familyId: familyId, currentUid: uid, passphrase: nil)
        let url = try await exporter.export(entries: [entry], groups: [group], familyName: nil)

        let container = try makeContainer()
        let importer = PasswordsTxtImporter(familyId: familyId, modelContext: container.mainContext, currentUid: uid)
        let preview = try await importer.parse(url: url, passphrase: nil)
        XCTAssertEqual(preview.totalCount, 1)
        try await importer.commit(preview: preview, strategy: .keepBoth)

        let desc = FetchDescriptor<PasswordEntry>()
        let imported = try container.mainContext.fetch(desc)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(try imported[0].decryptTitle(), "Gmail")
        XCTAssertEqual(try imported[0].decryptUsername(), "mario@example.com")
    }

    func test_parse_legacy_passBox_line() async throws {
        try seedFamilyKey()
        let container = try makeContainer()
        let importer = PasswordsTxtImporter(familyId: familyId, modelContext: container.mainContext, currentUid: uid)

        let url = try writeTemp("Account: Github Group: Work WebSite: https://github.com Username: me Password: 1234 Note: legacy")
        let preview = try await importer.parse(url: url, passphrase: nil)
        XCTAssertEqual(preview.totalCount, 1)
        XCTAssertTrue(preview.rowErrors.isEmpty)
    }

    func test_parse_legacy_passBox_multiple_records_in_same_text() async throws {
        try seedFamilyKey()
        let container = try makeContainer()
        let importer = PasswordsTxtImporter(familyId: familyId, modelContext: container.mainContext, currentUid: uid)
        let url = try writeTemp(
            "Account: A Group: G1 WebSite: https://a Username: u1 Password: p1 Note: n1 Account: B Group: G2 WebSite: https://b Username: u2 Password: p2 Note: n2"
        )
        let preview = try await importer.parse(url: url, passphrase: nil)
        XCTAssertEqual(preview.totalCount, 2)
        XCTAssertEqual(preview.legacyAmbiguousRecordIndices, [1])
    }

    func test_parse_multiline_notes() async throws {
        try seedFamilyKey()
        let container = try makeContainer()
        let importer = PasswordsTxtImporter(familyId: familyId, modelContext: container.mainContext, currentUid: uid)
        let txt = """
        # KidBox Password Export v1
        ---
        Title: Test
        Password: pass
        Note: riga1\\nriga2
        Visibility: family
        ---
        """
        let url = try writeTemp(txt)
        let preview = try await importer.parse(url: url, passphrase: nil)
        try await importer.commit(preview: preview, strategy: .keepBoth)
        let entries = try container.mainContext.fetch(FetchDescriptor<PasswordEntry>())
        XCTAssertEqual(try entries[0].decryptNotes(), "riga1\nriga2")
    }

    func test_parse_encrypted_file() async throws {
        try seedFamilyKey()
        let exporter = PasswordsTxtExporter(familyId: familyId, currentUid: uid, passphrase: "abc12345")
        let entry = PasswordEntry(
            familyId: familyId,
            createdBy: uid,
            visibility: KBVisibilityScope.family,
            titleCipher: try PasswordCypher.encrypt("A", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid),
            passwordCipher: try PasswordCypher.encrypt("B", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid)
        )
        let url = try await exporter.export(entries: [entry], groups: [], familyName: nil)
        let importer = PasswordsTxtImporter(familyId: familyId, modelContext: try makeContainer().mainContext, currentUid: uid)
        let preview = try await importer.parse(url: url, passphrase: "abc12345")
        XCTAssertEqual(preview.totalCount, 1)
    }

    func test_parse_errors_empty_missingTitle_wrongPassphrase() async throws {
        try seedFamilyKey()
        let importer = PasswordsTxtImporter(familyId: familyId, modelContext: try makeContainer().mainContext, currentUid: uid)
        let empty = try writeTemp("")
        await XCTAssertThrowsErrorAsync(try await importer.parse(url: empty, passphrase: nil))

        let missingTitle = try writeTemp("""
        # KidBox Password Export v1
        ---
        Password: x
        ---
        """)
        let preview = try await importer.parse(url: missingTitle, passphrase: nil)
        XCTAssertEqual(preview.totalCount, 0)
        XCTAssertFalse(preview.rowErrors.isEmpty)

        let exporter = PasswordsTxtExporter(familyId: familyId, currentUid: uid, passphrase: "ok-passphrase")
        let entry = PasswordEntry(
            familyId: familyId,
            createdBy: uid,
            visibility: KBVisibilityScope.family,
            titleCipher: try PasswordCypher.encrypt("A", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid),
            passwordCipher: try PasswordCypher.encrypt("B", familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid, familyKeyUserId: uid)
        )
        let encryptedURL = try await exporter.export(entries: [entry], groups: [], familyName: nil)
        await XCTAssertThrowsErrorAsync(try await importer.parse(url: encryptedURL, passphrase: "wrong"))
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @autoclosure @escaping () async throws -> Any,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        // Expected
    }
}
