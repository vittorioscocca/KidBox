//
//  TreatmentDetailDestinationView.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

import SwiftUI
import SwiftData

/// Risolve il KBTreatment per id e mostra TreatmentDetailView.
/// (Stesso pattern di ChildDestinationView)
struct TreatmentDetailDestinationView: View {
    @Environment(\.modelContext) private var modelContext
    let treatmentId: String
    let familyId: String
    let childId: String
    
    var body: some View {
        if let t = fetch() {
            TreatmentDetailView(treatment: t)
        } else {
            Text("Cura non trovata").foregroundStyle(.secondary)
        }
    }
    
    private func fetch() -> KBTreatment? {
        let tid = treatmentId
        let desc = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.id == tid })
        return try? modelContext.fetch(desc).first
    }
}
