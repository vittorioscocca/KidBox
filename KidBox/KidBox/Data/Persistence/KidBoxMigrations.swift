//
//  KidBoxMigrations.swift
//  KidBox
//
//  Created by vscocca on 12/02/26.
//

import Foundation
import SwiftData
import OSLog

@ModelActor
actor KidBoxMigrationActor {
    
    func runAll() throws {
        try backfillChildFamilyIdIfNeeded()
    }
    
    /// Backfill: imposta `familyId` sui child che arrivano da uno schema vecchio.
    /// Regole:
    /// 1) se child.family?.id esiste -> usa quello
    /// 2) altrimenti, se esiste una sola famiglia locale -> usa quella
    /// 3) altrimenti lascia vuoto (non inventiamo id)
    func backfillChildFamilyIdIfNeeded() throws {
        // Prendo tutte le famiglie (per eventuale fallback “single family”)
        let families = try modelContext.fetch(FetchDescriptor<KBFamily>())
        let singleFamilyId: String? = (families.count == 1) ? families.first?.id : nil
        
        // Trovo tutti i children con familyId vuoto
        let desc = FetchDescriptor<KBChild>(
            predicate: #Predicate { $0.familyId == "" }
        )
        let orphans = try modelContext.fetch(desc)
        
        if orphans.isEmpty { return }
        
        for c in orphans {
            if let fid = c.family?.id {
                c.familyId = fid
            } else if let fid = singleFamilyId {
                c.familyId = fid
            } else {
                // Ambiguo: più famiglie e nessuna relationship => non decidiamo noi
                continue
            }
        }
        
        try modelContext.save()
    }
}
