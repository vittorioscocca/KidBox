//
//  PasswordStrength.swift
//  KidBox
//
//  Euristica pura Swift: entropia stimata + penalità pattern comuni → 5 livelli.
//

import Foundation
import SwiftUI

enum PasswordStrengthLevel: Int, CaseIterable, Comparable, Sendable {
    case veryWeak = 0
    case weak
    case fair
    case strong
    case veryStrong

    static func < (lhs: PasswordStrengthLevel, rhs: PasswordStrengthLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Etichetta breve per UI (italiano, coerente con il resto del modulo Password).
    var label: String {
        switch self {
        case .veryWeak: return "Molto debole"
        case .weak: return "Debole"
        case .fair: return "Discreta"
        case .strong: return "Forte"
        case .veryStrong: return "Molto forte"
        }
    }

    func barColor(colorScheme: ColorScheme) -> Color {
        switch self {
        case .veryWeak:
            return Color(red: 0.85, green: 0.22, blue: 0.22)
        case .weak:
            return Color(red: 0.95, green: 0.45, blue: 0.12)
        case .fair:
            return colorScheme == .dark
                ? Color(red: 0.95, green: 0.82, blue: 0.25)
                : Color(red: 0.75, green: 0.55, blue: 0.05)
        case .strong:
            return KBTheme.green
        case .veryStrong:
            return KBTheme.tint
        }
    }
}

struct PasswordStrengthResult: Equatable, Sendable {
    let level: PasswordStrengthLevel
    /// Riempimento barra 0…1 (derivato dal punteggio interno).
    let fillFraction: Double
    /// Stima bit di entropia (solo informativa).
    let estimatedBits: Double
}

enum PasswordStrength {

    /// Valutazione principale: password vuota → molto debole.
    static func evaluate(_ password: String) -> PasswordStrengthResult {
        let s = password
        if s.isEmpty {
            return PasswordStrengthResult(level: .veryWeak, fillFraction: 0, estimatedBits: 0)
        }

        let L = s.count
        let hasLower = s.contains { $0.isLowercase }
        let hasUpper = s.contains { $0.isUppercase }
        let hasDigit = s.contains { $0.isNumber }
        let hasSymbol = s.contains { !$0.isLetter && !$0.isNumber }

        var pool = 0
        if hasLower { pool += 26 }
        if hasUpper { pool += 26 }
        if hasDigit { pool += 10 }
        if hasSymbol { pool += 33 }

        pool = max(pool, 2)
        let uniformBits = Double(L) * log2(Double(pool))
        let shannonPerChar = shannonEntropyPerCharacter(s)
        let shannonTotal = Double(L) * shannonPerChar

        // Combina modello “uniforme da unione di classi” e Shannon sulla distribuzione reale.
        var estimated = 0.55 * uniformBits + 0.45 * shannonTotal

        var penalty = 1.0
        penalty *= repeatingRunPenalty(s)
        penalty *= sequentialPenalty(s)
        penalty *= keyboardPenalty(s)
        penalty *= commonPasswordPenalty(s)

        if L < 8 { penalty *= 0.45 }
        else if L < 12 { penalty *= 0.82 }

        estimated *= penalty
        estimated = max(0, min(estimated, 160))

        // Soglie su bit stimati (allineate a ~password casuali 12–16 caratteri misti).
        let level: PasswordStrengthLevel
        switch estimated {
        case ..<18: level = .veryWeak
        case ..<32: level = .weak
        case ..<48: level = .fair
        case ..<64: level = .strong
        default: level = .veryStrong
        }

        let fill = min(1, estimated / 80)
        return PasswordStrengthResult(level: level, fillFraction: fill, estimatedBits: estimated)
    }

    // MARK: - Shannon (per carattere, base 2)

    private static func shannonEntropyPerCharacter(_ s: String) -> Double {
        guard !s.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for ch in s {
            counts[ch, default: 0] += 1
        }
        let n = Double(s.count)
        var h = 0.0
        for c in counts.values {
            let p = Double(c) / n
            h -= p * log2(p)
        }
        return h
    }

    // MARK: - Penalità

    private static func repeatingRunPenalty(_ s: String) -> Double {
        var maxRun = 1
        var run = 1
        let arr = Array(s)
        guard arr.count > 1 else { return 1 }
        for i in 1..<arr.count {
            if arr[i] == arr[i - 1] {
                run += 1
                maxRun = max(maxRun, run)
            } else {
                run = 1
            }
        }
        if maxRun >= s.count, s.count >= 4 { return 0.25 }
        if maxRun >= 4 { return 0.65 }
        if maxRun == 3 { return 0.85 }
        return 1
    }

    private static func sequentialPenalty(_ s: String) -> Double {
        let lower = s.lowercased()
        if containsSequence(lower, minLen: 4, ascending: true) { return 0.72 }
        if containsSequence(lower, minLen: 4, ascending: false) { return 0.72 }
        if containsDigitRun(s, len: 4, step: 1) { return 0.75 }
        return 1
    }

    private static func containsSequence(_ s: String, minLen: Int, ascending: Bool) -> Bool {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let idx: [Character: Int] = Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($0.element, $0.offset) })

        let chars = Array(s)
        var run = 1
        for i in 1..<chars.count {
            guard let a = idx[chars[i - 1]], let b = idx[chars[i]] else {
                run = 1
                continue
            }
            let ok = ascending ? (b == a + 1) : (b == a - 1)
            if ok {
                run += 1
                if run >= minLen { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    private static func containsDigitRun(_ s: String, len: Int, step: Int) -> Bool {
        let digits = s.filter(\.isNumber)
        let arr = digits.map { Int(String($0)) ?? 0 }
        guard arr.count >= len else { return false }
        var run = 1
        for i in 1..<arr.count {
            if arr[i] == arr[i - 1] + step {
                run += 1
                if run >= len { return true }
            } else {
                run = 1
            }
        }
        return false
    }

    private static let keyboardRows = [
        "qwertyuiop", "asdfghjkl", "zxcvbnm",
        "1234567890",
    ]

    private static func keyboardPenalty(_ s: String) -> Double {
        let t = s.lowercased()
        for row in keyboardRows {
            if containsKeyboardRun(t, row: row, minLen: 4) { return 0.7 }
        }
        return 1
    }

    private static func containsKeyboardRun(_ s: String, row: String, minLen: Int) -> Bool {
        let chars = Array(s.lowercased())
        let r = Array(row)
        var idx = 0
        while idx < chars.count {
            guard let pos = r.firstIndex(of: chars[idx]) else {
                idx += 1
                continue
            }
            var length = 1
            var ni = idx + 1
            var expected = r.index(after: pos)
            while ni < chars.count, expected < r.endIndex {
                if chars[ni] == r[expected] {
                    length += 1
                    ni += 1
                    r.formIndex(after: &expected)
                } else {
                    break
                }
            }
            if length >= minLen { return true }
            idx += 1
        }
        return false
    }

    private static let commonPasswords: Set<String> = [
        "password", "password1", "123456", "12345678", "123456789", "qwerty", "abc123",
        "letmein", "welcome", "monkey", "dragon", "111111", "sunshine", "princess",
        "football", "iloveyou", "admin", "login", "master", "passw0rd", "654321",
    ]

    private static func commonPasswordPenalty(_ s: String) -> Double {
        let t = s.lowercased()
        if commonPasswords.contains(t) { return 0.15 }
        for w in commonPasswords where w.count >= 4 {
            if t.contains(w) { return 0.45 }
        }
        return 1
    }
}

// MARK: - SwiftUI

struct StrengthMeterView: View {
    let password: String
    @Environment(\.colorScheme) private var colorScheme

    private var result: PasswordStrengthResult {
        PasswordStrength.evaluate(password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(KBTheme.secondaryBackground(colorScheme))
                    Capsule()
                        .fill(result.level.barColor(colorScheme: colorScheme))
                        .frame(width: max(4, geo.size.width * result.fillFraction))
                }
            }
            .frame(height: 6)

            HStack {
                Text(result.level.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result.level.barColor(colorScheme: colorScheme))
                Spacer()
                if !password.isEmpty {
                    Text(String(format: "~%.0f bit", result.estimatedBits))
                        .font(.caption2)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Forza password: \(result.level.label)")
    }
}
