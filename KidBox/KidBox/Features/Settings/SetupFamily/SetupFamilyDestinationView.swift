//
//  SetupFamilyDestinationView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Wrapper che traduce `Route.setupFamilyEdit(familyId, childId)`
/// in `SetupFamilyView(mode: .edit(family:child:))`.
///
/// Perché esiste:
/// - Evita `@Query` dinamiche in una destination.
/// - Fa un fetch “one-shot” da SwiftData e passa i model a `SetupFamilyView`.
///
/// Fallback behavior:
/// - Se family/child non sono presenti localmente (wipe, desync, migrazione, ecc),
///   apre `SetupFamilyView(mode: .create)` come fallback safe.
///
/// Logging:
/// - In SwiftUI NON loggare nel `body` (può essere ricomputato spesso).
/// - Logghiamo solo in `onAppear` e includiamo la reason del fallback.
struct SetupFamilyDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    
    let familyId: String
    let childId: String
    
    @State private var didLogAppear = false
    
    var body: some View {
        // fetch “manuale” così non dobbiamo fare @Query dinamiche
        let family = fetchFamily(id: familyId)
        let child = fetchChild(id: childId)
        
        Group {
            if let family, let child {
                SetupFamilyView(mode: .edit(family: family, child: child))
            } else {
                // fallback safe: se non trovo i dati (wipe, desync, ecc)
                SetupFamilyView(mode: .create)
            }
        }
        .onAppear {
            // evita spam log se il body viene ricostruito
            guard !didLogAppear else { return }
            didLogAppear = true
            
            let hasFamily = (family != nil)
            let hasChild  = (child != nil)
            
            if hasFamily && hasChild {
                KBLog.navigation.info(
                    "SetupFamilyDestinationView: open EDIT familyId=\(familyId, privacy: .public) childId=\(childId, privacy: .public)"
                )
            } else {
                KBLog.navigation.info(
                    "SetupFamilyDestinationView: fallback CREATE (missing family=\(!hasFamily), child=\(!hasChild)) familyId=\(familyId, privacy: .public) childId=\(childId, privacy: .public)"
                )
            }
        }
    }
    
    // MARK: - Local fetch helpers
    
    private func fetchFamily(id: String) -> KBFamily? {
        do {
            let fid = id
            let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
            return try modelContext.fetch(desc).first
        } catch {
            KBLog.data.error(
                "SetupFamilyDestinationView: fetchFamily failed familyId=\(id, privacy: .public) err=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
    
    private func fetchChild(id: String) -> KBChild? {
        do {
            let cid = id
            let desc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == cid })
            return try modelContext.fetch(desc).first
        } catch {
            KBLog.data.error(
                "SetupFamilyDestinationView: fetchChild failed childId=\(id, privacy: .public) err=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
