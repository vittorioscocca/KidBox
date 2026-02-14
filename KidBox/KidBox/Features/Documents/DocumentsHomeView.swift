//
//  DocumentsView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import OSLog

/// Entry point for the "Documenti" area.
///
/// Shows:
/// - An empty state if the user has no active family in local SwiftData
/// - The root `DocumentFolderView` otherwise
///
/// - Note: Avoid logging in `body` to prevent spam due to SwiftUI recomputations.
///   Logging is performed only on lifecycle or user actions.
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
        .onAppear {
            KBLog.ui.info("DocumentsHomeView appeared familyId=\(familyId.isEmpty ? "EMPTY" : familyId, privacy: .public)")
        }
        .onChange(of: families.first?.id) { _, newValue in
            let fid = newValue ?? ""
            KBLog.ui.info("DocumentsHomeView active family changed familyId=\(fid.isEmpty ? "EMPTY" : fid, privacy: .public)")
        }
    }
    
    private var emptyNoFamily: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            Text("Prima crea o unisciti a una famiglia.")
                .font(.headline)
            
            Button("Vai a Family") {
                KBLog.ui.info("DocumentsHomeView CTA tap: navigate to familySettings")
                coordinator.navigate(to: .familySettings)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.horizontal)
    }
}
