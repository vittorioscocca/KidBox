import SwiftUI
import SwiftData
import FirebaseAuth

struct GroupsManagementView: View {
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingGroup: PasswordGroup?
    @State private var showCreate = false
    @State private var pendingDeleteGroup: PasswordGroup?
    @State private var reassignmentTargetId: String?
    @State private var showReassignmentDialog = false

    @Query private var groups: [PasswordGroup]
    @Query private var entries: [PasswordEntry]

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _groups = Query(
            filter: #Predicate<PasswordGroup> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordGroup.sortIndex, order: .forward), SortDescriptor(\PasswordGroup.updatedAt, order: .reverse)]
        )
        _entries = Query(
            filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
    }

    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var visibleGroups: [PasswordGroup] {
        groups.filter { $0.isVisible(to: currentUid) }.sorted { a, b in
            if PasswordGroupsService.isUnassigned(a, familyId: familyId) { return false }
            if PasswordGroupsService.isUnassigned(b, familyId: familyId) { return true }
            let an = (try? a.decryptName()) ?? a.id
            let bn = (try? b.decryptName()) ?? b.id
            return an.localizedCaseInsensitiveCompare(bn) == .orderedAscending
        }
    }
    private var visibleEntries: [PasswordEntry] {
        entries.filter { $0.isVisible(to: currentUid) }
    }

    var body: some View {
        List {
            ForEach(visibleGroups, id: \.id) { group in
                Button {
                    editingGroup = group
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: group.icon).foregroundStyle(Color(hex: group.color) ?? KBTheme.tint)
                        Circle().fill(Color(hex: group.color) ?? KBTheme.tint).frame(width: 8, height: 8)
                        Text((try? group.decryptName()) ?? "Gruppo")
                        Spacer()
                        Text("\(passwordCount(for: group))")
                            .font(.caption.bold())
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        attemptDelete(group)
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                    .disabled(!canAttemptDelete(group))
                }
                .listRowBackground(KBTheme.cardBackground(colorScheme))
            }
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Gestisci gruppi")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingGroup != nil },
            set: { if !$0 { editingGroup = nil } }
        )) {
            if let group = editingGroup {
                EditGroupSheet(familyId: familyId, mode: .edit(group))
            }
        }
        .sheet(isPresented: $showCreate) {
            EditGroupSheet(familyId: familyId, mode: .create)
        }
        .confirmationDialog("Sposta password prima di eliminare", isPresented: $showReassignmentDialog, titleVisibility: .visible) {
            ForEach(reassignmentCandidates(), id: \.id) { g in
                Button((try? g.decryptName()) ?? "Gruppo") {
                    reassignmentTargetId = g.id
                    executeDeleteWithReassignment()
                }
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    private func passwordCount(for group: PasswordGroup) -> Int {
        visibleEntries.filter { $0.groupId == group.id }.count
    }

    private func canAttemptDelete(_ group: PasswordGroup) -> Bool {
        !PasswordGroupsService.isUnassigned(group, familyId: familyId)
    }

    private func attemptDelete(_ group: PasswordGroup) {
        guard canAttemptDelete(group) else { return }
        let count = passwordCount(for: group)
        if group.isSystem && count > 0 {
            pendingDeleteGroup = group
            showReassignmentDialog = true
            return
        }
        if !group.isSystem {
            pendingDeleteGroup = group
            reassignmentTargetId = PasswordGroupsService.groupId(familyId: familyId, slug: PasswordGroupsService.unassignedSlug)
            executeDeleteWithReassignment()
            return
        }
        softDeleteGroup(group)
    }

    private func reassignmentCandidates() -> [PasswordGroup] {
        guard let deleting = pendingDeleteGroup else { return [] }
        return visibleGroups.filter { $0.id != deleting.id }
    }

    private func executeDeleteWithReassignment() {
        guard let group = pendingDeleteGroup else { return }
        guard let targetId = reassignmentTargetId ?? PasswordGroupsService.resolveUnassignedGroup(familyId: familyId, modelContext: modelContext)?.id else { return }
        for entry in visibleEntries where entry.groupId == group.id {
            entry.groupId = targetId
            entry.updatedAt = .now
            entry.syncState = .pendingUpsert
            PasswordsRepository.enqueuePasswordEntryUpsert(entryId: entry.id, familyId: familyId, modelContext: modelContext)
        }
        softDeleteGroup(group)
        pendingDeleteGroup = nil
        reassignmentTargetId = nil
    }

    private func softDeleteGroup(_ group: PasswordGroup) {
        group.deletedAt = .now
        group.updatedAt = .now
        group.syncState = .pendingDelete
        try? modelContext.save()
        PasswordsRepository.enqueuePasswordGroupDelete(groupId: group.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}

