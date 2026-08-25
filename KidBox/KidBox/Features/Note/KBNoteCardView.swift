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
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var previewPlain: String = " "
    
    // MARK: - Dynamic theme (same as LoginView)
    
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Titolo bold
            Text(highlightedText(note.title.isEmpty ? "Senza titolo" : note.title))
                .font(.system(.body, design: .default, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
            
            // Anteprima corpo, poi data sotto (stesso ordine di Android)
            Text(highlightedText(previewPlain))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Orario e chi ha creato/condiviso la nota sulla stessa riga,
            // allineati a sinistra (icona cartella + nome — stile Apple Notes).
            let editorName = resolvedName(uid: note.updatedBy)
            HStack(spacing: 4) {
                Text(formattedDate(note.updatedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !editorName.isEmpty {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 2)
                    Text(editorName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .task(id: note.body) {
            await rebuildPreview(from: note.body)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        let locale = kbDeviceLocale()
        if cal.isDateInToday(date) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        } else if cal.isDateInYesterday(date) {
            return NSLocalizedString("Ieri", comment: "Yesterday")
        } else if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide).locale(locale))
        } else {
            return date.formatted(.dateTime.day().month(.twoDigits).year(.twoDigits).locale(locale))
        }
    }
    
    @MainActor
    private func rebuildPreview(from htmlOrPlain: String) async {
        let trimmed = htmlOrPlain.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { previewPlain = "Nessun contenuto"; return }
        if !trimmed.contains("<") { previewPlain = String(trimmed.prefix(previewLimit)); return }
        // ⚠️ Niente più parser HTML di NSAttributedString su un Task.detached:
        //    è basato su WebKit, va usato solo dal main thread ed era il costo
        //    dominante nello scorrere l'elenco note. Qui serve una riga di
        //    anteprima, quindi tagliamo l'HTML in ingresso e togliamo i tag.
        let clean = NoteHtmlSanitizer.plainText(from: htmlOrPlain, maxInputLength: 1_500)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        previewPlain = clean.isEmpty ? "Nessun contenuto" : String(clean.prefix(previewLimit))
    }

    /// L'anteprima è su una riga sola: oltre questa lunghezza è testo scartato.
    private var previewLimit: Int { 160 }
    
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
