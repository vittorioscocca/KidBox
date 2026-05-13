//
//  CredentialProviderViewController.swift
//  KidBoxAutoFill
//

import AuthenticationServices
import LocalAuthentication
import SwiftUI
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {

    private var hosting: UIHostingController<AnyView>?
    private var credentialListTask: Task<Void, Never>?
    private var otpListTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    // MARK: - Configuration onboarding (Impostazioni → AutoFill)

    override func prepareInterfaceForExtensionConfiguration() {
        let root = AnyView(
            AutoFillConfigureOnboardingView {
                self.extensionContext.completeExtensionConfigurationRequest()
            }
            .environment(\.colorScheme, traitCollection.userInterfaceStyle == .dark ? .dark : .light)
        )
        embed(root)
    }

    // MARK: - Password list

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        // UI sincrona subito: senza questo iOS può presentare uno sheet vuoto o chiudere l’estensione
        // mentre il Task asincrono carica keychain / snapshot.
        embedLoading()
        credentialListTask?.cancel()
        credentialListTask = Task { @MainActor in
            await runPrepareCredentialList(serviceIdentifiers: serviceIdentifiers)
        }
    }

    @MainActor
    private func runPrepareCredentialList(serviceIdentifiers: [ASCredentialServiceIdentifier]) async {
        let snapshotState = await Self.loadSnapshotState()
        guard !Task.isCancelled else { return }
        switch snapshotState {
        case .locked:
            embedLocked()
            return
        case .decryptFailed:
            embedDecryptFailed()
            return
        case .loaded(let snapshot):
            guard await evaluateBiometry() else {
                cancelUserCanceled()
                return
            }
            let requestHost = Self.normalizedHost(from: serviceIdentifiers.first)
            let sorted = Self.sortItems(snapshot.items, requestHost: requestHost)
            let root = AnyView(
                AutoFillPasswordPickerView(
                    items: sorted,
                    requestHost: requestHost,
                    faviconURL: { host in KidBoxAutoFillPaths.faviconFileURL(forHost: host) },
                    onSelect: { [weak self] item in
                        guard let self else { return }
                        let cred = ASPasswordCredential(user: item.username, password: item.password)
                        self.extensionContext.completeRequest(withSelectedCredential: cred, completionHandler: nil)
                    },
                    onCancel: { [weak self] in
                        self?.cancelUserCanceled()
                    }
                )
                .environment(\.colorScheme, self.traitCollection.userInterfaceStyle == .dark ? .dark : .light)
            )
            embed(root)
        }
    }

    // MARK: - QuickType without UI

    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        Task { await runProvideWithoutUI(identity: credentialIdentity) }
    }

    @MainActor
    private func runProvideWithoutUI(identity: ASPasswordCredentialIdentity) async {
        guard let key = SharedFamilyKey.loadMirroredFamilyKey() else {
            cancelInteractionRequired()
            return
        }
        let snapshot: AutoFillSnapshot
        do {
            snapshot = try AutoFillSnapshotFileStore.loadDecrypted(using: key)
        } catch {
            cancelInteractionRequired()
            return
        }
        guard let id = identity.recordIdentifier, let item = snapshot.items.first(where: { $0.id == id }) else {
            cancelInteractionRequired()
            return
        }
        if KidBoxAutoFillPreferences.requireBiometricForQuickType {
            cancelInteractionRequired()
            return
        }
        let cred = ASPasswordCredential(user: item.username, password: item.password)
        extensionContext.completeRequest(withSelectedCredential: cred, completionHandler: nil)
    }

    // MARK: - QuickType → Face ID then fill

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        Task { await runPrepareInterface(for: credentialIdentity) }
    }

    @MainActor
    private func runPrepareInterface(for credentialIdentity: ASPasswordCredentialIdentity) async {
        guard let key = SharedFamilyKey.loadMirroredFamilyKey() else {
            embedLocked()
            return
        }
        let snapshot: AutoFillSnapshot
        do {
            snapshot = try AutoFillSnapshotFileStore.loadDecrypted(using: key)
        } catch {
            cancelUserCanceled()
            return
        }
        guard let id = credentialIdentity.recordIdentifier, let item = snapshot.items.first(where: { $0.id == id }) else {
            cancelUserCanceled()
            return
        }
        guard await evaluateBiometry() else {
            cancelUserCanceled()
            return
        }
        let cred = ASPasswordCredential(user: item.username, password: item.password)
        extensionContext.completeRequest(withSelectedCredential: cred, completionHandler: nil)
    }

    // MARK: - OTP (iOS 18+)

    @available(iOS 18.0, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        embedLoading()
        otpListTask?.cancel()
        otpListTask = Task { @MainActor in
            await runPrepareOTPList(serviceIdentifiers: serviceIdentifiers)
        }
    }

    @MainActor
    @available(iOS 18.0, *)
    private func runPrepareOTPList(serviceIdentifiers: [ASCredentialServiceIdentifier]) async {
        let snapshotState = await Self.loadSnapshotState()
        guard !Task.isCancelled else { return }
        let snapshot: AutoFillSnapshot
        switch snapshotState {
        case .locked:
            embedLocked()
            return
        case .decryptFailed:
            embedDecryptFailed()
            return
        case .loaded(let value):
            snapshot = value
        }
        guard await evaluateBiometry() else {
            cancelUserCanceled()
            return
        }
        let requestHost = Self.normalizedHost(from: serviceIdentifiers.first)
        let otpRows: [AutoFillOTPDisplayRow] = snapshot.items.compactMap { item in
            guard let otp = item.otp else { return nil }
            // Stesso TOTP dell’app (`OTPService` → `TOTPCodeGenerator`); l’estensione non importa `OTPService` (SwiftData/PasswordEntry).
            guard let code = TOTPCodeGenerator.currentCode(
                secretBase32: otp.secret,
                digits: otp.digits,
                period: otp.period,
                algorithm: otp.algorithm
            ) else { return nil }
            if let rh = requestHost, !rh.isEmpty {
                guard let h = item.website, AutoFillWebsiteHost.host(h, matchesRequest: rh) else { return nil }
            }
            return AutoFillOTPDisplayRow(id: item.id, title: item.title, username: item.username, website: item.website, code: code)
        }
        let sorted = otpRows.sorted { lhs, rhs in
            let lm = lhs.website.map { AutoFillWebsiteHost.host($0, matchesRequest: requestHost) } ?? false
            let rm = rhs.website.map { AutoFillWebsiteHost.host($0, matchesRequest: requestHost) } ?? false
            if lm != rm { return lm && !rm }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        let root = AnyView(
            AutoFillOTPPickerView(
                rows: sorted,
                onSelect: { [weak self] row in
                    guard let self else { return }
                    let cred = ASOneTimeCodeCredential(code: row.code)
                    self.extensionContext.completeOneTimeCodeRequest(using: cred, completionHandler: nil)
                },
                onCancel: { [weak self] in
                    self?.cancelUserCanceled()
                }
            )
            .environment(\.colorScheme, self.traitCollection.userInterfaceStyle == .dark ? .dark : .light)
        )
        embed(root)
    }

    // MARK: - Helpers

    private func embed(_ root: AnyView) {
        hosting?.willMove(toParent: nil)
        hosting?.view.removeFromSuperview()
        hosting?.removeFromParent()
        let h = UIHostingController(rootView: root)
        h.view.backgroundColor = .clear
        addChild(h)
        h.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(h.view)
        NSLayoutConstraint.activate([
            h.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            h.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            h.view.topAnchor.constraint(equalTo: view.topAnchor),
            h.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        h.didMove(toParent: self)
        hosting = h
    }

    private func embedLocked() {
        let root = AnyView(
            AutoFillLockedView()
                .environment(\.colorScheme, traitCollection.userInterfaceStyle == .dark ? .dark : .light)
        )
        embed(root)
    }

    private func embedLoading() {
        let root = AnyView(
            AutoFillLoadingView()
                .environment(\.colorScheme, traitCollection.userInterfaceStyle == .dark ? .dark : .light)
        )
        embed(root)
    }

    private func embedDecryptFailed() {
        let root = AnyView(
            AutoFillDecryptFailedView(onDismiss: { [weak self] in
                self?.cancelUserCanceled()
            })
            .environment(\.colorScheme, traitCollection.userInterfaceStyle == .dark ? .dark : .light)
        )
        embed(root)
    }

    private func evaluateBiometry() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        do {
            return try await ctx.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Sblocca KidBox per AutoFill."
            )
        } catch {
            return false
        }
    }

    private func cancelUserCanceled() {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue
            )
        )
    }

    private func cancelInteractionRequired() {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    private static func normalizedHost(from id: ASCredentialServiceIdentifier?) -> String? {
        guard let id else { return nil }
        return AutoFillWebsiteHost.normalizedHost(from: id.identifier)
    }

    private static func sortItems(_ items: [AutoFillSnapshot.Item], requestHost: String?) -> [AutoFillSnapshot.Item] {
        items.sorted { lhs, rhs in
            let lm = lhs.website.map { AutoFillWebsiteHost.host($0, matchesRequest: requestHost) } ?? false
            let rm = rhs.website.map { AutoFillWebsiteHost.host($0, matchesRequest: requestHost) } ?? false
            if lm != rm { return lm && !rm }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private enum SnapshotState {
        case locked
        case decryptFailed
        case loaded(AutoFillSnapshot)
    }

    private static func loadSnapshotState() async -> SnapshotState {
        await Task.detached(priority: .userInitiated) {
            guard let key = SharedFamilyKey.loadMirroredFamilyKey() else {
                return .locked
            }
            do {
                return .loaded(try AutoFillSnapshotFileStore.loadDecrypted(using: key))
            } catch {
                return .decryptFailed
            }
        }.value
    }
}

// MARK: - SwiftUI (AutoFill)

private struct AutoFillConfigureOnboardingView: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.horizontal.fill")
                .font(.system(size: 44))
                .foregroundStyle(KBTheme.bubbleTint)
            Text("Apri KidBox per accedere e sbloccare il tuo vault")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Dopo il primo accesso in app, le password saranno disponibili in AutoFill.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: onContinue) {
                Text("Ho capito")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(KBTheme.bubbleTint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme))
    }
}

private struct AutoFillLockedView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(KBTheme.bubbleTint)
            Text("Apri KidBox per attivare AutoFill")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme))
    }
}

private struct AutoFillLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Caricamento password…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme))
    }
}

private struct AutoFillDecryptFailedView: View {
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Impossibile leggere le password salvate")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Apri KidBox una volta per sincronizzare il vault, poi riprova.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: onDismiss) {
                Text("Chiudi")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(KBTheme.bubbleTint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme))
    }
}

private struct AutoFillPasswordPickerView: View {
    let items: [AutoFillSnapshot.Item]
    let requestHost: String?
    let faviconURL: (String) -> URL?
    let onSelect: (AutoFillSnapshot.Item) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    private var filtered: [AutoFillSnapshot.Item] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            item.title.lowercased().contains(q)
                || item.username.lowercased().contains(q)
                || (item.website?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        HStack(spacing: 12) {
                            faviconView(for: item.website)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(item.username)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .navigationTitle("KidBox")
            .searchable(text: $query, prompt: Text("Cerca"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { onCancel() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KBTheme.background(colorScheme))
    }

    @ViewBuilder
    private func faviconView(for host: String?) -> some View {
        if let host,
           let url = faviconURL(host),
           FileManager.default.fileExists(atPath: url.path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                case .failure:
                    Image(systemName: "globe")
                        .foregroundStyle(KBTheme.bubbleTint)
                case .empty:
                    ProgressView()
                        .scaleEffect(0.8)
                @unknown default:
                    Image(systemName: "globe")
                        .foregroundStyle(KBTheme.bubbleTint)
                }
            }
        } else {
            Image(systemName: "globe")
                .foregroundStyle(KBTheme.bubbleTint)
        }
    }
}

@available(iOS 18.0, *)
private struct AutoFillOTPDisplayRow: Identifiable {
    let id: String
    let title: String
    let username: String
    let website: String?
    let code: String
}

@available(iOS 18.0, *)
private struct AutoFillOTPPickerView: View {
    let rows: [AutoFillOTPDisplayRow]
    let onSelect: (AutoFillOTPDisplayRow) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            List {
                ForEach(rows) { row in
                    Button {
                        onSelect(row)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.title)
                                .font(.body.weight(.semibold))
                            Text(row.code)
                                .font(.title2.monospacedDigit().weight(.bold))
                                .foregroundStyle(KBTheme.bubbleTint)
                            if !row.username.isEmpty {
                                Text(row.username)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Codici OTP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { onCancel() }
                }
            }
        }
        .background(KBTheme.background(colorScheme))
    }
}
