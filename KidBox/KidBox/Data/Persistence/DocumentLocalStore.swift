//
//  DocumentLocalStore.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import Foundation

enum DocumentLocalStore {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    /// Salva su disco e ritorna il localPath relativo (da mettere su KBDocument.localPath)
    static func save(data: Data, familyId: String, docId: String, fileName: String) throws -> String {
        let safeFileName = sanitizeFileName(fileName)
        let relativeFolder = "kidbox/documents/\(familyId)/\(docId)"
        let folderURL = documentsDirectory.appendingPathComponent(relativeFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        let fileURL = folderURL.appendingPathComponent(safeFileName)
        try data.write(to: fileURL, options: [.atomic])
        
        return "\(relativeFolder)/\(safeFileName)"
    }
    
    static func delete(localPath: String) throws {
        let url = documentsDirectory.appendingPathComponent(localPath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    private static func sanitizeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "file" }
        // rimpiazza i caratteri “problematici”
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return trimmed.components(separatedBy: bad).joined(separator: "_")
    }
}
