import SwiftUI
import SwiftData
import FirebaseAuth

struct GroupPickerSheet: View {
    let familyId: String
    @Binding var selectedGroupId: String?
    let passwordVisibility: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCreate = false

    @Query private var groups: [PasswordGroup]
    private var currentUid: String? { Auth.auth().currentUser?.uid }

    init(familyId: String, selectedGroupId: Binding<String?>, passwordVisibility: String) {
        self.familyId = familyId
        self._selectedGroupId = selectedGroupId
        self.passwordVisibility = passwordVisibility
        let fid = familyId
        _groups = Query(
            filter: #Predicate<PasswordGroup> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordGroup.sortIndex, order: .forward), SortDescriptor(\PasswordGroup.updatedAt, order: .reverse)]
        )
    }

    private var visibleGroups: [PasswordGroup] {
        let uid = currentUid
        let mustBeFamily = PasswordEntry.normalizedPasswordVisibility(passwordVisibility) == KBVisibilityScope.family
        return groups
            .filter { $0.isVisible(to: uid) }
            .filter { g in !mustBeFamily || PasswordEntry.normalizedPasswordVisibility(g.visibility) == KBVisibilityScope.family }
            .sorted { lhs, rhs in
                let leftName = (try? lhs.decryptName()) ?? lhs.id
                let rightName = (try? rhs.decryptName()) ?? rhs.id
                if PasswordGroupsService.isUnassigned(lhs, familyId: familyId) { return false }
                if PasswordGroupsService.isUnassigned(rhs, familyId: familyId) { return true }
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleGroups, id: \.id) { group in
                    Button {
                        selectedGroupId = group.id
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: group.icon).foregroundStyle(Color(hex: group.color) ?? KBTheme.tint)
                            Circle().fill(Color(hex: group.color) ?? KBTheme.tint).frame(width: 8, height: 8)
                            Text((try? group.decryptName()) ?? "Gruppo")
                                .foregroundStyle(KBTheme.primaryText(colorScheme))
                            Spacer()
                            if selectedGroupId == group.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    showCreate = true
                } label: {
                    Label("+ Nuovo gruppo", systemImage: "plus.circle.fill")
                        .foregroundStyle(KBTheme.tint)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Gruppo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreate) {
                EditGroupSheet(familyId: familyId, mode: .create) { newGroup in
                    selectedGroupId = newGroup.id
                }
            }
        }
    }
}

