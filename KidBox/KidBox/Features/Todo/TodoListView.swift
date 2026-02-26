import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog

struct TodoListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @Query private var todos: [KBTodoItem]
    @Query private var members: [KBFamilyMember]
    
    private let remote = TodoRemoteStore()
    
    private let familyId: String
    private let childId: String
    private let listId: String
    
    @State private var showEditSheet = false
    @State private var editingTodoId: String? = nil
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
    
    private var visibleTodos: [KBTodoItem] {
        todos.filter { $0.listId == listId && !$0.isDeleted }
    }
    
    // MARK: - Body
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                if visibleTodos.isEmpty {
                    Text("Nessun To-Do")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleTodos) { todo in
                        row(todo)
                            .id(todo.id) // ✅ per scrollTo
                    }
                    .onDelete(perform: deleteTodos)
                }
            }
            .navigationTitle(listName)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        KBLog.todo.kbInfo("[TodoListView][\(viewTrace)] tap + addTodo listId=\(listId)")
                        editingTodoId = nil
                        showEditSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                TodoEditView(
                    familyId: familyId,
                    childId: childId,
                    listId: listId,
                    listName: listName,
                    todoIdToEdit: editingTodoId
                )
                .onAppear {
                    KBLog.todo.kbDebug("[TodoListView][\(viewTrace)] TodoEditView appeared todoIdToEdit=\(editingTodoId ?? "nil") listId=\(listId)")
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
                    // anche se realtime era già partito, se abbiamo highlight pendente proviamo subito
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
                    
                    // dopo flush, prova highlight
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
                // qui NON stoppo io, perché gestisci già i listener da SyncCenter altrove.
                // Se vuoi, puoi rimettere stopTodoRealtime() qui, ma dipende dalla tua strategia globale.
            }
        }
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
        
        // Aspetta che il todo sia realmente visibile in questa lista
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.title)
                    .strikethrough(todo.isDone)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 8) {
                    if let name = displayName(for: todo.assignedTo) {
                        Label(name, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let due = todo.dueAt {
                        Text(due.formatted(.dateTime.day().month().hour().minute()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    if (todo.priorityRaw ?? 0) == 1 {
                        Text("Urgente")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.2)))
                            .foregroundStyle(.red)
                    }
                    
                    if todo.reminderEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Promemoria attivo")
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
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
            editingTodoId = todo.id
            showEditSheet = true
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
}
