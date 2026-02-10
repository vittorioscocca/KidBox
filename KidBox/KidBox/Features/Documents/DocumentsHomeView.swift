//
//  DocumentsView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData

struct DocumentsHomeView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    
    private var familyId: String { families.first?.id ?? "" }
    
    var body: some View {
        Group {
            if familyId.isEmpty {
                emptyNoFamily
            } else {
                // ✅ Root del filesystem: da qui hai N livelli
                DocumentFolderView(familyId: familyId, folderId: nil, folderTitle: "Documenti")
                    .id("root-\(familyId)")
            }
        }
        .navigationTitle("Documenti")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var emptyNoFamily: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Prima crea o unisciti a una famiglia.")
                .font(.headline)
            
            Button("Vai a Family") {
                coordinator.navigate(to: .familySettings)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.horizontal)
    }
}
