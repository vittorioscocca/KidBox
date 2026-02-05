//
//  SetupFamilyDestinationView.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftUI
import SwiftData

/// Wrapper che traduce Route.setupFamilyEdit(familyId, childId)
/// in SetupFamilyView(mode: .edit(family:child:))
struct SetupFamilyDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    
    let familyId: String
    let childId: String
    
    var body: some View {
        // fetch “manuale” così non dobbiamo fare @Query dinamiche
        let family = fetchFamily(id: familyId)
        let child = fetchChild(id: childId)
        
        if let family, let child {
            SetupFamilyView(mode: .edit(family: family, child: child))
        } else {
            // fallback safe: se non trovo i dati (wipe, desync, ecc)
            SetupFamilyView(mode: .create)
        }
    }
    
    private func fetchFamily(id: String) -> KBFamily? {
        do {
            let fid = id
            let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
            return try modelContext.fetch(desc).first
        } catch {
            return nil
        }
    }
    
    private func fetchChild(id: String) -> KBChild? {
        do {
            let cid = id
            let desc = FetchDescriptor<KBChild>(predicate: #Predicate { $0.id == cid })
            return try modelContext.fetch(desc).first
        } catch {
            return nil
        }
    }
}
