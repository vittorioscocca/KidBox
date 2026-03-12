//
//  KBShareModels.swift
//  KBShare  ← solo Share Extension target
//
//  Adatta KBSaveClassifier (file condiviso) al contesto della Share Extension.
//  Qui non esiste KBChatMessage — lavoriamo direttamente con KBSharePayload.
//

import Foundation
import SwiftUI

// MARK: - Payload in ingresso dalla Share Extension

struct KBSharePayload {
    let type: KBShareContentType
}

enum KBShareContentType {
    case image(URL?)
    case text(String)
    case url(String)
    case file(URL)
    case unknown
}

// MARK: - Classificazione payload → destinazioni
//
// Matrice contenuto → destinazioni:
//
// Testo          → Chat, Note, Todo, (Evento se contiene data), (Spesa se lista)
// URL web        → Chat, Note, Todo
// Immagine       → Chat, Documenti
// File generico  → Chat, Documenti
// Video          → Chat  (upload pesante, via App Group)
// Sconosciuto    → Chat
//
// .chat è SEMPRE presente — è la chat interna di KidBox.

extension KBSharePayload {
    
    /// Destinazioni sincrone di default — placeholder immediato prima che l'AI risponda.
    var defaultDestinations: [KBShareDestination] {
        switch type {
            
        case .image:
            // Foto → chat + Foto e video crittografati
            return [.chat, .encryptedMedia]
            
        case .text(let t):
            let lines = t.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let isShort = lines.count == 1 && t.count < 120
            return isShort ? [.chat, .note, .todo] : [.chat, .note]
            
        case .url(let u):
            if let f = URL(string: u), f.isFileURL {
                return [.chat, .document]
            }
            return [.chat, .note, .todo]
            
        case .file(let url):
            let ext = url.pathExtension.lowercased()
            let isVideo = ["mp4", "mov", "m4v"].contains(ext)
            let isPhoto = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext)
            if isVideo || isPhoto {
                // Media → chat + Foto e video crittografati
                return [.chat, .encryptedMedia]
            }
            // File generico → chat + documenti
            return [.chat, .document]
            
        case .unknown:
            return [.chat]
        }
    }
    
    /// Classificazione async AI — da chiamare in .task {} o in un Task dal ViewController.
    /// Per contenuti non-testuali restituisce direttamente le destinazioni corrette
    /// senza passare per il classifier (che lavora solo su testo).
    func classify() async -> KBClassificationResult {
        switch type {
            
        case .text(let t):
            return await KBSaveClassifier.shared.classify(text: t)
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                return classifyFile(url: fileURL)
            } else {
                // URL web: l'AI classifica il testo dell'URL
                // ma escludiamo .document che non ha senso per un link
                let result = await KBSaveClassifier.shared.classify(text: u)
                let filtered = result.actions.filter {
                    if case .document = $0 { return false }
                    return true
                }
                return KBClassificationResult(
                    actions: filtered,
                    detectedDate: result.detectedDate,
                    isAIClassified: result.isAIClassified
                )
            }
            
        case .image(let url):
            // Foto → Foto e video crittografati
            let fileName = url?.lastPathComponent ?? "foto.jpg"
            return KBClassificationResult(
                actions: [.encryptedMedia(sourceURL: url?.absoluteString ?? "", fileName: fileName, isVideo: false)],
                detectedDate: nil, isAIClassified: false)
            
        case .file(let url):
            return classifyFile(url: url)
            
        case .unknown:
            return KBClassificationResult(actions: [], detectedDate: nil, isAIClassified: false)
        }
    }
    
    private func classifyFile(url: URL) -> KBClassificationResult {
        let ext = url.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v"].contains(ext)
        let isPhoto = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(ext)
        if isVideo || isPhoto {
            return KBClassificationResult(
                actions: [.encryptedMedia(sourceURL: url.absoluteString, fileName: url.lastPathComponent, isVideo: isVideo)],
                detectedDate: nil, isAIClassified: false)
        }
        let hint: KBMediaHint = .generic(fileName: url.lastPathComponent)
        return KBSaveClassifier.shared.classify(mediaURL: url.absoluteString, mimeHint: hint)
    }
}

// MARK: - KBShareDestination display (SwiftUI — share extension)
//
// KBShareDestination è definito in KBSaveClassifier.swift (file condiviso).
// Qui aggiungiamo solo la parte visuale.

extension KBShareDestination {
    
    var label: String {
        switch self {
        case .chat:             return "Chat famiglia"
        case .document:         return "Documenti"
        case .todo:             return "To-Do"
        case .grocery:          return "Lista spesa"
        case .event:            return "Evento"
        case .note:             return "Note"
        case .encryptedMedia:   return "Foto e video"
        }
    }
    
    var icon: String {
        switch self {
        case .chat:             return "bubble.left.and.bubble.right.fill"
        case .document:         return "folder.fill"
        case .todo:             return "checkmark.circle.fill"
        case .grocery:          return "cart.fill"
        case .event:            return "calendar"
        case .note:             return "note.text"
        case .encryptedMedia:   return "photo.stack.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .chat:             return .blue
        case .document:         return Color(red: 0.6, green: 0.45, blue: 0.85)
        case .todo:             return .orange
        case .grocery:          return .green
        case .event:            return .red
        case .note:             return .yellow
        case .encryptedMedia:   return .cyan
        }
    }
    
    var rawStringValue: String { rawValue }
}
