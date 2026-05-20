//
//  KBHealthAgeFormatting.swift
//  KidBox
//

import Foundation

enum KBHealthAgeFormatting {
    static func ageDescription(from birthDate: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: birthDate, to: Date())
        let years = comps.year ?? 0
        let months = comps.month ?? 0
        if years > 0 { return "\(years) ann\(years == 1 ? "o" : "i")" }
        if months > 0 { return "\(months) mes\(months == 1 ? "e" : "i")" }
        return "Neonato"
    }
}
