//
//  PwnedChecker.swift
//  KidBox
//
//  HIBP k-anonymity check per password compromise:
//  - La password in chiaro NON lascia mai il device.
//  - Vengono inviati solo i primi 5 caratteri dell'hash SHA-1 (prefix search).
//  - Endpoint: https://api.pwnedpasswords.com/range/{prefix}
//

import Foundation
import CryptoKit
import Network

actor PwnedChecker {
    static let shared = PwnedChecker()

    /// Sentinel quando il check non e disponibile (offline / rete non raggiungibile).
    static let unknown = -1

    private struct PrefixCacheEntry {
        let expiresAt: Date
        let suffixToCount: [String: Int]
    }

    private let session: URLSession
    private let cacheTTL: TimeInterval = 24 * 60 * 60
    private var prefixCache: [String: PrefixCacheEntry] = [:]
    private var lastRequestAt: Date?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "kidbox.passwords.pwned.monitor")
    private var isOnline = true

    init(session: URLSession = .shared) {
        self.session = session
        monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.setOnline(path.status == .satisfied) }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    private func setOnline(_ online: Bool) {
        isOnline = online
    }

    /// Returns breach count for a password.
    /// - `0`: non trovata nei breach pubblici HIBP.
    /// - `>0`: numero di occorrenze.
    /// - `PwnedChecker.unknown`: offline/non raggiungibile (non fallisce l'UX).
    func check(_ password: String) async throws -> Int {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard isOnline else { return Self.unknown }

        let sha1 = Self.sha1Hex(trimmed)
        let prefix = String(sha1.prefix(5))
        let suffix = String(sha1.dropFirst(5))

        do {
            let map = try await fetchMap(prefix: prefix)
            return map[suffix] ?? 0
        } catch {
            return Self.unknown
        }
    }

    private func fetchMap(prefix: String) async throws -> [String: Int] {
        let now = Date()
        if let cached = prefixCache[prefix], cached.expiresAt > now {
            return cached.suffixToCount
        }

        // Throttle globale: max 1 request / 200ms.
        if let last = lastRequestAt {
            let elapsed = now.timeIntervalSince(last)
            let minDelta = 0.2
            if elapsed < minDelta {
                let waitNs = UInt64((minDelta - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: waitNs)
            }
        }
        lastRequestAt = Date()

        guard let url = URL(string: "https://api.pwnedpasswords.com/range/\(prefix)") else { return [:] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("true", forHTTPHeaderField: "Add-Padding")
        req.setValue("KidBox", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let parsed = Self.parseRangeResponse(data)
        prefixCache[prefix] = PrefixCacheEntry(
            expiresAt: Date().addingTimeInterval(cacheTTL),
            suffixToCount: parsed
        )
        return parsed
    }

    private static func parseRangeResponse(_ data: Data) -> [String: Int] {
        guard let body = String(data: data, encoding: .utf8) else { return [:] }
        var map: [String: Int] = [:]
        for rawLine in body.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let suffix = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let count = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if suffix.count == 35 {
                map[suffix] = count
            }
        }
        return map
    }

    private static func sha1Hex(_ s: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}
