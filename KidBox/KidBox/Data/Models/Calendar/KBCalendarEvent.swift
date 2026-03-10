//
//  KBCalendarEvent.swift
//  KidBox
//
//  Created by vscocca on 10/03/26.
//

import Foundation
import SwiftData

// MARK: - KBCalendarEvent (SwiftData model)

@Model
final class KBCalendarEvent {
    
    // ── Identity ──────────────────────────────────────────────────────────────
    @Attribute(.unique) var id: String
    var familyId: String
    /// Optional – nil means the event belongs to the whole family (not a single child).
    var childId: String?
    
    // ── Content ───────────────────────────────────────────────────────────────
    var title: String
    var notes: String?
    var location: String?
    
    // ── Timing ────────────────────────────────────────────────────────────────
    var startDate: Date
    var endDate: Date
    /// When true startDate/endDate cover full calendar days (no hour/minute).
    var isAllDay: Bool
    
    // ── Categorisation ────────────────────────────────────────────────────────
    /// Stored as raw string for forward compatibility (e.g. "medical", "school", "sport", "other").
    var categoryRaw: String
    
    // ── Recurrence (simple) ───────────────────────────────────────────────────
    /// "none" | "daily" | "weekly" | "monthly" | "yearly"
    var recurrenceRaw: String
    
    // ── Reminder ──────────────────────────────────────────────────────────────
    /// Minutes before startDate; nil = no reminder.
    var reminderMinutes: Int?
    
    // ── Sync bookkeeping ──────────────────────────────────────────────────────
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date
    var updatedBy: String
    var createdBy: String
    var syncStateRaw: Int         // maps to KBSyncState
    var lastSyncError: String?
    
    // MARK: Computed helpers
    
    var category: KBEventCategory {
        get { KBEventCategory(rawValue: categoryRaw) ?? .family }
        set { categoryRaw = newValue.rawValue }
    }
    
    var recurrence: KBEventRecurrence {
        get { KBEventRecurrence(rawValue: recurrenceRaw) ?? .none }
        set { recurrenceRaw = newValue.rawValue }
    }
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    // MARK: Init
    
    init(
        id:               String       = UUID().uuidString,
        familyId:         String,
        childId:          String?      = nil,
        title:            String,
        notes:            String?      = nil,
        location:         String?      = nil,
        startDate:        Date,
        endDate:          Date,
        isAllDay:         Bool         = false,
        category:         KBEventCategory  = .family,
        recurrence:       KBEventRecurrence = .none,
        reminderMinutes:  Int?         = nil,
        isDeleted:        Bool         = false,
        createdAt:        Date         = Date(),
        updatedAt:        Date         = Date(),
        updatedBy:        String       = "",
        createdBy:        String       = ""
    ) {
        self.id              = id
        self.familyId        = familyId
        self.childId         = childId
        self.title           = title
        self.notes           = notes
        self.location        = location
        self.startDate       = startDate
        self.endDate         = endDate
        self.isAllDay        = isAllDay
        self.categoryRaw     = category.rawValue
        self.recurrenceRaw   = recurrence.rawValue
        self.reminderMinutes = reminderMinutes
        self.isDeleted       = isDeleted
        self.createdAt       = createdAt
        self.updatedAt       = updatedAt
        self.updatedBy       = updatedBy
        self.createdBy       = createdBy
        self.syncStateRaw    = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError   = nil
    }
}

// MARK: - Supporting enums

enum KBEventCategory: String, CaseIterable, Identifiable {
    case children      = "children"       // 👶 Bambini
    case school        = "school"         // 🏫 Scuola
    case health        = "health"         // 🏥 Salute
    case family        = "family"         // 👨‍👩‍👧 Famiglia
    case admin         = "admin"          // 🧾 Amministrazione
    case leisure       = "leisure"        // 🎉 Tempo libero
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .children: return "Bambini"
        case .school:   return "Scuola"
        case .health:   return "Salute"
        case .family:   return "Famiglia"
        case .admin:    return "Amministrazione"
        case .leisure:  return "Tempo libero"
        }
    }
    
    var systemImage: String {
        switch self {
        case .children: return "figure.and.child.holdinghands"
        case .school:   return "backpack"
        case .health:   return "cross.case"
        case .family:   return "house.fill"
        case .admin:    return "doc.text"
        case .leisure:  return "party.popper"
        }
    }
    
    var color: String {   // hex used in UI
        switch self {
        case .children: return "F1C40F"   // giallo
        case .school:   return "3498DB"   // blu
        case .health:   return "E74C3C"   // rosso
        case .family:   return "2ECC71"   // verde
        case .admin:    return "7F8C8D"   // grigio
        case .leisure:  return "9B59B6"   // viola
        }
    }
}

enum KBEventRecurrence: String, CaseIterable, Identifiable {
    case none    = "none"
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"
    case yearly  = "yearly"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .none:    return "Nessuna"
        case .daily:   return "Giornaliera"
        case .weekly:  return "Settimanale"
        case .monthly: return "Mensile"
        case .yearly:  return "Annuale"
        }
    }
}

// MARK: - DTO (Firestore transfer object)

struct KBCalendarEventDTO {
    var id:              String
    var familyId:        String
    var childId:         String?
    var title:           String
    var notes:           String?
    var location:        String?
    var startDate:       Date
    var endDate:         Date
    var isAllDay:        Bool
    var categoryRaw:     String
    var recurrenceRaw:   String
    var reminderMinutes: Int?
    var isDeleted:       Bool
    var createdAt:       Date
    var updatedAt:       Date
    var updatedBy:       String
    var createdBy:       String
}
