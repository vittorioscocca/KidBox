//
//  ChatSuggestedActions.swift
//  KidBox  ← solo main app target
//
//  «Azioni suggerite»: piccoli banner sotto la bolla di un messaggio di testo
//  (Aggiungi a calendario, lista spesa, to-do, Note; Mostra in mappa) che alla
//  pressione eseguono subito l'azione. Ogni tipo si accende/spegne da
//  Impostazioni > Messaggi > Azioni suggerite.
//  Un tipo acceso ma mai toccato per 30 giorni si spegne da solo: l'orologio
//  parte la prima volta che compare, riparte a ogni tocco e a ogni riaccensione.
//

import SwiftUI

// MARK: - Preferenze

enum KBSuggestedActionKind: String, CaseIterable, Identifiable {
    case calendar, grocery, todo, note, map
    
    var id: String { rawValue }
    
    /// Chiave UserDefaults (per dispositivo). Default: acceso.
    var defaultsKey: String { "kb.chat.suggested.\(rawValue)" }
    
    var title: String {
        switch self {
        case .calendar: return "Aggiungi a calendario"
        case .grocery:  return "Aggiungi a lista spesa"
        case .todo:     return "Aggiungi a to-do"
        case .note:     return "Aggiungi a Note"
        case .map:      return "Mostra in mappa"
        }
    }
    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .grocery:  return "cart.fill"
        case .todo:     return "checkmark.circle.fill"
        case .note:     return "note.text"
        case .map:      return "map.fill"
        }
    }
    var color: Color {
        switch self {
        case .calendar: return .red
        case .grocery:  return .green
        case .todo:     return .orange
        case .note:     return .yellow
        case .map:      return .blue
        }
    }
    
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }
    
    // MARK: Scadenza dei suggerimenti non usati
    
    static let staleAfter: TimeInterval = 30 * 24 * 3600
    
    private var lastUsedKey: String { "\(defaultsKey).lastUsed" }
    
    /// Riparte l'orologio dei 30 giorni (tocco del banner o riaccensione).
    func markUsed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastUsedKey)
    }
    
    /// Il tipo è comparso: se l'orologio non è mai partito parte ora; se sono
    /// passati 30 giorni senza un tocco, il tipo si spegne. true = resta visibile.
    @discardableResult
    func noteShown() -> Bool {
        guard isEnabled else { return false }
        let d = UserDefaults.standard
        guard let last = d.object(forKey: lastUsedKey) as? Double else {
            markUsed()
            return true
        }
        if Date().timeIntervalSince1970 - last > Self.staleAfter {
            d.set(false, forKey: defaultsKey)
            return false
        }
        return true
    }
}

extension KBSaveAction {
    var suggestedKind: KBSuggestedActionKind? {
        switch self {
        case .event:   return .calendar
        case .grocery: return .grocery
        case .todo:    return .todo
        case .note:    return .note
        case .map:     return .map
        case .document, .encryptedMedia: return nil
        }
    }
}

// MARK: - Calcolo (con cache: le bolle si ricreano scorrendo)

@MainActor
enum KBSuggestedActionsCache {
    private static var cache: [String: [KBSaveAction]] = [:]
    
    static func actions(for message: KBChatMessage) async -> [KBSaveAction] {
        guard message.type == .text,
              let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return [] }
        let key = "\(message.id)|\(text.hashValue)"
        if let hit = cache[key] { return hit }
        
        var result: [KBSaveAction] = []
        if let address = KBAddressDetector.firstAddress(in: text) {
            result.append(.map(address: address))
        }
        result += await KBSaveClassifier.shared.suggestedChips(text: text)
        let limited = Array(result.prefix(3))
        cache[key] = limited
        return limited
    }
}

// MARK: - Riga di banner

struct ChatSuggestedActionsRow: View {
    let message: KBChatMessage
    let onTap: (KBSaveAction) -> Void
    
    @State private var actions: [KBSaveAction] = []
    @State private var doneIds: Set<String> = []
    // Letti da @AppStorage così il banner sparisce appena si spegne il tipo.
    @AppStorage(KBSuggestedActionKind.calendar.defaultsKey) private var calendarOn = true
    @AppStorage(KBSuggestedActionKind.grocery.defaultsKey)  private var groceryOn = true
    @AppStorage(KBSuggestedActionKind.todo.defaultsKey)     private var todoOn = true
    @AppStorage(KBSuggestedActionKind.note.defaultsKey)     private var noteOn = true
    @AppStorage(KBSuggestedActionKind.map.defaultsKey)      private var mapOn = true
    
    private func isOn(_ kind: KBSuggestedActionKind) -> Bool {
        switch kind {
        case .calendar: return calendarOn
        case .grocery:  return groceryOn
        case .todo:     return todoOn
        case .note:     return noteOn
        case .map:      return mapOn
        }
    }
    
    private var visible: [(action: KBSaveAction, kind: KBSuggestedActionKind)] {
        actions.compactMap { a in
            guard let k = a.suggestedKind, isOn(k) else { return nil }
            return (a, k)
        }
    }
    
    var body: some View {
        Group {
            if !visible.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visible, id: \.action.id) { item in
                            chip(item.action, item.kind)
                        }
                    }
                }
            }
        }
        .task(id: message.id + (message.text ?? "")) {
            let found = await KBSuggestedActionsCache.actions(for: message)
            // Fuori dall'aggiornamento della view: può spegnere un tipo scaduto.
            for kind in Set(found.compactMap(\.suggestedKind)) { kind.noteShown() }
            actions = found
        }
    }
    
    private func chip(_ action: KBSaveAction, _ kind: KBSuggestedActionKind) -> some View {
        let done = doneIds.contains(action.id)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            doneIds.insert(action.id)
            kind.markUsed()
            onTap(action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : kind.icon)
                    .font(.footnote)
                    .foregroundStyle(done ? Color.green : kind.color)
                Text(LocalizedStringKey(kind.title))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Impostazioni

struct KBSuggestedActionsSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    var body: some View {
        List {
            Section {
                ForEach(KBSuggestedActionKind.allCases) { kind in
                    KindToggle(kind: kind)
                        .listRowBackground(cardBackground)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("I suggerimenti che non usi smetteranno di apparire dopo 30 giorni.")
                    Text("Sotto un messaggio di testo compaiono i banner delle azioni attive: un tocco e l'azione parte. Il riconoscimento avviene sul dispositivo.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Azioni suggerite")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private struct KindToggle: View {
        let kind: KBSuggestedActionKind
        @AppStorage private var isOn: Bool
        
        init(kind: KBSuggestedActionKind) {
            self.kind = kind
            _isOn = AppStorage(wrappedValue: true, kind.defaultsKey)
        }
        
        var body: some View {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { kind.markUsed() }   // riaccendere fa ripartire i 30 giorni
                    isOn = on
                }
            )) {
                HStack(spacing: 12) {
                    Image(systemName: kind.icon)
                        .foregroundStyle(kind.color)
                        .frame(width: 22)
                    Text(LocalizedStringKey(kind.title))
                }
            }
            .tint(KBTheme.bubbleTint)
        }
    }
}
