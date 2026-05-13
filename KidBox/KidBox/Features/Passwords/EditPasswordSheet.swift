//
//  EditPasswordSheet.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct EditPasswordSheet: View {
    let familyId: String
    let entryId: String
    let openGenerator: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query private var queriedEntries: [PasswordEntry]
    @Query private var groups: [PasswordGroup]
    @Query private var members: [KBFamilyMember]

    @State private var titleText = ""
    @State private var username = ""
    @State private var password = ""
    @State private var website = ""
    @State private var notes = ""
    @State private var groupSelection: String? = nil
    @State private var showGroupPicker = false
    @State private var selectedVisibilityScope = KBVisibilityScope.family
    @State private var selectedVisibilityMemberIds: Set<String> = []
    @State private var isVisibilitySheetPresented = false
    @State private var hasExpiry = false
    @State private var expiresAt = Date.now
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var passwordAtLoad = ""
    @State private var didHydrate = false
    @State private var generatorOptions = PasswordGeneratorOptions()
    @State private var isGeneratorExpanded = false
    /// Dopo "Genera password" la password resta visibile in chiaro.
    @State private var showPasswordInClearText = false

    init(familyId: String, entryId: String, openGenerator: Bool = false) {
        self.familyId = familyId
        self.entryId = entryId
        self.openGenerator = openGenerator
        let eid = entryId
        let fid = familyId
        _queriedEntries = Query(
            filter: #Predicate<PasswordEntry> { $0.id == eid && $0.familyId == fid && $0.deletedAt == nil }
        )
        _groups = Query(
            filter: #Predicate<PasswordGroup> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordGroup.updatedAt, order: .reverse)]
        )
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }

    private var entry: PasswordEntry? { queriedEntries.first }

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var selectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }

    private var visibleGroups: [PasswordGroup] {
        let uid = currentUid
        return groups.filter { $0.isVisible(to: uid) }
    }

    private var sortedGroups: [PasswordGroup] {
        visibleGroups.sorted { a, b in
            let na = (try? a.decryptName()) ?? a.id
            let nb = (try? b.decryptName()) ?? b.id
            return na.localizedCaseInsensitiveCompare(nb) == .orderedAscending
        }
    }

    private var canSave: Bool {
        !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && entry != nil
            && isCreator
    }

    private var isCreator: Bool {
        guard let e = entry, let uid = currentUid else { return false }
        return e.createdBy == uid
    }

    var body: some View {
        NavigationStack {
            Group {
                if entry == nil {
                    ContentUnavailableView(
                        "Voce non trovata",
                        systemImage: "key.slash",
                        description: Text("Potrebbe essere stata eliminata.")
                    )
                } else if !isCreator {
                    ContentUnavailableView(
                        "Modifica non consentita",
                        systemImage: "lock.shield",
                        description: Text("Solo il creatore può modificare questa password.")
                    )
                } else {
                    formContent
                }
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle("Modifica password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") { Task { await save() } }
                        .disabled(isSaving || !canSave)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Salvataggio…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .sheet(isPresented: $isVisibilitySheetPresented) {
                VisibilityPickerSheet(
                    selectedScope: $selectedVisibilityScope,
                    selectedMemberIds: $selectedVisibilityMemberIds,
                    members: selectableMembers,
                    currentUid: currentUid,
                    scopeSectionTitle: "Chi può vedere questa password",
                    allowedScopes: [KBVisibilityScope.family, KBVisibilityScope.members, KBVisibilityScope.onlyCreator]
                ) { scope, memberIds in
                    selectedVisibilityScope = scope
                    selectedVisibilityMemberIds = memberIds
                }
            }
            .sheet(isPresented: $showGroupPicker) {
                GroupPickerSheet(
                    familyId: familyId,
                    selectedGroupId: $groupSelection,
                    passwordVisibility: selectedVisibilityScope
                )
            }
            .onAppear {
                isGeneratorExpanded = openGenerator
                hydrateIfNeeded()
            }
            .onChange(of: queriedEntries) { _, new in
                guard new.first != nil else { return }
                if !didHydrate {
                    hydrateIfNeeded()
                }
            }
        }
    }

    private var formContent: some View {
        Form {
            Section("Visibilità") {
                Button {
                    isVisibilitySheetPresented = true
                } label: {
                    HStack {
                        Text(KBVisibilityScope.chipLabel(for: selectedVisibilityScope))
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Credenziali") {
                TextField("Titolo", text: $titleText)
                TextField("Nome utente", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Group {
                    if showPasswordInClearText {
                        TextField("Password", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                }
                .onChange(of: password) { _, new in
                    if new.isEmpty { showPasswordInClearText = false }
                }
                StrengthMeterView(password: password)
                DisclosureGroup("Generatore", isExpanded: $isGeneratorExpanded) {
                    Stepper(value: $generatorOptions.length, in: 8...64) {
                        Text("Lunghezza: \(generatorOptions.length)")
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                    }
                    Toggle("Maiuscole (A–Z)", isOn: $generatorOptions.includeUppercase)
                    Toggle("Minuscole (a–z)", isOn: $generatorOptions.includeLowercase)
                    Toggle("Numeri", isOn: $generatorOptions.includeNumbers)
                    Toggle("Simboli", isOn: $generatorOptions.includeSymbols)
                    Toggle("Escludi caratteri ambigui (0 O 1 l I)", isOn: $generatorOptions.excludeAmbiguous)
                    HStack {
                        Button("Genera password") {
                            password = PasswordGenerator.generate(options: generatorOptions)
                            showPasswordInClearText = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(KBTheme.tint)
                        Spacer()
                    }
                }
            }

            Section("Sito web") {
                TextField("https://…", text: $website)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Gruppo") {
                Button {
                    showGroupPicker = true
                } label: {
                    HStack {
                        Text(selectedGroupLabel())
                            .foregroundStyle(KBTheme.primaryText(colorScheme))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Note") {
                TextField("Note (opzionale)", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section {
                Toggle("Data di scadenza", isOn: $hasExpiry)
                if hasExpiry {
                    DatePicker("Scade il", selection: $expiresAt, displayedComponents: [.date])
                }
            }

            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
    }

    private func hydrateIfNeeded() {
        guard !didHydrate, let e = entry else { return }
        didHydrate = true
        titleText = (try? e.decryptTitle()) ?? ""
        username = (try? e.decryptUsername()) ?? ""
        let pw = (try? e.decryptPassword()) ?? ""
        password = pw
        passwordAtLoad = pw
        website = (try? e.decryptWebsite()) ?? ""
        notes = (try? e.decryptNotes()) ?? ""
        selectedVisibilityScope = PasswordEntry.normalizedPasswordVisibility(e.visibility)
        selectedVisibilityMemberIds = Set(e.visibilityMemberIds)
        if let gid = e.groupId, !gid.isEmpty {
            groupSelection = gid
        } else {
            groupSelection = nil
        }
        if let ex = e.expiresAt {
            hasExpiry = true
            expiresAt = ex
        } else {
            hasExpiry = false
            expiresAt = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
        }
    }

    private var encryptionCreatedBy: String {
        guard let e = entry else { return currentUid ?? "" }
        return e.createdBy.isEmpty ? (currentUid ?? "") : e.createdBy
    }

    @MainActor
    private func save() async {
        errorMessage = nil
        guard let e = entry else { return }
        guard isCreator else {
            errorMessage = "Solo il creatore può modificare questa password."
            return
        }
        let vis = PasswordEntry.normalizedPasswordVisibility(selectedVisibilityScope)
        let visMemberIds = vis == KBVisibilityScope.members ? Array(selectedVisibilityMemberIds) : []
        let titlePlain = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdBy = encryptionCreatedBy
        if vis == KBVisibilityScope.family, let selectedGroup = sortedGroups.first(where: { $0.id == groupSelection }) {
            let groupVisibility = PasswordEntry.normalizedPasswordVisibility(selectedGroup.visibility)
            if groupVisibility != KBVisibilityScope.family {
                errorMessage = "Una password condivisa con la famiglia può appartenere solo a un gruppo famiglia."
                return
            }
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let resolvedGroupId: String? = groupSelection ?? PasswordGroupsService.resolveUnassignedGroup(familyId: familyId, modelContext: modelContext)?.id

            let titleCipher = try PasswordCypher.encrypt(titlePlain, familyId: familyId, visibility: vis, createdBy: createdBy)
            let passCipher = try PasswordCypher.encrypt(password, familyId: familyId, visibility: vis, createdBy: createdBy)
            let userCipher: Data? = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : try PasswordCypher.encrypt(username, familyId: familyId, visibility: vis, createdBy: createdBy)
            let webCipher: Data? = website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : try PasswordCypher.encrypt(website, familyId: familyId, visibility: vis, createdBy: createdBy)
            let notesCipher: Data? = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : try PasswordCypher.encrypt(notes, familyId: familyId, visibility: vis, createdBy: createdBy)

            e.titleCipher = titleCipher
            e.usernameCipher = userCipher
            e.passwordCipher = passCipher
            e.websiteCipher = webCipher
            e.notesCipher = notesCipher
            e.visibility = vis
            e.visibilityMemberIds = visMemberIds
            e.groupId = resolvedGroupId
            e.iconURL = await resolveFaviconURL(from: website)
            e.expiresAt = hasExpiry ? expiresAt : nil
            e.updatedAt = .now
            if password != passwordAtLoad {
                e.passwordUpdatedAt = .now
            }
            e.syncState = .pendingUpsert

            try modelContext.save()
            PasswordsRepository.enqueuePasswordEntryUpsert(entryId: e.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            Task { await NotificationManager.shared.syncPasswordExpiryNotifications(for: e) }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectedGroupLabel() -> String {
        guard let groupSelection else {
            return NSLocalizedString("passwords.group.unassigned", comment: "")
        }
        return (try? sortedGroups.first(where: { $0.id == groupSelection })?.decryptName()) ?? "Gruppo"
    }

    private func resolveFaviconURL(from websiteRaw: String) async -> String? {
        guard let normalized = normalizeWebsite(websiteRaw),
              let host = normalized.host,
              !host.isEmpty else {
            return nil
        }

        if let html = await fetchHtml(from: normalized),
           let htmlIcon = parseBestIconHref(from: html, baseURL: normalized) {
            return htmlIcon.absoluteString
        }

        if let origin = baseOrigin(from: normalized),
           let faviconURL = URL(string: "/favicon.ico", relativeTo: origin),
           await isReachable(url: faviconURL) {
            return faviconURL.absoluteURL.absoluteString
        }
        if let origin = baseOrigin(from: normalized),
           let appleIconURL = URL(string: "/apple-touch-icon.png", relativeTo: origin),
           await isReachable(url: appleIconURL) {
            return appleIconURL.absoluteURL.absoluteString
        }

        return "https://www.google.com/s2/favicons?domain=\(host)&sz=64"
    }

    private func normalizeWebsite(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    private func baseOrigin(from url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return URL(string: "\(scheme)://\(host)")
    }

    private func fetchHtml(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5
        request.setValue("KidBox/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...399).contains(http.statusCode) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func isReachable(url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.5
        request.setValue("KidBox/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...399).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func parseBestIconHref(from html: String, baseURL: URL) -> URL? {
        guard let iconRegex = try? NSRegularExpression(
            pattern: #"<link\b[^>]*\brel\s*=\s*["'][^"']*icon[^"']*["'][^>]*\bhref\s*=\s*["']([^"']+)["'][^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = iconRegex.matches(in: html, options: [], range: range)
        let hrefs: [String] = matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let hrefRange = match.range(at: 1)
            guard hrefRange.location != NSNotFound else { return nil }
            return ns.substring(with: hrefRange)
        }
        let sorted = hrefs.sorted { lhs, rhs in
            iconPriority(lhs) < iconPriority(rhs)
        }
        for href in sorted {
            if let resolved = URL(string: href, relativeTo: baseURL)?.absoluteURL {
                return resolved
            }
        }
        return nil
    }

    private func iconPriority(_ href: String) -> Int {
        let lowered = href.lowercased()
        if lowered.contains("apple-touch-icon") { return 0 }
        if lowered.contains("favicon") { return 1 }
        return 2
    }
}
