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
        guard let uid = assignedTo else { return "Nessuno" }
        return familyMembers.first(where: { $0.userId == uid })?.displayName ?? "Membro"
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
                                if dueDate == nil {
                                    dueDate = Date()
                                }
                            } else {
                                dueDate = nil
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
                    
                    Toggle("Urgente", isOn: $isUrgent)
                }
                
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
        }
        .sheet(isPresented: $showAssigneePicker) {
            AssigneePickerView(
                familyId: familyId,
                selected: $assignedTo
            )
        }
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
        
        // Default: se non assegnato, resta "Nessuno" (B)
    }
    
    // MARK: - Save
    
    @MainActor
    private func save() async {
        errorMessage = nil
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let existing = editingTodo {
            // ✅ Update
            existing.title = trimmedTitle
            existing.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            existing.dueAt = hasDate ? dueDate : nil
            
            existing.assignedTo = assignedTo
            if existing.createdBy == nil {
                existing.createdBy = uid
            }
            existing.priorityRaw = isUrgent ? 1 : 0
            
            existing.updatedBy = uid
            existing.updatedAt = now
            existing.syncState = .pendingUpsert
            existing.lastSyncError = nil
            
            do {
                try modelContext.save()
            } catch {
                errorMessage = "SwiftData save failed: \(error.localizedDescription)"
                return
            }
            
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
        
        // new fields
        local.assignedTo = assignedTo
        local.createdBy = uid
        local.priorityRaw = isUrgent ? 1 : 0
        
        local.syncState = .pendingUpsert
        local.lastSyncError = nil
        
        modelContext.insert(local)
        
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
    
    @Environment(\.dismiss) private var dismiss
    @Query private var members: [KBFamilyMember]
    
    private var familyMembers: [KBFamilyMember] {
        members.filter { $0.familyId == familyId && !$0.isDeleted }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Button("Nessuno") {
                    selected = nil
                    dismiss()
                }
                
                ForEach(familyMembers) { member in
                    Button {
                        selected = member.userId
                        dismiss()
                    } label: {
                        HStack {
                            Text(member.displayName ?? "Nessun membro presente")
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
