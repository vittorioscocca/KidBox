//
//  PasswordDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import LocalAuthentication
import AVFoundation

struct PasswordDetailView: View {
    let familyId: String
    let entryId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var queriedEntries: [PasswordEntry]
    @Query private var familyPasswordEntries: [PasswordEntry]

    @State private var isPasswordVisible = false
    @State private var showEditSheet = false
    @State private var openGeneratorOnEdit = false
    @State private var showDeleteConfirm = false
    @State private var showCreatorOnlyAlert = false
    @State private var showOtpConfigureSheet = false
    @State private var showOtpScannerSheet = false
    @State private var showOtpSavedAlert = false
    @State private var showOtpRemoveConfirm = false
    @State private var otpSecretDraft = ""

    init(familyId: String, entryId: String) {
        self.familyId = familyId
        self.entryId = entryId
        let eid = entryId
        let fid = familyId
        _queriedEntries = Query(
            filter: #Predicate<PasswordEntry> { $0.id == eid && $0.familyId == fid && $0.deletedAt == nil }
        )
        _familyPasswordEntries = Query(
            filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
    }

    private var entry: PasswordEntry? { queriedEntries.first }
    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var canManageEntry: Bool {
        guard let e = entry, let uid = currentUid else { return false }
        return e.createdBy == uid
    }

    var body: some View {
        Group {
            if let e = entry {
                if e.isVisible(to: currentUid) {
                    scrollContent(e: e)
                } else {
                    ContentUnavailableView(
                        "Non disponibile",
                        systemImage: "eye.slash",
                        description: Text("Non hai accesso a questa voce.")
                    )
                }
            } else {
                ContentUnavailableView(
                    "Password non trovata",
                    systemImage: "key.slash",
                    description: Text("Potrebbe essere stata eliminata o non ancora sincronizzata.")
                )
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle(entry.map { navigationTitle(for: $0) } ?? "Dettaglio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let e = entry, e.isVisible(to: currentUid) {
                    Button {
                        toggleFavorite(e)
                    } label: {
                        Image(systemName: e.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(e.isFavorite ? .yellow : .primary)
                    }
                    .accessibilityLabel(e.isFavorite ? "Togli dai preferiti" : "Aggiungi ai preferiti")
                    Button {
                        if canManageEntry {
                            openGeneratorOnEdit = false
                            showEditSheet = true
                        } else {
                            showCreatorOnlyAlert = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                    }
                    Menu {
                        if OTPService.payload(elementID: e.id) != nil {
                            Button(role: .destructive) {
                                if canManageEntry {
                                    showOtpRemoveConfirm = true
                                } else {
                                    showCreatorOnlyAlert = true
                                }
                            } label: {
                                Label("Rimuovi OTP", systemImage: "trash.circle")
                            }
                        } else {
                            Button {
                                otpSecretDraft = ""
                                showOtpConfigureSheet = true
                            } label: {
                                Label("Configura OTP", systemImage: "qrcode.viewfinder")
                            }
                        }
                        Button(role: .destructive) {
                            if canManageEntry {
                                showDeleteConfirm = true
                            } else {
                                showCreatorOnlyAlert = true
                            }
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditPasswordSheet(
                familyId: familyId,
                entryId: entryId,
                openGenerator: openGeneratorOnEdit
            )
        }
        .sheet(isPresented: $showOtpConfigureSheet) {
            otpConfigureSheet
        }
        .sheet(isPresented: $showOtpScannerSheet) {
            otpScannerSheet
        }
        .confirmationDialog("Eliminare questa password?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                deleteEntry()
            }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Rimuovere OTP da questa voce?", isPresented: $showOtpRemoveConfirm, titleVisibility: .visible) {
            Button("Rimuovi OTP", role: .destructive) {
                removeOtpConfiguration()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il codice a tempo non sarà più generato per questa password.")
        }
        .alert("Modifica non consentita", isPresented: $showCreatorOnlyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Solo il creatore della password può modificarla o eliminarla.")
        }
        .alert("OTP configurato", isPresented: $showOtpSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Configurazione OTP salvata con successo.")
        }
    }

    private func navigationTitle(for e: PasswordEntry) -> String {
        let t = (try? e.decryptTitle())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Dettaglio" : t
    }

    @ViewBuilder
    private func scrollContent(e: PasswordEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(KBVisibilityScope.chipLabel(for: PasswordEntry.normalizedPasswordVisibility(e.visibility)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))

                copyButtonsRow(e)

                credentialCard(e)

                passwordSecurityCard(e)

                if let payload = OTPService.payload(elementID: e.id) {
                    OtpLiveCard(payload: payload, colorScheme: colorScheme)
                }

                metaCard(e)
            }
            .padding()
        }
    }

    private func copyButtonsRow(_ e: PasswordEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                copyUsername(e)
            } label: {
                actionButtonLabel("Copia utente", systemImage: "person.crop.rectangle")
            }
            .buttonStyle(.bordered)

            Button {
                copyPassword(e)
            } label: {
                actionButtonLabel("Copia password", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(KBTheme.tint)

            Button {
                if canManageEntry {
                    openGeneratorOnEdit = true
                    showEditSheet = true
                } else {
                    showCreatorOnlyAlert = true
                }
            } label: {
                actionButtonLabel("Cambia password", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func actionButtonLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    private func credentialCard(_ e: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            detailField(title: "Titolo", value: (try? e.decryptTitle()) ?? "—")
            detailField(title: "Nome utente", value: (try? e.decryptUsername()) ?? "—")
            passwordBlock(e)
            websiteBlock(e)
            notesBlock(e)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detailField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            Text(value)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
        }
    }

    private func passwordBlock(_ e: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Password")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                Spacer()
                if isPasswordVisible {
                    Button("Nascondi") {
                        isPasswordVisible = false
                    }
                    .font(.subheadline.weight(.semibold))
                } else {
                    Button("Mostra") {
                        Task { await unlockPasswordVisibility() }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            if isPasswordVisible, let plain = try? e.decryptPassword() {
                Text(plain)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
            } else {
                Text("••••••••")
                    .font(.body.monospaced())
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
        }
    }

    @ViewBuilder
    private func websiteBlock(_ e: PasswordEntry) -> some View {
        let raw = (try? e.decryptWebsite())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sito web")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                Button {
                    openWebsiteURL(raw)
                } label: {
                    Label(raw, systemImage: "safari")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(KBTheme.tint)
            }
        }
    }

    @ViewBuilder
    private func notesBlock(_ e: PasswordEntry) -> some View {
        let raw = (try? e.decryptNotes())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                Text(raw)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
            }
        }
    }

    private func passwordSecurityCard(_ e: PasswordEntry) -> some View {
        let plain = (try? e.decryptPassword()) ?? ""
        let summary = PasswordSecuritySummary.make(
            entry: e,
            familyEntries: familyPasswordEntries,
            currentUid: currentUid,
            decryptedPassword: plain.isEmpty ? nil : plain
        )

        return VStack(alignment: .leading, spacing: 14) {
            Text("Sicurezza password")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KBTheme.primaryText(colorScheme))

            securityInfoRow(
                icon: hibpIcon(summary.hibp),
                tint: hibpTint(summary.hibp, colorScheme: colorScheme),
                title: "Controllo fughe (HIBP)",
                detail: hibpDetailText(summary),
                footnote: hibpFootnote(summary)
            )

            securityInfoRow(
                icon: "square.on.square",
                tint: summary.duplicateOtherCount > 0
                    ? Color(red: 0.95, green: 0.55, blue: 0.12)
                    : KBTheme.green,
                title: "Password duplicata",
                detail: duplicateDetailText(summary.duplicateOtherCount),
                footnote: nil
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Forza stimata")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                StrengthMeterView(password: plain)
                if summary.isWeak {
                    Text("Considera una password più lunga e varia.")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.95, green: 0.45, blue: 0.12))
                }
            }

            Button {
                coordinator.navigate(to: .passwordsSecurity(familyId: familyId))
            } label: {
                Label("Apri report Sicurezza password", systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(KBTheme.tint)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func securityInfoRow(
        icon: String,
        tint: Color,
        title: String,
        detail: String,
        footnote: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
            }
        }
    }

    private func hibpIcon(_ status: PasswordHIBPStatus) -> String {
        switch status {
        case .notChecked: return "questionmark.circle"
        case .safe: return "checkmark.shield.fill"
        case .compromised: return "exclamationmark.triangle.fill"
        }
    }

    private func hibpTint(_ status: PasswordHIBPStatus, colorScheme: ColorScheme) -> Color {
        switch status {
        case .notChecked:
            return KBTheme.secondaryText(colorScheme)
        case .safe:
            return KBTheme.green
        case .compromised:
            return Color(red: 0.85, green: 0.22, blue: 0.22)
        }
    }

    private func hibpDetailText(_ summary: PasswordSecuritySummary) -> String {
        switch summary.hibp {
        case .notChecked:
            return "Non ancora verificata con i database di fughe note."
        case .safe:
            return "Nessuna occorrenza trovata nei controlli eseguiti."
        case .compromised(let count):
            let formatted = count.formatted(.number.locale(kbDeviceLocale()))
            return "Trovata \(formatted) volte in data breach pubblici."
        }
    }

    private func hibpFootnote(_ summary: PasswordSecuritySummary) -> String? {
        switch summary.hibp {
        case .notChecked:
            return "Esegui «Scansiona ora» nel report sicurezza per aggiornare questo stato."
        case .safe, .compromised:
            if let at = summary.hibpCheckedAt {
                return "Ultimo controllo: \(at.formatted(date: .abbreviated, time: .shortened))."
            }
            return nil
        }
    }

    private func duplicateDetailText(_ otherCount: Int) -> String {
        switch otherCount {
        case 0:
            return "Nessun’altra voce nella famiglia usa la stessa password."
        case 1:
            return "Un’altra voce usa la stessa password."
        default:
            return "\(otherCount) altre voci usano la stessa password."
        }
    }

    private func metaCard(_ e: PasswordEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ultimo aggiornamento: \(e.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            if let ex = e.expiresAt {
                Text("Scadenza: \(ex.formatted(date: .abbreviated, time: .omitted))")
                    .font(.footnote)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            Text("Password modificata: \(e.passwordUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openWebsiteURL(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        if !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s) else {
            coordinator.globalBannerMessage = "URL non valido."
            return
        }
        openURL(u)
    }

    @MainActor
    private func unlockPasswordVisibility() async {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            coordinator.globalBannerMessage = "Sblocco non disponibile: imposta un codice o Face ID."
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Mostra la password salvata."
            )
            if ok {
                isPasswordVisible = true
            }
        } catch {
            coordinator.globalBannerMessage = "Sblocco annullato."
        }
    }

    private func copyUsername(_ e: PasswordEntry) {
        let u = (try? e.decryptUsername())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !u.isEmpty else {
            coordinator.globalBannerMessage = "Nessun nome utente da copiare."
            return
        }
        KBClipboard.copy(u, expiresIn: 60, localOnly: true)
        coordinator.globalBannerMessage = "Nome utente copiato (60 s negli appunti)."
    }

    private func copyPassword(_ e: PasswordEntry) {
        guard let plain = try? e.decryptPassword() else {
            coordinator.globalBannerMessage = "Impossibile copiare la password."
            return
        }
        KBClipboard.copy(plain, expiresIn: 60, localOnly: true)
        coordinator.globalBannerMessage = "Password copiata (60 s negli appunti)."
    }

    private func deleteEntry() {
        guard let e = entry else { return }
        guard canManageEntry else {
            coordinator.globalBannerMessage = "Solo il creatore può eliminare questa password."
            return
        }
        e.deletedAt = .now
        e.updatedAt = .now
        e.syncState = .pendingDelete
        try? modelContext.save()
        PasswordsRepository.enqueuePasswordEntryDelete(entryId: e.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        Task { await NotificationManager.shared.syncPasswordExpiryNotifications(for: e) }
        coordinator.globalBannerMessage = "Password eliminata."
        coordinator.navigateBack()
    }

    private func removeOtpConfiguration() {
        guard canManageEntry else {
            showCreatorOnlyAlert = true
            return
        }
        guard let entry else { return }
        OtpKeychainStore.deleteOtpConfig(elementID: entry.id)
        entry.otpConfigCipher = nil
        entry.updatedAt = .now
        entry.syncState = .pendingUpsert
        entry.lastSyncError = nil
        try? modelContext.save()
        PasswordsRepository.enqueuePasswordEntryUpsert(entryId: entry.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        AutoFillSnapshotWriter.scheduleRebuild(modelContext: modelContext)
        WatchOtpSyncService.sendOtpPayloadIfNeeded(entry: entry)
        coordinator.globalBannerMessage = "OTP rimosso."
    }

    private func toggleFavorite(_ e: PasswordEntry) {
        e.isFavorite.toggle()
        e.updatedAt = .now
        e.syncState = .pendingUpsert
        e.lastSyncError = nil
        try? modelContext.save()
        PasswordsRepository.enqueuePasswordEntryUpsert(entryId: e.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    private var otpConfigureSheet: some View {
        NavigationStack {
            Form {
                Section("Chiave Base32") {
                    TextField("Inserisci chiave oppure otpauth://...", text: $otpSecretDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                }
                Section {
                    Button("Scansiona codice QR") {
                        showOtpScannerSheet = true
                    }
                }
            }
            .navigationTitle("Configura OTP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") {
                        showOtpConfigureSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salva") {
                        saveOtpConfiguration()
                    }
                    .disabled(!canManageEntry)
                }
            }
        }
    }

    private var otpScannerSheet: some View {
        NavigationStack {
            QRCodeScannerView { raw in
                guard canManageEntry else {
                    showOtpScannerSheet = false
                    showCreatorOnlyAlert = true
                    return
                }
                guard let config = OTPService.extractOtpConfig(from: raw),
                      let entry else {
                    showOtpScannerSheet = false
                    coordinator.globalBannerMessage = "QR OTP non valido."
                    return
                }
                let saved = OtpKeychainStore.saveOtpConfig(elementID: entry.id, config: config)
                showOtpScannerSheet = false
                if saved {
                    showOtpConfigureSheet = false
                    showOtpSavedAlert = true
                } else {
                    coordinator.globalBannerMessage = "Impossibile salvare la configurazione OTP."
                }
            }
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { showOtpScannerSheet = false }
                }
            }
        }
    }

    private func saveOtpConfiguration() {
        guard canManageEntry else {
            showCreatorOnlyAlert = true
            return
        }
        guard let entry else { return }
        var raw = otpSecretDraft.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !raw.isEmpty else {
            coordinator.globalBannerMessage = "Inserisci una chiave OTP valida."
            return
        }
        if raw.lowercased().hasPrefix("otpauth://") {
            guard let config = OTPService.extractOtpConfig(from: raw),
                  OtpKeychainStore.saveOtpConfig(elementID: entry.id, config: config) else {
                coordinator.globalBannerMessage = "URL OTP non valido."
                return
            }
        } else {
            let config: [String: Any] = [
                "secret": raw,
                "period": 30,
                "digits": 6,
                "algorithm": "SHA1"
            ]
            guard OtpKeychainStore.saveOtpConfig(elementID: entry.id, config: config) else {
                coordinator.globalBannerMessage = "Impossibile salvare la configurazione OTP."
                return
            }
        }
        showOtpConfigureSheet = false
        showOtpSavedAlert = true
    }
}

// MARK: - OTP live (OTPService → TOTPCodeGenerator, stesso stack dell’AutoFill)

private struct OtpLiveCard: View {
    let payload: PasswordOtpPayload
    let colorScheme: ColorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var currentCode: String?
    @State private var remainingSeconds: Int = 0
    @State private var progress: Float = 1
    @State private var lastTimeCounter: Int?
    @State private var timer: Timer?

    var body: some View {
        otpBody(p: payload)
            .onAppear {
                tick(date: Date())
                startTimer()
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    @ViewBuilder
    private func otpBody(p: PasswordOtpPayload) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OTP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(currentCode ?? "···")
                    .font(.title2.monospaced().weight(.semibold))
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                Spacer(minLength: 8)
                Button {
                    copyOtp(currentCode)
                } label: {
                    Label("Copia", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .disabled(currentCode == nil)
            }
            ProgressView(value: max(0, min(1, Double(progress))))
                .tint(remainingSeconds <= 10 ? Color.red : KBTheme.tint)
            Text("Si aggiorna tra \(remainingSeconds) s")
                .font(.caption)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            tick(date: Date())
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick(date: Date) {
        let period = max(1, payload.period)
        let now = date.timeIntervalSince1970
        let timeCounter = Int(floor(now / Double(period)))
        let elapsed = now.truncatingRemainder(dividingBy: Double(period))
        let remaining = max(0, Double(period) - elapsed)
        remainingSeconds = Int(ceil(remaining))
        progress = Float(remaining / Double(period))
        if lastTimeCounter != timeCounter {
            currentCode = OTPService.currentTotpCode(payload: payload, at: date)
            lastTimeCounter = timeCounter
        }
    }

    private func copyOtp(_ code: String?) {
        guard let code, code.count >= 4, code.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) else {
            coordinator.globalBannerMessage = "Codice OTP non disponibile."
            return
        }
        KBClipboard.copy(code.replacingOccurrences(of: " ", with: ""), expiresIn: 60, localOnly: true)
        coordinator.globalBannerMessage = "OTP copiato (60 s negli appunti)."
    }
}
