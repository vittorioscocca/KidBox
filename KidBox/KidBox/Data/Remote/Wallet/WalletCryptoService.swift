//
//  WalletCryptoService.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation

/// Helper di cifratura dedicato al modulo Wallet.
///
/// Riusa la chiave per-famiglia di `DocumentCryptoService` (una sola chiave
/// AES-GCM caricata da `FamilyKeychainStore`), così:
/// - i PDF dei biglietti, una volta sigillati, sono indistinguibili da
///   quelli della sezione Documents per il backend
/// - Cloud Functions schedulate possono leggere/aggiornare metadati
///   *non sensibili* (eventDate, kind, isDeleted) senza accedere al
///   contenuto cifrato (titolo, location, PNR, posto, note, PDF)
///
/// Convenzioni:
/// - i campi testuali sono salvati su Firestore come stringa base64 di
///   `AES.GCM.SealedBox.combined` (stesso formato di `NoteCryptoService`)
/// - i PDF sono caricati su Firebase Storage come bytes raw del
///   `combined` (nonce + ciphertext + tag), non base64-encoded, per
///   risparmiare ~33% di banda
enum WalletCryptoService {

    enum CryptoError: Error {
        case invalidBase64
        case invalidUTF8
    }

    // MARK: - Stringhe (base64)

    /// Cifra una stringa UTF-8 in base64(AES.GCM.SealedBox.combined).
    static func encryptString(_ plaintext: String, familyId: String, userId: String) throws -> String {
        let data = Data(plaintext.utf8)
        let combined = try DocumentCryptoService.encrypt(data, familyId: familyId, userId: userId)
        return combined.base64EncodedString()
    }

    /// Decifra base64(AES.GCM.SealedBox.combined) in stringa UTF-8.
    static func decryptString(_ combinedB64: String, familyId: String, userId: String) throws -> String {
        guard let combined = Data(base64Encoded: combinedB64) else {
            throw CryptoError.invalidBase64
        }
        let plaintext = try DocumentCryptoService.decrypt(combined, familyId: familyId, userId: userId)
        guard let s = String(data: plaintext, encoding: .utf8) else {
            throw CryptoError.invalidUTF8
        }
        return s
    }

    /// Variante "optional" comoda per i campi opzionali (location, seat, PNR, notes).
    /// Restituisce `nil` se l'input è nil o stringa vuota.
    static func encryptOptional(_ plaintext: String?, familyId: String, userId: String) throws -> String? {
        guard let p = plaintext, !p.isEmpty else { return nil }
        return try encryptString(p, familyId: familyId, userId: userId)
    }

    /// Variante "optional" che torna `nil` su input nil/vuoto e propaga l'errore di decodifica.
    static func decryptOptional(_ combinedB64: String?, familyId: String, userId: String) throws -> String? {
        guard let b = combinedB64, !b.isEmpty else { return nil }
        return try decryptString(b, familyId: familyId, userId: userId)
    }

    // MARK: - PDF (raw Data)

    /// Cifra un PDF e restituisce i bytes `combined` da caricare su Firebase Storage.
    /// Pass-through di `DocumentCryptoService.encrypt` con un nome semantico.
    static func encryptPDF(_ pdfData: Data, familyId: String, userId: String) throws -> Data {
        try DocumentCryptoService.encrypt(pdfData, familyId: familyId, userId: userId)
    }

    /// Decifra i bytes `combined` letti da Firebase Storage e restituisce il PDF in chiaro.
    static func decryptPDF(_ combined: Data, familyId: String, userId: String) throws -> Data {
        try DocumentCryptoService.decrypt(combined, familyId: familyId, userId: userId)
    }
}
