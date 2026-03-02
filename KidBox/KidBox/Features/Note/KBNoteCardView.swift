//
//  NoteCardView.swift
//  KidBox
//
//  Created by vscocca on 02/03/26.
//

import SwiftUI
import SwiftData

struct KBNoteCardView: View {
    let note: KBNote
    let members: [KBFamilyMember]
    /// Query corrente dalla home. Se vuota non viene applicato nessun highlight.
    var searchQuery: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlightedText(note.title.isEmpty ? "Senza titolo" : note.title))
                .font(.headline)
                .lineLimit(1)
            
            Text(highlightedText(note.body.isEmpty ? " " : note.body))
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
    }
    
    // MARK: - Highlight
    
    /// Restituisce un AttributedString con tutte le occorrenze di `searchQuery`
    /// evidenziate in giallo. Case e diacritic insensitive.
    private func highlightedText(_ input: String) -> AttributedString {
        var attributed = AttributedString(input)
        
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return attributed }
        
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var searchRange = input.startIndex..<input.endIndex
        
        while let range = input.range(of: q, options: options, range: searchRange) {
            // Converti Range<String.Index> → Range<AttributedString.Index>
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].backgroundColor = .yellow
                attributed[attrRange].foregroundColor = .black
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
