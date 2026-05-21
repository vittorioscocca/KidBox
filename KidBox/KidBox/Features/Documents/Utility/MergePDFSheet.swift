//
//  MergePDFSheet.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//

import SwiftUI
internal import os

/// Sheet presented when the user wants to merge selected PDF documents.
///
/// The user can drag rows to reorder the PDFs before merging.
/// The final merge order matches the list order (top = first pages).
struct MergePDFSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    // The callback signature carries the ordered doc list so the ViewModel
    // merges in exactly the order the user chose.
    let onMerge: ([KBDocument], String) async -> Void
    
    // Ordered list — user can drag to rearrange
    @State private var orderedDocs: [KBDocument]
    @State private var mergedTitle: String = ""
    @State private var isMerging = false
    @State private var errorText: String?
    
    init(docs: [KBDocument], onMerge: @escaping ([KBDocument], String) async -> Void) {
        _orderedDocs = State(initialValue: docs)
        self.onMerge = onMerge
    }
    
    var body: some View {
        NavigationStack {
            List {
                // ── Title input ──────────────────────────────────────────
                Section("Nome del PDF unito") {
                    TextField("Es. Documenti identità", text: $mergedTitle)
                        .textInputAutocapitalization(.sentences)
                }
                
                // ── Reorderable list ─────────────────────────────────────
                Section {
                    ForEach(Array(orderedDocs.enumerated()), id: \.element.id) { index, doc in
                        HStack(spacing: 12) {
                            // Order badge
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.orange, in: Circle())
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title.isEmpty ? doc.fileName : doc.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                
                                Text(prettySize(doc.fileSize))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "doc.richtext.fill")
                                .foregroundStyle(.red.opacity(0.8))
                                .font(.title3)
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { from, to in
                        orderedDocs.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    HStack {
                        Text("Ordine pagine (\(orderedDocs.count) file)")
                        Spacer()
                        // Hint visivo
                        Label("Trascina per riordinare", systemImage: "line.3.horizontal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // ── Error feedback ───────────────────────────────────────
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Unisci PDF")
            .navigationBarTitleDisplayMode(.inline)
            // EditMode always on so drag handles are always visible
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .disabled(isMerging)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startMerge() }
                    } label: {
                        if isMerging {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text("Unisci").bold()
                        }
                    }
                    .disabled(isMerging || finalTitle.isEmpty)
                }
            }
            .interactiveDismissDisabled(isMerging)
        }
        .onAppear { mergedTitle = suggestedTitle }
    }
    
    // MARK: - Helpers
    
    private var suggestedTitle: String {
        let base = orderedDocs.first.map { $0.title.isEmpty ? $0.fileName : $0.title } ?? "Documenti uniti"
        let nameNoExt = (base as NSString).deletingPathExtension
        return "\(nameNoExt) (uniti)"
    }
    
    private var finalTitle: String {
        mergedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor
    private func startMerge() async {
        guard !finalTitle.isEmpty else { return }
        errorText = nil
        isMerging = true
        defer { isMerging = false }
        
        KBLog.data.kbInfo("MergePDFSheet startMerge count=\(orderedDocs.count) title=\(finalTitle)")
        
        // Pass orderedDocs (user's chosen order) and title to the ViewModel.
        await onMerge(orderedDocs, finalTitle)
        dismiss()
    }
    
    private func prettySize(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b < 1024        { return "\(bytes) B" }
        let kb = b / 1024
        if kb < 1024       { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024       { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", mb / 1024)
    }
}
