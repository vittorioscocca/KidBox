//
//  FamilySwitcherView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct FamilySwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]

    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var newFamilyName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var isSyncingRemote = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(families) { family in
                        FamilyRowView(
                            family: family,
                            isActive: coordinator.activeFamilyId == family.id
                        ) {
                            let service = MultiFamilyService(
                                modelContext: modelContext,
                                coordinator: coordinator
                            )
                            service.switchToFamily(family.id)
                            dismiss()
                        }
                    }
                }

                Section {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Crea nuova famiglia", systemImage: "plus")
                    }
                }

                Section {
                    Button {
                        showJoinSheet = true
                    } label: {
                        Label("Entra in una famiglia", systemImage: "qrcode.viewfinder")
                    }
                } footer: {
                    Text("Scansiona il QR di chi vuole invitarti o inserisci il codice a 6 cifre.")
                        .font(.caption)
                }
            }
            .navigationTitle("Le tue famiglie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSyncingRemote {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .task { await syncFamiliesFromRemote() }
            .sheet(isPresented: $showCreateSheet) {
                createFamilySheet
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinFamilyView()
                    .environmentObject(coordinator)
            }
            .alert(
                "Errore",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var createFamilySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome famiglia (es. Famiglia Rossi)", text: $newFamilyName)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Text("I documenti, le note e i profili saranno separati dalle altre famiglie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        createFamily()
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView()
                            } else {
                                Text("Crea famiglia")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isCreating
                    )
                }
            }
            .navigationTitle("Nuova famiglia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        showCreateSheet = false
                        newFamilyName = ""
                    }
                    .disabled(isCreating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Fetcha le memberships da Firestore e inserisce in SwiftData le famiglie mancanti.
    /// Così le famiglie create su altri device compaiono nel picker senza bootstrap completo.
    private func syncFamiliesFromRemote() async {
        isSyncingRemote = true
        defer { isSyncingRemote = false }

        do {
            let memberships = try await MembershipRemoteStore().fetchMembershipsForCurrentUser()
            let localIds = Set(families.map { $0.id })
            let missing = memberships.filter { !localIds.contains($0.familyId) }
            guard !missing.isEmpty else { return }

            let remote = FamilyReadRemoteStore()
            let now = Date()
            let uid = Auth.auth().currentUser?.uid ?? ""

            for membership in missing {
                guard let fetched = try? await remote.fetchFamily(familyId: membership.familyId) else { continue }
                let family = KBFamily(
                    id: fetched.id,
                    name: fetched.name,
                    createdBy: fetched.ownerUid,
                    updatedBy: fetched.ownerUid,
                    createdAt: now,
                    updatedAt: now
                )
                modelContext.insert(family)

                // Inserisci anche il member corrente se mancante
                let fetchedId = fetched.id
                let memberDesc = FetchDescriptor<KBFamilyMember>(
                    predicate: #Predicate { $0.familyId == fetchedId && $0.userId == uid }
                )
                if (try? modelContext.fetch(memberDesc))?.isEmpty != false {
                    let member = KBFamilyMember(
                        id: uid,
                        familyId: fetched.id,
                        userId: uid,
                        role: membership.role,
                        displayName: Auth.auth().currentUser?.displayName,
                        email: Auth.auth().currentUser?.email,
                        photoURL: Auth.auth().currentUser?.photoURL?.absoluteString,
                        updatedBy: uid,
                        createdAt: now,
                        updatedAt: now
                    )
                    modelContext.insert(member)
                }
            }
            try? modelContext.save()
        } catch {
            KBLog.sync.kbError("FamilySwitcher syncFamiliesFromRemote error: \(error.localizedDescription)")
        }
    }

    private func createFamily() {
        let trimmed = newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        let service = MultiFamilyService(modelContext: modelContext, coordinator: coordinator)
        Task {
            do {
                let familyId = try await service.createEmptyFamily(name: trimmed)
                service.switchToFamily(familyId)
                showCreateSheet = false
                newFamilyName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - FamilyRowView

private struct FamilyRowView: View {
    let family: KBFamily
    let isActive: Bool
    let onTap: () -> Void

    private var heroURL: URL? {
        guard let raw = family.heroPhotoURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @ViewBuilder
    private var familyAvatar: some View {
        ZStack {
            if let heroURL {
                AsyncImage(url: heroURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderAvatar
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemFill))
            Image(systemName: "house.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                familyAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(family.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if isActive {
                        Text("Famiglia attiva")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
