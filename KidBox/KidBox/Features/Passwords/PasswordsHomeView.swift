//
//  PasswordsHomeView.swift
//  KidBox
//
//  Elenco password per famiglia (Firestore + SwiftData, cifratura chiave famiglia).
//  UI: KBTheme, lista standard; promemoria scadenza via NotificationManager.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import CryptoKit

/// Dati minimi e `Sendable` per calcolare i warning sicurezza off-main (vedi
/// `PasswordsHomeView.computeWarningEntryIds`). Evita di toccare le `@Model` SwiftData
/// fuori dal main actor.
struct PasswordWarningSnapshot: Sendable {
    let id: String
    let familyId: String
    let visibility: String
    let createdBy: String
    let passwordCipher: Data
    let pwnedCount: Int?
}

private struct PasswordSection: Identifiable {
    let id: String
    let title: String
    let headerTint: Color
    let headerIcon: String
    let entries: [PasswordEntry]
}

private enum PasswordListFormatting {
    static func username(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "—" }
        return raw
    }
}

struct PasswordsHomeView: View {
    let familyId: String

    private enum PasswordListScope: Equatable {
        case all
        case favorites
        /// Visibilità «tutta la famiglia» (`KBVisibilityScope.family`).
        case familyShared
        /// Visibilità «solo io» per password create dall’utente corrente.
        case onlyMinePrivate
        case group(String)
    }

    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var entries: [PasswordEntry]
    @Query private var groups: [PasswordGroup]

    @State private var searchQuery = ""
    @State private var showAdd = false
    @State private var listScope: PasswordListScope = .all
    @State private var expandedSectionIds: Set<String> = []
    @State private var showGroupsManagement = false
    @State private var showImportExport = false
    @State private var didRunInitialHomeTasks = false
    @State private var warningEntryIdsCache: Set<String> = []
    @State private var isSelecting = false
    @State private var selectedIds: Set<String> = []
    @State private var showBulkDeleteConfirm = false

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _entries = Query(
            filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
        _groups = Query(
            filter: #Predicate<PasswordGroup> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordGroup.updatedAt, order: .reverse)]
        )
    }

    private var visibleEntries: [PasswordEntry] {
        let uid = currentUid
        return entries.filter { $0.isVisible(to: uid) }
    }

    private var visibleGroups: [PasswordGroup] {
        let uid = currentUid
        return groups.filter { $0.isVisible(to: uid) }
    }

    private var unassignedGroupId: String {
        PasswordGroupsService.groupId(familyId: familyId, slug: PasswordGroupsService.unassignedSlug)
    }

    private var sections: [PasswordSection] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uid = currentUid
        let base = visibleEntries.filter { e in
            switch listScope {
            case .all:
                return true
            case .favorites:
                return e.isFavorite
            case .familyShared:
                return PasswordEntry.normalizedPasswordVisibility(e.visibility) == KBVisibilityScope.family
            case .onlyMinePrivate:
                guard let uid, !uid.isEmpty else { return false }
                return PasswordEntry.normalizedPasswordVisibility(e.visibility) == KBVisibilityScope.onlyCreator
                    && e.createdBy == uid
            case .group(let gid):
                return (e.groupId ?? unassignedGroupId) == gid
            }
        }

        let filtered: [PasswordEntry] = {
            guard !q.isEmpty else { return base }
            return base.filter { entry in
                let title = (try? entry.decryptTitle())?.lowercased() ?? ""
                let user = (try? entry.decryptUsername())?.lowercased() ?? ""
                return title.contains(q) || user.contains(q)
            }
        }()

        var bucket: [String: [PasswordEntry]] = [:]
        for e in filtered {
            let gid = e.groupId ?? ""
            bucket[gid, default: []].append(e)
        }

        let groupById = Dictionary(uniqueKeysWithValues: visibleGroups.map { ($0.id, $0) })

        var result: [PasswordSection] = []

        let sortedGroups = visibleGroups.sorted { a, b in
            let na = (try? a.decryptName()) ?? a.id
            let nb = (try? b.decryptName()) ?? b.id
            if PasswordGroupsService.isUnassigned(a, familyId: familyId) { return false }
            if PasswordGroupsService.isUnassigned(b, familyId: familyId) { return true }
            return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
        }

        for g in sortedGroups {
            guard let list = bucket[g.id], !list.isEmpty else { continue }
            let title = (try? g.decryptName()) ?? "Gruppo"
            let hex = g.color
            let tint = Color(hex: hex) ?? KBTheme.tint
            result.append(PasswordSection(id: g.id, title: title, headerTint: tint, headerIcon: g.icon, entries: list.sorted { $0.updatedAt > $1.updatedAt }))
            bucket[g.id] = nil
        }

        var loose: [PasswordEntry] = []
        for (k, v) in bucket {
            guard !v.isEmpty else { continue }
            if k.isEmpty || groupById[k] == nil {
                loose.append(contentsOf: v)
            }
        }

        if !loose.isEmpty {
            result.append(
                PasswordSection(
                    id: PasswordGroupsService.groupId(familyId: familyId, slug: PasswordGroupsService.unassignedSlug),
                    title: NSLocalizedString("passwords.group.unassigned", comment: ""),
                    headerTint: KBTheme.secondaryText(colorScheme),
                    headerIcon: "tray",
                    entries: loose.sorted { $0.updatedAt > $1.updatedAt }
                )
            )
        }

        return result
    }

    private var flatEntries: [PasswordEntry] {
        sections.flatMap(\.entries)
    }

    private var emptyPasswordsTitle: String {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return "Nessun risultato" }
        switch listScope {
        case .favorites: return "Nessuna preferita"
        case .familyShared: return "Nessuna condivisa in famiglia"
        case .onlyMinePrivate: return "Nessuna solo per te"
        default: return "Nessuna password"
        }
    }

    private var emptyPasswordsDescription: Text {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return Text("Prova con altre parole chiave.")
        }
        switch listScope {
        case .favorites:
            return Text("Segna le password come preferite dal dettaglio o con uno swipe sulla riga.")
        case .familyShared:
            return Text("Qui compaiono le password con visibilità «Tutta la famiglia».")
        case .onlyMinePrivate:
            return Text("Qui compaiono le password con visibilità «Solo io» che hai creato tu.")
        default:
            return Text("Tocca + per aggiungere la prima credenziale.")
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            groupFilterBar
            if flatEntries.isEmpty {
                ContentUnavailableView(
                    emptyPasswordsTitle,
                    systemImage: "key.fill",
                    description: emptyPasswordsDescription
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            } else {
                passwordEntriesList
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Password")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isSelecting ? "Annulla" : "Seleziona") {
                    if isSelecting {
                        isSelecting = false
                        selectedIds = []
                    } else {
                        isSelecting = true
                        selectedIds = []
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Menu {
                        Button("Gestisci gruppi", systemImage: "folder.badge.gearshape") {
                            showGroupsManagement = true
                        }
                        Button("Importa/Esporta", systemImage: "arrow.left.arrow.right.square") {
                            showImportExport = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    Button {
                        coordinator.navigate(to: .passwordsSecurity(familyId: familyId))
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                    .modifier(SecurityToolbarBadgeModifier(count: warningEntryIdsCache.count))
                }
                .accessibilityLabel("Sicurezza password")
            }
            if isSelecting, !selectedIds.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    Button(role: .destructive) {
                        showBulkDeleteConfirm = true
                    } label: {
                        Text("Elimina (\(selectedIds.count))")
                    }
                    Spacer()
                }
            }
        }
        .searchable(text: $searchQuery, prompt: "Cerca")
        .onChange(of: listScope) { _, _ in
            selectedIds = []
        }
        .confirmationDialog(
            "Eliminare \(selectedIds.count) password?",
            isPresented: $showBulkDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                deleteSelectedEntries()
            }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showAdd) {
            AddPasswordSheet(familyId: familyId)
        }
        .sheet(isPresented: $showGroupsManagement) {
            NavigationStack { GroupsManagementView(familyId: familyId) }
        }
        .sheet(isPresented: $showImportExport) {
            PasswordsImportExportView(familyId: familyId)
        }
        .task {
            guard !didRunInitialHomeTasks else { return }
            didRunInitialHomeTasks = true
            PasswordGroupsService.seedDefaultGroupsIfNeeded(familyId: familyId, modelContext: modelContext)
            PasswordsSecurityScanner.markModuleOpened(familyId: familyId)
            if PasswordsSecurityScanner.shouldRunWeeklyAutoScan(familyId: familyId) {
                _ = await PasswordsSecurityScanner(modelContext: modelContext, familyId: familyId).runFullSecurityScan()
            }
        }
        .task(id: warningSignature) {
            // Snapshot Sendable costruiti sul main actor (le @Model SwiftData non sono
            // thread-safe); il lavoro pesante (decrypt + forza + duplicati) gira off-main.
            let uid = currentUid
            let snapshots: [PasswordWarningSnapshot] = visibleEntries.map {
                PasswordWarningSnapshot(
                    id: $0.id,
                    familyId: $0.familyId,
                    visibility: $0.visibility,
                    createdBy: $0.createdBy,
                    passwordCipher: $0.passwordCipher,
                    pwnedCount: $0.pwnedCount
                )
            }
            let result = await Task.detached(priority: .utility) {
                PasswordsHomeView.computeWarningEntryIds(snapshots: snapshots, uid: uid)
            }.value
            warningEntryIdsCache = result
        }
        .onAppear {
            PasswordsHomeBadgeAck.acknowledgeCurrent(entries: entries, familyId: familyId, currentUid: currentUid)
        }
        .overlay(alignment: .bottomTrailing) {
            if !isSelecting {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(KBTheme.tint))
                        .shadow(color: KBTheme.tint.opacity(0.35), radius: 10, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 24)
                .accessibilityLabel("Aggiungi password")
            }
        }
    }

    private var passwordEntriesList: some View {
        List {
            ForEach(sections) { section in
                Section {
                    if expandedSectionIds.contains(section.id) || expandedSectionIds.isEmpty {
                        ForEach(section.entries, id: \.id) { entry in
                            row(for: entry)
                                .listRowBackground(KBTheme.cardBackground(colorScheme))
                        }
                    }
                } header: {
                    Button {
                        toggleSection(section.id)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.headerIcon)
                                .foregroundStyle(section.headerTint)
                            Circle()
                                .fill(section.headerTint.opacity(0.35))
                                .frame(width: 8, height: 8)
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                            Text("\(section.entries.count)")
                                .font(.caption2.bold())
                                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                            Spacer()
                            Image(systemName: (expandedSectionIds.contains(section.id) || expandedSectionIds.isEmpty) ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var groupFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: NSLocalizedString("Tutti", comment: "Passwords filter: all"), selected: listScope == .all) {
                    listScope = .all
                }
                filterChip(title: NSLocalizedString("Preferite", comment: "Passwords filter: favorites"), selected: listScope == .favorites) {
                    listScope = .favorites
                }
                filterChip(title: NSLocalizedString("In famiglia", comment: "Passwords filter: family shared"), selected: listScope == .familyShared) {
                    listScope = .familyShared
                }
                filterChip(title: NSLocalizedString("Solo io", comment: "Passwords filter: only me"), selected: listScope == .onlyMinePrivate) {
                    listScope = .onlyMinePrivate
                }
                ForEach(visibleGroups, id: \.id) { group in
                    filterChip(
                        title: (try? group.decryptName()) ?? "Gruppo",
                        selected: {
                            if case .group(let gid) = listScope { return gid == group.id }
                            return false
                        }()
                    ) {
                        listScope = .group(group.id)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func filterChip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? KBTheme.tint.opacity(0.18) : KBTheme.cardBackground(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleSection(_ id: String) {
        if expandedSectionIds.isEmpty {
            expandedSectionIds = Set(sections.map(\.id))
        }
        if expandedSectionIds.contains(id) {
            expandedSectionIds.remove(id)
        } else {
            expandedSectionIds.insert(id)
        }
    }

    @ViewBuilder
    private func row(for entry: PasswordEntry) -> some View {
        let title = (try? entry.decryptTitle()) ?? "—"
        let username = PasswordListFormatting.username(try? entry.decryptUsername())

        Button {
            if isSelecting {
                if selectedIds.contains(entry.id) {
                    selectedIds.remove(entry.id)
                } else {
                    selectedIds.insert(entry.id)
                }
            } else {
                if entry.isFavorite {
                    WatchOtpSyncService.sendOtpPayloadIfNeeded(entry: entry)
                }
                // Distingue "trovato cercando" da "trovato sfogliando": è la sola
                // differenza che dice se il contenuto è davvero a portata di click.
                coordinator.setRetrievalOrigin(searchQuery.isEmpty ? .list : .search)
                coordinator.navigate(to: .passwordDetail(familyId: familyId, entryId: entry.id))
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: selectedIds.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedIds.contains(entry.id) ? KBTheme.tint : .secondary)
                }
                entryIcon(entry: entry)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if entry.isFavorite, !isSelecting {
                            Image(systemName: "star.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("Preferita")
                        }
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                            .lineLimit(1)
                    }
                    Text(username)
                        .font(.subheadline)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if warningEntryIdsCache.contains(entry.id), !isSelecting {
                    Text("!")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.red))
                        .accessibilityLabel("Warning sicurezza")
                }
                if !isSelecting {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isSelecting {
                Button {
                    toggleFavorite(entry)
                } label: {
                    Label(entry.isFavorite ? "Togli preferito" : "Preferito", systemImage: entry.isFavorite ? "star.slash" : "star.fill")
                }
                .tint(.yellow)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isSelecting {
                Button {
                    copyPassword(entry)
                } label: {
                    Label("Copia password", systemImage: "doc.on.doc")
                }
                .tint(.indigo)

                Button(role: .destructive) {
                    deleteEntry(entry)
                } label: {
                    Label("Elimina", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func entryIcon(entry: PasswordEntry) -> some View {
        if let s = entry.iconURL, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFit().padding(6)
                case .failure:
                    Image(systemName: "key.fill").foregroundStyle(KBTheme.tint)
                case .empty:
                    ProgressView()
                @unknown default:
                    Image(systemName: "key.fill").foregroundStyle(KBTheme.tint)
                }
            }
            .background(KBTheme.secondaryBackground(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            let title = (try? entry.decryptTitle()) ?? ""
            Text(initials(for: title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KBTheme.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KBTheme.secondaryBackground(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
    
    private func initials(for title: String) -> String {
        let words = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.isEmpty { return "•" }
        let first = String(words[0].prefix(1)).uppercased()
        if words.count == 1 { return first }
        let second = String(words[1].prefix(1)).uppercased()
        return "\(first)\(second)"
    }

    private func copyPassword(_ entry: PasswordEntry) {
        guard let plain = try? entry.decryptPassword() else {
            coordinator.globalBannerMessage = "Impossibile copiare la password."
            return
        }
        KBClipboard.copy(plain, expiresIn: 60, localOnly: true)
        coordinator.globalBannerMessage = "Password copiata (60 s negli appunti)."
    }
    
    private var warningSignature: String {
        visibleEntries
            .map { "\($0.id):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.pwnedCount ?? -1)" }
            .sorted()
            .joined(separator: "|")
    }
    
    /// Calcola gli id con warning sicurezza (compromesse / deboli / duplicate) a partire da
    /// snapshot Sendable. `nonisolated` così può girare in un `Task.detached` senza bloccare
    /// il main thread su librerie password grandi.
    nonisolated static func computeWarningEntryIds(
        snapshots: [PasswordWarningSnapshot],
        uid: String?
    ) -> Set<String> {
        var compromised: Set<String> = []
        var weak: Set<String> = []
        var clustersByHash: [String: [String]] = [:]

        for snap in snapshots {
            if (snap.pwnedCount ?? 0) > 0 { compromised.insert(snap.id) }

            guard let plain = try? PasswordCypher.decrypt(
                snap.passwordCipher,
                familyId: snap.familyId,
                visibility: snap.visibility,
                createdBy: snap.createdBy,
                familyKeyUserId: uid
            ), !plain.isEmpty else { continue }

            if PasswordStrength.evaluate(plain).level <= .weak {
                weak.insert(snap.id)
            }
            let digest = SHA256.hash(data: Data(plain.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            clustersByHash[hex, default: []].append(snap.id)
        }

        let duplicate = Set(clustersByHash.values.filter { $0.count > 1 }.flatMap { $0 })
        return compromised.union(weak).union(duplicate)
    }

    private func deleteEntry(_ entry: PasswordEntry) {
        entry.deletedAt = .now
        entry.updatedAt = .now
        entry.syncState = .pendingDelete
        try? modelContext.save()
        PasswordsRepository.enqueuePasswordEntryDelete(entryId: entry.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        Task { await NotificationManager.shared.syncPasswordExpiryNotifications(for: entry) }
    }

    private func toggleFavorite(_ entry: PasswordEntry) {
        entry.isFavorite.toggle()
        entry.updatedAt = .now
        entry.syncState = .pendingUpsert
        entry.lastSyncError = nil
        try? modelContext.save()
        PasswordsRepository.enqueuePasswordEntryUpsert(entryId: entry.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    private func deleteSelectedEntries() {
        let ids = selectedIds
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let entry = entries.first(where: { $0.id == id }) else { continue }
            entry.deletedAt = .now
            entry.updatedAt = .now
            entry.syncState = .pendingDelete
            PasswordsRepository.enqueuePasswordEntryDelete(entryId: entry.id, familyId: familyId, modelContext: modelContext)
            Task { await NotificationManager.shared.syncPasswordExpiryNotifications(for: entry) }
        }
        try? modelContext.save()
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        selectedIds = []
        isSelecting = false
        coordinator.globalBannerMessage = ids.count == 1 ? "Password eliminata." : "\(ids.count) password eliminate."
    }
}

/// Badge sullo scudo: usa il layout nativo `.badge` del toolbar (più leggibile del capsule custom).
private struct SecurityToolbarBadgeModifier: ViewModifier {
    let count: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if count > 0 {
            content.badge(count > 99 ? "99+" : "\(count)")
        } else {
            content
        }
    }
}
