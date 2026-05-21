//
//  GeofenceMemberPickerSheet.swift
//  KidBox
//
//  Created by vscocca on 21/05/26.
//

import SwiftUI

/// Selettore membri famiglia per geofence (tutti o elenco UID).
struct GeofenceMemberPickerSheet: View {

    let navigationTitle: String
    let sectionTitle: String
    let footer: String
    @Binding var useAllMembers: Bool
    @Binding var selectedUserIds: Set<String>
    let members: [KBFamilyMember]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        useAllMembers = true
                        selectedUserIds.removeAll()
                    } label: {
                        HStack {
                            Text("Tutti i membri")
                            Spacer()
                            Image(systemName: useAllMembers ? "largecircle.fill.circle" : "circle")
                        }
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text(footer)
                }

                Section {
                    ForEach(members, id: \.userId) { member in
                        Button {
                            useAllMembers = false
                            if selectedUserIds.contains(member.userId) {
                                selectedUserIds.remove(member.userId)
                            } else {
                                selectedUserIds.insert(member.userId)
                            }
                        } label: {
                            HStack {
                                Text(member.displayName ?? "Membro")
                                Spacer()
                                Image(systemName: (!useAllMembers && selectedUserIds.contains(member.userId))
                                    ? "checkmark.circle.fill"
                                    : "circle")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(sectionTitle)
                } footer: {
                    if useAllMembers {
                        Text("Tocca un membro per scegliere solo alcune persone.")
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Conferma") {
                        if useAllMembers {
                            selectedUserIds.removeAll()
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
