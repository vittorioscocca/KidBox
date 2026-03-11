//
//  KBShareModels.swift
//  KidBox
//
//  Created by vscocca on 10/03/26.
//
import Foundation
import SwiftUI

enum KBShareContentType {
    case image(URL?)
    case text(String)
    case url(String)
    case file(URL)
    case unknown
}

struct KBSharePayload {
    let type: KBShareContentType
}

extension KBShareDestination {
    var rawStringValue: String {
        switch self {
        case .chat:     return "chat"
        case .document: return "document"
        case .todo:     return "todo"
        case .grocery:  return "grocery"
        case .event:    return "event"
        case .note:     return "note"
        }
    }
}

// MARK: - Destinazioni disponibili per tipo di contenuto
//
// Matrice contenuto → destinazioni:
//
// Testo          → Chat, Note, Todo, (Evento se contiene data), (Spesa se è una lista)
// URL web        → Chat, Note, Todo
// Immagine       → Chat, Documenti
// File generico  → Chat, Documenti
// Video          → Chat (solo — upload pesante, via App Group)
// Sconosciuto    → Chat

extension KBSharePayload {
    
    var availableDestinations: [KBShareDestination] {
        switch type {
            
        case .image:
            // Immagine → chat o archivio documenti famiglia
            return [.chat, .document]
            
        case .text(let t):
            return destinations(forText: t)
            
        case .url(let u):
            if let fileURL = URL(string: u), fileURL.isFileURL {
                // File locale (es. PDF da iCloud Drive)
                return destinations(forFileURL: fileURL)
            } else {
                // URL web → chat, note, todo (un link può diventare
                // un appunto o un'attività da fare)
                return [.chat, .note, .todo]
            }
            
        case .file(let url):
            return destinations(forFileURL: url)
            
        case .unknown:
            return [.chat]
        }
    }
    
    // MARK: - Helpers
    
    /// Destinazioni per un file locale in base all'estensione.
    private func destinations(forFileURL url: URL) -> [KBShareDestination] {
        let ext = url.pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "m4v", "m4v"].contains(ext)
        
        if isVideo {
            // Video: solo chat (upload via App Group, nessun senso archiviarli in Documenti)
            return [.chat]
        } else {
            // PDF, doc, immagine, zip, ecc. → chat o documenti famiglia
            return [.chat, .document]
        }
    }
    
    /// Destinazioni per testo puro, con euristica sul contenuto.
    private func destinations(forText text: String) -> [KBShareDestination] {
        // Base: chat, note, todo
        var result: [KBShareDestination] = [.chat, .note, .todo]
        
        // Se il testo contiene una data → suggerisci Evento (posizione 1)
        if looksLikeDate(text) {
            result.insert(.event, at: 1)
        }
        
        // Se il testo è una lista di righe → suggerisci Lista spesa
        // (inserita dopo .event se presente, altrimenti dopo .chat)
        if looksLikeList(text) {
            let groceryIndex = result.firstIndex(of: .todo) ?? result.endIndex
            result.insert(.grocery, at: groceryIndex)
        }
        
        return result
    }
    
    private func looksLikeDate(_ t: String) -> Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        return detector?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
    
    private func looksLikeList(_ t: String) -> Bool {
        let lines = t.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.count >= 2
    }
}

// MARK: - KBShareDestination

enum KBShareDestination: CaseIterable, Identifiable {
    case chat, document, todo, grocery, event, note
    
    var id: Self { self }
    
    var label: String {
        switch self {
        case .chat:     return "Chat famiglia"
        case .document: return "Documenti"
        case .todo:     return "To-Do"
        case .grocery:  return "Lista spesa"
        case .event:    return "Evento"
        case .note:     return "Note"
        }
    }
    
    var icon: String {
        switch self {
        case .chat:     return "bubble.left.and.bubble.right.fill"
        case .document: return "folder.fill"
        case .todo:     return "checkmark.circle.fill"
        case .grocery:  return "cart.fill"
        case .event:    return "calendar"
        case .note:     return "note.text"
        }
    }
    
    var color: Color {
        switch self {
        case .chat:     return .blue
        case .document: return Color(red: 0.6, green: 0.45, blue: 0.85)
        case .todo:     return .orange
        case .grocery:  return .green
        case .event:    return .red
        case .note:     return .yellow
        }
    }
}
