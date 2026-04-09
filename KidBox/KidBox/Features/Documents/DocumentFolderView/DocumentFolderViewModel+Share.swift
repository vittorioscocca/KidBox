//
//  DocumentFolderViewModel+Share.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//

import Foundation
import SwiftData
import OSLog

// MARK: - Share / Send to Chat

extension DocumentFolderViewModel {
    
    // MARK: - Selection helpers
    
    /// Documents currently selected that are NOT folders.
    var selectedShareableDocs: [KBDocument] {
        selectedItems.compactMap { item -> KBDocument? in
            guard case .doc(let id) = item else { return nil }
            return docs.first(where: { $0.id == id })
        }
    }
    
    /// True when at least one document is selected.
    var canShareSelectedDocs: Bool { !selectedShareableDocs.isEmpty }
    
    // MARK: - Share via iOS sheet
    
    /// Downloads and decrypts the given documents, returning temporary decrypted URLs
    /// named after the document title (not the internal storage filename).
    ///
    /// - Parameters:
    ///   - docs: Documents to share. Defaults to `selectedShareableDocs` when `nil`.
    ///   - modelContext: The view's model context.
    @MainActor
    func prepareShareURLs(docs: [KBDocument]? = nil, modelContext: ModelContext) async -> [URL] {
        let targets = docs ?? selectedShareableDocs
        guard !targets.isEmpty else { return [] }
        
        KBLog.data.info("DocumentFolderViewModel prepareShareURLs started count=\(targets.count)")
        
        isDownloading = true
        downloadCurrentName = "Preparazione condivisione…"
        downloadProgress = 0
        
        defer {
            isDownloading = false
            downloadCurrentName = ""
            downloadProgress = 0
        }
        
        var urls: [URL] = []
        
        for (i, doc) in targets.enumerated() {
            downloadCurrentName = doc.title.isEmpty ? doc.fileName : doc.title
            downloadProgress = Double(i) / Double(targets.count)
            KBLog.data.debug("DocumentFolderViewModel prepareShareURLs downloading docId=\(doc.id)")
            do {
                let rawURL = try await DocumentLocalCache.downloadToLocal(doc: doc, modelContext: modelContext)
                // Rinomina con il titolo utente prima di passare allo share sheet
                let namedURL = try Self.namedURL(from: rawURL, doc: doc)
                urls.append(namedURL)
            } catch {
                KBLog.data.error("DocumentFolderViewModel prepareShareURLs failed docId=\(doc.id): \(error.localizedDescription)")
            }
        }
        
        downloadProgress = 1.0
        KBLog.data.info("DocumentFolderViewModel prepareShareURLs done count=\(urls.count)/\(targets.count)")
        return urls
    }
    
}
