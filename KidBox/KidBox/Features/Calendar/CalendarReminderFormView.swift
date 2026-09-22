//
//  CalendarReminderFormView.swift
//  KidBox
//
//  Il ramo «Promemoria» del calendario: un to-do vero, creato da qui.
//

import SwiftUI
import SwiftData
import FirebaseAuth

/// Quale dei due si sta inserendo dal calendario.
enum CalendarNewItemKind: String, CaseIterable, Identifiable {
    case event
    case reminder

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .event:    return "Evento"
        case .reminder: return "Promemoria"
        }
    }
}

/// Un promemoria del calendario **non è** un'entità nuova: è un `KBTodoItem`
/// con una scadenza, nella lista che l'utente sceglie qui. Il calendario è solo
/// un'altra porta d'ingresso agli stessi to-do — chi li apre da To-Do li trova
/// identici, con assegnatario, visibilità e note al loro posto.
///
/// La forma della scheda ricalca Promemoria di Apple: nome, note, data, ora
/// con interruttore, urgente, elenco. L'unica differenza dichiarata è che qui
/// «Urgente» è anche la scelta della **sveglia**, non un'etichetta di colore.
struct CalendarReminderFormView: View {

    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme

    let familyId: String
    let childId: String
    /// Giorno proposto quando si crea dal calendario.
    let initialDate: Date
    /// Promemoria da modificare; `nil` = nuovo.
    var todo: KBTodoItem?
    /// Mostra la barra di navigazione con Annulla: falso quando la scheda è
    /// già dentro il selettore Evento/Promemoria, che la barra ce l'ha sua.
    var showsNavigationChrome: Bool = true

    @Query private var members: [KBFamilyMember]
    @Query private var allLists: [KBTodoList]
    @Query private var allTodos: [KBTodoItem]

    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate = Date()
    @State private var hasTime = true
    @State private var isUrgent = false
    @State private var listId: String = ""
    @State private var assignedTo: String? = nil
    @State private var showAssigneePicker = false
    @State private var isVisibilitySheetPresented = false
    @State private var selectedVisibilityScope = KBVisibilityScope.family
    @State private var selectedVisibilityMemberIds: Set<String> = []
    @State private var showVisibilityLockedAlert = false
    @State private var didPopulate = false
    @State private var errorMessage: String? = nil

    private let remote = TodoRemoteStore()

    init(
        familyId: String,
        childId: String,
        initialDate: Date,
        todo: KBTodoItem? = nil,
        showsNavigationChrome: Bool = true
    ) {
        self.familyId = familyId
        self.childId = childId
        self.initialDate = initialDate
        self.todo = todo
        self.showsNavigationChrome = showsNavigationChrome

        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \KBFamilyMember.displayName
        )
        _allLists = Query(
            filter: #Predicate<KBTodoList> { $0.familyId == fid && !$0.isDeleted },
            sort: \KBTodoList.createdAt
        )
        _allTodos = Query(
            filter: #Predicate<KBTodoItem> { $0.familyId == fid && !$0.isDeleted },
            sort: \KBTodoItem.updatedAt, order: .reverse
        )
    }

    private var currentUid: String? { Auth.auth().currentUser?.uid }
    private var isNew: Bool { todo == nil }

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
    private var buttonBg: Color { colorScheme == .dark ? .white : .black }
    private var buttonFg: Color { colorScheme == .dark ? .black : .white }

    /// Le stesse liste che si vedono in To-Do: una lista di soli elementi
    /// privati di un altro membro non deve comparire nel selettore.
    private var visibleLists: [KBTodoList] {
        allLists.filter { list in
            TodoListExposure.memberCanSeeListRow(
                listId: list.id,
                todos: allTodos,
                currentUid: currentUid,
                listCreatedBy: list.createdBy
            )
        }
    }

    private var familyMembers: [KBFamilyMember] { members }

    private var isPrivateScope: Bool {
        KBVisibilityScope.normalized(selectedVisibilityScope) == KBVisibilityScope.onlyCreator
    }

    private var canEditVisibility: Bool {
        guard let todo else { return true }
        guard let uid = currentUid else { return false }
        let creator = (todo.createdBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return creator.isEmpty || creator == uid
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var assigneeLabel: String {
        guard let assignedTo else { return String(localized: "Nessuno") }
        if assignedTo == currentUid { return "Me" }
        guard let m = familyMembers.first(where: { $0.userId == assignedTo }) else { return assignedTo }
        let name = (m.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let email = (m.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return email.isEmpty ? String(localized: "Membro") : email
    }

    var body: some View {
        content
            .onAppear {
                guard !didPopulate else { return }
                didPopulate = true
                populate()
            }
            .sheet(isPresented: $showAssigneePicker) {
                AssigneePickerView(
                    familyId: familyId,
                    selected: $assignedTo,
                    meUID: currentUid,
                    meDisplayName: familyMembers.first(where: { $0.userId == currentUid })?.displayName,
                    members: familyMembers.filter { $0.userId != currentUid }
                )
            }
            .sheet(isPresented: $isVisibilitySheetPresented) {
                VisibilityPickerSheet(
                    selectedScope: $selectedVisibilityScope,
                    selectedMemberIds: $selectedVisibilityMemberIds,
                    members: familyMembers.filter { $0.userId != currentUid },
                    currentUid: currentUid,
                    scopeSectionTitle: "Chi può vedere questo promemoria"
                ) { scope, ids in
                    selectedVisibilityScope = scope
                    selectedVisibilityMemberIds = ids
                }
            }
            .alert("Visibilità bloccata", isPresented: $showVisibilityLockedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Solo chi ha creato il promemoria può modificare la visibilità.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if showsNavigationChrome {
            NavigationStack {
                scrollBody
                    .navigationTitle(isNew ? "Nuovo promemoria" : "Modifica promemoria")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annulla") { dismiss() }
                        }
                    }
            }
        } else {
            scrollBody
        }
    }

    private var scrollBody: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    textCard
                    dateCard
                    listCard
                    if !isPrivateScope { assigneeCard }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    saveButton
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal)
                .padding(.top, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Schede

    private var textCard: some View {
        formCard {
            TextField("Nome o descrizione del promemoria", text: $title)
                .font(.body)
            Divider()
            TextField("Note", text: $notes, axis: .vertical)
                .lineLimit(2...)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                label("Visibilità")
                Button {
                    if canEditVisibility {
                        isVisibilitySheetPresented = true
                    } else {
                        showVisibilityLockedAlert = true
                    }
                } label: {
                    HStack {
                        Text(KBVisibilityScope.chipLabel(for: selectedVisibilityScope))
                            .font(.custom("Nunito", size: 14))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(cardBackground.opacity(colorScheme == .dark ? 0.55 : 0.85))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                            .clipShape(Capsule())
                        Spacer(minLength: 8)
                        if canEditVisibility {
                            Text("Cambia")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateCard: some View {
        formCard {
            label("Data e ora")
            HStack {
                Label("Data", systemImage: "calendar")
                Spacer()
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, kbDeviceLocale())
            }
            Divider()
            Toggle(isOn: $hasTime) {
                Label("Ora", systemImage: "clock")
            }
            .tint(buttonBg)
            if hasTime {
                HStack {
                    Spacer()
                    DatePicker("", selection: $dueDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.locale, kbDeviceLocale())
                }
            }
            Divider()
            Toggle(isOn: $isUrgent) {
                Label("Urgente", systemImage: "alarm.waves.left.and.right")
            }
            .tint(buttonBg)
            Text(kbUrgentFooterText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var listCard: some View {
        formCard {
            label("Elenco")
            if visibleLists.isEmpty {
                Text("Non c'è ancora un elenco: il promemoria finisce in «Promemoria», creato adesso.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Elenco", selection: $listId) {
                    ForEach(visibleLists, id: \.id) { list in
                        Text(list.name).tag(list.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var assigneeCard: some View {
        formCard {
            label("Assegnato a")
            Button {
                showAssigneePicker = true
            } label: {
                HStack {
                    Text(assigneeLabel)
                        .foregroundStyle(assignedTo == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            Text(isNew ? "Aggiungi promemoria" : "Salva modifiche")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(buttonFg)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(buttonBg.opacity(canSave ? 1 : 0.35), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(cardBackground))
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    // MARK: - Stato

    private func populate() {
        if let todo {
            title = todo.title
            notes = todo.notes ?? ""
            dueDate = todo.dueAt ?? initialDate
            hasTime = todo.hasDueTime
            isUrgent = todo.isUrgent
            listId = todo.listId ?? visibleLists.first?.id ?? ""
            assignedTo = todo.assignedTo
            selectedVisibilityScope = KBVisibilityScope.normalized(todo.visibilityScope)
            selectedVisibilityMemberIds = Set(todo.visibilityMemberIds ?? [])
        } else {
            // Dal calendario si arriva con un giorno, non con un'ora: si
            // propone la prossima mezz'ora tonda, come farebbe un'agenda.
            dueDate = kbSuggestedReminderDate(on: initialDate)
            listId = visibleLists.first?.id ?? ""
            selectedVisibilityScope = KBVisibilityScope.family
            selectedVisibilityMemberIds = []
        }
    }

    // MARK: - Salvataggio

    @MainActor
    private func save() async {
        errorMessage = nil
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        // Senza orario il promemoria suona alle 9:00, come «tutto il giorno»
        // in Promemoria di Apple: un avviso a mezzanotte non lo legge nessuno.
        let due = hasTime ? dueDate : kbStartOfDayReminderTime(dueDate)

        let targetListId = resolvedListId(uid: uid)
        guard !targetListId.isEmpty else {
            errorMessage = String(localized: "Elenco non disponibile: riprova.")
            return
        }

        let memberIds = selectedVisibilityScope == KBVisibilityScope.members
            ? Array(selectedVisibilityMemberIds).sorted()
            : []

        let item: KBTodoItem
        if let existing = todo {
            existing.title = trimmedTitle
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.dueAt = due
            existing.dueHasTime = hasTime
            existing.isUrgent = isUrgent
            existing.listId = targetListId
            if existing.createdBy == nil { existing.createdBy = uid }
            if canEditVisibility {
                existing.visibilityScope = selectedVisibilityScope
                existing.visibilityMemberIds = memberIds
            }
            existing.assignedTo = isPrivateScope ? uid : assignedTo
            existing.updatedBy = uid
            existing.updatedAt = now
            existing.syncState = .pendingUpsert
            existing.lastSyncError = nil
            item = existing
        } else {
            let created = KBTodoItem(
                id: UUID().uuidString,
                familyId: familyId,
                childId: childId,
                title: trimmedTitle,
                listId: targetListId,
                visibilityScope: selectedVisibilityScope,
                visibilityMemberIds: memberIds,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                dueAt: due,
                dueHasTime: hasTime,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now
            )
            created.createdBy = uid
            created.assignedTo = isPrivateScope ? uid : assignedTo
            created.isUrgent = isUrgent
            created.syncState = .pendingUpsert
            modelContext.insert(created)
            item = created
            AppAnalytics.contentCreated(type: "todo")
        }

        // Un promemoria creato dal calendario **ha** una scadenza: l'avviso è
        // il motivo per cui esiste, quindi si arma senza chiederlo di nuovo.
        TodoReminderService.cancel(todoId: item.id)
        do {
            let rid = try await TodoReminderService.schedule(
                todoId: item.id,
                listId: targetListId,
                familyId: familyId,
                childId: childId,
                title: trimmedTitle,
                dueAt: due,
                isUrgent: isUrgent
            )
            item.reminderEnabled = true
            item.reminderId = rid
        } catch {
            // Il promemoria resta salvato: senza permesso notifiche non suona,
            // ma perderlo del tutto sarebbe peggio.
            item.reminderEnabled = false
            item.reminderId = nil
            errorMessage = String(localized: "Promemoria salvato, ma la notifica non è stata creata: controlla i permessi.")
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        SyncCenter.shared.enqueueTodoUpsert(todoId: item.id, familyId: familyId, modelContext: modelContext)
        await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)

        if errorMessage == nil { dismiss() }
    }

    /// L'elenco scelto, oppure «Promemoria» creato al volo quando la famiglia
    /// non ne ha ancora nessuno: senza `listId` il to-do esisterebbe ma non si
    /// vedrebbe in nessuna lista (è la trappola degli orfani già nota).
    private func resolvedListId(uid: String) -> String {
        if !listId.isEmpty, visibleLists.contains(where: { $0.id == listId }) {
            return listId
        }
        if let first = visibleLists.first { return first.id }
        let list = KBTodoList(
            familyId: familyId,
            childId: childId,
            name: String(localized: "Promemoria"),
            createdBy: uid
        )
        modelContext.insert(list)
        try? modelContext.save()
        SyncCenter.shared.enqueueTodoListUpsert(listId: list.id, familyId: familyId, modelContext: modelContext)
        listId = list.id
        return list.id
    }
}

// MARK: - Helper condivisi con la scheda evento

/// Spiegazione sotto l'interruttore «Urgente»: dice cosa fa davvero, invece di
/// lasciare credere che sia un colore. Il testo cambia quando le sveglie non
/// sono disponibili, così la promessa resta vera.
var kbUrgentFooterText: String {
    if !KBUrgentAlarmService.isSupported {
        return String(localized: "Urgente mette in evidenza il promemoria. Su questo dispositivo la sveglia non è disponibile: arriva una notifica.")
    }
    if KBUrgentAlarmService.isDenied {
        return String(localized: "Le sveglie sono state negate a KidBox: il promemoria urgente arriva come notifica. Puoi riattivarle nelle Impostazioni.")
    }
    return String(localized: "Un promemoria urgente attiva una sveglia: suona anche se il telefono è silenzioso o se è attiva una full immersion.")
}

/// Prossima mezz'ora tonda del giorno scelto, o le 9:00 se il giorno è futuro.
func kbSuggestedReminderDate(on day: Date) -> Date {
    let cal = Calendar.current
    if cal.isDateInToday(day) {
        let next = Date().addingTimeInterval(30 * 60)
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: next)
        comps.minute = (comps.minute ?? 0) < 30 ? 30 : 0
        if (comps.minute ?? 0) == 0 { comps.hour = (comps.hour ?? 0) + 1 }
        return cal.date(from: comps) ?? next
    }
    return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
}

/// L'ora a cui suona un promemoria senza orario.
func kbStartOfDayReminderTime(_ day: Date) -> Date {
    Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
}
