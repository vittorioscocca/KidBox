//
//  PasswordsSecurityScanner.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseAuth

@MainActor
final class PasswordsSecurityScanner {
    private let modelContext: ModelContext
    private let familyId: String
    private let checker: PwnedChecker

    init(modelContext: ModelContext, familyId: String, checker: PwnedChecker = .shared) {
        self.modelContext = modelContext
        self.familyId = familyId
        self.checker = checker
    }

    /// Esegue lo scan completo su tutte le entry visibili.
    /// - Returns: numero di entry newly-compromised trovate in questo run.
    func runFullSecurityScan() async -> Int {
        let uid = Auth.auth().currentUser?.uid
        let descriptor = FetchDescriptor<PasswordEntry>(
            predicate: #Predicate<PasswordEntry> { $0.familyId == familyId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
        guard let all = try? modelContext.fetch(descriptor) else { return 0 }
        let visible = all.filter { $0.isVisible(to: uid) }

        var newlyCompromised = 0
        var touched = 0

        for entry in visible {
            // onlyCreator: solo il creatore esegue il check.
            let vis = PasswordEntry.normalizedPasswordVisibility(entry.visibility)
            if vis == KBVisibilityScope.onlyCreator, entry.createdBy != uid {
                continue
            }

            guard let plain = try? entry.decryptPassword(), !plain.isEmpty else { continue }
            let prev = entry.pwnedCount ?? 0

            let result = (try? await checker.check(plain)) ?? PwnedChecker.unknown
            if result == PwnedChecker.unknown {
                continue
            }

            entry.pwnedCount = result
            entry.pwnedCheckedAt = .now
            entry.updatedAt = .now
            entry.syncState = .pendingUpsert
            PasswordsRepository.enqueuePasswordEntryUpsert(
                entryId: entry.id,
                familyId: familyId,
                modelContext: modelContext
            )

            if prev <= 0, result > 0 {
                newlyCompromised += 1
            }
            touched += 1
        }

        if touched > 0 {
            try? modelContext.save()
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            UserDefaults.standard.set(Date(), forKey: Self.lastScanKey(familyId: familyId))
            UserDefaults.standard.set(true, forKey: Self.moduleOpenedKey(familyId: familyId))
        }

        if newlyCompromised > 0 {
            await NotificationManager.shared.schedulePasswordSecuritySummaryNotification(
                familyId: familyId,
                newlyCompromised: newlyCompromised
            )
        }
        return newlyCompromised
    }

    static func markModuleOpened(familyId: String) {
        UserDefaults.standard.set(true, forKey: moduleOpenedKey(familyId: familyId))
    }

    static func shouldRunWeeklyAutoScan(familyId: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: moduleOpenedKey(familyId: familyId)) else { return false }
        guard let last = UserDefaults.standard.object(forKey: lastScanKey(familyId: familyId)) as? Date else {
            return true
        }
        return Date().timeIntervalSince(last) >= 7 * 24 * 60 * 60
    }

    private static func moduleOpenedKey(familyId: String) -> String {
        "kb.password.security.opened.\(familyId)"
    }

    private static func lastScanKey(familyId: String) -> String {
        "kb.password.security.lastScan.\(familyId)"
    }
}
