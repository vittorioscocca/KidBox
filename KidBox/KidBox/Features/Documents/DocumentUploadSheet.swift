//
//  DocumentUploadSheet.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FirebaseAuth

struct DocumentUploadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \KBDocumentCategory.sortOrder, order: .forward)
    private var categories: [KBDocumentCategory]
    
    let family: KBFamily
    let defaultChildId: String?
    let fileURL: URL
    let onDone: () -> Void
    
    @State private var title: String = ""
    @State private var selectedCategoryId: String = ""
    @State private var scope: Scope = .family
    @State private var isUploading = false
    @State private var errorText: String?
    
    private let storage = DocumentStorageService()
    
    enum Scope: String, CaseIterable, Identifiable {
        case family = "Famiglia"
        case child = "Bimbo/a"
        var id: String { rawValue }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("File") {
                    Text(fileURL.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("Dati") {
                    TextField("Titolo (es. Tessera sanitaria)", text: $title)
                    
                    Picker("Categoria", selection: $selectedCategoryId) {
                        ForEach(visibleCategories) { c in
                            Text(c.title).tag(c.id)
                        }
                    }
                    
                    Picker("A chi appartiene", selection: $scope) {
                        ForEach(Scope.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    
                    if scope == .child {
                        Text("Usiamo il primo bimbo/a configurato (MVP).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
                
                Section {
                    Button(isUploading ? "Caricamento…" : "Carica") {
                        Task { await upload() }
                    }
                    .disabled(isUploading || selectedCategoryId.isEmpty || titleTrimmed.isEmpty)
                }
            }
            .navigationTitle("Nuovo documento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") {
                        dismiss()
                        onDone()
                    }
                }
            }
            .onAppear {
                title = fileURL.deletingPathExtension().lastPathComponent
                selectedCategoryId = visibleCategories.first?.id ?? ""
            }
        }
    }
    
    private var visibleCategories: [KBDocumentCategory] {
        categories.filter { $0.familyId == family.id && !$0.isDeleted }
    }
    
    private var titleTrimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor
    private func upload() async {
        errorText = nil
        isUploading = true
        defer { isUploading = false }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = guessMimeType(from: fileURL)
            let fileName = fileURL.lastPathComponent
            
            let docId = UUID().uuidString
            let childId: String? = (scope == .child) ? defaultChildId : nil
            
            // 1) upload binary su Storage
            let uploadRes = try await storage.upload(
                familyId: family.id,
                docId: docId,
                fileName: fileName,
                mimeType: mimeType,
                data: data
            )
            
            // 2) crea locale (SwiftData)
            let local = KBDocument(
                id: docId,
                familyId: family.id,
                childId: childId,
                categoryId: selectedCategoryId,
                title: titleTrimmed,
                fileName: fileName,
                mimeType: mimeType,
                fileSize: Int64(data.count),
                storagePath: uploadRes.storagePath,
                downloadURL: uploadRes.downloadURL,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now,
                isDeleted: false
            )
            
            local.syncState = .pendingUpsert
            local.lastSyncError = nil
            
            modelContext.insert(local)
            try modelContext.save()
            
            // 3) enqueue outbox + flush (Firestore metadata)
            SyncCenter.shared.enqueueDocumentUpsert(
                documentId: local.id,
                familyId: family.id,
                modelContext: modelContext
            )
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
            
            dismiss()
            onDone()
            
        } catch {
            errorText = error.localizedDescription
        }
    }
    
    private func guessMimeType(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return "application/pdf" }
        if ext == "jpg" || ext == "jpeg" { return "image/jpeg" }
        if ext == "png" { return "image/png" }
        return "application/octet-stream"
    }
}
