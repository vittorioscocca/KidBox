//
//  VisibilityPickerSheet.swift
//  KidBox
//

import SwiftUI

/// A visibility picker that can be used either as a standalone sheet (embedded = false,
/// wraps content in its own NavigationStack) or pushed onto a parent NavigationStack
/// (embedded = true, no inner NavigationStack – avoids the nested-sheet/stack problem).
struct VisibilityPickerSheet: View {
    @Binding var selectedScope: String
    @Binding var selectedMemberIds: Set<String>
    let members: [KBFamilyMember]
    let currentUid: String?
    let scopeSectionTitle: String
    /// When true the view is pushed via `navigationDestination` and must NOT have its own NavigationStack.
    var embedded: Bool = false
    /// Se valorizzato, mostra solo queste opzioni (ordine preservato). Es. Password v1: `[family, onlyCreator]`.
    var allowedScopes: [String]? = nil
    let onConfirm: (String, Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss

    private var visibilityOptions: [(scope: String, title: String)] {
        let all: [(String, String)] = [
            (KBVisibilityScope.family, "👨‍👩‍👧 Tutta la famiglia"),
            (KBVisibilityScope.members, "👥 Membri selezionati"),
            (KBVisibilityScope.onlyCreator, "🔒 Solo io"),
        ]
        if let allowed = allowedScopes, !allowed.isEmpty {
            return all.filter { allowed.contains($0.0) }
        }
        return all
    }

    var body: some View {
        if embedded {
            pickerList
        } else {
            NavigationStack {
                pickerList
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { dismiss() }
                                .controlSize(.regular)
                        }
                    }
            }
            .presentationDetents([.fraction(0.36), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var pickerList: some View {
        List {
            Section(scopeSectionTitle) {
                ForEach(visibilityOptions, id: \.scope) { row in
                    visibilityRow(row.scope, row.title)
                }
            }

            if selectedScope == KBVisibilityScope.members {
                Section("Seleziona membri") {
                    ForEach(members, id: \.id) { member in
                        Button {
                            if selectedMemberIds.contains(member.userId) {
                                selectedMemberIds.remove(member.userId)
                            } else {
                                selectedMemberIds.insert(member.userId)
                            }
                        } label: {
                            HStack {
                                Text(member.displayName ?? "Membro")
                                Spacer()
                                Image(systemName: selectedMemberIds.contains(member.userId)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Visibilità")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Conferma") {
                    var finalIds = selectedMemberIds
                    if selectedScope != KBVisibilityScope.members {
                        finalIds = []
                    }
                    if let currentUid {
                        finalIds.remove(currentUid)
                    }
                    onConfirm(selectedScope, finalIds)
                    // When embedded (pushed via navigationDestination inside a sheet),
                    // do NOT call dismiss() — it risks dismissing the enclosing sheet
                    // instead of just popping the navigation push.  The parent is
                    // responsible for setting isPresented = false in its onConfirm callback.
                    if !embedded {
                        dismiss()
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    private func visibilityRow(_ scope: String, _ title: String) -> some View {
        Button {
            selectedScope = scope
            if scope != KBVisibilityScope.members {
                selectedMemberIds.removeAll()
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: selectedScope == scope ? "largecircle.fill.circle" : "circle")
            }
        }
        .buttonStyle(.plain)
    }
}
