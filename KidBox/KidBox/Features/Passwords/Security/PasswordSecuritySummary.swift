//
//  PasswordSecuritySummary.swift
//  KidBox
//
//  Riepilogo locale (HIBP in cache, duplicati, forza) per una singola voce — allineato a PasswordsSecurityView.
//

import Foundation

enum PasswordHIBPStatus: Equatable {
    /// `pwnedCount == nil`: scan HIBP non ancora riuscito su questa voce.
    case notChecked
    /// Controllata e 0 occorrenze nei dataset noti.
    case safe
    /// Controllata e > 0 occorrenze (HIBP k-anonymity).
    case compromised(count: Int)
}

struct PasswordSecuritySummary: Equatable {
    let hibp: PasswordHIBPStatus
    let hibpCheckedAt: Date?
    let duplicateOtherCount: Int
    let strength: PasswordStrengthResult

    var isWeak: Bool {
        strength.level <= .weak
    }

    /// True se almeno una condizione “da attenzione” come nel report Sicurezza.
    var hasAttentionIssue: Bool {
        switch hibp {
        case .compromised: return true
        case .notChecked, .safe: break
        }
        if duplicateOtherCount > 0 { return true }
        if isWeak { return true }
        return false
    }

    /// - Parameter decryptedPassword: se già nota, evita un secondo decrypt solo per la forza.
    static func make(
        entry: PasswordEntry,
        familyEntries: [PasswordEntry],
        currentUid: String?,
        decryptedPassword: String? = nil
    ) -> PasswordSecuritySummary {
        let visible = familyEntries.filter { $0.deletedAt == nil && $0.isVisible(to: currentUid) }
        let duplicateOtherCount = DuplicateDetector(entries: visible, currentUid: currentUid)
            .duplicates(of: entry)
            .count

        let plainForStrength = decryptedPassword ?? (try? entry.decryptPassword()) ?? ""
        let strength = PasswordStrength.evaluate(plainForStrength)

        let hibp: PasswordHIBPStatus
        if let c = entry.pwnedCount {
            hibp = c > 0 ? .compromised(count: c) : .safe
        } else {
            hibp = .notChecked
        }

        return PasswordSecuritySummary(
            hibp: hibp,
            hibpCheckedAt: entry.pwnedCheckedAt,
            duplicateOtherCount: duplicateOtherCount,
            strength: strength
        )
    }
}
