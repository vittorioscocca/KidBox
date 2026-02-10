//
//  DocumentLocalCacheService.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import Foundation

final class DocumentLocalCacheService {
    
    func ensureLocalFile(for doc: KBDocument) async throws -> URL {
        
        // 1) se esiste già in locale -> ritorna
        if let url = doc.localFileURL,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        
        // 2) serve downloadURL
        guard let s = doc.downloadURL, let remoteURL = URL(string: s) else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Nessun link remoto disponibile."
            ])
        }
        
        // 3) scarica in tmp
        let (tmp, _) = try await URLSession.shared.download(from: remoteURL)
        
        // 4) sposta in cache con nome stabile
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("KidBoxDocuments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let fileName = doc.fileName.isEmpty ? doc.id : doc.fileName
        let rel = "KidBoxDocuments/\(doc.id)_\(fileName)"
        let dst = base.appendingPathComponent(rel)
        
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
        
        // 5) salva localPath sul doc
        doc.localPath = rel
        
        return dst
    }
}
