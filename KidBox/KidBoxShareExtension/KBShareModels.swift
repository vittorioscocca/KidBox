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

// Destinazioni disponibili in base al tipo
extension KBSharePayload {
    var availableDestinations: [KBShareDestination] {
        switch type {
        case .image:
            return [.chat, .document]
        case .text(let t):
            // Euristica: se somiglia a una data → evento
            // Se somiglia a una lista → spesa o todo
            return destinations(forText: t)
        case .url:
            return [.chat, .note]
        case .file:
            return [.chat, .document]
        case .unknown:
            return [.chat]
        }
    }
    
    private func destinations(forText text: String) -> [KBShareDestination] {
        var result: [KBShareDestination] = [.chat, .todo, .note]
        if looksLikeDate(text)    { result.insert(.event, at: 1) }
        if looksLikeList(text)    { result.insert(.grocery, at: 2) }
        return result
    }
    
    private func looksLikeDate(_ t: String) -> Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        return detector?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
    
    private func looksLikeList(_ t: String) -> Bool {
        let lines = t.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.count >= 2
    }
}

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
