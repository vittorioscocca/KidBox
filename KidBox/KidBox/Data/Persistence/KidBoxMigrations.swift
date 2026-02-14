//
//  KidBoxMigrations.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import Foundation
import SwiftData
import OSLog

/// Migration actor for KidBox SwiftData models.
///
/// `KidBoxMigrationActor` runs schema backfills and data fixes that must be executed
/// on the SwiftData `ModelActor` to ensure thread safety and consistent persistence.
///
/// Notes:
/// - Keep migrations idempotent (safe to run multiple times).
/// - Avoid inventing identifiers when data is ambiguous.
/// - Prefer relationship-derived values when possible.
@ModelActor
actor KidBoxMigrationActor {
    
    // MARK: - Entry point
    
    /// Runs all available migrations/backfills.
    ///
    /// - Important: Must remain idempotent.
    func runAll() async throws {
        await MainActor.run { KBLog.persistence.kbInfo("Migrations runAll started") }
        defer { Task { await MainActor.run { KBLog.persistence.kbInfo("Migrations runAll finished") } } }
        
        try await backfillChildFamilyIdIfNeeded()
    }
    
    // MARK: - Backfills
    
    /// Backfill: sets `familyId` on `KBChild` rows coming from an older schema.
    ///
    /// Rules (unchanged):
    /// 1) If `child.family?.id` exists → use it.
    /// 2) Else, if there is exactly one local family → use that family id.
    /// 3) Else leave `familyId` empty (do not guess).
    ///
    /// This migration is idempotent: only children with `familyId == ""` are updated.
    func backfillChildFamilyIdIfNeeded() async throws {
        await MainActor.run { KBLog.persistence.kbDebug("Backfill child.familyId started") }
        
        // Fetch all families (for potential single-family fallback).
        let families = try modelContext.fetch(FetchDescriptor<KBFamily>())
        let singleFamilyId: String? = (families.count == 1) ? families.first?.id : nil
        
        let familiesCount = families.count
        await MainActor.run { [familiesCount, singleFamilyId] in
            let idText = singleFamilyId ?? "nil"
            KBLog.persistence.kbDebug("Families count=\(familiesCount) singleFamilyId=\(idText)")
        }
        
        // Find children with empty familyId.
        let desc = FetchDescriptor<KBChild>(
            predicate: #Predicate { $0.familyId == "" }
        )
        let orphans = try modelContext.fetch(desc)
        let orphanCount = orphans.count
        
        guard orphanCount > 0 else {
            await MainActor.run {
                KBLog.persistence.kbDebug("No orphan children found (familyId already set)")
            }
            return
        }
        
        await MainActor.run { [orphanCount] in
            KBLog.persistence.kbInfo("Found orphan children count=\(orphanCount)")
        }
        
        var updated = 0
        var skippedAmbiguous = 0
        
        for c in orphans {
            if let fid = c.family?.id {
                c.familyId = fid
                updated += 1
            } else if let fid = singleFamilyId {
                c.familyId = fid
                updated += 1
            } else {
                // Ambiguous: multiple families and no relationship → don't decide.
                skippedAmbiguous += 1
                continue
            }
        }
        
        // Persist changes only if we actually updated something.
        if updated > 0 {
            try modelContext.save()
            let updatedCopy = updated
            let skippedCopy = skippedAmbiguous
            await MainActor.run { [updatedCopy, skippedCopy] in
                KBLog.persistence.kbInfo("Backfill child.familyId completed updated=\(updatedCopy) skipped=\(skippedCopy)")
            }
        } else {
            let skippedCopy = skippedAmbiguous
            await MainActor.run { [skippedCopy] in
                KBLog.persistence.kbInfo("Backfill child.familyId completed (no updates) skipped=\(skippedCopy)")
            }
        }
    }
}

