//
//  ChatAttachmentFileNaming.swift
//  KidBox
//
//  Android (DocumentProvider / cartella Download) può restituire URI con ultimo segmento
//  tipo `msf:188` — non è un nome file. Se usato come `text` / nome su Storage, iOS non
//  sa come aprire l’allegato. Qui normalizziamo il testo in sync e il nome file in preview.
//

import Foundation

enum ChatAttachmentFileNaming {

    /// `content://…/document/msf:123` → lastPathSegment `msf:123` (non leggibile come nome file).
    static func isDownloadsMsfPlaceholder(_ name: String) -> Bool {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        return t.range(of: #"^msf:\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Testo messaggio documento mostrato in UI / SwiftData dopo sync.
    static func sanitizeDocumentDisplayText(_ text: String) -> String {
        if isDownloadsMsfPlaceholder(text) { return "Allegato" }
        return text
    }

    static func sniffPreferredExtension(from data: Data) -> String {
        guard !data.isEmpty else { return "bin" }
        var head = [UInt8](repeating: 0, count: min(16, data.count))
        data.copyBytes(to: &head, count: head.count)
        if head.count >= 4, head[0] == 0x25, head[1] == 0x50, head[2] == 0x44, head[3] == 0x46 { return "pdf" }
        if head.count >= 3, head[0] == 0xFF, head[1] == 0xD8, head[2] == 0xFF { return "jpg" }
        if head.count >= 8, head[0] == 0x89, head[1] == 0x50, head[2] == 0x4E, head[3] == 0x47 { return "png" }
        if head.count >= 6, head[0] == 0x47, head[1] == 0x49, head[2] == 0x46, head[3] == 0x38 { return "gif" }
        if head.count >= 12, head[0] == 0x52, head[1] == 0x49, head[2] == 0x46, head[3] == 0x46,
           head[8] == 0x57, head[9] == 0x45, head[10] == 0x42, head[11] == 0x50 { return "webp" }
        if head.count >= 2, head[0] == 0x50, head[1] == 0x4B { return "zip" }
        return "bin"
    }

    /// Nome file per copia temporanea e Quick Look dopo download.
    static func localPreviewFileName(storedText: String?, remoteURL: URL, sniffedExtension: String) -> String {
        let trimmed = storedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stored = trimmed.isEmpty ? remoteURL.lastPathComponent : trimmed
        if isDownloadsMsfPlaceholder(stored) { return "Allegato.\(sniffedExtension)" }
        let pathExt = (stored as NSString).pathExtension.lowercased()
        if pathExt.isEmpty { return "\(stored).\(sniffedExtension)" }
        return stored
    }
}
