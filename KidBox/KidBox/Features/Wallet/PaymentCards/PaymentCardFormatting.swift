//
//  PaymentCardFormatting.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//
//  Circuito, controlli e formattazione delle carte di pagamento. Tutto gira
//  sul dispositivo sul numero già decifrato: il circuito non si salva, si
//  ricava. La stessa logica è in Android (`PaymentCardFormatting.kt`) e nella
//  web app (`paymentCardFormat.js`): se cambia qui, cambia anche lì.
//

import Foundation

enum PaymentCardNetwork: String {
    case visa, mastercard, amex, maestro, discover, diners, jcb, unionpay, other

    /// Riconoscimento dalle prime cifre (IIN). Non è una verifica: serve solo
    /// a mostrare il circuito giusto sulla carta.
    static func detect(_ number: String) -> PaymentCardNetwork {
        let d = number.filter(\.isNumber)
        guard let first = d.first else { return .other }
        func prefix(_ n: Int) -> Int { Int(d.prefix(n)) ?? -1 }
        if first == "4" { return .visa }
        if [34, 37].contains(prefix(2)) { return .amex }
        if (51...55).contains(prefix(2)) || (2221...2720).contains(prefix(4)) { return .mastercard }
        if prefix(4) == 6011 || prefix(2) == 65 || (644...649).contains(prefix(3)) { return .discover }
        if (3528...3589).contains(prefix(4)) { return .jcb }
        if prefix(2) == 36 || prefix(2) == 38 || prefix(2) == 39 || (300...305).contains(prefix(3)) { return .diners }
        if prefix(2) == 62 { return .unionpay }
        if prefix(2) == 50 || (56...69).contains(prefix(2)) { return .maestro }
        return .other
    }

    var displayName: String {
        switch self {
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .amex: return "American Express"
        case .maestro: return "Maestro"
        case .discover: return "Discover"
        case .diners: return "Diners Club"
        case .jcb: return "JCB"
        case .unionpay: return "UnionPay"
        case .other: return NSLocalizedString("Carta", comment: "Payment card network: unknown")
        }
    }
}

enum PaymentCardFormat {

    /// Solo cifre, massimo 19.
    static func digits(_ raw: String) -> String {
        String(raw.filter(\.isNumber).prefix(19))
    }

    /// Numero a gruppi: 4-6-5 per American Express, 4-4-4-4(-3) per gli altri.
    static func grouped(_ number: String) -> String {
        let d = digits(number)
        let sizes = PaymentCardNetwork.detect(d) == .amex ? [4, 6, 5] : [4, 4, 4, 4, 3]
        var out: [String] = []
        var rest = Substring(d)
        for size in sizes where !rest.isEmpty {
            out.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return out.joined(separator: " ")
    }

    /// Numero mascherato: restano visibili solo le ultime 4 cifre.
    static func masked(_ number: String) -> String {
        let d = digits(number)
        guard d.count > 4 else { return d }
        return "•••• •••• •••• " + String(d.suffix(4))
    }

    /// Controllo di Luhn. Un numero che non lo passa quasi certamente ha un
    /// errore di battitura: il form avvisa ma non blocca.
    static func passesLuhn(_ number: String) -> Bool {
        let d = digits(number)
        guard d.count >= 12 else { return false }
        var sum = 0
        for (i, ch) in d.reversed().enumerated() {
            var n = ch.wholeNumberValue ?? 0
            if i % 2 == 1 {
                n *= 2
                if n > 9 { n -= 9 }
            }
            sum += n
        }
        return sum % 10 == 0
    }

    // MARK: - Scadenza «MM/AA»

    /// Normalizza quello che si digita in `MM/AA`, inserendo la barra da sé.
    static func expiryInput(_ raw: String) -> String {
        let d = String(raw.filter(\.isNumber).prefix(4))
        guard d.count > 2 else { return d }
        return String(d.prefix(2)) + "/" + String(d.dropFirst(2))
    }

    /// `true` se la scadenza è completa e il mese è 01–12.
    static func isValidExpiry(_ expiry: String) -> Bool {
        guard let (m, _) = monthYear(expiry) else { return false }
        return (1...12).contains(m)
    }

    /// Scaduta = finito il mese indicato.
    static func isExpired(_ expiry: String, now: Date = .now) -> Bool {
        guard let (m, y) = monthYear(expiry), (1...12).contains(m) else { return false }
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: now)
        let curY = (comps.year ?? 2000) % 100
        let curM = comps.month ?? 1
        return y < curY || (y == curY && m < curM)
    }

    private static func monthYear(_ expiry: String) -> (Int, Int)? {
        let d = expiry.filter(\.isNumber)
        guard d.count == 4, let m = Int(d.prefix(2)), let y = Int(d.suffix(2)) else { return nil }
        return (m, y)
    }

    // MARK: - IBAN

    /// Maiuscolo, senza spazi, massimo 34 caratteri.
    static func ibanCompact(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(34))
    }

    /// IBAN a gruppi di 4, come sugli estratti conto.
    static func ibanGrouped(_ raw: String) -> String {
        let c = ibanCompact(raw)
        return stride(from: 0, to: c.count, by: 4).map { i -> String in
            let start = c.index(c.startIndex, offsetBy: i)
            let end = c.index(start, offsetBy: min(4, c.count - i))
            return String(c[start..<end])
        }.joined(separator: " ")
    }

    /// Controllo ISO 13616 (mod 97). Anche qui il form avvisa, non blocca.
    static func isValidIBAN(_ raw: String) -> Bool {
        let c = ibanCompact(raw)
        guard c.count >= 15,
              c.prefix(2).allSatisfy(\.isLetter),
              c.dropFirst(2).prefix(2).allSatisfy(\.isNumber) else { return false }
        let rearranged = String(c.dropFirst(4)) + String(c.prefix(4))
        var remainder = 0
        for ch in rearranged {
            let value: Int
            if let n = ch.wholeNumberValue {
                value = n
            } else if let ascii = ch.asciiValue, ch.isLetter {
                value = Int(ascii) - 55 // A=10 … Z=35
            } else {
                return false
            }
            for digit in String(value) {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }
}

/// Colori proposti per la carta: una palette fissa, uguale su iOS, Android e
/// web, invece di un selettore libero.
enum PaymentCardPalette {
    static let defaultHex = "#1C1C1E"
    static let all: [String] = [
        "#1C1C1E", // nero
        "#0A3D91", // blu
        "#1B7F5A", // verde
        "#8E1B3A", // bordeaux
        "#B8860B", // oro
        "#6E6E73", // argento
        "#5856D6", // viola
        "#D2462E", // rosso
    ]
}
