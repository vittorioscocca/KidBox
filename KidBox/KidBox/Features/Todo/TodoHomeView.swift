//
//  TodoHomeView.swift
//  KidBox
//
//  Created by vscocca on 25/02/26.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog
import Combine

struct TodoHomeView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.modelContext) private var modelContext
    
    // Family/Child attivi
    @Query(sort: \KBFamily.updatedAt, order: .reverse)
    private var families: [KBFamily]
    
    // Liste Todo
    @Query(sort: \KBTodoList.createdAt, order: .forward)
    private var allLists: [KBTodoList]
    
    @Query(sort: \KBTodoItem.updatedAt, order: .reverse)
    private var allTodos: [KBTodoItem]
    
    // UI state create/edit list
    @State private var showListEditor = false
    @State private var listNameDraft = ""
    @State private var editingListId: String? = nil
    
    @State private var showShareTodoSheet = false
    @State private var sharePrefillTitle = ""
    
    // ✅ Sync
    @State private var didStartRealtime = false
    private let remote = TodoRemoteStore()
    
    // Trace id per correlare log durante la vita della view
    @State private var viewTrace: String = {
        let s = UUID().uuidString
        return String(s.prefix(8))
    }()
    
    private var activeFamily: KBFamily? { families.first }
    private var activeChild: KBChild? { activeFamily?.children.first }
    
    private var familyId: String { activeFamily?.id ?? "" }
    private var childId: String { activeChild?.id ?? "" }
    
    private var visibleLists: [KBTodoList] {
        guard !familyId.isEmpty, !childId.isEmpty else { return [] }
        return allLists.filter { $0.familyId == familyId && $0.childId == childId && !$0.isDeleted }
    }
    
    private var visibleTodos: [KBTodoItem] {
        guard !familyId.isEmpty, !childId.isEmpty else { return [] }
        return allTodos.filter {
            $0.familyId == familyId &&
            $0.childId == childId &&
            !$0.isDeleted
        }
    }
    
    private var todayCount: Int {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? now
        
        return visibleTodos.filter { t in
            guard !t.isDone, let due = t.dueAt else { return false }
            return due >= start && due < end
        }.count
    }
    
    private var allCount: Int { visibleTodos.filter { !$0.isDone }.count }
    
    private var assignedToMeCount: Int {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        return visibleTodos.filter { !$0.isDone && $0.assignedTo == uid }.count
    }
    
    private var completedCount: Int { visibleTodos.filter { $0.isDone }.count }
    
    private var notCompletedCount: Int { visibleTodos.filter { !$0.isDone }.count }
    
    private var notAssignedToMeCount: Int {
        let uid = Auth.auth().currentUser?.uid ?? ""
        return visibleTodos.filter { !$0.isDone && $0.assignedTo != uid }.count
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                cardsSection
                listsSection
            }
            .padding()
        }
        .navigationTitle("To-Do")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap + newList familyId=\(familyId) childId=\(childId)")
                    editingListId = nil
                    listNameDraft = ""
                    showListEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nuova lista")
            }
        }
        .onAppear {
            BadgeManager.shared.activeSections.insert("todos")
            KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] onAppear familyId=\(familyId) childId=\(childId) didStartRealtime=\(didStartRealtime) lists=\(visibleLists.count) todosVisible=\(visibleTodos.count)")
            logCounters("onAppear")
            startRealtimeIfNeeded()
            guard !familyId.isEmpty else { return }
            
            // 1️⃣ reset su Firestore
            Task { await CountersService.shared.reset(familyId: familyId, field: .todos) }
            
            // 2️⃣ azzera subito badge locale (UX immediata)
            BadgeManager.shared.clearTodos()
            
            if let text = coordinator.pendingShareText {
                sharePrefillTitle = text
                coordinator.pendingShareText = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showShareTodoSheet = true
                }
            }
        }
        .onDisappear {
            BadgeManager.shared.activeSections.remove("todos")
            KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] onDisappear -> stopTodoListRealtime + stopTodoRealtime (reset didStartRealtime)")
        }
        .sheet(isPresented: $showListEditor) {
            listEditorSheet
                .onAppear {
                    KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] listEditorSheet appeared editingListId=\(editingListId ?? "nil")")
                }
                .onDisappear {
                    KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] listEditorSheet disappeared")
                }
        }
        .sheet(isPresented: $showShareTodoSheet) {
            if !familyId.isEmpty, !childId.isEmpty,
               let list = visibleLists.first {
                TodoEditView(
                    familyId: familyId,
                    childId: childId,
                    listId: list.id,
                    listName: list.name,
                    todoIdToEdit: nil,
                    prefillTitle: sharePrefillTitle
                )
            }
        }
        // Log “se cambia qualcosa” (utile per vedere flicker o refresh)
        .onChange(of: allTodos.count) { _, newValue in
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] allTodos.count changed -> \(newValue) visible=\(visibleTodos.count)")
        }
        .onChange(of: allLists.count) { _, newValue in
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] allLists.count changed -> \(newValue) visible=\(visibleLists.count)")
        }
        // Stessa logica di pendingShareVideoPath in ChatView:
        // onReceive scatta appena handleIncomingShare setta il draft,
        // anche se TodoHomeView era già montata (nessuna dipendenza da onAppear).
        // Se c'è almeno una lista, apre direttamente lo sheet di creazione todo.
        // Se non ci sono liste ancora, il draft rimane sul coordinator e
        // TodoListView lo consumerà via onReceive quando l'utente apre una lista.
        .onReceive(coordinator.$pendingShareTodoDraft.compactMap { $0 }) { draft in
            guard !familyId.isEmpty, !childId.isEmpty else { return }
            guard visibleLists.first != nil else {
                // Nessuna lista disponibile — TodoListView lo consumerà dopo
                KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] pendingShareTodoDraft received but no lists yet — keeping for TodoListView")
                return
            }
            coordinator.pendingShareTodoDraft = nil
            sharePrefillTitle = draft.title
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showShareTodoSheet = true
            }
        }
    }
    
    // MARK: - Realtime
    
    private func startRealtimeIfNeeded() {
        guard !didStartRealtime else {
            KBLog.sync.kbDebug("[TodoHomeView][\(viewTrace)] startRealtimeIfNeeded skipped: didStartRealtime=true")
            return
        }
        guard !familyId.isEmpty, !childId.isEmpty else {
            KBLog.sync.kbInfo("[TodoHomeView][\(viewTrace)] startRealtimeIfNeeded skipped: missing familyId/childId familyId=\(familyId) childId=\(childId)")
            return
        }
        
        didStartRealtime = true
        
        KBLog.sync.kbInfo("[TodoHomeView][\(viewTrace)] startTodoListRealtime familyId=\(familyId) childId=\(childId)")
        SyncCenter.shared.startTodoListRealtime(
            familyId: familyId,
            childId: childId,
            modelContext: modelContext,
            remote: remote
        )
        
        KBLog.sync.kbInfo("[TodoHomeView][\(viewTrace)] startTodoRealtime (for counters) familyId=\(familyId) childId=\(childId)")
        SyncCenter.shared.startTodoRealtime(
            familyId: familyId,
            childId: childId,
            modelContext: modelContext,
            remote: remote
        )
        
        Task { @MainActor in
            KBLog.sync.kbDebug("[TodoHomeView][\(viewTrace)] flush (startRealtimeIfNeeded)")
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
        }
    }
    
    // MARK: - Counters logging
    
    private func logCounters(_ label: String) {
        let sampleTodoIds = visibleTodos.prefix(6).map(\.id).joined(separator: ",")
        let sampleListIds = visibleLists.prefix(6).map(\.id).joined(separator: ",")
        
        KBLog.todo.kbDebug("""
        [TodoHomeView][\(viewTrace)] counters[\(label)]
        listsVisible=\(visibleLists.count) listIds=[\(sampleListIds)]
        todosVisible=\(visibleTodos.count) todoIds=[\(sampleTodoIds)]
        today=\(todayCount) allNotDone=\(allCount) assignedToMe=\(assignedToMeCount)
        completed=\(completedCount) notCompleted=\(notCompletedCount) notAssignedToMe=\(notAssignedToMeCount)
        """)
    }
    
    // MARK: - Cards
    
    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Panoramica")
                .font(.headline)
            
            let fid = familyId
            let cid = childId
            
            HStack(spacing: 12) {
                card(
                    title: "Oggi",
                    count: todayCount,
                    icon: "calendar",
                    tint: .orange
                ) {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap card=today fid=\(fid) cid=\(cid) count=\(todayCount)")
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .today))
                }
                
                card(
                    title: "Tutti",
                    count: allCount,
                    icon: "list.bullet",
                    tint: .blue
                ) {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap card=all fid=\(fid) cid=\(cid) count=\(allCount)")
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .all))
                }
            }
            
            HStack(spacing: 12) {
                card(
                    title: "Assegnati a me",
                    count: assignedToMeCount,
                    icon: "person.fill.checkmark",
                    tint: .teal
                ) {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap card=assignedToMe fid=\(fid) cid=\(cid) count=\(assignedToMeCount)")
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .assignedToMe))
                }
                
                card(
                    title: "Completati",
                    count: completedCount,
                    icon: "checkmark.seal.fill",
                    tint: .green
                ) {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap card=completed fid=\(fid) cid=\(cid) count=\(completedCount)")
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .completed))
                }
            }
            
            HStack(spacing: 12) {
                card(
                    title: "Non assegnati a me",
                    count: notAssignedToMeCount,
                    icon: "person.crop.circle.badge.xmark",
                    tint: .purple
                ) {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap card=notAssignedToMe fid=\(fid) cid=\(cid) count=\(notAssignedToMeCount)")
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .notAssignedToMe))
                }
                
                card(
                    title: "Non completati",
                    count: notCompletedCount,
                    icon: "circle",
                    tint: .red
                ) {
                    KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap card=notCompleted fid=\(fid) cid=\(cid) count=\(notCompletedCount)")
                    coordinator.navigate(to: .todoSmart(familyId: fid, childId: cid, kind: .notCompleted))
                }
            }
        }
    }
    
    private func card(
        title: String,
        count: Int,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(tint)
                    
                    Spacer()
                    
                    if count > 0 {
                        Text(count > 99 ? "99+" : "\(count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(tint))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                
                Text(title)
                    .font(.headline)
                
                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Lists
    
    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Le mie liste")
                .font(.headline)
            
            if familyId.isEmpty || childId.isEmpty {
                Text("Crea o unisciti a una famiglia per usare i To-Do.")
                    .foregroundStyle(.secondary)
            } else if visibleLists.isEmpty {
                Text("Nessuna lista")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleLists) { list in
                        Button {
                            KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap list open listId=\(list.id) fid=\(list.familyId) cid=\(list.childId)")
                            coordinator.navigate(to: .todoList(familyId: list.familyId, childId: list.childId, listId: list.id))
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet")
                                    .foregroundStyle(.secondary)
                                Text(list.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Modifica") {
                                KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] context edit listId=\(list.id)")
                                editingListId = list.id
                                listNameDraft = list.name
                                showListEditor = true
                            }
                            Button("Elimina", role: .destructive) {
                                KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] context delete listId=\(list.id)")
                                deleteList(list)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var listEditorSheet: some View {
        NavigationStack {
            Form {
                TextField("Nome lista", text: $listNameDraft)
            }
            .navigationTitle(editingListId == nil ? "Nuova lista" : "Modifica lista")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap saveList editingListId=\(editingListId ?? "nil")")
                        saveList()
                    }
                    .disabled(listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] tap cancel listEditor editingListId=\(editingListId ?? "nil")")
                        showListEditor = false
                        editingListId = nil
                        listNameDraft = ""
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveList() {
        guard !familyId.isEmpty, !childId.isEmpty else {
            KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] saveList aborted: missing familyId/childId")
            return
        }
        
        let name = listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] saveList aborted: empty name")
            return
        }
        
        let listId: String
        let now = Date()
        
        if let eid = editingListId,
           let list = visibleLists.first(where: { $0.id == eid }) {
            // modifica esistente
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] saveList update listId=\(eid)")
            list.name = name
            list.updatedAt = now
            listId = list.id
        } else {
            // nuova lista
            let list = KBTodoList(familyId: familyId, childId: childId, name: name)
            modelContext.insert(list)
            listId = list.id
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] saveList create listId=\(listId)")
        }
        
        do {
            try modelContext.save()
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] saveList save OK listId=\(listId)")
        } catch {
            KBLog.todo.kbError("[TodoHomeView][\(viewTrace)] saveList save FAIL listId=\(listId) err=\(String(describing: error))")
        }
        
        // ✅ Sync remoto
        KBLog.sync.kbDebug("[TodoHomeView][\(viewTrace)] enqueueTodoListUpsert listId=\(listId) fid=\(familyId)")
        SyncCenter.shared.enqueueTodoListUpsert(listId: listId, familyId: familyId, modelContext: modelContext)
        
        Task { @MainActor in
            KBLog.sync.kbDebug("[TodoHomeView][\(viewTrace)] flush (saveList) listId=\(listId)")
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
            logCounters("after saveList flush")
        }
        
        showListEditor = false
        self.editingListId = nil
        self.listNameDraft = ""
    }
    
    private func deleteList(_ list: KBTodoList) {
        let listId = list.id
        let fid = familyId
        let cid = childId
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        
        KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] deleteList START listId=\(listId) fid=\(fid) cid=\(cid)")
        
        // 🔹 1) Trova tutti i todo collegati
        let desc = FetchDescriptor<KBTodoItem>(
            predicate: #Predicate {
                $0.familyId == fid &&
                $0.childId == cid &&
                $0.listId == listId &&
                $0.isDeleted == false
            }
        )
        
        let todosToDelete = (try? modelContext.fetch(desc)) ?? []
        let sample = todosToDelete.prefix(10).map(\.id).joined(separator: ",")
        
        KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] deleteList fetched todosToDelete=\(todosToDelete.count) sampleIds=[\(sample)]")
        
        // 🔹 2) Soft delete todos
        for todo in todosToDelete {
            let before = "isDeleted=\(todo.isDeleted) syncState=\(todo.syncState.rawValue) updatedAt=\(todo.updatedAt)"
            
            todo.isDeleted = true
            todo.syncState = .pendingDelete
            todo.lastSyncError = nil
            todo.updatedBy = uid
            todo.updatedAt = now
            
            let after = "isDeleted=\(todo.isDeleted) syncState=\(todo.syncState.rawValue) updatedAt=\(todo.updatedAt)"
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] deleteList todoId=\(todo.id) BEFORE \(before) AFTER \(after)")
            
            KBLog.sync.kbDebug("[TodoHomeView][\(viewTrace)] enqueueTodoDelete todoId=\(todo.id) fid=\(fid)")
            SyncCenter.shared.enqueueTodoDelete(todoId: todo.id, familyId: fid, modelContext: modelContext)
        }
        
        // 🔹 3) Soft delete lista
        // 🔹 3) Soft delete lista
        list.isDeleted = true
        list.updatedAt = now
        // NB: KBTodoList non ha updatedBy -> non settarlo
        KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] deleteList listId=\(listId) set isDeleted=true updatedAt=\(now)")
        
        do {
            try modelContext.save()
            KBLog.todo.kbDebug("[TodoHomeView][\(viewTrace)] deleteList local save OK listId=\(listId)")
        } catch {
            KBLog.todo.kbError("[TodoHomeView][\(viewTrace)] deleteList local save FAIL listId=\(listId) err=\(String(describing: error))")
        }
        
        // 🔹 4) Sync lista
        KBLog.sync.kbDebug("[TodoHomeView][\(viewTrace)] enqueueTodoListDelete listId=\(listId) fid=\(fid)")
        SyncCenter.shared.enqueueTodoListDelete(listId: listId, familyId: fid, modelContext: modelContext)
        
        Task { @MainActor in
            KBLog.sync.kbInfo("[TodoHomeView][\(viewTrace)] flush (deleteList) listId=\(listId) todosToDelete=\(todosToDelete.count)")
            await SyncCenter.shared.flush(modelContext: modelContext, remote: remote)
            KBLog.todo.kbInfo("[TodoHomeView][\(viewTrace)] deleteList DONE listId=\(listId)")
            logCounters("after deleteList flush")
        }
    }
}
