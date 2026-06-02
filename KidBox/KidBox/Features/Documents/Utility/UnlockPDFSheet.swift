//
//  UnlockPDFSheet.swift
//  KidBox
//
//  Created by vscocca on 25/05/26.
//

import SwiftUI
internal import os

/// Sheet shown when the user wants to remove the password from a single PDF.
///
/// The user enters the PDF password and confirms; the parent `DocumentFolderView`
/// runs the unlock+upload pipeline and a new password-free document is created
/// in the same folder. The original document is preserved.
struct UnlockPDFSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Source PDF the user wants to unlock.
    let doc: KBDocument

    /// Callback called when the user confirms with a non-empty password.
    /// The parent owns the actual unlock pipeline so this view stays purely
    /// presentational.
    let onUnlock: (KBDocument, String, String) async -> Void

    @State private var password: String = ""
    @State private var unlockedTitle: String = ""
    @State private var isWorking = false
    @State private var showPassword = false
    @State private var errorText: String?

    init(
        doc: KBDocument,
        onUnlock: @escaping (KBDocument, String, String) async -> Void
    ) {
        self.doc = doc
        self.onUnlock = onUnlock
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Documento di origine ─────────────────────────────────
                Section("PDF da sbloccare") {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.doc.fill")
                            .foregroundStyle(.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.title.isEmpty ? doc.fileName : doc.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(prettySize(doc.fileSize))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // ── Password ─────────────────────────────────────────────
                Section {
                    HStack {
                        Group {
                            if showPassword {
                                TextField("Password del PDF", text: $password)
                            } else {
                                SecureField("Password del PDF", text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.go)
                        .onSubmit { Task { await startUnlock() } }

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showPassword ? "Nascondi password" : "Mostra password")
                    }
                } header: {
                    Text("Password del PDF")
                } footer: {
                    Text("La password viene usata solo localmente per produrre una copia non protetta. Verrà creato un nuovo documento nella stessa cartella; l'originale resta invariato.")
                        .font(.footnote)
                }

                // ── Nome del nuovo PDF ───────────────────────────────────
                Section("Nome del nuovo PDF") {
                    TextField("Es. Documento sbloccato", text: $unlockedTitle)
                        .textInputAutocapitalization(.sentences)
                }

                // ── Errore ───────────────────────────────────────────────
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Sblocca PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .disabled(isWorking)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startUnlock() }
                    } label: {
                        if isWorking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text("Sblocca").bold()
                        }
                    }
                    .disabled(isWorking || password.isEmpty || finalTitle.isEmpty)
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
        .onAppear { unlockedTitle = suggestedTitle }
    }

    // MARK: - Helpers

    private var suggestedTitle: String {
        let base = doc.title.isEmpty ? doc.fileName : doc.title
        let nameNoExt = (base as NSString).deletingPathExtension
        return "\(nameNoExt) (sbloccato)"
    }

    private var finalTitle: String {
        unlockedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func startUnlock() async {
        guard !password.isEmpty, !finalTitle.isEmpty else { return }
        errorText = nil
        isWorking = true
        defer { isWorking = false }

        // The parent ViewModel surfaces failures via its own `errorText`
        // observable; here we only capture nothing because `onUnlock` returns
        // Void (no need to keep this sheet open on failure either - the
        // ViewModel keeps any failure message visible at the folder level).
        KBLog.data.kbInfo("UnlockPDFSheet startUnlock docId=\(doc.id) titleLen=\(finalTitle.count)")
        await onUnlock(doc, password, finalTitle)
        dismiss()
    }

    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024  { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}
