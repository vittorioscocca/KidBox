//
//  KBNoteCardView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import UIKit

struct KBNoteCardView: View {
    let note: KBNote
    let members: [KBFamilyMember]
    var searchQuery: String = ""
    
    // ✅ Cache preview (plain text) to avoid heavy HTML parsing during render
    @State private var previewPlain: String = " "
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlightedText(note.title.isEmpty ? "Senza titolo" : note.title))
                .font(.headline)
                .lineLimit(1)
            
            Text(highlightedText(previewPlain))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
            
            HStack(spacing: 4) {
                let editorName = resolvedName(uid: note.updatedBy)
                if !editorName.isEmpty {
                    Text("✍️ \(editorName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(note.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 110, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // ✅ compute preview once, and recompute only when body changes
        .task(id: note.body) {
            await rebuildPreview(from: note.body)
        }
    }
    
    // MARK: - Preview building (async + cached)
    
    @MainActor
    private func rebuildPreview(from htmlOrPlain: String) async {
        // Fast path
        let trimmed = htmlOrPlain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            previewPlain = " "
            return
        }
        if !trimmed.contains("<") {
            // Already plain
            previewPlain = trimmed
            return
        }
        
        // Heavy path: do it off the main thread
        let result: String = await Task.detached(priority: .utility) {
            return htmlOrPlain.htmlToPlainTextHeavy()
        }.value
        
        let clean = result
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        previewPlain = clean.isEmpty ? " " : clean
    }
    
    // MARK: - Highlight
    
    private func highlightedText(_ input: String) -> AttributedString {
        var attributed = AttributedString(input)
        
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attributed }
        
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var searchRange = input.startIndex..<input.endIndex
        
        while let range = input.range(of: q, options: options, range: searchRange) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow.opacity(0.35)
            }
            searchRange = range.upperBound..<input.endIndex
        }
        
        return attributed
    }
    
    // MARK: - Name resolution
    
    private func resolvedName(uid: String) -> String {
        guard !uid.isEmpty else { return "" }
        guard let m = members.first(where: { $0.userId == uid }) else { return "" }
        let name = (m.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let email = (m.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? "" : email
    }
}

// MARK: - HTML -> plain text (heavy)

private extension String {
    /// Heavy conversion: call this off-main (uses NSAttributedString HTML importer).
    func htmlToPlainTextHeavy() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let attr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attr.string
        }
        return self
    }
}
