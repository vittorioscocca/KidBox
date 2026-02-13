//
//  DocumentLocalCache.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import Foundation
import SwiftData
import FirebaseStorage

enum DocumentLocalCache {
    static func baseDir() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("KidBoxDocs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    /// Leggi file CIFRATO da cache locale
    /// - Returns: Ciphertext (ancora cifrato)
    static func readEncrypted(localPath: String) throws -> Data {
        let url = try resolve(localPath: localPath)
        return try Data(contentsOf: url)
    }
    
    static func localURL(familyId: String, docId: String, fileName: String) throws -> URL {
        let safeName = fileName.isEmpty ? "\(docId)" : fileName
        let dir = try baseDir().appendingPathComponent(familyId, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // docId prefisso per evitare collisioni tra fileName uguali
        return dir.appendingPathComponent("\(docId)_\(safeName)")
    }
    
    static func write(familyId: String, docId: String, fileName: String, data: Data) throws -> String {
        let url = try localURL(familyId: familyId, docId: docId, fileName: fileName)
        try data.write(to: url, options: .atomic)
        // salviamo un path relativo “nostro” (più robusto se cambia baseDir)
        // es: "{familyId}/{docId}_file.pdf"
        return "\(familyId)/\(url.lastPathComponent)"
    }
    
    static func resolve(localPath: String) throws -> URL {
        let dir = try baseDir()
        return dir.appendingPathComponent(localPath)
    }
    
    static func exists(localPath: String?) -> URL? {
        guard let localPath else { return nil }
        do {
            let url = try resolve(localPath: localPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }
    
    // Scarica da Firebase Storage usando storagePath (preferibile a downloadURL)
    static func downloadToLocal(doc: KBDocument, modelContext: ModelContext) async throws -> URL {
        let storagePath = doc.storagePath
        guard !storagePath.isEmpty else {
            throw NSError(domain: "KidBox", code: -2, userInfo: [NSLocalizedDescriptionKey: "storagePath vuoto"])
        }
        
        let ref = Storage.storage().reference(withPath: storagePath)
        let encrypted = try await ref.data(maxSize: 30 * 1024 * 1024)
        
        // ✅ DECRYPT
        let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: doc.familyId)
        
        // ✅ Salva in TEMP (viene cancellato quando chiudi)
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "\(doc.id)_\(doc.fileName)"
        let tempURL = tempDir.appendingPathComponent(tempFileName)
        
        try decrypted.write(to: tempURL, options: .atomic)
        
        // Non salvare localPath persistentemente
        // doc.localPath rimane nil o vuoto
        
        return tempURL
    }
}
