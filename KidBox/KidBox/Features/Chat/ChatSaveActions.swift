//
//  ChatSaveActions.swift
//  KidBox  ← solo main app target
//
//  Cosa si può salvare in KidBox da un messaggio della chat: euristica sincrona
//  e riconoscimento degli indirizzi. Li usano i banner di «Azioni suggerite»
//  (ChatSuggestedActions.swift); il «Salva in…» a pressione lunga non c'è più.
//

import SwiftUI

// MARK: - KBChatMessage + azioni di salvataggio

extension KBChatMessage {
    
    /// Euristica sincrona: dove ha senso salvare il messaggio (per i media, una destinazione sola).
    var quickSaveActions: [KBSaveAction] {
        switch type {
            
        case .text:
            guard let text = self.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return [] }
            
            let lines = text
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            var result: [KBSaveAction] = []
            if let address = KBAddressDetector.firstAddress(in: text) {
                result.append(.map(address: address))
            }
            if lines.count >= 2 { result.append(.grocery(lines: lines)) }
            
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.date.rawValue)
            let range = NSRange(text.startIndex..., in: text)
            if let date = detector?.firstMatch(in: text, range: range)?.date {
                result.append(.event(title: text, date: date))
            }
            // Todo solo per testo breve su riga singola
            if lines.count == 1 && text.count < 120 {
                result.append(.todo(title: lines.first ?? text))
            }
            result.append(.note(
                title: lines.first ?? text,
                body: lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : text))
            return result
            
        case .photo:
            guard let url = mediaURL else { return [] }
            return [.encryptedMedia(sourceURL: url, fileName: "foto.jpg", isVideo: false)]
            
        case .video:
            guard let url = mediaURL else { return [] }
            return [.encryptedMedia(sourceURL: url, fileName: "video.mp4", isVideo: true)]
            
        case .document:
            guard let url = mediaURL else { return [] }
            return [.document(mediaURL: url, fileName: self.text ?? "documento")]
            
        case .audio, .location, .mediaGroup, .contact:
            return []
        }
    }
}

// MARK: - Riconoscimento indirizzi

enum KBAddressDetector {
    /// Primo indirizzo postale nel testo (NSDataDetector), nil se assente.
    nonisolated static func firstAddress(in text: String) -> String? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.address.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = detector.firstMatch(in: text, range: range),
              let r = Range(m.range, in: text) else { return nil }
        let s = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
