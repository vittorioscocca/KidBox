//
//  ChatStorageService.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseStorage
import OSLog

/// Errori specifici del servizio storage chat.
enum ChatStorageError: Error {
    case notAuthenticated
    case emptyData
    case missingURL
}

/// Firebase Storage service per i media della chat (foto, video, audio).
///
/// Path Storage:
/// - Foto:  `families/{familyId}/chat/{messageId}/photo.jpg`
/// - Video: `families/{familyId}/chat/{messageId}/video.mp4`
/// - Audio: `families/{familyId}/chat/{messageId}/audio.m4a`
///
/// I media della chat NON vengono cifrati con AES-GCM (a differenza dei documenti)
/// perché Firebase Storage Rules già garantiscono l'accesso solo ai membri della famiglia.
/// Questa scelta semplifica la gestione e lo streaming video/audio nativo.
final class ChatStorageService {
    
    private let storage = Storage.storage()
    
    // MARK: - Upload
    
    /// Carica un file media (foto/video/audio) su Firebase Storage.
    ///
    /// - Parameters:
    ///   - data: Bytes del file da caricare.
    ///   - familyId: ID della famiglia.
    ///   - messageId: ID del messaggio a cui appartiene il media.
    ///   - fileName: Nome file con estensione (es. "photo.jpg", "audio.m4a").
    ///   - mimeType: MIME type del file (es. "image/jpeg", "audio/m4a").
    ///   - progressHandler: Callback opzionale con il progresso 0.0...1.0.
    ///
    /// - Returns: `(storagePath, downloadURL)` da salvare nel messaggio.
    func upload(
        data: Data,
        familyId: String,
        messageId: String,
        fileName: String,
        mimeType: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> (storagePath: String, downloadURL: String) {
        
        guard Auth.auth().currentUser != nil else {
            KBLog.storage.kbError("ChatStorage upload failed: not authenticated")
            throw ChatStorageError.notAuthenticated
        }
        
        guard !data.isEmpty else {
            KBLog.storage.kbError("ChatStorage upload failed: empty data msgId=\(messageId)")
            throw ChatStorageError.emptyData
        }
        
        let path = "families/\(familyId)/chat/\(messageId)/\(fileName)"
        let ref  = storage.reference(withPath: path)
        
        let metadata = StorageMetadata()
        metadata.contentType = mimeType
        
        KBLog.storage.kbInfo("ChatStorage upload start msgId=\(messageId) bytes=\(data.count)")
        
        // Upload con progress tracking
        let url: URL = try await withCheckedThrowingContinuation { cont in
            var done = false
            let task = ref.putData(data, metadata: metadata)
            
            task.observe(.progress) { snap in
                guard let p = snap.progress, p.totalUnitCount > 0 else { return }
                let val = Double(p.completedUnitCount) / Double(p.totalUnitCount)
                progressHandler?(val)
            }
            
            task.observe(.success) { _ in
                guard !done else { return }
                done = true
                Task {
                    do {
                        let url = try await ref.downloadURL()
                        cont.resume(returning: url)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            
            task.observe(.failure) { snap in
                guard !done else { return }
                done = true
                cont.resume(throwing: snap.error ?? NSError(
                    domain: "KidBox", code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Upload fallito"]))
            }
        }
        
        KBLog.storage.kbInfo("ChatStorage upload OK msgId=\(messageId)")
        return (storagePath: path, downloadURL: url.absoluteString)
    }
    
    // MARK: - Download
    
    /// Scarica i byte di un media dalla chat (per audio/video offline).
    ///
    /// - Parameters:
    ///   - storagePath: Path su Firebase Storage.
    ///   - maxSizeMB: Limite massimo in MB (default 50).
    func download(storagePath: String, maxSizeMB: Int = 50) async throws -> Data {
        guard Auth.auth().currentUser != nil else {
            throw ChatStorageError.notAuthenticated
        }
        
        KBLog.storage.kbInfo("ChatStorage download start path=\(storagePath)")
        let ref  = storage.reference(withPath: storagePath)
        let data = try await ref.data(maxSize: Int64(maxSizeMB) * 1024 * 1024)
        KBLog.storage.kbInfo("ChatStorage download OK bytes=\(data.count)")
        return data
    }
    
    // MARK: - Delete
    
    /// Elimina il media da Firebase Storage.
    func delete(storagePath: String) async throws {
        guard Auth.auth().currentUser != nil else {
            throw ChatStorageError.notAuthenticated
        }
        
        guard !storagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        KBLog.storage.kbInfo("ChatStorage delete start path=\(storagePath)")
        try await storage.reference(withPath: storagePath).delete()
        KBLog.storage.kbInfo("ChatStorage delete OK")
    }
    
    // MARK: - Helpers
    
    /// Restituisce il nome file e il MIME type corretti per ogni tipo di messaggio.
    static func fileInfo(for type: KBChatMessageType) -> (fileName: String, mimeType: String) {
        switch type {
        case .photo: return ("photo.jpg",  "image/jpeg")
        case .video: return ("video.mp4",  "video/mp4")
        case .audio: return ("audio.m4a",  "audio/x-m4a")
        case .text:  return ("file.bin",   "application/octet-stream")
        }
    }
}
