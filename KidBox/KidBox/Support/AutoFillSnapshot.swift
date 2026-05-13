//
//  AutoFillSnapshot.swift
//  KidBox
//
//  Snapshot locale cifrato (AES-GCM) nel container App Group per l’estensione AutoFill.
//

import CryptoKit
import Foundation

// MARK: - Paths

enum KidBoxAutoFillPaths {
    static let appGroupId = "group.it.vittorioscocca.kidbox"
    static let subfolder = "KidBoxAutoFill"
    static let snapshotFileName = "snapshot.kbpw-enc"

    static func appGroupContainer() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
    }

    /// Crea `…/KidBoxAutoFill/` se mancante.
    static func autofillDirectoryURL() -> URL? {
        guard let base = appGroupContainer() else { return nil }
        let dir = base.appendingPathComponent(subfolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func snapshotFileURL() -> URL? {
        autofillDirectoryURL()?.appendingPathComponent(snapshotFileName, isDirectory: false)
    }

    static func faviconsDirectoryURL() -> URL? {
        guard let d = autofillDirectoryURL() else { return nil }
        let fav = d.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: fav, withIntermediateDirectories: true)
        return fav
    }

    static func faviconFileURL(forHost host: String) -> URL? {
        let safe = host
            .lowercased()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        guard !safe.isEmpty else { return nil }
        return faviconsDirectoryURL()?.appendingPathComponent("\(safe).png", isDirectory: false)
    }
}

// MARK: - OTP payload (stesso schema JSON di `PasswordOtpPayload` nel modulo principale)

struct AutoFillOtpPayload: Codable, Equatable, Sendable {
    var secret: String
    var digits: Int = 6
    var period: Int = 30
    var algorithm: String = "SHA1"
}

// MARK: - Snapshot model

struct AutoFillSnapshot: Codable, Equatable, Sendable {
    var version: Int
    var updatedAt: Date
    var items: [Item]

    struct Item: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var username: String
        var password: String
        /// Host normalizzato (no scheme, no path), minuscolo.
        var website: String?
        /// `"family"` | `"members"` | `"private"` (only creator) come in SwiftData/Firestore.
        var visibility: String
        var owner: String
        var otp: AutoFillOtpPayload?
    }

    static func makeEmpty() -> AutoFillSnapshot {
        AutoFillSnapshot(version: 1, updatedAt: .now, items: [])
    }
}

// MARK: - Crypto envelope (combined AES-GCM)

enum AutoFillSnapshotCryptoError: Error {
    case missingCombinedCiphertext
    case decryptFailed
}

extension AutoFillSnapshot {

    func encryptedBlob(using key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plain = try encoder.encode(self)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let combined = sealed.combined else { throw AutoFillSnapshotCryptoError.missingCombinedCiphertext }
        return combined
    }

    static func decrypt(fromCombined data: Data, using key: SymmetricKey) throws -> AutoFillSnapshot {
        let box = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(box, using: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AutoFillSnapshot.self, from: plain)
    }
}

/// Preferenze AutoFill condivise tra app ed estensione (App Group `UserDefaults`).
enum KidBoxAutoFillPreferences {
    private static let suite = UserDefaults(suiteName: KidBoxAutoFillPaths.appGroupId)
    private static let requireBioKey = "kidbox.autofill.requireBiometricForQuickType"

    /// Default `true`: richiede Face ID anche per riempimento da QuickType senza aprire la lista.
    static var requireBiometricForQuickType: Bool {
        get {
            if suite?.object(forKey: requireBioKey) == nil { return true }
            return suite?.bool(forKey: requireBioKey) ?? true
        }
        set { suite?.set(newValue, forKey: requireBioKey) }
    }
}

enum AutoFillSnapshotFileStore {

    static func readEncryptedFile() -> Data? {
        guard let url = KidBoxAutoFillPaths.snapshotFileURL(),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return try? Data(contentsOf: url)
    }

    static func loadDecrypted(using key: SymmetricKey) throws -> AutoFillSnapshot {
        guard let data = readEncryptedFile() else { return .makeEmpty() }
        return try AutoFillSnapshot.decrypt(fromCombined: data, using: key)
    }

    /// Scrive il blob cifrato (app principale).
    static func writeEncrypted(_ blob: Data) throws {
        guard let url = KidBoxAutoFillPaths.snapshotFileURL() else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try blob.write(to: url, options: .atomic)
    }

    static func deleteSnapshotFile() {
        guard let url = KidBoxAutoFillPaths.snapshotFileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Host parsing / matching (no naive substring match)

enum AutoFillWebsiteHost {

    /// Estrae host minuscolo senza scheme/port/path; rimuove `www.`.
    static func normalizedHost(from raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if !s.contains("://"), !s.contains("/"), !s.contains("?") {
            var h = s.lowercased()
            if h.hasPrefix("www.") { h = String(h.dropFirst(4)) }
            if let colon = h.firstIndex(of: ":") { h = String(h[..<colon]) }
            return h.isEmpty ? nil : h
        }
        if !s.contains("://") { s = "https://\(s)" }
        guard let url = URL(string: s), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// True se l’host della voce corrisponde all’host richiesto (uguaglianza o sottodominio sicuro).
    static func host(_ entryHost: String?, matchesRequest requestHost: String?) -> Bool {
        guard let e = entryHost, let r = requestHost, !e.isEmpty, !r.isEmpty else { return false }
        if e == r { return true }
        if e.hasSuffix("." + r) { return true }
        if r.hasSuffix("." + e) { return true }
        return false
    }
}
