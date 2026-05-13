//
//  TOTPCodeGenerator.swift
//  KidBox
//
//  RFC 6238 TOTP (HOTP-SHA1) per AutoFill / UI; il segreto arriva da `PasswordOtpPayload` / snapshot.
//

import CryptoKit
import Foundation

enum TOTPCodeGenerator {

    /// Codice TOTP (padding a `digits` caratteri) o `nil` se config non valida.
    /// - Parameter referenceDate: default `Date()`; impostabile nei test per counter deterministici.
    static func currentCode(
        secretBase32: String,
        digits: Int = 6,
        period: Int = 30,
        algorithm: String = "SHA1",
        referenceDate: Date = Date(),
    ) -> String? {
        guard let secretData = decodeBase32(secretBase32) else { return nil }
        let counter = UInt64(referenceDate.timeIntervalSince1970) / UInt64(max(1, period))
        guard let hotp = hotp(
            secret: secretData,
            counter: counter,
            digits: max(4, min(10, digits)),
            algorithm: algorithm
        ) else { return nil }
        return hotp
    }

    /// True se `raw` decodifica in Base32 (RFC 4648) senza caratteri invalidi.
    static func isValidSecretBase32(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return decodeBase32(trimmed) != nil
    }

    // MARK: - HOTP-SHA1

    private static func hotp(secret: Data, counter: UInt64, digits: Int, algorithm: String) -> String? {
        let ctrData = hotpCounterData(counter)
        let key = SymmetricKey(data: secret)
        let hash: Data
        switch algorithm.uppercased() {
        case "SHA1":
            hash = Data(HMAC<Insecure.SHA1>.authenticationCode(for: ctrData, using: key))
        case "SHA256":
            hash = Data(HMAC<SHA256>.authenticationCode(for: ctrData, using: key))
        case "SHA512":
            hash = Data(HMAC<SHA512>.authenticationCode(for: ctrData, using: key))
        default:
            return nil
        }
        let offset = Int(hash[hash.count - 1] & 0x0f)
        guard offset + 3 < hash.count else { return nil }
        let binary =
            ((UInt32(hash[offset]) & 0x7f) << 24)
            | (UInt32(hash[offset + 1]) << 16)
            | (UInt32(hash[offset + 2]) << 8)
            | UInt32(hash[offset + 3])
        let otp = Int(binary) % Int(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }

    private static func hotpCounterData(_ counter: UInt64) -> Data {
        var d = Data(repeating: 0, count: 8)
        for i in 0..<8 {
            d[i] = UInt8((counter >> (56 - i * 8)) & 0xff)
        }
        return d
    }

    // MARK: - Base32 (RFC 4648)

    private static let base32Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    private static func decodeBase32(_ input: String) -> Data? {
        let cleaned = input.uppercased().filter { $0 != " " && $0 != "=" }
        guard !cleaned.isEmpty else { return nil }
        var bits = 0
        var value = 0
        var out = [UInt8]()
        for ch in cleaned {
            guard let r = base32Chars.firstIndex(of: ch) else { return nil }
            let idx = base32Chars.distance(from: base32Chars.startIndex, to: r)
            value = (value << 5) | idx
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return Data(out)
    }
}
