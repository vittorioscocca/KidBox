//
//  DocumentUploadView.swift
//  KidBox
//

import SwiftUI

/// Schermata pre-caricamento: imposta la visibilità prima di Fotocamera / Libreria / file.
struct DocumentUploadView: View {
    @Binding var visibilityScope: String
    @Binding var visibilityMemberIds: Set<String>
    let members: [KBFamilyMember]
    let currentUid: String?
    /// `true`: chip apre `VisibilityPickerSheet`. Dopo il salvataggio la visibilità resta modificabile da `DocumentDetailView`.
    let isNewDocument: Bool
    let scopeSectionTitle: String
    let onContinue: () -> Void
    
    @State private var isVisibilitySheetPresented = false
    
    private var selectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Scegli chi potrà vedere il documento che stai per caricare.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    
                    visibilityChip
                        .padding(.leading, 4)
                }
                
                Button {
                    onContinue()
                } label: {
                    Text("Continua")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Nuovo documento")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isVisibilitySheetPresented) {
            VisibilityPickerSheet(
                selectedScope: $visibilityScope,
                selectedMemberIds: $visibilityMemberIds,
                members: selectableMembers,
                currentUid: currentUid,
                scopeSectionTitle: scopeSectionTitle
            ) { scope, ids in
                visibilityScope = scope
                visibilityMemberIds = ids
            }
        }
    }
    
    @ViewBuilder
    private var visibilityChip: some View {
        Button {
            guard isNewDocument else { return }
            isVisibilitySheetPresented = true
        } label: {
            Text(KBVisibilityScope.chipLabel(for: visibilityScope))
                .font(.custom("Nunito", size: 14))
                .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.949, green: 0.941, blue: 0.922))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isNewDocument)
    }
}
