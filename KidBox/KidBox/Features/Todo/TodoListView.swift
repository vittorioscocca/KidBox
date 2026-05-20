import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog

struct TodoListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme)  private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    // MARK: - Dynamic theme (same as LoginView)
    
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
    
    @Query private var todos: [KBTodoItem]
    @Query private var members: [KBFamilyMember]
    
    private let remote = TodoRemoteStore()
    
    private let familyId: String
    private let childId: String
    private let listId: String
    
    @State private var editingTarget: TodoEditTarget? = nil
    @State private var didStartRealtime = false
    
    @StateObject private var highlightStore = TodoHighlightStore.shared
    @State private var highlightedTodoId: String? = nil
    
    // Query per recuperare il nome della lista
    @Query private var allLists: [KBTodoList]
    
    // Trace per correlare log durante la vita della view
    @State private var viewTrace: String = {
        let s = UUID().uuidString
        return String(s.prefix(8))
    }()
    
    // MARK: - Init
    
    init(familyId: String, childId: String, listId: String) {
        self.familyId = familyId
        self.childId = childId
        self.listId = listId
        
        let fid = familyId
        let cid = childId
        
        _todos = Query(
            filter: #Predicate<KBTodoItem> { t in
                t.familyId == fid &&
                t.childId == cid &&
                t.isDeleted == false
            },
            sort: [SortDescriptor(\KBTodoItem.createdAt, order: .reverse)]
        )
        
        KBLog.todo.kbDebug("TodoListView init familyId=\(familyId) childId=\(childId) listId=\(listId)")
    }
    
    // MARK: - Computed
    
    private var listName: String {
        allLists.first(where: { $0.id == listId })?.name ?? "Lista"
    }
    
    private var currentUid: String? { Auth.auth().currentUser?.uid }

    private var visibleTodos: [KBTodoItem] {
        todos.filter {
            $0.listId == listId &&
            !$0.isDeleted &&
            $0.isVisible(to: currentUid)
        }
    }
    
    /// Lista con solo To-Do di altri (tutti non visibili al membro corrente).
    private var listAccessDenied: Bool {
        !TodoListExposure.memberCanSeeListRow(
            listId: listId,
            todos: todos.filter { !$0.isDeleted },
            currentUid: currentUid,
        )
    }
    
    // MARK: - Body
    
    var body: some View {
        Group {
            if listAccessDenied {
                listAccessDeniedContent
            } else {
        ScrollViewReader { proxy in
            List {
                if visibleTodos.isEmpty {
                    Text("Nessun To-Do")
                        .foregroundStyle(.secondary)
                        .listRowBackground(cardBackground)
                } else {
                    ForEach(visibleTodos) { todo in
                        row(todo)
                            .id(todo.id)
                            .listRowBackground(cardBackground)
                    }
                    .onDelete(perform: deleteTodos)
                }
            }
            .scrollContentBackground(.hidden)   // ← nasconde il grigio di sistema
            .background(backgroundColor)
            .navigationTitle(listName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] tap + addTodo listId=\(listId)")
                        editingTarget = TodoEditTarget(id: UUID().uuidString, todoId: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingTarget) { target in
                TodoEditView(
                    familyId: familyId,
                    childId: childId,
                    listId: listId,
                    listName: listName,
                    todoIdToEdit: target.todoId
                )
                .onAppear {
                    let idStr = target.todoId ?? "nil"
                    KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] TodoEditView appeared todoIdToEdit=\(idStr) listId=\(listId)")
                }
                .onDisappear {
                    KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] TodoEditView disappeared listId=\(listId)")
                }
            }
            .onAppear {
                KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] onAppear listId=\(listId) didStartRealtime=\(didStartRealtime) todosQueryCount=\(todos.count) visibleCount=\(visibleTodos.count)")
                
                let sample = visibleTodos.prefix(5).map(\.id).joined(separator: ",")
                KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] visible sample ids=[\(sample)]")
                
                guard !didStartRealtime else {
                    Task { @MainActor in
                        applyHighlightIfNeeded(proxy: proxy, reason: "onAppear (already started)")
                    }
                    return
                }
                
                didStartRealtime = true
                
                KBLog.sync.kbInfo("[TodoListView][\(viewTrace)] startTodoRealtime familyId=\(familyId) childId=\(childId)")
                SyncCenter.shared.startTodoRealtime(
                    familyId: familyId,
                    childId: childId,
                    modelContext: modelContext,
                    remote: remote
                )
                
                Task { @MainActor in
                    KBLog.sync.kbDebug("[TodoListView][\(viewTrace)] flush (onAppear)")
                    await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
                    
                    applyHighlightIfNeeded(proxy: proxy, reason: "onAppear after flush")
                }
            }
            .onChange(of: highlightStore.todoIdToHighlight) { _, _ in
                Task { @MainActor in
                    applyHighlightIfNeeded(proxy: proxy, reason: "highlightStore changed")
                }
            }
            .onChange(of: visibleTodos.count) { old, new in
                KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] visibleTodos.count changed \(old)->\(new)")
                Task { @MainActor in
                    applyHighlightIfNeeded(proxy: proxy, reason: "visibleTodos.count changed")
                }
            }
            .onDisappear {
                KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] onDisappear listId=\(listId)")
            }
        }
            }
        }
    }
    
    private var listAccessDeniedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Questo contenuto non è più disponibile.")
                .font(.headline)
            Text("Questa lista contiene solo attività personali di altri membri.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(backgroundColor)
        .navigationTitle(listName)
    }
    
    // MARK: - Highlight
    
    @MainActor
    private func applyHighlightIfNeeded(proxy: ScrollViewProxy, reason: String) {
        guard !familyId.isEmpty else { return }
        
        // 1️⃣ reset su Firestore
        Task { await CountersService.shared.reset(familyId: familyId, field: .todos) }
        
        // 2️⃣ azzera subito badge locale (UX immediata)
        BadgeManager.shared.clearTodos()
        guard let targetId = highlightStore.todoIdToHighlight else { return }
        
        guard visibleTodos.contains(where: { $0.id == targetId }) else {
            KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] highlight pending (not in visibleTodos yet) todoId=\(targetId) reason=\(reason)")
            return
        }
        
        KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] highlight APPLY todoId=\(targetId) reason=\(reason)")
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            proxy.scrollTo(targetId, anchor: .center)
            highlightedTodoId = targetId
        }
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedTodoId = nil
            }
            highlightStore.consumeIfMatches(targetId)
            KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] highlight consumed todoId=\(targetId)")
        }
    }
    
    // MARK: - Row
    
    private func row(_ todo: KBTodoItem) -> some View {
        let isHighlighted = (highlightedTodoId == todo.id)
        
        return HStack(spacing: 12) {
            Button {
                KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] tap toggleDone todoId=\(todo.id) isDone=\(todo.isDone)")
                Task { await toggleDone(todo) }
            } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 5) {
                // Riga 1: titolo + urgente + promemoria
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(todo.title)
                        .strikethrough(todo.isDone)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if (todo.priorityRaw ?? 0) == 1 {
                        Text("Urgente")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.2)))
                            .foregroundStyle(.red)
                            .fixedSize()
                    }
                    
                    if todo.reminderEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Promemoria attivo")
                    }
                }
                
                // Riga 2: assignee · scadenza
                let hasAssignee = displayName(for: todo.assignedTo) != nil
                let hasDue = todo.dueAt != nil
                
                if hasAssignee || hasDue {
                    HStack(spacing: 4) {
                        if let name = displayName(for: todo.assignedTo) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(hasDue ? 0 : 1)
                        }
                        
                        if let due = todo.dueAt {
                            if hasAssignee {
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                            }
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(due.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                                .layoutPriority(1)
                        }
                        
                        Spacer(minLength: 0)
                    }
                }

                TodoNotesPreviewText(notes: todo.notes)
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHighlighted ? Color.yellow.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? Color.yellow.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] tap edit todoId=\(todo.id) listId=\(listId)")
            editingTarget = TodoEditTarget(id: todo.id, todoId: todo.id)
        }
    }
    
    // MARK: - Helpers
    
    private func displayName(for uid: String?) -> String? {
        guard let uid else { return nil }
        return members.first(where: { $0.userId == uid })?.displayName
    }
    
    @MainActor
    private func toggleDone(_ todo: KBTodoItem) async {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        let before = "isDone=\(todo.isDone) isDeleted=\(todo.isDeleted) syncState=\(todo.syncState.rawValue)"
        
        todo.isDone.toggle()
        todo.updatedBy = uid
        todo.updatedAt = now
        todo.doneAt = todo.isDone ? now : nil
        todo.doneBy = todo.isDone ? uid : nil
        todo.syncState = .pendingUpsert
        
        let after = "isDone=\(todo.isDone) isDeleted=\(todo.isDeleted) syncState=\(todo.syncState.rawValue)"
        
        KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] toggleDone todoId=\(todo.id) BEFORE \(before) AFTER \(after)")
        
        do {
            try modelContext.save()
            KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] toggleDone save OK todoId=\(todo.id)")
        } catch {
            KBLog.todo.kbError("[TodoListView][\(viewTrace)] toggleDone save FAIL todoId=\(todo.id) err=\(String(describing: error))")
        }
        
        KBLog.sync.kbDebug("[TodoListView][\(viewTrace)] enqueueTodoUpsert todoId=\(todo.id)")
        SyncCenter.shared.enqueueTodoUpsert(todoId: todo.id, familyId: familyId, modelContext: modelContext)
        
        KBLog.sync.kbDebug("[TodoListView][\(viewTrace)] flush (toggleDone) todoId=\(todo.id)")
        await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
    }
    
    private func deleteTodos(offsets: IndexSet) {
        Task { @MainActor in
            let uid = Auth.auth().currentUser?.uid ?? "local"
            let now = Date()
            
            KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] deleteTodos offsets=\(offsets) visibleCount=\(visibleTodos.count) listId=\(listId)")
            
            let preIds = visibleTodos.prefix(10).map(\.id).joined(separator: ",")
            KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] deleteTodos PRE visibleIds=[\(preIds)]")
            
            for index in offsets {
                guard visibleTodos.indices.contains(index) else {
                    KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] deleteTodos indexOutOfRange index=\(index) visibleCount=\(visibleTodos.count)")
                    continue
                }
                
                let todo = visibleTodos[index]
                let before = "isDeleted=\(todo.isDeleted) syncState=\(todo.syncState.rawValue) updatedAt=\(todo.updatedAt)"
                
                todo.isDeleted = true
                todo.updatedBy = uid
                todo.updatedAt = now
                todo.syncState = .pendingDelete
                todo.lastSyncError = nil
                
                let after = "isDeleted=\(todo.isDeleted) syncState=\(todo.syncState.rawValue) updatedAt=\(todo.updatedAt)"
                
                KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] deleteTodos todoId=\(todo.id) BEFORE \(before) AFTER \(after)")
                
                KBLog.sync.kbDebug("[TodoListView][\(viewTrace)] enqueueTodoDelete todoId=\(todo.id)")
                SyncCenter.shared.enqueueTodoDelete(todoId: todo.id, familyId: familyId, modelContext: modelContext)
            }
            
            do {
                try modelContext.save()
                KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] deleteTodos save OK")
                
                DispatchQueue.main.async {
                    let ids = visibleTodos.map(\.id).joined(separator: ",")
                    KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] NEXT TICK visibleCount=\(visibleTodos.count) ids=[\(ids)]")
                }
            } catch {
                KBLog.todo.kbError("[TodoListView][\(viewTrace)] deleteTodos save FAIL err=\(String(describing: error))")
            }
            
            KBLog.sync.kbDebug("[TodoListView][\(viewTrace)] flush (deleteTodos)")
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
            
            let postIds = visibleTodos.prefix(10).map(\.id).joined(separator: ",")
            KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] deleteTodos POST visibleIds=[\(postIds)] visibleCount=\(visibleTodos.count)")
        }
    }
    
    // MARK: - TodoEditTarget
    
    /// Wrapper Identifiable usato da .sheet(item:) per garantire stabilità
    /// del valore anche quando SwiftUI ricrea TodoListView durante il layout.
    /// Senza questo, @State var editingTodoId veniva azzerato prima che la
    /// sheet completasse il suo onAppear, causando la form vuota.
    struct TodoEditTarget: Identifiable {
        /// ID univoco della presentazione (stabile per tutta la vita della sheet)
        let id: String
        /// nil = nuovo todo, non-nil = edit di un todo esistente
        let todoId: String?
    }
}
