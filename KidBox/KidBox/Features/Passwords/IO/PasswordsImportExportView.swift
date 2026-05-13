import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import LocalAuthentication
import FirebaseAuth

struct PasswordsImportExportView: View {
    let familyId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var entries: [PasswordEntry]
    @Query private var groups: [PasswordGroup]

    @State private var encryptExport = true
    @State private var exportPassphrase = ""
    @State private var showPlainExportWarning = false
    @State private var isWorking = false
    @State private var exportedURL: URL?

    @State private var showImporter = false
    @State private var importPassphrase = ""
    @State private var selectedImportURL: URL?
    @State private var importPreview: ImportPreview?
    @State private var mergeStrategy: MergeStrategy = .skipDuplicates

    @State private var showImportError = false
    @State private var importErrorMessage = ""

    private var currentUid: String? { Auth.auth().currentUser?.uid }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _entries = Query(filter: #Predicate<PasswordEntry> { $0.familyId == fid && $0.deletedAt == nil })
        _groups = Query(filter: #Predicate<PasswordGroup> { $0.familyId == fid && $0.deletedAt == nil })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Esporta") {
                    Toggle("Cifra con passphrase", isOn: $encryptExport)
                    if encryptExport {
                        SecureField("Passphrase export", text: $exportPassphrase)
                    }
                    if let exportedURL {
                        ShareLink(item: exportedURL) {
                            Label("Condividi file esportato", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button("Esporta password") {
                        if encryptExport {
                            Task { await startExport() }
                        } else {
                            showPlainExportWarning = true
                        }
                    }
                    .disabled(isWorking || (encryptExport && exportPassphrase.isEmpty))
                }

                Section("Importa") {
                    SecureField("Passphrase import (se file cifrato)", text: $importPassphrase)
                    Button("Seleziona file .kbpw/.txt") { showImporter = true }
                        .disabled(isWorking)
                    if let preview = importPreview {
                        Text("Record da importare: \(preview.totalCount)")
                        Text("Conflitti: \(preview.conflicts.count)")
                        Text("Gruppi nuovi: \(preview.groupsToCreate.count)")
                    }
                }
            }
            .navigationTitle("Importa/Esporta")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Chiudi") { dismiss() } }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, .kidBoxKbpw],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                selectedImportURL = url
                Task { await prepareImportPreview(url: url) }
            }
            .sheet(
                isPresented: Binding(
                    get: { importPreview != nil },
                    set: { isPresented in
                        if !isPresented { importPreview = nil }
                    }
                )
            ) {
                if let preview = importPreview {
                    importPreviewSheet(preview)
                }
            }
            .alert("⚠️ Il file conterrà tutte le tue password in chiaro. Conservalo solo in luoghi affidabili.", isPresented: $showPlainExportWarning) {
                Button("Annulla", role: .cancel) {}
                Button("Continua", role: .destructive) { Task { await startExport() } }
            }
            .alert("Import non riuscito", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage)
            }
            .overlay {
                if isWorking {
                    ProgressView("Operazione in corso…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder
    private func importPreviewSheet(_ preview: ImportPreview) -> some View {
        NavigationStack {
            List {
                Section("Anteprima import") {
                    Text("Verranno importate \(preview.totalCount) password.")
                    if !preview.groupsToCreate.isEmpty {
                        Text("Gruppi da creare: \(preview.groupsToCreate.joined(separator: ", "))")
                    }
                    if preview.skippedOnlyCreatorFromOtherUsers > 0 {
                        Text("Le password 'Solo io' di altri utenti verranno ignorate: \(preview.skippedOnlyCreatorFromOtherUsers).")
                            .foregroundStyle(.orange)
                    }
                    if !preview.legacyAmbiguousRecordIndices.isEmpty {
                        let refs = preview.legacyAmbiguousRecordIndices.map { "N\($0)" }.joined(separator: ", ")
                        Text("Trovato testo ambiguo in \(preview.legacyAmbiguousRecordIndices.count) note — verifica i record \(refs).")
                            .foregroundStyle(.orange)
                    }
                }
                if !preview.conflicts.isEmpty {
                    Section("Conflitti Title + Username") {
                        ForEach(preview.conflicts.prefix(30)) { conflict in
                            Text("• \(conflict.title) / \(conflict.username)")
                        }
                    }
                }
                if !preview.rowErrors.isEmpty {
                    Section("Errori di parsing") {
                        ForEach(preview.rowErrors) { err in
                            Text("• Riga \(err.row): \(err.message)")
                        }
                    }
                }
                Section("Strategia merge") {
                    Picker("Merge strategy", selection: $mergeStrategy) {
                        Text("Salta duplicati").tag(MergeStrategy.skipDuplicates)
                        Text("Sovrascrivi per Title+Username").tag(MergeStrategy.overwriteByTitleUsername)
                        Text("Mantieni entrambi").tag(MergeStrategy.keepBoth)
                    }
                    .pickerStyle(.inline)
                }
            }
            .navigationTitle("Anteprima")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { importPreview = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Importa \(preview.totalCount) password") { Task { await commitImport(preview: preview) } }
                        .disabled(isWorking || preview.totalCount == 0)
                }
            }
        }
    }

    private func startExport() async {
        guard await authenticateUser(reason: "Autorizza l'esportazione password.") else { return }
        guard let uid = currentUid else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let exporter = PasswordsTxtExporter(
                familyId: familyId,
                currentUid: uid,
                passphrase: encryptExport ? exportPassphrase : nil
            )
            exportedURL = try await exporter.export(entries: entries, groups: groups, familyName: nil)
            coordinator.globalBannerMessage = "Export completato."
        } catch {
            coordinator.globalBannerMessage = "Export non riuscito."
        }
    }

    private func prepareImportPreview(url: URL) async {
        guard let uid = currentUid else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let importer = PasswordsTxtImporter(familyId: familyId, modelContext: modelContext, currentUid: uid)
            importPreview = try await importer.parse(url: url, passphrase: importPassphrase.isEmpty ? nil : importPassphrase)
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func commitImport(preview: ImportPreview) async {
        guard let uid = currentUid else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let importer = PasswordsTxtImporter(familyId: familyId, modelContext: modelContext, currentUid: uid)
            try await importer.commit(preview: preview, strategy: mergeStrategy)
            importPreview = nil
            coordinator.globalBannerMessage = "Import completato."
        } catch {
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }

    private func authenticateUser(reason: String) async -> Bool {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}

private extension UTType {
    static let kidBoxKbpw = UTType(exportedAs: "it.vittorioscocca.kidbox.kbpw")
}
