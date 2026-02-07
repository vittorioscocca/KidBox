//
//  CategoryDocumentsView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - View

struct CategoryDocumentsView: View {
    enum LayoutMode: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case list = "Lista"
        var id: String { rawValue }
    }
    
    struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let familyId: String
    let categoryId: String
    let categoryTitle: String
    
    // documenti di questa categoria
    @Query private var docs: [KBDocument]
    @State private var layout: LayoutMode = .grid
    
    // upload
    @State private var showImporter = false
    @State private var isUploading = false
    @State private var errorText: String?
    
    @State private var isDeleting = false
    private let deleteService = DocumentDeleteService()
    
    // “scope” documento: famiglia o child
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]
    private var activeChildId: String? { families.first?.children.first?.id } // MVP: primo child
    
    // preview
    @State private var previewURL: IdentifiableURL?
    
    init(familyId: String, categoryId: String, categoryTitle: String) {
        self.familyId = familyId
        self.categoryId = categoryId
        self.categoryTitle = categoryTitle
        
        let fid = familyId
        let cid = categoryId
        
        _docs = Query(
            filter: #Predicate<KBDocument> { d in
                d.familyId == fid &&
                d.categoryId == cid &&
                d.isDeleted == false
            },
            sort: [SortDescriptor(\KBDocument.updatedAt, order: .reverse)]
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }
            
            header
            
            if docs.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle(categoryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isUploading)
                .accessibilityLabel("Aggiungi documento")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.item], // accetta tutto (pdf, immagini, doc, etc)
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImport(result) }
        }
        .overlay {
            if isUploading {
                ZStack {
                    Color.black.opacity(0.10).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Caricamento documento…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .sheet(item: $previewURL) { item in
            SafariView(url: item.url)
        }
    }
    
    // MARK: - UI
    
    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $layout) {
                ForEach(LayoutMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            
            Spacer()
            
            Text("\(docs.count)")
                .font(.caption).bold()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nessun documento")
                .font(.headline)
            Text("Premi + per caricare un file in questa categoria.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var content: some View {
        Group {
            switch layout {
            case .grid:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(docs) { doc in
                            DocumentGridCard(doc: doc) {
                                open(doc)
                            } onDelete: {
                                deleteDocument(doc)
                            }
                        }
                    }
                    .padding()
                }
                
            case .list:
                List {
                    ForEach(docs) { doc in
                        Button {
                            open(doc)
                        } label: {
                            DocumentRow(doc: doc)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteDocument(doc)
                            } label: {
                                Label("Elimina", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
    
    // MARK: - Actions
    
    @MainActor
    private func handleImport(_ result: Result<[URL], Error>) async {
        errorText = nil
        
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            
            // iOS security-scoped
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            
            isUploading = true
            defer { isUploading = false }
            
            let data = try Data(contentsOf: url)
            if data.isEmpty {
                errorText = "File vuoto."
                return
            }
            
            let fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            let mime = mimeType(forExtension: ext) ?? "application/octet-stream"
            let size = Int64(data.count)
            
            // titolo “umano” di default = file senza estensione
            let title = url.deletingPathExtension().lastPathComponent
            
            // child scope (MVP): se vuoi scegliere in UI, lo aggiungiamo dopo
            let childId = activeChildId // nil = famiglia
            
            // 1) LOCAL create
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            let documentId = UUID().uuidString
            
            let storagePath = "families/\(familyId)/documents/\(documentId)"
            
            let local = KBDocument(
                id: documentId,
                familyId: familyId,
                childId: childId,
                categoryId: categoryId,
                title: title,
                fileName: fileName,
                mimeType: mime,
                fileSize: size,
                storagePath: storagePath,
                downloadURL: nil,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now,
                isDeleted: false
            )
            local.syncState = .pendingUpsert
            local.lastSyncError = nil
            
            modelContext.insert(local)
            try modelContext.save()
            
            // 2) REMOTE upload + Firestore metadata
            do {
                let service = DocumentUploadService()
                let urlString = try await service.uploadDocument(
                    familyId: familyId,
                    documentId: documentId,
                    storagePath: storagePath,
                    data: data,
                    mimeType: mime,
                    meta: .init(
                        familyId: familyId,
                        childId: childId,
                        categoryId: categoryId,
                        title: title,
                        fileName: fileName,
                        mimeType: mime,
                        fileSize: size
                    )
                )
                
                local.downloadURL = urlString
                local.syncState = .synced
                local.lastSyncError = nil
                local.updatedAt = Date()
                local.updatedBy = uid
                try modelContext.save()
                
            } catch {
                local.syncState = .error
                local.lastSyncError = error.localizedDescription
                try? modelContext.save()
                errorText = error.localizedDescription
            }
            
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    private func open(_ doc: KBDocument) {
        guard let s = doc.downloadURL, let url = URL(string: s) else {
            errorText = "Questo documento non ha ancora un link remoto (upload non completato)."
            return
        }
        previewURL = IdentifiableURL(url: url)
    }
    
    @MainActor
    private func deleteDocument(_ doc: KBDocument) {
        guard !isDeleting else { return }
        isDeleting = true
        
        Task { @MainActor in
            defer { isDeleting = false }
            
            do {
                try await deleteService.deleteDocumentHard(familyId: familyId, doc: doc)
                
                // LOCAL delete
                modelContext.delete(doc)
                try modelContext.save()
                
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
    
    // MARK: - Helpers
    
    private func mimeType(forExtension ext: String) -> String? {
        if ext.isEmpty { return nil }
        if let ut = UTType(filenameExtension: ext),
           let m = ut.preferredMIMEType {
            return m
        }
        // fallback comuni
        switch ext {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        default: return nil
        }
    }
}

// MARK: - Upload service (Storage + Firestore)

struct RemoteDocumentMeta {
    let familyId: String
    let childId: String?
    let categoryId: String
    let title: String
    let fileName: String
    let mimeType: String
    let fileSize: Int64
}

final class DocumentUploadService {
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    
    func uploadDocument(
        familyId: String,
        documentId: String,
        storagePath: String,
        data: Data,
        mimeType: String,
        meta: RemoteDocumentMeta
    ) async throws -> String {
        
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // ✅ Storage
        let ref = storage.reference(withPath: storagePath)
        
        let md = StorageMetadata()
        md.contentType = mimeType
        
        _ = try await ref.putDataAsync(data, metadata: md)
        
        let url = try await ref.downloadURL()
        let urlString = url.absoluteString
        
        // ✅ Firestore metadata (realtime -> altri device)
        var payload: [String: Any] = [
            "familyId": meta.familyId,
            "categoryId": meta.categoryId,
            "title": meta.title,
            "fileName": meta.fileName,
            "mimeType": meta.mimeType,
            "fileSize": meta.fileSize,
            "storagePath": storagePath,
            "downloadURL": urlString,
            "isDeleted": false,
            "updatedBy": uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let childId = meta.childId {
            payload["childId"] = childId
        } else {
            payload["childId"] = FieldValue.delete()
        }
        
        try await db.collection("families")
            .document(familyId)
            .collection("documents")
            .document(documentId)
            .setData(payload, merge: true)
        
        return urlString
    }
}

// MARK: - Cards / Rows

private struct DocumentGridCard: View {
    let doc: KBDocument
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title)
                            .font(.subheadline).bold()
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        
                        Text(doc.fileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    SyncPill(state: doc.syncState, error: doc.lastSyncError)
                }
                
                Text(prettySize(doc.fileSize))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        }
    }
    
    private var iconName: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf") { return "doc.richtext" }
        if m.contains("image") { return "photo" }
        if m.contains("text") { return "doc.text" }
        return "doc"
    }
    
    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024 { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.1f GB", gb)
    }
}

private struct DocumentRow: View {
    let doc: KBDocument
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title)
                    .font(.subheadline).bold()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                Text(doc.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            SyncPill(state: doc.syncState, error: doc.lastSyncError)
        }
        .padding(.vertical, 6)
    }
    
    private var iconName: String {
        let m = doc.mimeType.lowercased()
        if m.contains("pdf") { return "doc.richtext" }
        if m.contains("image") { return "photo" }
        if m.contains("text") { return "doc.text" }
        return "doc"
    }
}

// MARK: - Safari preview

import SafariServices

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
