//
//  DocumentLocalCache.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import Foundation
import SwiftData
import FirebaseStorage
import OSLog

/// Local encrypted document cache utilities.
///
/// Responsibilities:
/// - Provide an Application Support base directory for KidBox documents
/// - Build stable local URLs for a given family/document/filename
/// - Read/write encrypted blobs (ciphertext) from/to local storage
/// - Resolve a relative localPath into an absolute file URL
/// - Best-effort existence check
/// - Download encrypted blobs from Firebase Storage and return a TEMP decrypted file URL
///
/// Security model (current behavior, unchanged):
/// - Persistent cache stores **encrypted data** (ciphertext).
/// - When downloading from remote, data is decrypted and written to **temporary** location only.
/// - `localPath` should not be persisted for decrypted temporary files.
enum DocumentLocalCache {
    
    // MARK: - Directories
    
    /// Returns the base directory in Application Support where KidBox stores cached document files.
    ///
    /// - Returns: `<Application Support>/KidBoxDocs/`
    ///
    /// - Throws: If Application Support cannot be located or directory creation fails.
    static func baseDir() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let dir = appSupport.appendingPathComponent("KidBoxDocs", isDirectory: true)
        
        if !fm.fileExists(atPath: dir.path) {
            KBLog.persistence.kbInfo("Creating KidBoxDocs base dir")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } else {
            KBLog.persistence.kbDebug("KidBoxDocs base dir exists")
        }
        
        return dir
    }
    
    // MARK: - Read (encrypted)
    
    /// Reads an encrypted file from local cache.
    ///
    /// - Parameter localPath: Relative cache path (e.g. `{familyId}/{docId}_file.pdf`)
    /// - Returns: Ciphertext bytes (still encrypted).
    ///
    /// - Throws: If resolution fails or the file cannot be read.
    static func readEncrypted(localPath: String) throws -> Data {
        let url = try resolve(localPath: localPath)
        KBLog.persistence.kbDebug("Reading encrypted cache file at \(localPath)")
        return try Data(contentsOf: url)
    }
    
    // MARK: - Paths
    
    /// Builds the expected local URL for a given family/document/filename inside the cache.
    ///
    /// Behavior (unchanged):
    /// - Creates `<baseDir>/<familyId>/` if missing.
    /// - Prefixes the filename with `docId_` to avoid collisions.
    ///
    /// - Returns: Absolute URL in Application Support cache.
    static func localURL(familyId: String, docId: String, fileName: String) throws -> URL {
        let safeName = fileName.isEmpty ? "\(docId)" : fileName
        
        let dir = try baseDir().appendingPathComponent(familyId, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            KBLog.persistence.kbInfo("Creating family cache dir familyId=\(familyId)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        return dir.appendingPathComponent("\(docId)_\(safeName)")
    }
    
    /// Writes bytes to local cache for a family/document/filename.
    ///
    /// Behavior (unchanged):
    /// - Writes atomically to `<baseDir>/<familyId>/<docId>_<safeName>`
    /// - Returns a relative path for persistence (robust if baseDir changes):
    ///   `{familyId}/{lastPathComponent}`
    ///
    /// - Returns: Relative localPath to store in metadata.
    static func write(familyId: String, docId: String, fileName: String, data: Data) throws -> String {
        let url = try localURL(familyId: familyId, docId: docId, fileName: fileName)
        
        KBLog.persistence.kbInfo("Writing cache file familyId=\(familyId) docId=\(docId) bytes=\(data.count)")
        try data.write(to: url, options: .atomic)
        
        let relative = "\(familyId)/\(url.lastPathComponent)"
        KBLog.persistence.kbDebug("Cache write completed localPath=\(relative)")
        return relative
    }
    
    /// Resolves a relative `localPath` into an absolute URL under `baseDir`.
    ///
    /// - Parameter localPath: Relative cache path.
    /// - Returns: Absolute file URL.
    static func resolve(localPath: String) throws -> URL {
        let dir = try baseDir()
        return dir.appendingPathComponent(localPath)
    }
    
    /// Best-effort check whether a cached file exists.
    ///
    /// - Parameter localPath: Optional relative localPath.
    /// - Returns: Absolute URL if the file exists, otherwise `nil`.
    static func exists(localPath: String?) -> URL? {
        guard let localPath else { return nil }
        do {
            let url = try resolve(localPath: localPath)
            let ok = FileManager.default.fileExists(atPath: url.path)
            KBLog.persistence.kbDebug("Cache exists? \(ok) localPath=\(localPath)")
            return ok ? url : nil
        } catch {
            KBLog.persistence.kbError("Cache exists() failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Remote download -> TEMP decrypted file
    
    /// Downloads an encrypted document from Firebase Storage and returns a TEMP decrypted local URL.
    ///
    /// Behavior (unchanged):
    /// - Uses `doc.storagePath` (preferred over downloadURL).
    /// - Downloads ciphertext from Firebase Storage.
    /// - Decrypts using `DocumentCryptoService.decrypt(_, familyId:)`.
    /// - Writes decrypted bytes to `FileManager.default.temporaryDirectory`.
    /// - Does **not** persist `localPath` for the decrypted file.
    ///
    /// - Parameters:
    ///   - doc: The document metadata.
    ///   - modelContext: Present for API symmetry (currently unused).
    ///
    /// - Returns: URL of the decrypted TEMP file.
    static func downloadToLocal(doc: KBDocument, modelContext: ModelContext) async throws -> URL {
        let storagePath = doc.storagePath
        guard !storagePath.isEmpty else {
            KBLog.storage.kbError("downloadToLocal failed: storagePath empty docId=\(doc.id)")
            throw NSError(
                domain: "KidBox",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "storagePath vuoto"]
            )
        }
        
        KBLog.storage.kbInfo("Downloading encrypted file from Storage docId=\(doc.id)")
        let ref = Storage.storage().reference(withPath: storagePath)
        
        // ciphertext download
        let encrypted = try await ref.data(maxSize: 30 * 1024 * 1024)
        KBLog.storage.kbDebug("Download OK bytes=\(encrypted.count) docId=\(doc.id)")
        
        // decrypt
        KBLog.storage.kbDebug("Decrypting downloaded data docId=\(doc.id)")
        let decrypted = try DocumentCryptoService.decrypt(encrypted, familyId: doc.familyId)
        KBLog.storage.kbDebug("Decrypt OK bytes=\(decrypted.count) docId=\(doc.id)")
        
        // write to TEMP
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileName = "\(doc.id)_\(doc.fileName)"
        let tempURL = tempDir.appendingPathComponent(tempFileName)
        
        KBLog.storage.kbInfo("Writing TEMP decrypted file docId=\(doc.id)")
        try decrypted.write(to: tempURL, options: .atomic)
        
        KBLog.storage.kbInfo("TEMP file ready docId=\(doc.id)")
        return tempURL
    }
}
