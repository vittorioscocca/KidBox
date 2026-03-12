//
//  ChatSaveSheet.swift
//  KidBox  ← solo main app target
//
//  Sheet "Salva in…" che appare tenendo premuto un messaggio in chat.
//  Usa KBSaveClassifier (file condiviso) per la classificazione AI on-device.
//

import SwiftUI

// MARK: - Sheet

struct ChatSaveSheet: View {
    let message: KBChatMessage
    let onSelect: (KBSaveAction) -> Void
    let onDismiss: () -> Void
    
    @State private var actions: [KBSaveAction]? = nil   // nil = in caricamento
    @State private var isAIClassified = false
    
    /// Mostra subito l'euristica sincrona, poi aggiorna con AI.
    private var displayedActions: [KBSaveAction] {
        actions ?? message.quickSaveActions
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                
                // Preview testo
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
                
                // Header
                HStack {
                    Text("Salva in…")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if actions != nil {
                        if isAIClassified {
                            Label("Apple Intelligence", systemImage: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                                .transition(.opacity)
                        }
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .animation(.easeInOut, value: actions != nil)
                .padding(.horizontal)
                .padding(.top, 16)
                
                // Griglia azioni
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(displayedActions) { action in
                        Button {
                            onSelect(action)
                            onDismiss()
                        } label: {
                            ActionCard(action: action)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .animation(.spring(duration: 0.35), value: displayedActions.map(\.id))
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
            .task {
                let result = await message.classifyForSave()
                withAnimation {
                    actions = result.actions
                    isAIClassified = result.isAIClassified
                }
            }
        }
    }
}

// MARK: - Card

private struct ActionCard: View {
    let action: KBSaveAction
    
    var body: some View {
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

// MARK: - KBChatMessage + classify

extension KBChatMessage {
    
    /// Classificazione async con AI — chiamata da .task {}
    func classifyForSave() async -> KBClassificationResult {
        switch type {
        case .text:
            guard let text = self.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return .empty }
            return await KBSaveClassifier.shared.classify(text: text)
            
        case .photo:
            guard let url = mediaURL else { return .empty }
            return KBSaveClassifier.shared.classify(mediaURL: url, mimeHint: .image)
            
        case .video:
            guard let url = mediaURL else { return .empty }
            return KBSaveClassifier.shared.classify(mediaURL: url, mimeHint: .video)
            
        case .document:
            guard let url = mediaURL else { return .empty }
            return KBSaveClassifier.shared.classify(
                mediaURL: url, mimeHint: .generic(fileName: self.text ?? "documento"))
            
        case .audio, .location:
            return .empty
        }
    }
    
    /// Euristica sincrona — preview immediato mentre l'AI elabora.
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
            return [.document(mediaURL: url, fileName: "foto.jpg")]
            
        case .video:
            guard let url = mediaURL else { return [] }
            return [.document(mediaURL: url, fileName: "video.mp4")]
            
        case .document:
            guard let url = mediaURL else { return [] }
            return [.document(mediaURL: url, fileName: self.text ?? "documento")]
            
        case .audio, .location:
            return []
        }
    }
}

// MARK: - KBClassificationResult convenience

extension KBClassificationResult {
    static var empty: KBClassificationResult {
        .init(actions: [], detectedDate: nil, isAIClassified: false)
    }
}

// MARK: - KBSaveAction display (SwiftUI — solo main app)

extension KBSaveAction {
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
