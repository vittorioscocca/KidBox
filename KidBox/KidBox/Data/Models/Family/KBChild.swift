//
//  KBChild.swift.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import SwiftData

/// Represents a child within a family.
///
/// A child is the center of KidBox: most entities (routines, events, todos, schedules)
/// reference a specific `childId`.
///
/// - Important: KidBox is child-centric: data is about the child, not about the parents.
@Model
final class KBChild {
    @Attribute(.unique) var id: String
    
    // ✅ optional: migrazione "light" più tollerante
    var familyId: String?
    
    var name: String
    var birthDate: Date?
    
    // ── Dati fisici (opzionali) ──
    var weightKg: Double?
    var heightCm: Double?
    
    var createdBy: String
    var createdAt: Date
    
    var updatedBy: String?
    var updatedAt: Date?
    
    @Relationship var family: KBFamily?
    
    init(
        id: String,
        familyId: String?,
        name: String,
        birthDate: Date?,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        createdBy: String,
        createdAt: Date,
        updatedBy: String?,
        updatedAt: Date?
    ) {
        self.id        = id
        self.familyId  = familyId
        self.name      = name
        self.birthDate = birthDate
        self.weightKg  = weightKg
        self.heightCm  = heightCm
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
    }
}

extension KBChild {
    
    /// Età in anni interi, calcolata da birthDate.
    var ageYears: Int? {
        guard let bd = birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: bd, to: Date()).year
    }
    
    /// Stringa descrittiva dell'età (es. "2 anni", "8 mesi").
    var ageDescription: String {
        guard let bd = birthDate else { return "" }
        let comps = Calendar.current.dateComponents([.year, .month], from: bd, to: Date())
        let years  = comps.year  ?? 0
        let months = comps.month ?? 0
        if years > 0 { return "\(years) ann\(years == 1 ? "o" : "i")" }
        if months > 0 { return "\(months) mes\(months == 1 ? "e" : "i")" }
        return "Neonato"
    }
    
    /// Avatar emoji in base all'età.
    var avatarEmoji: String {
        guard let years = ageYears else { return "👶" }
        switch years {
        case 0:      return "👶"
        case 1...3:  return "🧒"
        case 4...9:  return "👦"
        default:     return "🧑"
        }
    }
}
