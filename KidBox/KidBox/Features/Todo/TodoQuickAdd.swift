//
//  TodoQuickAdd.swift
//  KidBox
//
//  Inserimento veloce dei to-do, come Promemoria di Apple: il «+» apre una
//  riga in cima alla lista (i to-do sono dal più recente) col titolo già a fuoco, una nota e quattro
//  scorciatoie (data, assegna, urgente). «Invio» salva e apre la riga dopo;
//  la «i» salva e apre la scheda completa (`TodoEditView`) per il resto.
//
//  Il to-do nasce come dalla scheda: visibile alla famiglia, senza promemoria
//  (quello si accende dalla scheda, dove c'è anche l'orario).
//

import SwiftUI
import SwiftData

struct TodoQuickDraft: Equatable {
    /// L'id del to-do che nascerà. Viaggia con Handoff: se la stessa bozza
    /// viene salvata su due dispositivi, è lo stesso to-do e non un doppione.
    var id = UUID().uuidString
    var title = ""
    var notes = ""
    var due: Date? = nil
    var assignedTo: String? = nil
    var isUrgent = false

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { trimmedTitle.isEmpty }
}

enum TodoQuickAdd {

    /// Crea il to-do e lo manda in sincronizzazione. `nil` se il titolo è vuoto.
    @MainActor
    @discardableResult
    static func create(
        _ draft: TodoQuickDraft,
        familyId: String,
        childId: String,
        listId: String,
        modelContext: ModelContext
    ) -> String? {
        guard !draft.isEmpty else { return nil }
        let id = draft.id
        // Già salvato dall'altro dispositivo (bozza passata con Handoff):
        // non si riscrive con la versione rimasta qui, magari più vecchia.
        if ((try? modelContext.fetchCount(FetchDescriptor<KBTodoItem>(
            predicate: #Predicate { $0.id == id }
        ))) ?? 0) > 0 { return id }
        let uid = KBUid.current ?? "local"
        let now = Date()
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = KBTodoItem(
            id: id,
            familyId: familyId,
            childId: childId,
            title: draft.trimmedTitle,
            listId: listId,
            notes: notes.isEmpty ? nil : notes,
            // Senza orario: come nella scheda, la scadenza «del giorno» sta alle 9.
            dueAt: draft.due.map(kbStartOfDayReminderTime),
            dueHasTime: false,
            isDone: false,
            doneAt: nil,
            doneBy: nil,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        item.assignedTo = draft.assignedTo
        item.createdBy = uid
        item.priorityRaw = draft.isUrgent ? 1 : 0
        item.visibilityScope = KBVisibilityScope.family
        item.visibilityMemberIds = []
        item.syncState = .pendingUpsert
        item.lastSyncError = nil
        modelContext.insert(item)
        try? modelContext.save()

        SyncCenter.shared.enqueueTodoUpsert(todoId: id, familyId: familyId, modelContext: modelContext)
        Task { await SyncCenter.shared.flush(modelContext: modelContext, remote: TodoRemoteStore()) }
        return id
    }
}

// MARK: - Riga

enum TodoQuickField: Hashable { case title, notes }

struct TodoQuickAddRow: View {
    @Binding var draft: TodoQuickDraft
    var focus: FocusState<TodoQuickField?>.Binding
    let members: [KBFamilyMember]
    let onSubmit: () -> Void
    let onInfo: () -> Void

    /// Le scorciatoie entrano una dopo l'altra, appena la riga è comparsa.
    @State private var chipsShown = false

    private var cal: Calendar { .current }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .imageScale(.large)
                .foregroundStyle(draft.isUrgent ? Color.red : Color.secondary)
                .padding(.top, 1)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: $draft.title)
                    .focused(focus, equals: .title)
                    .submitLabel(.next)
                    .onSubmit(onSubmit)

                TextField("Aggiungi nota", text: $draft.notes, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...4)
                    .focused(focus, equals: .notes)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        dateChip.chipEntrance(chipsShown, index: 0)
                        assigneeChip.chipEntrance(chipsShown, index: 1)
                        urgentChip.chipEntrance(chipsShown, index: 2)
                    }
                    .padding(.vertical, 2)
                }
                .padding(.top, 2)
            }

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dettagli")
        }
        .padding(.vertical, 6)
        .onAppear {
            focus.wrappedValue = .title
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.1)) { chipsShown = true }
        }
    }

    // MARK: Scorciatoie

    private var dateLabel: String? {
        guard let due = draft.due else { return nil }
        if cal.isDateInToday(due) { return String(localized: "Oggi") }
        if cal.isDateInTomorrow(due) { return String(localized: "Domani") }
        return due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func setDue(_ date: Date?) {
        withAnimation(.snappy) { draft.due = date.map { cal.startOfDay(for: $0) } }
    }

    private var dateChip: some View {
        Menu {
            Button { setDue(Date()) } label: { Label("Oggi", systemImage: "sun.max") }
            Button { setDue(cal.date(byAdding: .day, value: 1, to: Date())) } label: {
                Label("Domani", systemImage: "sunrise")
            }
            Button {
                // Sabato prossimo (oggi, se è sabato).
                let next = cal.nextDate(after: cal.startOfDay(for: Date()).addingTimeInterval(-1),
                                        matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
                setDue(next)
            } label: { Label("Questo weekend", systemImage: "sofa") }
            Button {
                let next = cal.nextDate(after: Date(), matching: DateComponents(weekday: 2), matchingPolicy: .nextTime)
                setDue(next)
            } label: { Label("Prossima settimana", systemImage: "calendar.badge.clock") }
            if draft.due != nil {
                Divider()
                Button(role: .destructive) { setDue(nil) } label: { Label("Nessuna data", systemImage: "xmark") }
            }
        } label: {
            QuickChip(systemImage: "calendar", text: dateLabel, active: draft.due != nil, tint: .red)
        }
    }

    private var assigneeName: String? {
        guard let uid = draft.assignedTo else { return nil }
        if uid == KBUid.current { return String(localized: "A me") }
        let m = members.first { $0.userId == uid }
        let name = (m?.displayName ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? m?.email?.split(separator: "@").first.map(String.init) : name.split(separator: " ").first.map(String.init)
    }

    private var assigneeChip: some View {
        Menu {
            if let me = KBUid.current {
                Button { withAnimation(.snappy) { draft.assignedTo = me } } label: {
                    Label("A me", systemImage: "person.fill")
                }
            }
            ForEach(members.filter { $0.userId != KBUid.current }, id: \.userId) { m in
                Button {
                    withAnimation(.snappy) { draft.assignedTo = m.userId }
                } label: {
                    Text(verbatim: (m.displayName?.isEmpty == false ? m.displayName : m.email) ?? m.userId)
                }
            }
            if draft.assignedTo != nil {
                Divider()
                Button(role: .destructive) { withAnimation(.snappy) { draft.assignedTo = nil } } label: {
                    Label("Nessuno", systemImage: "xmark")
                }
            }
        } label: {
            QuickChip(systemImage: "person", text: assigneeName, active: draft.assignedTo != nil, tint: .blue)
        }
    }

    private var urgentChip: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { draft.isUrgent.toggle() }
        } label: {
            QuickChip(systemImage: draft.isUrgent ? "flag.fill" : "flag",
                      text: draft.isUrgent ? String(localized: "Urgente") : nil,
                      active: draft.isUrgent, tint: .red)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: draft.isUrgent)
    }
}

// MARK: - Pezzi comuni (anche per la spesa)

/// Capsula grigia con l'icona; attiva diventa del colore e mostra il valore.
struct QuickChip: View {
    let systemImage: String
    var text: String? = nil
    var active = false
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .symbolEffect(.bounce, value: active)
            if let text {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
            }
        }
        .foregroundStyle(active ? tint : Color.primary)
        .padding(.horizontal, text == nil ? 0 : 12)
        .frame(minWidth: 40, minHeight: 36)
        .background(
            Capsule().fill(active ? tint.opacity(0.15) : Color(.tertiarySystemFill))
        )
        .contentShape(Capsule())
    }
}

extension View {
    /// Entrata a cascata delle scorciatoie: salgono e si allargano una dopo l'altra.
    func chipEntrance(_ shown: Bool, index: Int) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.6)
            .offset(y: shown ? 0 : 8)
            .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(Double(index) * 0.06), value: shown)
    }
}

extension TodoQuickDraft {
    var handoff: KBHandoffDraft {
        KBHandoffDraft(kind: .todo, fields: [
            "id": id, "title": title, "notes": notes,
            "due": KBHandoffDraft.dateString(due),
            "assignedTo": assignedTo, "urgent": isUrgent ? "1" : nil,
        ])
    }

    init(handoff d: KBHandoffDraft) {
        self.init()
        if let v = d.fields["id"] { id = v }
        title = d.fields["title"] ?? ""
        notes = d.fields["notes"] ?? ""
        due = d.date("due")
        assignedTo = d.fields["assignedTo"]
        isUrgent = d.fields["urgent"] == "1"
    }
}

extension AnyTransition {
    /// La riga veloce scende dall'alto con una molla e se ne va sfumando.
    static var quickAddRow: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
        )
    }
}
