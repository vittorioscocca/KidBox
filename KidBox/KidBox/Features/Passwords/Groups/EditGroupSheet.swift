import SwiftUI
import SwiftData
import FirebaseAuth

struct EditGroupSheet: View {
    enum Mode {
        case create
        case edit(PasswordGroup)
    }

    let familyId: String
    let mode: Mode
    let onSaved: ((PasswordGroup) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var members: [KBFamilyMember]
    @State private var name = ""
    @State private var icon = "folder.fill"
    @State private var color = "#7C6FDE"
    @State private var visibility = KBVisibilityScope.family
    @State private var visibilityMemberIds: Set<String> = []
    @State private var showVisibilitySheet = false
    @State private var errorMessage: String?

    private let iconOptions: [String] = [
        "key.fill", "lock.fill", "person.fill", "briefcase.fill", "creditcard.fill", "cart.fill",
        "house.fill", "gamecontroller.fill", "tv.fill", "display", "bubble.left.and.bubble.right.fill",
        "airplane", "car.fill", "heart.fill", "cross.case.fill", "book.fill", "globe",
        "building.2.fill", "camera.fill", "music.note", "film.fill", "doc.text.fill", "folder.fill",
        "tray.fill", "gift.fill", "wifi", "icloud.fill", "paperplane.fill", "graduationcap.fill", "wrench.and.screwdriver.fill",
    ]
    private let colorOptions: [String] = [
        "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF2D55", "#FF375F", "#FF9500",
        "#FFD60A", "#34C759", "#30D158", "#64D2FF", "#8E8E93", "#7C6FDE",
    ]

    init(familyId: String, mode: Mode, onSaved: ((PasswordGroup) -> Void)? = nil) {
        self.familyId = familyId
        self.mode = mode
        self.onSaved = onSaved
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }

    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var isUnassignedGroup: Bool {
        if case .edit(let group) = mode {
            return PasswordGroupsService.isUnassigned(group, familyId: familyId)
        }
        return false
    }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 30
    }
    private var selectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dettagli gruppo") {
                    TextField("Nome", text: $name)
                        .disabled(isUnassignedGroup)
                    Text("\(name.count)/30")
                        .font(.caption)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                Section("Icona") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(iconOptions, id: \.self) { item in
                            Button {
                                icon = item
                            } label: {
                                Image(systemName: item)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .padding(.vertical, 6)
                                    .background((item == icon ? KBTheme.tint.opacity(0.18) : KBTheme.secondaryBackground(colorScheme)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Colore") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Button {
                                color = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex) ?? KBTheme.tint)
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        if color == hex {
                                            Circle().strokeBorder(.white, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Visibilità") {
                    Button {
                        showVisibilitySheet = true
                    } label: {
                        HStack {
                            Text(KBVisibilityScope.chipLabel(for: visibility))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if let errorMessage, !errorMessage.isEmpty {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle(modeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Salva") { save() }.disabled(!canSave) }
            }
            .onAppear { hydrate() }
            .sheet(isPresented: $showVisibilitySheet) {
                VisibilityPickerSheet(
                    selectedScope: $visibility,
                    selectedMemberIds: $visibilityMemberIds,
                    members: selectableMembers,
                    currentUid: currentUid,
                    scopeSectionTitle: "Chi può vedere questo gruppo",
                    allowedScopes: [KBVisibilityScope.family, KBVisibilityScope.onlyCreator]
                ) { scope, memberIds in
                    visibility = scope
                    visibilityMemberIds = memberIds
                }
            }
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create: return "Nuovo gruppo"
        case .edit: return "Modifica gruppo"
        }
    }

    private func hydrate() {
        guard case .edit(let group) = mode else { return }
        name = (try? group.decryptName()) ?? ""
        icon = group.icon
        color = group.color
        visibility = PasswordEntry.normalizedPasswordVisibility(group.visibility)
        visibilityMemberIds = Set(group.visibilityMemberIds)
    }

    private func save() {
        errorMessage = nil
        guard let uid = currentUid else {
            errorMessage = "Accesso non valido."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Inserisci un nome gruppo."
            return
        }
        guard trimmed.count <= 30 else {
            errorMessage = "Il nome deve avere massimo 30 caratteri."
            return
        }
        do {
            switch mode {
            case .create:
                let groupId = UUID().uuidString
                let cipher = try PasswordCypher.encrypt(trimmed, familyId: familyId, visibility: visibility, createdBy: uid)
                let group = PasswordGroup(
                    id: groupId,
                    familyId: familyId,
                    nameCipher: cipher,
                    icon: icon,
                    color: color,
                    visibility: visibility,
                    visibilityMemberIds: Array(visibilityMemberIds),
                    createdBy: uid,
                    isSystem: false
                )
                group.syncState = .pendingUpsert
                modelContext.insert(group)
                try modelContext.save()
                PasswordsRepository.enqueuePasswordGroupUpsert(groupId: group.id, familyId: familyId, modelContext: modelContext)
                SyncCenter.shared.flushGlobal(modelContext: modelContext)
                onSaved?(group)
            case .edit(let group):
                if !isUnassignedGroup {
                    group.nameCipher = try PasswordCypher.encrypt(trimmed, familyId: familyId, visibility: visibility, createdBy: group.createdBy)
                }
                group.icon = icon
                group.color = color
                group.visibility = visibility
                group.visibilityMemberIds = Array(visibilityMemberIds)
                group.updatedAt = .now
                group.syncState = .pendingUpsert
                try modelContext.save()
                PasswordsRepository.enqueuePasswordGroupUpsert(groupId: group.id, familyId: familyId, modelContext: modelContext)
                SyncCenter.shared.flushGlobal(modelContext: modelContext)
                onSaved?(group)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

