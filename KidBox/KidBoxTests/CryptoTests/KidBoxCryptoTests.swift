//
//  KidBoxCryptoTests.swift
//  KidBoxTests
//
//  Unit test per DocumentCryptoService, NoteCryptoService e InviteCrypto.
//  Questi test NON toccano Firestore/Keychain reali — usano chiavi iniettate in memoria.
//

import XCTest
import CryptoKit
@testable import KidBox

// MARK: - DocumentCryptoService Tests

final class DocumentCryptoServiceTests: XCTestCase {
    
    // MARK: - Helpers
    
    /// Inietta una chiave AES-256 nel Keychain per il test, ritorna il familyId usato.
    private func injectTestKey(familyId: String = "test-family-001",
                               userId: String  = "test-user-001") throws -> (String, String) {
        let rawKey = SymmetricKey(size: .bits256)
        try FamilyKeychainStore.saveFamilyKey(rawKey, familyId: familyId, userId: userId)
        return (familyId, userId)
    }
    
    override func tearDown() {
        super.tearDown()
        // Pulizia Keychain dopo ogni test — sovrascriviamo con una chiave dummy
        // (FamilyKeychainStore non espone delete pubblico, saveFamilyKey sovrascrive)
        let dummy = SymmetricKey(size: .bits256)
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: "test-family-001", userId: "test-user-001")
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: "test-family-002", userId: "test-user-001")
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: "no-key-family",   userId: "test-user-001")
    }
    
    // MARK: - Round-trip
    
    func test_encryptDecrypt_roundTrip_succeeds() throws {
        let (familyId, userId) = try injectTestKey()
        let plaintext = "Referto pediatrico: tutto ok.".data(using: .utf8)!
        
        let encrypted = try DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: userId)
        let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: userId)
        
        XCTAssertEqual(plaintext, decrypted, "Round-trip encrypt→decrypt deve restituire il plaintext originale")
    }
    
    func test_encrypt_producesDifferentCiphertextEachTime() throws {
        let (familyId, userId) = try injectTestKey()
        let plaintext = "Stesso testo".data(using: .utf8)!
        
        let enc1 = try DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: userId)
        let enc2 = try DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: userId)
        
        XCTAssertNotEqual(enc1, enc2, "Ogni cifratura deve usare un nonce diverso → output diverso")
    }
    
    func test_encrypt_emptyData_succeeds() throws {
        let (familyId, userId) = try injectTestKey()
        let empty = Data()
        
        let encrypted = try DocumentCryptoService.encrypt(empty, familyId: familyId, userId: userId)
        let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: userId)
        
        XCTAssertEqual(empty, decrypted, "Cifratura di Data vuota deve fare round-trip correttamente")
    }
    
    func test_encrypt_largePayload_succeeds() throws {
        let (familyId, userId) = try injectTestKey()
        let large = Data(repeating: 0xAB, count: 5 * 1024 * 1024) // 5 MB
        
        let encrypted = try DocumentCryptoService.encrypt(large, familyId: familyId, userId: userId)
        let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: userId)
        
        XCTAssertEqual(large, decrypted, "Round-trip su payload da 5 MB deve riuscire")
    }
    
    // MARK: - Missing key
    
    func test_encrypt_missingKey_throwsMissingFamilyKey() throws {
        // UUID random → certamente non ha mai una chiave in Keychain
        let unknownFamilyId = "no-key-\(UUID().uuidString)"
        XCTAssertThrowsError(
            try DocumentCryptoService.encrypt(Data("test".utf8),
                                              familyId: unknownFamilyId,
                                              userId:   "test-user-001")
        ) { error in
            XCTAssertEqual(error as? DocumentCryptoService.CryptoError,
                           .missingFamilyKey,
                           "Deve lanciare missingFamilyKey se la chiave non è in Keychain")
        }
    }
    
    func test_decrypt_missingKey_throwsMissingFamilyKey() throws {
        let (familyId, userId) = try injectTestKey()
        let encrypted = try DocumentCryptoService.encrypt(Data("test".utf8),
                                                          familyId: familyId,
                                                          userId: userId)
        
        // Proviamo decrypt con una famiglia per cui non è stata iniettata nessuna chiave
        XCTAssertThrowsError(
            try DocumentCryptoService.decrypt(encrypted,
                                              familyId: "family-without-key-\(UUID().uuidString)",
                                              userId: userId)
        ) { error in
            XCTAssertEqual(error as? DocumentCryptoService.CryptoError,
                           .missingFamilyKey)
        }
    }
    
    // MARK: - Tampered ciphertext
    
    func test_decrypt_tamperedCiphertext_throwsCryptoKitError() throws {
        let (familyId, userId) = try injectTestKey()
        let plaintext = "Dato sensibile".data(using: .utf8)!
        var encrypted = try DocumentCryptoService.encrypt(plaintext, familyId: familyId, userId: userId)
        
        // Modifica un byte nel mezzo del ciphertext (dopo i 12 byte di nonce)
        let tamperIndex = encrypted.index(encrypted.startIndex, offsetBy: 20)
        encrypted[tamperIndex] ^= 0xFF
        
        XCTAssertThrowsError(
            try DocumentCryptoService.decrypt(encrypted, familyId: familyId, userId: userId),
            "Un ciphertext manomesso deve fallire la verifica AES-GCM"
        )
    }
    
    // MARK: - Cross-family isolation
    
    func test_decrypt_wrongFamilyKey_fails() throws {
        let (familyId1, userId) = try injectTestKey(familyId: "test-family-001")
        try injectTestKey(familyId: "test-family-002", userId: userId)
        
        let plaintext = "Dato famiglia 1".data(using: .utf8)!
        let encrypted = try DocumentCryptoService.encrypt(plaintext,
                                                          familyId: familyId1,
                                                          userId: userId)
        
        // Tentativo di decrypt con chiave di un'altra famiglia → deve fallire
        XCTAssertThrowsError(
            try DocumentCryptoService.decrypt(encrypted,
                                              familyId: "test-family-002",
                                              userId: userId),
            "Il decrypt con la chiave di un'altra famiglia deve fallire"
        )
    }
}

// MARK: - NoteCryptoService Tests

final class NoteCryptoServiceTests: XCTestCase {
    
    private let familyId = "note-test-family"
    private let userId   = "note-test-user"
    
    override func setUp() {
        super.setUp()
        let key = SymmetricKey(size: .bits256)
        try? FamilyKeychainStore.saveFamilyKey(key, familyId: familyId, userId: userId)
    }
    
    override func tearDown() {
        super.tearDown()
        // Sovrascriviamo con chiave dummy per "pulire"
        let dummy = SymmetricKey(size: .bits256)
        try? FamilyKeychainStore.saveFamilyKey(dummy, familyId: familyId, userId: userId)
    }
    
    func test_encryptDecryptString_roundTrip() throws {
        let original = "Nota importante per la famiglia 🏠"
        let encrypted = try NoteCryptoService.encryptString(original, familyId: familyId, userId: userId)
        let decrypted = try NoteCryptoService.decryptString(encrypted, familyId: familyId, userId: userId)
        XCTAssertEqual(original, decrypted)
    }
    
    func test_encryptString_producesValidBase64() throws {
        let encrypted = try NoteCryptoService.encryptString("test", familyId: familyId, userId: userId)
        XCTAssertNotNil(Data(base64Encoded: encrypted), "L'output deve essere Base64 valido")
    }
    
    func test_decryptString_invalidBase64_throwsError() throws {
        XCTAssertThrowsError(
            try NoteCryptoService.decryptString("not-valid-base64!!!",
                                                familyId: familyId,
                                                userId: userId)
        ) { error in
            XCTAssertEqual(error as? NoteCryptoService.CryptoError, .invalidBase64)
        }
    }
    
    func test_encryptDecryptString_unicode_roundTrip() throws {
        let unicode = "Visita 🏥 del bambino: tutto ok ✅ — dose 💉"
        let encrypted = try NoteCryptoService.encryptString(unicode, familyId: familyId, userId: userId)
        let decrypted = try NoteCryptoService.decryptString(encrypted, familyId: familyId, userId: userId)
        XCTAssertEqual(unicode, decrypted)
    }
}

// MARK: - InviteCrypto Tests

final class InviteCryptoTests: XCTestCase {
    
    // MARK: - randomBytes
    
    func test_randomBytes_correctLength() {
        let bytes = InviteCrypto.randomBytes(32)
        XCTAssertEqual(bytes.count, 32)
    }
    
    func test_randomBytes_areRandom() {
        let a = InviteCrypto.randomBytes(32)
        let b = InviteCrypto.randomBytes(32)
        XCTAssertNotEqual(a, b, "Due chiamate devono produrre bytes diversi")
    }
    
    // MARK: - sha256Base64
    
    func test_sha256Base64_deterministico() {
        let data = "kidbox-test".data(using: .utf8)!
        let hash1 = InviteCrypto.sha256Base64(data)
        let hash2 = InviteCrypto.sha256Base64(data)
        XCTAssertEqual(hash1, hash2, "SHA256 è deterministico per lo stesso input")
    }
    
    func test_sha256Base64_differentInputs() {
        let h1 = InviteCrypto.sha256Base64("a".data(using: .utf8)!)
        let h2 = InviteCrypto.sha256Base64("b".data(using: .utf8)!)
        XCTAssertNotEqual(h1, h2)
    }
    
    func test_sha256Base64_isValidBase64() {
        let hash = InviteCrypto.sha256Base64("test".data(using: .utf8)!)
        XCTAssertNotNil(Data(base64Encoded: hash), "Output deve essere Base64 valido")
    }
    
    // MARK: - deriveWrapKey
    
    func test_deriveWrapKey_deterministico() {
        let secret   = InviteCrypto.randomBytes(32)
        let salt     = InviteCrypto.randomBytes(16)
        let familyId = "family-abc"
        
        let k1 = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        let k2 = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) },
                       k2.withUnsafeBytes { Data($0) },
                       "HKDF è deterministico per gli stessi input")
    }
    
    func test_deriveWrapKey_differentSalts_differentKeys() {
        let secret   = InviteCrypto.randomBytes(32)
        let salt1    = InviteCrypto.randomBytes(16)
        let salt2    = InviteCrypto.randomBytes(16)
        let familyId = "family-abc"
        
        let k1 = InviteCrypto.deriveWrapKey(secret: secret, salt: salt1, familyId: familyId)
        let k2 = InviteCrypto.deriveWrapKey(secret: secret, salt: salt2, familyId: familyId)
        
        XCTAssertNotEqual(k1.withUnsafeBytes { Data($0) },
                          k2.withUnsafeBytes { Data($0) },
                          "Salt diversi devono produrre chiavi diverse")
    }
    
    func test_deriveWrapKey_differentFamilyIds_differentKeys() {
        let secret = InviteCrypto.randomBytes(32)
        let salt   = InviteCrypto.randomBytes(16)
        
        let k1 = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: "family-A")
        let k2 = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: "family-B")
        
        XCTAssertNotEqual(k1.withUnsafeBytes { Data($0) },
                          k2.withUnsafeBytes { Data($0) },
                          "FamilyId diversi devono produrre chiavi diverse (domain separation)")
    }
    
    // MARK: - Wrap / Unwrap round-trip
    
    func test_wrapUnwrap_roundTrip() throws {
        let secret      = InviteCrypto.randomBytes(32)
        let salt        = InviteCrypto.randomBytes(16)
        let familyId    = "wrap-test-family"
        let masterKey   = SymmetricKey(size: .bits256)
        let wrapKey     = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        
        let wrapped = try InviteCrypto.wrapFamilyKey(familyKey: masterKey, wrapKey: wrapKey)
        let unwrapped = try InviteCrypto.unwrapFamilyKey(cipher: wrapped.cipher,
                                                         nonce: wrapped.nonce,
                                                         tag: wrapped.tag,
                                                         wrapKey: wrapKey)
        
        XCTAssertEqual(masterKey.withUnsafeBytes { Data($0) },
                       unwrapped.withUnsafeBytes { Data($0) },
                       "Wrap→Unwrap deve restituire la master key originale")
    }
    
    func test_unwrap_wrongWrapKey_fails() throws {
        let secret      = InviteCrypto.randomBytes(32)
        let salt        = InviteCrypto.randomBytes(16)
        let familyId    = "wrap-test-family"
        let masterKey   = SymmetricKey(size: .bits256)
        let wrapKey     = InviteCrypto.deriveWrapKey(secret: secret, salt: salt, familyId: familyId)
        let wrongKey    = SymmetricKey(size: .bits256)
        
        let wrapped = try InviteCrypto.wrapFamilyKey(familyKey: masterKey, wrapKey: wrapKey)
        
        XCTAssertThrowsError(
            try InviteCrypto.unwrapFamilyKey(cipher: wrapped.cipher,
                                             nonce: wrapped.nonce,
                                             tag: wrapped.tag,
                                             wrapKey: wrongKey),
            "Unwrap con chiave sbagliata deve fallire"
        )
    }
}
