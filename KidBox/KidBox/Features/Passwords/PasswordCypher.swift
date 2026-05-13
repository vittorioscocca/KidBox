//
//  PasswordCypher.swift
//  KidBox
//
//  Cifratura AES-GCM (CryptoKit) per il modulo Passwords, con chiave di famiglia da Keychain.
//
//  I dati non vivono in file utente / iCloud Documenti: solo blob cifrati in SwiftData e su Firestore.
//

import CryptoKit
import Foundation
import FirebaseAuth

/// Cifratura stringhe per `PasswordEntry` / `PasswordGroup` usando la stessa chiave AES-256
/// di Documenti e Wallet (`FamilyKeychainStore.loadFamilyKey`).
///
/// ## Chiave usata
/// - **Visibilità `family`**: si usa direttamente la `SymmetricKey` della famiglia per l’utente
///   corrente (`loadFamilyKey(familyId:userId:)`), identica a `DocumentCryptoService`.
/// - **Visibilità `onlyCreator`** (stored come `KBVisibilityScope.onlyCreator` = `"private"`):
///   si deriva una sotto-chiave con **HKDF-SHA256** da:
///   - `IKM` = chiave di famiglia
///   - `salt` = UTF-8 dell’UID del **creatore** (`createdBy`)
///   - `info` = costante `KidBox.Password.v1.onlyCreator`
///
///   Così il ciphertext è legato al creatore; gli altri membri possono ancora scaricare il
///   documento Firestore ma, se non sono il creatore, `decrypt` rifiuta prima ancora di
///   tentare materialmente (e in ogni caso solo il creatore condivide lo stesso `createdBy`
///   nel salt HKDF). **Nota di minaccia**: chiunque possegga la stessa chiave materiale di
///   famiglia potrebbe in teoria ricalcolare la sotto-chiave; il modello di minaccia è
///   “cooperazione familiare” come per gli altri segreti cifrati con la family key.
enum PasswordCypher {

    enum PasswordCryptoError: Error {
        case missingFamilyKey
        case missingCurrentUser
        case notCreatorForPrivateEntry
        case invalidUTF8
        case invalidCipher
    }

    private static let hkdfInfoOnlyCreator = Data("KidBox.Password.v1.onlyCreator".utf8)

    // MARK: - Public API

    /// Cifra una stringa UTF-8 in `AES.GCM.SealedBox.combined` (nonce + ciphertext + tag).
    /// - Parameter familyKeyUserId: se `nil`, usa `Auth.auth().currentUser?.uid` per caricare la chiave in Keychain (runtime app). Nei test passare l’UID usato con `FamilyKeychainStore.saveFamilyKey`.
    static func encrypt(
        _ plaintext: String,
        familyId: String,
        visibility: String,
        createdBy: String,
        familyKeyUserId: String? = nil
    ) throws -> Data {
        let uidForKey = try resolvedUidForFamilyKey(familyKeyUserId)
        let key = try symmetricKey(
            familyId: familyId,
            visibility: visibility,
            createdBy: createdBy,
            currentUid: uidForKey
        )
        let data = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw PasswordCryptoError.invalidCipher }
        return combined
    }

    /// Decifra `combined` in stringa UTF-8.
    static func decrypt(
        _ ciphertext: Data,
        familyId: String,
        visibility: String,
        createdBy: String,
        familyKeyUserId: String? = nil
    ) throws -> String {
        let uidForKey = try resolvedUidForFamilyKey(familyKeyUserId)
        let vis = PasswordEntry.normalizedPasswordVisibility(visibility)
        if vis == KBVisibilityScope.onlyCreator, uidForKey != createdBy {
            throw PasswordCryptoError.notCreatorForPrivateEntry
        }
        let key = try symmetricKey(
            familyId: familyId,
            visibility: visibility,
            createdBy: createdBy,
            currentUid: uidForKey
        )
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        let plain = try AES.GCM.open(box, using: key)
        guard let s = String(data: plain, encoding: .utf8) else { throw PasswordCryptoError.invalidUTF8 }
        return s
    }

    // MARK: - Key material

    private static func resolvedUidForFamilyKey(_ familyKeyUserId: String?) throws -> String {
        if let familyKeyUserId, !familyKeyUserId.isEmpty { return familyKeyUserId }
        return try currentUid()
    }

    private static func currentUid() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
            throw PasswordCryptoError.missingCurrentUser
        }
        return uid
    }

    private static func loadFamilyKey(familyId: String, userId: String) throws -> SymmetricKey {
        guard let key = FamilyKeychainStore.loadFamilyKey(familyId: familyId, userId: userId) else {
            throw PasswordCryptoError.missingFamilyKey
        }
        return key
    }

    /// Deriva la chiave AES-256 usata per cifrare/decifrare in base a visibilità e creatore.
    private static func symmetricKey(
        familyId: String,
        visibility: String,
        createdBy: String,
        currentUid: String
    ) throws -> SymmetricKey {
        let familyKey = try loadFamilyKey(familyId: familyId, userId: currentUid)
        let vis = PasswordEntry.normalizedPasswordVisibility(visibility)
        if vis == KBVisibilityScope.onlyCreator {
            let salt = Data(createdBy.utf8)
            return HKDF<SHA256>.deriveKey(
                inputKeyMaterial: familyKey,
                salt: salt,
                info: hkdfInfoOnlyCreator,
                outputByteCount: 32
            )
        }
        return familyKey
    }
}
