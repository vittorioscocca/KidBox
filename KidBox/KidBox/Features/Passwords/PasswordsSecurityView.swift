//
//  PasswordsSecurityView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

private struct DuplicateCluster: Identifiable {
    let id: String
    let entries: [PasswordEntry]
}

struct PasswordsSecurityView: View {
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var entries: [PasswordEntry]
    @State private var isScanning = false
    @State private var scanMessage: String?

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _entries = Query(
            filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil },
            sort: [SortDescriptor(\PasswordEntry.updatedAt, order: .reverse)]
        )
    }

    private var visibleEntries: [PasswordEntry] {
        entries.filter { $0.isVisible(to: currentUid) }
    }

    private var compromisedEntries: [PasswordEntry] {
        visibleEntries.filter { ($0.pwnedCount ?? 0) > 0 }
    }

    private var weakEntries: [PasswordEntry] {
        visibleEntries.filter {
            guard let plain = try? $0.decryptPassword() else { return false }
            return PasswordStrength.evaluate(plain).level <= .weak
        }
    }

    private var duplicateClusters: [DuplicateCluster] {
        let detector = DuplicateDetector.forCurrentUser(entries: visibleEntries)
        return detector.allDuplicateClusters().map { cluster in
            let id = cluster.map(\.id).sorted().joined(separator: "|")
            return DuplicateCluster(id: id, entries: cluster)
        }
    }

    var body: some View {
        List {
            if let scanMessage, !scanMessage.isEmpty {
                Section {
                    Text(scanMessage)
                        .font(.footnote)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                .listRowBackground(KBTheme.cardBackground(colorScheme))
            }

            compromisedSection
            duplicateSection
            weakSection

            Section("Privacy check HIBP") {
                Text("La password in chiaro non lascia mai il dispositivo: KidBox invia solo i primi 5 caratteri dell'hash SHA-1 con modello k-anonymity.")
                    .font(.footnote)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            .listRowBackground(KBTheme.cardBackground(colorScheme))
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Sicurezza password")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await scanNow() }
                } label: {
                    if isScanning {
                        ProgressView()
                    } else {
                        Text("Scansiona ora")
                    }
                }
                .disabled(isScanning)
            }
        }
        .onAppear {
            PasswordsSecurityScanner.markModuleOpened(familyId: familyId)
        }
    }

    @ViewBuilder
    private var compromisedSection: some View {
        Section("🔴 Compromesse") {
            if compromisedEntries.isEmpty {
                Text("Nessuna password compromessa rilevata.")
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            } else {
                ForEach(compromisedEntries, id: \.id) { entry in
                    securityRow(entry: entry, subtitle: compromisedText(for: entry.pwnedCount ?? 0))
                }
            }
        }
        .listRowBackground(KBTheme.cardBackground(colorScheme))
    }

    @ViewBuilder
    private var duplicateSection: some View {
        Section("🟡 Duplicate") {
            if duplicateClusters.isEmpty {
                Text("Nessuna password duplicata trovata.")
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            } else {
                ForEach(duplicateClusters) { cluster in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cluster da \(cluster.entries.count) voci")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                        ForEach(cluster.entries, id: \.id) { entry in
                            securityRow(entry: entry, subtitle: "Password uguale ad altre credenziali")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listRowBackground(KBTheme.cardBackground(colorScheme))
    }

    @ViewBuilder
    private var weakSection: some View {
        Section("🟠 Deboli") {
            if weakEntries.isEmpty {
                Text("Nessuna password debole trovata.")
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            } else {
                ForEach(weakEntries, id: \.id) { entry in
                    securityRow(entry: entry, subtitle: "Forza password: \(strengthLabel(for: entry))")
                }
            }
        }
        .listRowBackground(KBTheme.cardBackground(colorScheme))
    }

    private func strengthLabel(for entry: PasswordEntry) -> String {
        guard let plain = try? entry.decryptPassword() else { return "Debole" }
        return PasswordStrength.evaluate(plain).level.label
    }

    @ViewBuilder
    private func securityRow(entry: PasswordEntry, subtitle: String) -> some View {
        let title = (try? entry.decryptTitle())?.trimmingCharacters(in: .whitespacesAndNewlines)
        Button {
            coordinator.navigate(to: .passwordDetail(familyId: familyId, entryId: entry.id))
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text((title?.isEmpty == false ? title! : "Password"))
                    .foregroundStyle(KBTheme.primaryText(colorScheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
        }
        .buttonStyle(.plain)
    }

    private func compromisedText(for count: Int) -> String {
        let formatted = count.formatted(.number.locale(kbDeviceLocale()))
        return "Trovata \(formatted) volte in data breach"
    }

    private func scanNow() async {
        isScanning = true
        defer { isScanning = false }
        let scanner = PasswordsSecurityScanner(modelContext: modelContext, familyId: familyId)
        let newly = await scanner.runFullSecurityScan()
        if newly > 0 {
            scanMessage = "Scan completato: trovate \(newly) nuove password compromesse."
        } else {
            scanMessage = "Scan completato."
        }
    }
}

extension PasswordsSecurityView {
    /// Totale issue visibili per badge (compromesse + duplicate + deboli).
    static func issueCount(entries: [PasswordEntry], currentUid: String?) -> Int {
        let visible = entries.filter { $0.deletedAt == nil && $0.isVisible(to: currentUid) }
        let compromised = visible.filter { ($0.pwnedCount ?? 0) > 0 }.count
        let weak = visible.filter {
            guard let plain = try? $0.decryptPassword() else { return false }
            return PasswordStrength.evaluate(plain).level <= .weak
        }.count
        let duplicateEntries = Set(
            DuplicateDetector(entries: visible, currentUid: currentUid)
                .allDuplicateClusters()
                .flatMap { $0.map(\.id) }
        ).count
        return compromised + weak + duplicateEntries
    }
}
