//
//  DocumentDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

/// Metadati e visibilità di un documento già salvato (visibilità modificabile).
struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let document: KBDocument
    let members: [KBFamilyMember]

    @State private var showVisibilityPicker = false
    @State private var pickerScope = KBVisibilityScope.family
    @State private var pickerMemberIds: Set<String> = []

    private var metaRow: [(String, String)] {
        var rows: [(String, String)] = [
            ("Titolo", document.title.isEmpty ? document.fileName : document.title),
            ("File", document.fileName),
            ("Tipo", document.mimeType),
            ("Dimensione", formatBytes(document.fileSize)),
        ]
        if let notes = document.notes, !notes.isEmpty {
            rows.append(("Note", notes))
        }
        return rows
    }

    var body: some View {
        List {
            Section("Informazioni") {
                ForEach(metaRow, id: \.0) { pair in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pair.0).font(.caption).foregroundStyle(.secondary)
                        Text(pair.1).font(.body)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Visibilità") {
                Button {
                    pickerScope = KBVisibilityScope.normalized(document.visibilityScope)
                    pickerMemberIds = Set(document.visibilityMemberIds)
                    showVisibilityPicker = true
                } label: {
                    HStack {
                        Text(KBVisibilityScope.chipLabel(for: document.visibilityScope))
                            .font(.custom("Nunito", size: 14))
                            .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.949, green: 0.941, blue: 0.922))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Text("Puoi cambiare chi vede il documento in qualsiasi momento.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Documento")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVisibilityPicker) {
            VisibilityPickerSheet(
                selectedScope: $pickerScope,
                selectedMemberIds: $pickerMemberIds,
                members: members,
                currentUid: Auth.auth().currentUser?.uid,
                scopeSectionTitle: "Chi può vedere questo documento?",
                onConfirm: { scope, ids in
                    persistVisibility(scope: scope, memberIds: ids)
                }
            )
        }
    }

    private func persistVisibility(scope: String, memberIds: Set<String>) {
        var s = KBVisibilityScope.normalized(scope)
        var ids = memberIds
        if s == KBVisibilityScope.members && ids.isEmpty {
            s = KBVisibilityScope.family
        }

        document.visibilityScope = s
        document.visibilityMemberIds = s == KBVisibilityScope.members
            ? ids.sorted()
            : []

        let uid = Auth.auth().currentUser?.uid ?? document.updatedBy
        if s == KBVisibilityScope.onlyCreator, document.createdBy.isEmpty {
            document.createdBy = uid
        }

        document.updatedBy = uid
        document.updatedAt = Date()
        document.syncState = .pendingUpsert
        document.lastSyncError = nil

        do {
            try modelContext.save()
            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: document.id,
                familyId: document.familyId,
                modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            showVisibilityPicker = false
        } catch {
            // leave sheet open; SwiftData save failures are rare here
        }
    }

    private func formatBytes(_ n: Int64) -> String {
        let b = Double(n)
        if b < 1024 { return "\(n) B" }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
