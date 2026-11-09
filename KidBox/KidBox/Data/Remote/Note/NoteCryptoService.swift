//
//  NoteCryptoService.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import Foundation

enum NoteCryptoService {
    
    enum CryptoError: Error {
        case invalidBase64
        case invalidUTF8
    }
    
    /// Encrypts a UTF-8 string into base64(AES.GCM.SealedBox.combined)
    static func encryptString(_ plaintext: String, familyId: String, userId: String) throws -> String {
        let data = Data(plaintext.utf8)
        let combined = try DocumentCryptoService.encrypt(data, familyId: familyId, userId: userId)
        return combined.base64EncodedString()
    }
    
    /// Decrypts base64(AES.GCM.SealedBox.combined) into a UTF-8 string
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
}

// MARK: - Push con testo cifrato (sezioni)

/// Testo delle push che portano il blob `secure` di un documento sigillato
/// (`internal/cifratura-sezioni.md`, secondo giro § 5). Funzioni pure: stanno
/// qui perché questo file è già nei target dell'app e della Notification
/// Service Extension, che non conosce la tabella di `SectionCrypto`: le basta
/// il JSON decifrato.
enum SecurePushTemplate {

    /// JSON `{"campo": "valore"}` decifrato da `secure` → mappa dei soli valori stringa.
    static func values(fromJSON json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.compactMapValues { $0 as? String }
    }

    /// Sostituisce ogni `{campo}` col valore. Nil se un segnaposto non ha un
    /// valore non vuoto: chi chiama tiene allora la versione generica intera.
    static func fill(_ template: String, values: [String: String]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\{([A-Za-z0-9_]+)\\}") else { return nil }
        let ns = template as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1))
            guard let value = values[key], !value.isEmpty else { return nil }
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += value
            cursor = match.range.location + match.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Titolo e testo riempiti. Nil se un modello presente non si riempie:
    /// restano titolo e testo generici arrivati con la push. Un modello assente
    /// lascia la sua parte generica.
    static func render(titleTemplate: String?, bodyTemplate: String?,
                       values: [String: String]) -> (title: String?, body: String?)? {
        var title: String?
        var body: String?
        if let t = titleTemplate, !t.isEmpty {
            guard let filled = fill(t, values: values) else { return nil }
            title = filled
        }
        if let b = bodyTemplate, !b.isEmpty {
            guard let filled = fill(b, values: values) else { return nil }
            body = filled
        }
        return (title, body)
    }
}
