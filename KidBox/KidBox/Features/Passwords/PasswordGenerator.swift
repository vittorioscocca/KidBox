//
//  PasswordGenerator.swift
//  KidBox
//

import Foundation

/// Opzioni per la generazione (lunghezza 8–64, set di caratteri, esclusione ambigui).
struct PasswordGeneratorOptions: Equatable, Sendable {
    /// Lunghezza richiesta (viene clampata a 8…64 in `generate`).
    var length: Int = 18
    var includeUppercase: Bool = true
    var includeLowercase: Bool = true
    var includeNumbers: Bool = true
    var includeSymbols: Bool = true
    /// Esclude `0 O 1 l I` da tutti i pool (lettura più chiara, meno errori di battitura).
    var excludeAmbiguous: Bool = true

    static let `default` = PasswordGeneratorOptions()
}

enum PasswordGenerator {

    private static let lowercaseAll = "abcdefghijklmnopqrstuvwxyz"
    private static let uppercaseAll = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private static let digitsAll = "0123456789"
    /// Simboli ASCII stampabili comuni (nessun spazio).
    private static let symbolsAll = "!@#$%^&*()-_=+[]{}|;:,.<>?/~`"

    private static let ambiguous = CharacterSet(charactersIn: "0O1lI")

    /// Genera con le opzioni di default (compatibile con il comportamento precedente, lunghezza 18).
    static func make(length: Int = 18) -> String {
        var o = PasswordGeneratorOptions.default
        o.length = length
        return generate(options: o)
    }

    /// Costruisce i pool in base alle opzioni; se nessun set è attivo, usa alfanumerico + simboli.
    static func generate(options raw: PasswordGeneratorOptions) -> String {
        var options = raw
        options.length = max(8, min(64, options.length))

        var pools: [String] = []
        if options.includeLowercase {
            pools.append(filtered(lowercaseAll, excludeAmbiguous: options.excludeAmbiguous))
        }
        if options.includeUppercase {
            pools.append(filtered(uppercaseAll, excludeAmbiguous: options.excludeAmbiguous))
        }
        if options.includeNumbers {
            pools.append(filtered(digitsAll, excludeAmbiguous: options.excludeAmbiguous))
        }
        if options.includeSymbols {
            pools.append(symbolsAll)
        }

        if pools.isEmpty {
            var fallback = PasswordGeneratorOptions.default
            fallback.length = options.length
            return generate(options: fallback)
        }

        // Rimuovi pool vuoti (es. tutto filtrato via).
        pools = pools.filter { !$0.isEmpty }
        if pools.isEmpty {
            return make(length: options.length)
        }

        var rng = SystemRandomNumberGenerator()
        var chars: [Character] = []
        chars.reserveCapacity(options.length)

        // Garantisce almeno un carattere da ogni pool abilitato e non vuoto.
        for p in pools {
            guard let ch = randomChar(from: p, using: &rng) else { continue }
            chars.append(ch)
        }

        let union = pools.joined()
        guard !union.isEmpty else { return make(length: options.length) }

        while chars.count < options.length {
            guard let ch = randomChar(from: union, using: &rng) else { break }
            chars.append(ch)
        }

        chars.shuffle(using: &rng)
        return String(chars.prefix(options.length))
    }

    private static func filtered(_ s: String, excludeAmbiguous: Bool) -> String {
        guard excludeAmbiguous else { return s }
        return String(s.unicodeScalars.filter { !ambiguous.contains($0) })
    }

    private static func randomChar(from s: String, using rng: inout SystemRandomNumberGenerator) -> Character? {
        guard !s.isEmpty else { return nil }
        let idx = Int.random(in: 0..<s.count, using: &rng)
        let i = s.index(s.startIndex, offsetBy: idx)
        return s[i]
    }
}
