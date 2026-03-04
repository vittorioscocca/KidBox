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
    
    @State private var previewPlain: String = " "
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Titolo bold
            Text(highlightedText(note.title.isEmpty ? "Senza titolo" : note.title))
                .font(.system(.body, design: .default, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            // Data + anteprima corpo
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedDate(note.updatedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(highlightedText(previewPlain))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Autore
            let editorName = resolvedName(uid: note.updatedBy)
            if !editorName.isEmpty {
                Text("Autore: \(editorName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .task(id: note.body) {
            await rebuildPreview(from: note.body)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if cal.isDateInYesterday(date) {
            return "Ieri"
        } else if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        } else {
            return date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits))
        }
    }
    
    @MainActor
    private func rebuildPreview(from htmlOrPlain: String) async {
        let trimmed = htmlOrPlain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { previewPlain = "Nessun contenuto"; return }
        if !trimmed.contains("<") { previewPlain = trimmed; return }
        let result: String = await Task.detached(priority: .utility) {
            await htmlOrPlain.htmlToPlainTextHeavy()
        }.value
        let clean = result
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        previewPlain = clean.isEmpty ? "Nessun contenuto" : clean
    }
    
    private func highlightedText(_ input: String) -> AttributedString {
        var attributed = AttributedString(input)
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attributed }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var searchRange = input.startIndex..<input.endIndex
        while let range = input.range(of: q, options: options, range: searchRange) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow.opacity(0.5)
            }
            searchRange = range.upperBound..<input.endIndex
        }
        return attributed
    }
    
    private func resolvedName(uid: String) -> String {
        guard !uid.isEmpty else { return "" }
        guard let m = members.first(where: { $0.userId == uid }) else { return "" }
        let name = (m.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let email = (m.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? "" : email
    }
}

private extension String {
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
