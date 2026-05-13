//
//  OTPService.swift
//  KidBox
//
//  Gestione payload OTP (secret Base32 + metadata) e generazione TOTP via `TOTPCodeGenerator` (stesso stack di AutoFill).
//  Adattato a KidBox: il segreto e la config vivono in `PasswordEntry.otpConfigCipher`
//  cifrati con **`PasswordCypher`** (stessa chiave/visibilità della voce — nessun Keychain OTP separato).
//

import Foundation

/// JSON serializzato poi cifrato in `otpConfigCipher` (AES-GCM via `PasswordCypher`).
struct PasswordOtpPayload: Codable, Equatable, Sendable {
    var secret: String
    var digits: Int = 6
    var period: Int = 30
    /// v1: solo `"SHA1"` (Google Authenticator / RFC 6238 default).
    var algorithm: String = "SHA1"
}

/// Servizio OTP per il modulo Passwords (config in Keychain + delega TOTP a `TOTPCodeGenerator`).
enum OTPService {

    // MARK: - Config JSON (plaintext prima di `PasswordCypher.encrypt`)

    static func parsePayload(from json: String) -> PasswordOtpPayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PasswordOtpPayload.self, from: data)
    }

    static func encodePayload(_ payload: PasswordOtpPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Leggere la config dalla voce (decrypt con stessa policy della entry)

    /// Legge dal Keychain (`elementID` = id password) e restituisce il payload, o `nil`.
    static func payload(from entry: PasswordEntry) -> PasswordOtpPayload? {
        guard let config = OtpKeychainStore.retrieveOtpConfig(elementID: entry.id) else {
            return nil
        }
        return payload(fromConfig: config)
    }

    static func payload(elementID: String) -> PasswordOtpPayload? {
        guard let config = OtpKeychainStore.retrieveOtpConfig(elementID: elementID) else {
            return nil
        }
        return payload(fromConfig: config)
    }

    static func payload(fromConfig config: [String: Any]) -> PasswordOtpPayload? {
        guard let secret = (config["secret"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            return nil
        }
        let period = config["period"] as? Int ?? 30
        let digits = config["digits"] as? Int ?? 6
        let algorithm = (config["algorithm"] as? String ?? "SHA1").uppercased()
        return PasswordOtpPayload(secret: secret, digits: digits, period: period, algorithm: algorithm)
    }

    static func extractOtpConfig(from raw: String) -> [String: Any]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "otpauth" else {
            return nil
        }
        let items = components.queryItems ?? []
        guard let secret = items.first(where: { $0.name.lowercased() == "secret" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !secret.isEmpty else {
            return nil
        }
        let period = items.first(where: { $0.name.lowercased() == "period" })?.value.flatMap(Int.init) ?? 30
        let digits = items.first(where: { $0.name.lowercased() == "digits" })?.value.flatMap(Int.init) ?? 6
        let algorithm = items.first(where: { $0.name.lowercased() == "algorithm" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? "SHA1"
        return [
            "secret": secret,
            "period": period,
            "digits": digits,
            "algorithm": algorithm
        ]
    }

    static func isValidOtpSecret(_ raw: String) -> Bool {
        TOTPCodeGenerator.isValidSecretBase32(raw)
    }

    // MARK: - TOTP (stesso algoritmo dell’estensione AutoFill)

    /// Codice TOTP corrente per la voce, o `nil` se manca config OTP o non è valida.
    static func currentTotpCode(for entry: PasswordEntry, at date: Date = .init()) -> String? {
        guard let p = payload(from: entry) else { return nil }
        return currentTotpCode(payload: p, at: date)
    }

    static func currentTotpCode(payload: PasswordOtpPayload, at date: Date = .init()) -> String? {
        TOTPCodeGenerator.currentCode(
            secretBase32: payload.secret,
            digits: payload.digits,
            period: payload.period,
            algorithm: payload.algorithm,
            referenceDate: date,
        )
    }

}
