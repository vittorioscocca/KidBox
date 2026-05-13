//
//  DuplicateDetector.swift
//  KidBox
//
//  Duplicate detection locale:
//  - usa solo dati in memoria
//  - nessun hash persiste su SwiftData / Firestore
//

import Foundation
import FirebaseAuth
import CryptoKit

struct DuplicateDetector {
    let entries: [PasswordEntry]
    let currentUid: String?

    private func visibleEntries() -> [PasswordEntry] {
        entries.filter { $0.deletedAt == nil && $0.isVisible(to: currentUid) }
    }

    private func clustersByHash() -> [String: [PasswordEntry]] {
        var clusters: [String: [PasswordEntry]] = [:]
        for entry in visibleEntries() {
            guard let plain = try? entry.decryptPassword(), !plain.isEmpty else { continue }
            let h = Self.sha256Hex(plain)
            clusters[h, default: []].append(entry)
        }
        return clusters.filter { $0.value.count > 1 }
    }

    func duplicates(of entry: PasswordEntry) -> [PasswordEntry] {
        guard let plain = try? entry.decryptPassword(), !plain.isEmpty else { return [] }
        let target = Self.sha256Hex(plain)
        return (clustersByHash()[target] ?? []).filter { $0.id != entry.id }
    }

    func allDuplicateClusters() -> [[PasswordEntry]] {
        clustersByHash()
            .values
            .map { $0.sorted { $0.updatedAt > $1.updatedAt } }
            .sorted { ($0.first?.updatedAt ?? .distantPast) > ($1.first?.updatedAt ?? .distantPast) }
    }

    private static func sha256Hex(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension DuplicateDetector {
    static func forCurrentUser(entries: [PasswordEntry]) -> DuplicateDetector {
        DuplicateDetector(entries: entries, currentUid: Auth.auth().currentUser?.uid)
    }
}
