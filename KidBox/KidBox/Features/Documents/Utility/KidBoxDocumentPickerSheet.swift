//
//  KidBoxDocumentPickerSheet.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//


import SwiftUI
import SwiftData
import Combine
import OSLog
import FirebaseAuth

/// Sheet che consente all'utente di scegliere un documento dalla sezione
/// "Documenti" di KidBox per allegarlo a una visita, cura, esame o spesa.
///
/// Flow:
/// 1. Mostra la struttura cartelle (KBDocumentCategory) della famiglia
/// 2. L'utente naviga nelle cartelle e seleziona un documento
/// 3. Il documento viene scaricato e decriptato via `DocumentLocalCache.downloadToLocal`
/// 4. La URL temp (rinominata con il titolo utente) viene passata a `onPick`
///
/// - Note: La navigazione cartelle è ricorsiva tramite `NavigationStack` interno.
struct KidBoxDocumentPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    let familyId: String
    /// Se `true`, mostra solo documenti PDF (es. import wallet).
    var pdfOnly: Bool = false
    /// Se valorizzato (es. Garage/Casa `#FF6B00`), tinta toolbar e controlli della navigazione.
    var accentTint: Color? = nil
    /// Chiamata con la URL del file decriptato pronto per l'upload come allegato.
    let onPick: (URL) -> Void
    
    @State private var isLoading = false
    @State private var errorText: String?
    
    var body: some View {
        NavigationStack {
            KidBoxFolderPickerLevel(
                familyId: familyId,
                folderId: nil,
                folderTitle: "Documenti",
                pdfOnly: pdfOnly,
                isLoading: $isLoading,
                errorText: $errorText,
                onPick: { doc in
                    Task { await pick(doc) }
                }
            )
            .navigationTitle(pdfOnly ? "Scegli PDF" : "Scegli da KidBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Preparazione allegato…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .alert("Errore", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
        .modifier(KidBoxDocumentPickerAccentTintModifier(accentTint: accentTint))
    }
    
    // MARK: - Pick action
    
    @MainActor
    private func pick(_ doc: KBDocument) async {
        if pdfOnly && !Self.isPdfDocument(doc) {
            errorText = "Per il wallet serve un file PDF."
            return
        }
        isLoading = true
        defer { isLoading = false }
        
        KBLog.data.info("KidBoxDocumentPickerSheet pick docId=\(doc.id) title=\(doc.title)")
        
        do {
            let rawURL   = try await DocumentLocalCache.downloadToLocal(doc: doc, modelContext: modelContext)
            let namedURL = try namedURL(from: rawURL, doc: doc)
            KBLog.data.info("KidBoxDocumentPickerSheet pick ready fileName=\(namedURL.lastPathComponent)")
            dismiss()
            onPick(namedURL)
        } catch {
            errorText = "Impossibile aprire il documento: \(error.localizedDescription)"
            KBLog.data.error("KidBoxDocumentPickerSheet pick failed docId=\(doc.id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Rename helper (same logic as DocumentFolderViewModel+SendToChat)
    
    private func namedURL(from rawURL: URL, doc: KBDocument) throws -> URL {
        let ext = rawURL.pathExtension.isEmpty
        ? (doc.fileName as NSString).pathExtension
        : rawURL.pathExtension
        
        let baseName = doc.title.isEmpty
        ? (doc.fileName as NSString).deletingPathExtension
        : doc.title
        
        let safeName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let fileName = ext.isEmpty ? safeName : "\(safeName).\(ext)"
        
        let subdir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        
        let namedURL = subdir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: rawURL, to: namedURL)
        return namedURL
    }

    private static func isPdfDocument(_ doc: KBDocument) -> Bool {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf") { return true }
        return doc.fileName.lowercased().hasSuffix(".pdf")
    }
}

// MARK: - Recursive folder level

/// Un singolo livello della navigazione cartelle KidBox.
/// Si ricorsa tramite `NavigationLink` per ogni sottocartella.
private struct KidBoxFolderPickerLevel: View {
    @Environment(\.modelContext) private var modelContext
    
    let familyId:    String
    let folderId:    String?
    let folderTitle: String
    let pdfOnly: Bool
    @Binding var isLoading: Bool
    @Binding var errorText: String?
    let onPick: (KBDocument) -> Void
    
    // Cartelle e documenti del livello corrente
    @State private var folders: [KBDocumentCategory] = []
    @State private var docs:    [KBDocument]         = []
    
    var body: some View {
        List {
            // ── Sottocartelle ────────────────────────────────────────────
            if !folders.isEmpty {
                Section("Cartelle") {
                    ForEach(folders) { folder in
                        NavigationLink {
                            KidBoxFolderPickerLevel(
                                familyId: familyId,
                                folderId: folder.id,
                                folderTitle: folder.title,
                                pdfOnly: pdfOnly,
                                isLoading: $isLoading,
                                errorText: $errorText,
                                onPick: onPick
                            )
                        } label: {
                            Label(folder.title, systemImage: "folder.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            
            // ── Documenti ────────────────────────────────────────────────
            if !docs.isEmpty {
                Section(pdfOnly ? "Documenti PDF" : "Documenti") {
                    ForEach(docs) { doc in
                        Button {
                            onPick(doc)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mimeIcon(doc.mimeType))
                                    .foregroundStyle(mimeColor(doc.mimeType))
                                    .font(.title3)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.title.isEmpty ? doc.fileName : doc.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    Text(prettySize(doc.fileSize))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.orange)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }
            }
            
            // ── Stato vuoto ──────────────────────────────────────────────
            if folders.isEmpty && docs.isEmpty {
                ContentUnavailableView(
                    "Cartella vuota",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(pdfOnly ? "Nessun PDF in questa cartella." : "Nessun documento in questa cartella.")
                )
            }
        }
        .navigationTitle(folderTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadContent() }
        // Allineato a DocumentFolderView: senza questo, aprendo il picker prima che il listener
        // Firestore abbia scritto in SwiftData si vede "Cartella vuota" e non si aggiorna mai.
        .onReceive(SyncCenter.shared.docsChanged.filter { $0 == familyId }) { _ in
            loadContent()
        }
    }
    
    // MARK: - Load
    
    private func loadContent() {
        let fid = familyId
        let pid = folderId
        
        do {
            let allCats = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
            ))
            let allDocs = try modelContext.fetch(FetchDescriptor<KBDocument>(
                predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
            ))
            let viewerUid = Auth.auth().currentUser?.uid
            func filterBrowsable(_ raw: [KBDocumentCategory]) -> [KBDocumentCategory] {
                raw.filter {
                    DocumentFolderSubtreeVisibility.folderIsBrowsable(
                        folder: $0,
                        allCategories: allCats,
                        allDocuments: allDocs,
                        viewerUid: viewerUid
                    )
                }
            }

            // Cartelle
            if let pid {
                folders = filterBrowsable(
                    try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                        predicate: #Predicate { $0.familyId == fid && $0.parentId == pid && $0.isDeleted == false },
                        sortBy: [SortDescriptor(\.sortOrder)]
                    ))
                )
            } else {
                let a = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate { $0.familyId == fid && $0.parentId == nil && $0.isDeleted == false }
                ))
                let b = try modelContext.fetch(FetchDescriptor<KBDocumentCategory>(
                    predicate: #Predicate { $0.familyId == fid && $0.parentId == "" && $0.isDeleted == false }
                ))
                var map: [String: KBDocumentCategory] = [:]
                for x in a { map[x.id] = x }
                for x in b { map[x.id] = x }
                folders = filterBrowsable(map.values.sorted { $0.sortOrder < $1.sortOrder })
            }
            
            // Documenti
            let uid = Auth.auth().currentUser?.uid
            if let pid {
                docs = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.categoryId == pid && $0.isDeleted == false },
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                ))
            } else {
                let a = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.categoryId == nil && $0.isDeleted == false }
                ))
                let b = try modelContext.fetch(FetchDescriptor<KBDocument>(
                    predicate: #Predicate { $0.familyId == fid && $0.categoryId == "" && $0.isDeleted == false }
                ))
                var map: [String: KBDocument] = [:]
                for x in a { map[x.id] = x }
                for x in b { map[x.id] = x }
                docs = map.values.sorted { $0.updatedAt > $1.updatedAt }
            }
            docs = docs.filteredToVisibleDocuments(currentUid: uid)
            if pdfOnly {
                docs = docs.filter { Self.docIsPdf($0) }
            }
        } catch {
            KBLog.data.error("KidBoxFolderPickerLevel loadContent failed: \(error.localizedDescription)")
        }
    }

    private static func docIsPdf(_ doc: KBDocument) -> Bool {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf") { return true }
        return doc.fileName.lowercased().hasSuffix(".pdf")
    }
    
    // MARK: - Helpers
    
    private func mimeIcon(_ mime: String) -> String {
        let m = mime.lowercased()
        if m.contains("pdf")   { return "doc.richtext.fill" }
        if m.contains("image") { return "photo.fill" }
        if m.contains("word")  { return "doc.text.fill" }
        if m.contains("sheet") || m.contains("excel") { return "tablecells.fill" }
        return "doc.fill"
    }
    
    private func mimeColor(_ mime: String) -> Color {
        let m = mime.lowercased()
        if m.contains("pdf")   { return .red }
        if m.contains("image") { return .blue }
        if m.contains("word")  { return Color(red: 0.17, green: 0.44, blue: 0.86) }
        if m.contains("sheet") || m.contains("excel") { return Color(red: 0.13, green: 0.62, blue: 0.30) }
        return .indigo
    }
    
    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024    { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024   { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Accent (Garage / Casa)

private struct KidBoxDocumentPickerAccentTintModifier: ViewModifier {
    let accentTint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let accentTint {
            content.tint(accentTint)
        } else {
            content
        }
    }
}
