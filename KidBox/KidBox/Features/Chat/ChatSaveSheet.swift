//
//  ChatSaveSheet.swift
//  KidBox
//
//  Created by vscocca on 11/03/26.
//

import SwiftUI

// MARK: - Azione risultante

enum ChatSaveAction: Identifiable {
    case todo(title: String)
    case event(title: String, date: Date?)
    case grocery(lines: [String])
    case note(title: String, body: String)
    case document(mediaURL: String, fileName: String)
    
    var id: String {
        switch self {
        case .todo:     return "todo"
        case .event:    return "event"
        case .grocery:  return "grocery"
        case .note:     return "note"
        case .document: return "document"
        }
    }
}

// MARK: - Detection

extension KBChatMessage {
    
    /// Destinazioni "salva in…" disponibili per questo messaggio.
    var saveDestinations: [ChatSaveAction] {
        switch type {
            
        case .text:
            guard let text = self.text,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return [] }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var result: [ChatSaveAction] = []
            
            // Lista ≥ 2 righe → grocery (prima)
            let lines = trimmed.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if lines.count >= 2 {
                result.append(.grocery(lines: lines))
            }
            
            // Contiene data → evento
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.date.rawValue
            )
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = detector?.firstMatch(in: trimmed, range: range),
               let date = match.date {
                result.append(.event(title: trimmed, date: date))
            }
            
            // Sempre: todo e nota
            result.append(.todo(title: lines.first ?? trimmed))
            result.append(.note(
                title: lines.first ?? trimmed,
                body: lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : trimmed
            ))
            return result
            
        case .photo:
            guard let url = mediaURL else { return [] }
            return [.document(mediaURL: url, fileName: "foto.jpg")]
            
        case .document:
            guard let url = mediaURL else { return [] }
            return [.document(mediaURL: url, fileName: self.text ?? "documento")]
            
        case .video:
            guard let url = mediaURL else { return [] }
            return [.document(mediaURL: url, fileName: "video.mp4")]
            
        case .audio, .location:
            return []
        }
    }
}

// MARK: - Sheet view

struct ChatSaveSheet: View {
    let message: KBChatMessage
    let onSelect: (ChatSaveAction) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Preview del contenuto
                if let text = message.text, !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                
                Text("Salva in…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 16)
                
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(message.saveDestinations) { action in
                        Button {
                            onSelect(action)
                            onDismiss()
                        } label: {
                            actionCard(action)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Salva in…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { onDismiss() }
                }
            }
        }
    }
    
    private func actionCard(_ action: ChatSaveAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.title3)
                .foregroundStyle(action.color)
                .frame(width: 36, height: 36)
                .background(action.color.opacity(0.12), in: Circle())
            
            Text(action.label)
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Label / icon / color

private extension ChatSaveAction {
    var label: String {
        switch self {
        case .todo:     return "To-Do"
        case .event:    return "Evento"
        case .grocery:  return "Lista spesa"
        case .note:     return "Nota"
        case .document: return "Documenti"
        }
    }
    
    var icon: String {
        switch self {
        case .todo:     return "checkmark.circle.fill"
        case .event:    return "calendar"
        case .grocery:  return "cart.fill"
        case .note:     return "note.text"
        case .document: return "folder.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .todo:     return .orange
        case .event:    return .red
        case .grocery:  return .green
        case .note:     return .yellow
        case .document: return Color(red: 0.6, green: 0.45, blue: 0.85)
        }
    }
}
