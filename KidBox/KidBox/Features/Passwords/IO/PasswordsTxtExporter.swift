import Foundation
import CryptoKit
import CommonCrypto

struct PasswordsTxtExporter {
    enum ExportError: Error {
        case missingCurrentUser
        case keyDerivationFailed
        case encryptionFailed
    }

    let familyId: String
    let currentUid: String?
    let passphrase: String?

    func export(entries: [PasswordEntry], groups: [PasswordGroup], familyName: String?) async throws -> URL {
        guard let currentUid, !currentUid.isEmpty else { throw ExportError.missingCurrentUser }

        let groupById: [String: String] = Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            guard group.isVisible(to: currentUid), let name = try? group.decryptName() else { return nil }
            return (group.id, name)
        })

        var lines: [String] = ["# KidBox Password Export v1"]
        for entry in entries where entry.isVisible(to: currentUid) {
            let visibility = PasswordEntry.normalizedPasswordVisibility(entry.visibility)
            if visibility == KBVisibilityScope.onlyCreator, entry.createdBy != currentUid { continue }

            guard
                let title = try? entry.decryptTitle(),
                let password = try? entry.decryptPassword()
            else { continue }

            lines.append("---")
            lines.append("Title: \(escape(title))")
            lines.append("Username: \(escape((try? entry.decryptUsername()) ?? ""))")
            lines.append("Password: \(escape(password))")
            lines.append("WebSite: \(escape((try? entry.decryptWebsite()) ?? ""))")
            lines.append("Group: \(escape(groupById[entry.groupId ?? ""] ?? ""))")
            lines.append("Visibility: \(visibility)")
            lines.append("Note: \(escape((try? entry.decryptNotes()) ?? ""))")
            lines.append("CreatedBy: \(entry.createdBy)")
            lines.append("Favorite: \(entry.isFavorite ? "true" : "false")")
            lines.append("---")
        }

        var content = lines.joined(separator: "\n")
        if let passphrase, !passphrase.isEmpty {
            let encrypted = try encrypt(content.utf8Data, passphrase: passphrase)
            content = "# KidBox Password Export v1 (encrypted)\n\(encrypted.base64EncodedString())"
        }

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("KidBox-Passwords-\(Self.fileDateFormatter.string(from: .now)).txt")
        let bom = Data([0xEF, 0xBB, 0xBF])
        var data = Data()
        data.append(bom)
        data.append(content.utf8Data)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private func encrypt(_ plaintext: Data, passphrase: String) throws -> Data {
        let salt = try random(count: 16)
        let keyData = try deriveKey(passphrase: passphrase, salt: salt)
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw ExportError.encryptionFailed }
        return salt + combined
    }

    private func deriveKey(passphrase: String, salt: Data) throws -> Data {
        // Argon2id non disponibile in runtime iOS standard del progetto: fallback PBKDF2-SHA256.
        var out = Data(repeating: 0, count: 32)
        let outCount = out.count
        let status = out.withUnsafeMutableBytes { outBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase, passphrase.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress!, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100_000,
                    outBytes.bindMemory(to: UInt8.self).baseAddress!, outCount
                )
            }
        }
        guard status == kCCSuccess else { throw ExportError.keyDerivationFailed }
        return out
    }

    private func random(count: Int) throws -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        guard result == errSecSuccess else { throw ExportError.encryptionFailed }
        return data
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
    }

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
