//
//  TodoEditView.swift
//  KidBox
//
//  Created by vscocca on 25/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct TodoEditView: View {
    
    // Input
    let familyId: String
    let childId: String
    let listId: String
    let listName: String          // nome da mostrare nel titolo
    let todoIdToEdit: String?   // nil = new, non-nil = edit
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    // Members for assignee picker
    @Query private var members: [KBFamilyMember]
    
    // Load todo if editing
    @Query private var editTodos: [KBTodoItem]
    
    private var currentUID: String? { Auth.auth().currentUser?.uid }
    
    // Form state
    @State private var title = ""
    @State private var notes = ""
    @State private var dueDate: Date? = nil
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var isUrgent = false
    
    @State private var assignedTo: String? = nil
    @State private var showAssigneePicker = false
    @State private var errorMessage: String? = nil
    
    @State private var showReminderAlert = false
    @State private var wantsReminder = false   // decisione utente per questo edit
    @State private var reminderPreviewDate: Date = Date()
    
    private let remote = TodoRemoteStore()
    
    init(familyId: String, childId: String, listId: String, listName: String = "Lista", todoIdToEdit: String?) {
        self.familyId = familyId
        self.childId = childId
        self.todoIdToEdit = todoIdToEdit
        self.listId = listId
        self.listName = listName
        
        // ✅ Query solo del todo che sto editando (se nil -> empty)
        if let todoIdToEdit {
            _editTodos = Query(filter: #Predicate<KBTodoItem> { $0.id == todoIdToEdit })
        } else {
            _editTodos = Query(filter: #Predicate<KBTodoItem> { _ in false })
        }
    }
    
    private var editingTodo: KBTodoItem? { editTodos.first }
    
    private var familyMembers: [KBFamilyMember] {
        members.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    private var assigneeLabel: String {
        guard let assignedTo else { return "Nessuno" }
        if assignedTo == currentUID { return "Me" }
        return familyMembers.first(where: { $0.userId == assignedTo })?.displayName ?? "Membro"
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                
                Section {
                    TextField("Titolo", text: $title)
                    TextField("Note", text: $notes)
                }
                
                Section("Scadenza") {
                    Toggle("Imposta scadenza", isOn: $hasDate)
                        .onChange(of: hasDate) { _, isOn in
                            if isOn {
                                if dueDate == nil { dueDate = Date() }
                            } else {
                                dueDate = nil
                                // tolgo anche il promemoria (non ha senso senza scadenza)
                                wantsReminder = false
                            }
                        }
                    
                    if hasDate {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { dueDate ?? Date() },
                                set: { dueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                    }
                    
                    Toggle("Promemoria", isOn: Binding(
                        get: { wantsReminder },
                        set: { newValue in
                            // se non c’è scadenza, non si può attivare
                            guard hasDate, let due = dueDate else {
                                wantsReminder = false
                                return
                            }
                            
                            if newValue == true {
                                // NON attivare subito: mostra alert con data/ora scelta
                                reminderPreviewDate = due
                                showReminderAlert = true
                                wantsReminder = false   // resta off finché non conferma
                            } else {
                                // Spegnimento immediato (qui NON serve alert)
                                wantsReminder = false
                            }
                        }
                    ))
                    .disabled(!hasDate || dueDate == nil)
                }
                .alert("Creare un promemoria?", isPresented: $showReminderAlert) {
                    Button("Sì") {
                        wantsReminder = true
                    }
                    Button("No", role: .cancel) {
                        wantsReminder = false
                    }
                } message: {
                    Text("Vuoi ricevere una notifica locale il \(reminderPreviewDate.formatted(.dateTime.day().month().year().hour().minute()))?")
                }
                
                Toggle("Urgente", isOn: $isUrgent)
                
                Section("Assegnato a") {
                    Button {
                        showAssigneePicker = true
                    } label: {
                        HStack {
                            Text(assigneeLabel)
                                .foregroundStyle(assignedTo == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(todoIdToEdit == nil ? "Nuovo in \(listName)" : "Modifica in \(listName)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                }
                
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .onAppear {
                hydrateIfEditing()
            }
            .onChange(of: hasDate) { _, isOn in
                if isOn {
                    if dueDate == nil { dueDate = Date() }
                } else {
                    dueDate = nil
                    wantsReminder = false
                }
            }
        }
        .sheet(isPresented: $showAssigneePicker) {
            AssigneePickerView(
                familyId: familyId,
                selected: $assignedTo,
                meUID: currentUID,
                meDisplayName: meMember?.displayName,
                members: otherMembers
            )
        }
    }
    
    private var meMember: KBFamilyMember? {
        guard let uid = currentUID else { return nil }
        return familyMembers.first(where: { $0.userId == uid })
    }
    
    private var otherMembers: [KBFamilyMember] {
        let uid = currentUID
        return familyMembers
            .filter { $0.userId != uid }
            .sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
    }
    
    // MARK: - Hydrate
    
    @MainActor
    private func hydrateIfEditing() {
        guard let t = editingTodo else { return }
        
        title = t.title
        notes = t.notes ?? ""
        dueDate = t.dueAt
        hasDate = t.dueAt != nil
        hasTime = false // se vuoi gestirlo “vero” possiamo salvarlo, per ora semplice
        isUrgent = (t.priorityRaw ?? 0) == 1
        assignedTo = t.assignedTo
        wantsReminder = (t.dueAt != nil) ? t.reminderEnabled : false
    }
    
    // MARK: - Save
    
    @MainActor
    private func save() async {
        errorMessage = nil
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // helper: cancella reminder se presente
        func cancelReminderIfNeeded(_ todo: KBTodoItem) {
            if todo.reminderEnabled, let rid = todo.reminderId {
                TodoReminderService.cancel(reminderId: rid)
                todo.reminderEnabled = false
                todo.reminderId = nil
            }
        }
        
        // helper: schedule (sempre 1 per todo)
        func scheduleReminder(_ todo: KBTodoItem, due: Date) async {
            do {
                let rid = try await TodoReminderService.schedule(
                    todoId: todo.id,
                    title: todo.title,
                    dueAt: due
                )
                todo.reminderEnabled = true
                todo.reminderId = rid
            } catch {
                errorMessage = "Promemoria non creato: \(error.localizedDescription)"
            }
        }
        
        if let existing = editingTodo {
            // ✅ Update local fields
            existing.title = trimmedTitle
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.dueAt = hasDate ? dueDate : nil
            existing.assignedTo = assignedTo
            if existing.createdBy == nil { existing.createdBy = uid }
            existing.priorityRaw = isUrgent ? 1 : 0
            
            existing.updatedBy = uid
            existing.updatedAt = now
            existing.syncState = .pendingUpsert
            existing.lastSyncError = nil
            
            // ✅ Reminder logic
            if let due = existing.dueAt {
                if wantsReminder {
                    // reschedule always: safe if due changed, and id is stable
                    cancelReminderIfNeeded(existing)
                    await scheduleReminder(existing, due: due)
                } else {
                    // user doesn't want reminder
                    cancelReminderIfNeeded(existing)
                }
            } else {
                // no due date -> no reminder
                cancelReminderIfNeeded(existing)
            }
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "SwiftData save failed: \(error.localizedDescription)"
                return
            }
            
            // ✅ ONE enqueue + flush after final local state is stable
            SyncCenter.shared.enqueueTodoUpsert(todoId: existing.id, familyId: familyId, modelContext: modelContext)
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
            
            dismiss()
            return
        }
        
        // ✅ Create new
        let id = UUID().uuidString
        let local = KBTodoItem(
            id: id,
            familyId: familyId,
            childId: childId,
            title: trimmedTitle,
            listId: listId,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            dueAt: hasDate ? dueDate : nil,
            isDone: false,
            doneAt: nil,
            doneBy: nil,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now,
            isDeleted: false
        )
        
        local.assignedTo = assignedTo
        local.createdBy = uid
        local.priorityRaw = isUrgent ? 1 : 0
        local.syncState = .pendingUpsert
        local.lastSyncError = nil
        
        // ✅ insert first
        modelContext.insert(local)
        
        // ✅ reminder after insert (and if due exists)
        if wantsReminder, let due = local.dueAt {
            await scheduleReminder(local, due: due)
        }
        
        do {
            try modelContext.save()
        } catch {
            errorMessage = "SwiftData save failed: \(error.localizedDescription)"
            return
        }
        
        SyncCenter.shared.enqueueTodoUpsert(todoId: id, familyId: familyId, modelContext: modelContext)
        await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
        
        dismiss()
    }
}


// MARK: - Assignee Picker

struct AssigneePickerView: View {
    
    let familyId: String
    @Binding var selected: String?
    
    let meUID: String?
    let meDisplayName: String?
    let members: [KBFamilyMember]
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Button {
                    selected = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("Nessuno")
                        Spacer()
                        if selected == nil { Image(systemName: "checkmark") }
                    }
                }
                
                if let meUID {
                    Button {
                        selected = meUID
                        dismiss()
                    } label: {
                        HStack {
                            Text("Io")
                            Text(meDisplayName.map { "(\($0))" } ?? "")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if selected == meUID { Image(systemName: "checkmark") }
                        }
                    }
                }
                
                ForEach(members) { member in
                    Button {
                        selected = member.userId
                        dismiss()
                    } label: {
                        HStack {
                            Text(member.displayName ?? "Membro")
                            Spacer()
                            if selected == member.userId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Assegna a")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
