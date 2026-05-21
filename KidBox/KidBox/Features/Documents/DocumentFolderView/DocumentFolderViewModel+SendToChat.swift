//
//  DocumentFolderViewModel+SendToChat.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//

import Foundation
import SwiftData
import OSLog

// MARK: - Invia documento in chat

extension DocumentFolderViewModel {
    
    /// Scarica, decripta e invia un documento alla chat di famiglia.
    ///
    /// Flow:
    /// 1. Scarica e decripta il file via `DocumentLocalCache.downloadToLocal`
    /// 2. Rinomina il file temp con il titolo utente (non il nome interno storage)
    /// 3. Imposta `coordinator.pendingChatDocumentURL` con la URL rinominata
    /// 4. Naviga alla chat — `ChatView` intercetta la proprietà e chiama `sendDocument(url:)`
    @MainActor
    func sendToChat(doc: KBDocument, modelContext: ModelContext, coordinator: AppCoordinator) async {
        KBLog.data.kbInfo("DocumentFolderViewModel sendToChat started docId=\(doc.id) title=\(doc.title)")
        
        isDownloading = true
        downloadCurrentName = doc.title.isEmpty ? doc.fileName : doc.title
        downloadProgress = 0
        
        defer {
            isDownloading = false
            downloadCurrentName = ""
            downloadProgress = 0
        }
        
        do {
            let rawURL = try await DocumentLocalCache.downloadToLocal(doc: doc, modelContext: modelContext)
            
            // Rinomina con il titolo utente così in chat appare il nome corretto
            let namedURL = try Self.namedURL(from: rawURL, doc: doc)
            KBLog.data.kbInfo("DocumentFolderViewModel sendToChat ready fileName=\(namedURL.lastPathComponent)")
            
            coordinator.pendingChatDocumentURL = namedURL
            coordinator.navigate(to: .chat)
            
        } catch {
            errorText = "Impossibile preparare il documento: \(error.localizedDescription)"
            KBLog.data.kbError("DocumentFolderViewModel sendToChat failed docId=\(doc.id): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Shared helper
    
    /// Copia `rawURL` in una nuova URL temporanea il cui filename è il titolo utente
    /// del documento con la stessa estensione del file originale.
    ///
    /// Esempio:
    ///   rawURL   → `.../abc123_referto_ospedale.pdf`
    ///   namedURL → `.../Referto Giovanni.pdf`
    ///
    /// Usato sia da `sendToChat` che da `prepareShareURLs`.
    static func namedURL(from rawURL: URL, doc: KBDocument) throws -> URL {
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
        
        KBLog.data.kbDebug("namedURL \(rawURL.lastPathComponent) → \(namedURL.lastPathComponent)")
        return namedURL
    }
}
