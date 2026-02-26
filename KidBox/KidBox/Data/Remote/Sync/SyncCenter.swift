//
//  SyncCenter.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData
import OSLog
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Central sync orchestrator.
///
/// Responsibilities:
/// - Manage realtime listeners (inbound) for entities (todos, members, documents, etc.)
/// - Maintain an outbox (`KBSyncOp`) for offline-first outbound operations
/// - Periodically flush pending operations (auto flush)
/// - Apply inbound changes to local SwiftData storage
///
/// Notes:
/// - `@MainActor` because it touches SwiftData `ModelContext` and is used from UI flows.
/// - Avoid logging PII (email, photoURL, tokens).
@MainActor
final class SyncCenter: ObservableObject {
    
    static let shared = SyncCenter()
    private init() {}
    
    // MARK: - Realtime (Inbound)
    
    private var todoListener: ListenerRegistration?
    private var todoListListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?
    
    private let membersRemote = FamilyMemberRemoteStore()
    
    var documentsListener: ListenerRegistration?
    let documentRemote = DocumentRemoteStore()
    private let documentCategoryRemote = DocumentCategoryRemoteStore()
    
    /// When true, outbound flush/apply should avoid re-creating data while wiping.
    private(set) var isWipingLocalData = false
    
    private var accessLostHandled = Set<String>()
    
    private(set) var isFamilyBeingCreated = false
    
    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Join guard
    //
    // Sopprime handleFamilyAccessLost durante il join di una famiglia.
    // I listener della vecchia famiglia possono emettere PERMISSION_DENIED
    // nell'intervallo tra coordinator.setActiveFamily() e lo stop/start dei
    // listener, causando una revoca spuria dell'utente.
    // Il pattern è identico a isFamilyBeingCreated usato in FamilyCreationService.
    // ─────────────────────────────────────────────────────────────────────────
    private(set) var isJoiningFamily = false
    
    func beginFamilyCreation() { isFamilyBeingCreated = true }
    func endFamilyCreation()   { isFamilyBeingCreated = false }
    
    /// Segnala l'inizio di un join. Resetta anche accessLostHandled così un
    /// eventuale revoke legittimo post-join viene correttamente gestito.
    func beginFamilyJoin() {
        isJoiningFamily = true
        accessLostHandled.removeAll()
        KBLog.sync.kbDebug("beginFamilyJoin: join guard ON, accessLostHandled reset")
    }
    
    func endFamilyJoin() {
        isJoiningFamily = false
        KBLog.sync.kbDebug("endFamilyJoin: join guard OFF")
    }
    
    static func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain &&
        ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }
    
    @MainActor
    func handleFamilyAccessLost(familyId: String, source: String, error: Error) {
        guard !isFamilyBeingCreated else {
            KBLog.sync.kbDebug("handleFamilyAccessLost suppressed: family creation in progress")
            return
        }
        // ← NUOVO: sopprime durante il join per evitare revoche spurie dai
        //   listener della vecchia famiglia ancora attivi.
        guard !isJoiningFamily else {
            KBLog.sync.kbDebug("handleFamilyAccessLost suppressed: family join in progress source=\(source) familyId=\(familyId)")
            return
        }
        guard !accessLostHandled.contains(familyId) else { return }
        accessLostHandled.insert(familyId)
        
        KBLog.sync.kbError("Family access lost (PERMISSION_DENIED). familyId=\(familyId) source=\(source) err=\(error.localizedDescription)")
        
        stopMembersRealtime()
        stopTodoRealtime()
        stopTodoListRealtime()
        stopChildrenRealtime()
        stopFamilyBundleRealtime()
        stopDocumentsRealtime()
        
        // Notifica UI: "sei stato buttato fuori"
        Self._currentUserRevoked.send(familyId)
    }
    
    // MARK: - Todo Realtime
    
    /// Starts (or restarts) realtime listener for todos.
    func startTodoRealtime(
        familyId: String,
        childId: String,
        modelContext: ModelContext,
        remote: TodoRemoteStore
    ) {
        KBLog.sync.kbInfo("startTodoRealtime familyId=\(familyId) childId=\(childId)")
        stopTodoRealtime()
        
        todoListener = remote.listenTodos(
            familyId: familyId,
            childId: childId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyTodoInbound(changes: changes, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "todos", error: err)
                    }
                }
            }
        )
    }
    
    /// Stops todo realtime listener if active.
    func stopTodoRealtime() {
        if todoListener != nil {
            KBLog.sync.kbInfo("stopTodoRealtime")
        }
        todoListener?.remove()
        todoListener = nil
    }
    
    // MARK: - TodoList Realtime
    
    /// Avvia il listener realtime per le liste todo di una famiglia/figlio.
    func startTodoListRealtime(
        familyId: String,
        childId: String,
        modelContext: ModelContext,
        remote: TodoRemoteStore
    ) {
        KBLog.sync.kbInfo("startTodoListRealtime familyId=\(familyId) childId=\(childId)")
        stopTodoListRealtime()
        
        todoListListener = remote.listenTodoLists(
            familyId: familyId,
            childId: childId,
            onChange: { [weak self] changes in
                guard let self else { return }
                self.applyTodoListInbound(changes: changes, familyId: familyId, modelContext: modelContext)
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "todoLists", error: err)
                    }
                }
            }
        )
    }
    
    /// Ferma il listener realtime per le liste.
    func stopTodoListRealtime() {
        if todoListListener != nil {
            KBLog.sync.kbInfo("stopTodoListRealtime")
        }
        todoListListener?.remove()
        todoListListener = nil
    }
    
    // MARK: - Local wipe guard
    
    /// Signals that a local wipe is in progress. Sync should not resurrect data.
    func beginLocalWipe() {
        KBLog.sync.kbInfo("beginLocalWipe")
        isWipingLocalData = true
    }
    
    /// Signals that a local wipe has finished.
    func endLocalWipe() {
        KBLog.sync.kbInfo("endLocalWipe")
        isWipingLocalData = false
    }
    
    // MARK: - Members Realtime
    
    /// Starts (or restarts) realtime listener for family members.
    ///
    /// Also attempts a best-effort upsert of the current user's profile fields on Firestore,
    /// usando il nome da KBUserProfile (SwiftData) come fonte di verità.
    func startMembersRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startMembersRealtime familyId=\(familyId)")
        stopMembersRealtime()
        
        // Leggi il displayName canonico da KBUserProfile prima di fare l'upsert,
        // così Firestore riceve il nome giusto e non quello (vecchio) di Firebase Auth.
        let myDisplayName: String? = {
            guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return nil }
            let desc = FetchDescriptor<KBUserProfile>(predicate: #Predicate { $0.uid == uid })
            guard let profile = try? modelContext.fetch(desc).first else { return nil }
            let dn = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !dn.isEmpty && dn != "Utente" { return dn }
            let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let composed = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
            return composed.isEmpty ? nil : composed
        }()
        
        // Best-effort: populate "my" profile on Firestore (non-blocking)
        Task { [familyId, myDisplayName] in
            await membersRemote.upsertMyMemberProfileIfNeeded(familyId: familyId, displayName: myDisplayName)
        }
        
        membersListener = membersRemote.listenMembers(
            familyId: familyId,
            onChange: { [weak self] changes in
                guard let self else { return }
                Task { @MainActor in
                    self.applyMembersInbound(familyId: familyId, changes: changes, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "members", error: err)
                    }
                }
            }
        )
    }
    
    /// Stops members realtime listener if active.
    func stopMembersRealtime() {
        if membersListener != nil {
            KBLog.sync.kbInfo("stopMembersRealtime")
        }
        membersListener?.remove()
        membersListener = nil
    }
    
    /// Applies inbound member changes into SwiftData using LWW semantics.
    ///
    /// Behavior (unchanged):
    /// - Loads all local members for `familyId`
    /// - Upserts by id
    /// - Soft-delete remote => hard-delete local
    /// - Firestore remove => delete local row
    /// - If current user is removed, stop listeners (members/todo/documents)
    private func applyMembersInbound(
        familyId: String,
        changes: [FamilyMemberRemoteChange],
        modelContext: ModelContext
    ) {
        KBLog.sync.kbDebug("applyMembersInbound changes=\(changes.count) familyId=\(familyId)")
        
        do {
            let fid = familyId
            
            // 1) Load local members for the family
            let allLocal = try modelContext.fetch(
                FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.familyId == fid })
            )
            
            var localById: [String: KBFamilyMember] = [:]
            allLocal.forEach { localById[$0.id] = $0 }
            
            var seenIds = Set<String>()
            
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    seenIds.insert(dto.id)
                    
                    // Soft-delete remote => delete local, notify if current user
                    if dto.isDeleted {
                        if let local = localById[dto.id] {
                            let wasCurrentUser = local.userId == Auth.auth().currentUser?.uid
                            let famId = local.familyId
                            modelContext.delete(local)
                            if wasCurrentUser {
                                KBLog.sync.kbInfo("Current user soft-deleted from family familyId=\(famId)")
                                stopMembersRealtime()
                                stopTodoRealtime()
                                stopChildrenRealtime()
                                stopFamilyBundleRealtime()
                                documentsListener?.remove()
                                documentsListener = nil
                                Self._currentUserRevoked.send(famId)
                            }
                        }
                        continue
                    }
                    
                    if let local = localById[dto.id] {
                        let remoteStamp = dto.updatedAt ?? Date.distantPast
                        if dto.updatedAt == nil || remoteStamp >= local.updatedAt {
                            local.familyId = dto.familyId
                            local.userId = dto.userId
                            local.role = dto.role
                            
                            // FIX: per il membro corrente il displayName canonico è
                            // KBUserProfile (quello che l'utente ha salvato nel profilo).
                            // Firestore potrebbe avere ancora il valore vecchio (race
                            // condition tra write locale e snapshot in arrivo), quindi
                            // preferiamo sempre il nome locale se disponibile e non vuoto.
                            // Per gli altri membri usiamo normalmente il valore remoto.
                            let isMe = dto.userId == Auth.auth().currentUser?.uid
                            if isMe {
                                // Leggi il nome canonico da KBUserProfile
                                let uid = dto.userId
                                let profileDesc = FetchDescriptor<KBUserProfile>(
                                    predicate: #Predicate { $0.uid == uid }
                                )
                                if let profile = try? modelContext.fetch(profileDesc).first {
                                    let dn = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    let composed = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
                                    let localName = (!dn.isEmpty && dn != "Utente") ? dn
                                    : (!composed.isEmpty ? composed : nil)
                                    local.displayName = localName ?? dto.displayName
                                } else {
                                    local.displayName = dto.displayName
                                }
                            } else {
                                local.displayName = dto.displayName
                            }
                            
                            local.email = dto.email
                            local.photoURL = dto.photoURL
                            local.isDeleted = false
                            local.updatedAt = dto.updatedAt ?? Date()
                            local.updatedBy = dto.updatedBy ?? local.updatedBy
                        }
                    } else {
                        let now = Date()
                        
                        // FIX: anche alla prima creazione del record locale, usa il nome
                        // da KBUserProfile se si tratta del membro corrente.
                        let isMe = dto.userId == Auth.auth().currentUser?.uid
                        var resolvedDisplayName = dto.displayName
                        if isMe {
                            let uid = dto.userId
                            let profileDesc = FetchDescriptor<KBUserProfile>(
                                predicate: #Predicate { $0.uid == uid }
                            )
                            if let profile = try? modelContext.fetch(profileDesc).first {
                                let dn = (profile.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let fn = (profile.firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let ln = (profile.lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                let composed = "\(fn) \(ln)".trimmingCharacters(in: .whitespacesAndNewlines)
                                let localName = (!dn.isEmpty && dn != "Utente") ? dn
                                : (!composed.isEmpty ? composed : nil)
                                resolvedDisplayName = localName ?? dto.displayName
                            }
                        }
                        
                        let m = KBFamilyMember(
                            id: dto.id,
                            familyId: dto.familyId,
                            userId: dto.userId,
                            role: dto.role,
                            displayName: resolvedDisplayName,
                            email: dto.email,
                            photoURL: dto.photoURL,
                            updatedBy: dto.updatedBy ?? "remote",
                            createdAt: now,
                            updatedAt: dto.updatedAt ?? now,
                            isDeleted: false
                        )
                        modelContext.insert(m)
                    }
                    
                case .remove(let id):
                    seenIds.insert(id)
                    
                    if let local = localById[id] {
                        let removedUserId = local.userId
                        let famId = local.familyId
                        modelContext.delete(local)
                        
                        // If I'm removed: stop listeners to avoid resurrecting, then notify UI
                        if removedUserId == Auth.auth().currentUser?.uid {
                            KBLog.sync.kbInfo("Current user removed from family familyId=\(famId)")
                            
                            stopMembersRealtime()
                            stopTodoRealtime()
                            stopChildrenRealtime()
                            stopFamilyBundleRealtime()
                            
                            if documentsListener != nil {
                                KBLog.sync.kbInfo("Stopping documentsListener due to removal")
                            }
                            documentsListener?.remove()
                            documentsListener = nil
                            
                            // Notify UI to expel the user
                            KBLog.sync.kbInfo("Emitting currentUserRevoked familyId=\(famId)")
                            Self._currentUserRevoked.send(famId)
                        }
                    }
                }
            }
            
            try modelContext.save()
            KBLog.sync.kbDebug("applyMembersInbound saved localMembers=\(allLocal.count) changes=\(changes.count)")
            
        } catch {
            KBLog.sync.kbError("applyMembersInbound failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Remotes (default)
    
    private let todoRemote = TodoRemoteStore()
    
    // MARK: - Auto flush
    
    private var flushTask: Task<Void, Never>?
    
    /// Immediately flushes all pending outbox operations (best-effort).
    ///
    /// Behavior (unchanged):
    /// - Cancels any ongoing flushTask
    /// - Fetches ops eligible for retry (`nextRetryAt <= now`) ordered by `createdAt`
    /// - Processes ops sequentially
    func flushGlobal(modelContext: ModelContext) {
        KBLog.sync.kbInfo("flushGlobal requested")
        flushTask?.cancel()
        
        flushTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                let now = Date()
                let desc = FetchDescriptor<KBSyncOp>(
                    predicate: #Predicate { $0.nextRetryAt <= now },
                    sortBy: [SortDescriptor(\KBSyncOp.createdAt, order: .forward)]
                )
                
                let ops = try modelContext.fetch(desc)
                KBLog.sync.kbInfo("flushGlobal ops=\(ops.count)")
                
                for op in ops {
                    KBLog.sync.kbDebug("Processing op entity=\(op.entityTypeRaw) opType=\(op.opType) id=\(op.entityId)")
                    await self.process(op: op, modelContext: modelContext, remote: self.todoRemote)
                }
                
                KBLog.sync.kbInfo("flushGlobal completed")
                
            } catch {
                KBLog.sync.kbError("flushGlobal failed: \(error.localizedDescription)")
            }
        }
    }
    
    /// Starts a periodic auto flush loop (~30s).
    func startAutoFlush(modelContext: ModelContext) {
        KBLog.sync.kbInfo("startAutoFlush")
        flushTask?.cancel()
        
        flushTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.flush(modelContext: modelContext, remote: self.todoRemote)
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
    }
    
    /// Stops the auto flush loop.
    func stopAutoFlush() {
        KBLog.sync.kbInfo("stopAutoFlush")
        flushTask?.cancel()
        flushTask = nil
    }
    
    // MARK: - Outbox
    
    private var isFlushing = false
    
    func enqueueTodoUpsert(todoId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueTodoUpsert familyId=\(familyId) todoId=\(todoId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.todo.rawValue,
            entityId: todoId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueTodoListUpsert(listId: String, familyId: String, modelContext: ModelContext) {
        // ⚠️ Richiede SyncEntityType.todoList nel tuo enum SyncEntityType:
        //    case todoList = "todoList"
        KBLog.sync.kbDebug("enqueueTodoListUpsert familyId=\(familyId) listId=\(listId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.todoList.rawValue,
            entityId: listId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueTodoListDelete(listId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueTodoListDelete familyId=\(familyId) listId=\(listId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.todoList.rawValue,
            entityId: listId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    func enqueueTodoDelete(todoId: String, familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbDebug("enqueueTodoDelete familyId=\(familyId) todoId=\(todoId)")
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.todo.rawValue,
            entityId: todoId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
    /// Upserts (or replaces) a pending sync operation in the outbox.
    ///
    /// Behavior (unchanged):
    /// - If an op for same (familyId, entityType, entityId) exists => update its opType and reset retry state.
    /// - Else insert a new KBSyncOp.
    func upsertOp(
        familyId: String,
        entityType: String,
        entityId: String,
        opType: String,
        modelContext: ModelContext
    ) {
        do {
            let fid = familyId
            let et = entityType
            let eid = entityId
            
            let desc = FetchDescriptor<KBSyncOp>(predicate: #Predicate {
                $0.familyId == fid && $0.entityTypeRaw == et && $0.entityId == eid
            })
            
            if let existing = try modelContext.fetch(desc).first {
                existing.opType = opType
                existing.attempts = 0
                existing.lastError = nil
                existing.nextRetryAt = Date()
                KBLog.sync.kbDebug("Updated existing op entity=\(et) id=\(eid) opType=\(opType)")
            } else {
                let op = KBSyncOp(
                    familyId: familyId,
                    entityTypeRaw: entityType,
                    entityId: entityId,
                    opType: opType
                )
                modelContext.insert(op)
                KBLog.sync.kbDebug("Inserted new op entity=\(et) id=\(eid) opType=\(opType)")
            }
            
            try modelContext.save()
            
        } catch {
            KBLog.sync.kbError("enqueue op failed: \(error.localizedDescription)")
        }
    }
    
    /// Flushes outbox operations (guarded to avoid re-entrancy).
    func flush(modelContext: ModelContext, remote: TodoRemoteStore) async {
        guard !isFlushing else {
            KBLog.sync.kbDebug("flush skipped (already flushing)")
            return
        }
        
        isFlushing = true
        defer { isFlushing = false }
        
        do {
            let now = Date()
            let desc = FetchDescriptor<KBSyncOp>(
                predicate: #Predicate { $0.nextRetryAt <= now },
                sortBy: [SortDescriptor(\KBSyncOp.createdAt, order: .forward)]
            )
            
            let ops = try modelContext.fetch(desc)
            if !ops.isEmpty {
                KBLog.sync.kbDebug("flush ops=\(ops.count)")
            }
            
            for op in ops {
                await process(op: op, modelContext: modelContext, remote: remote)
            }
            
        } catch {
            KBLog.sync.kbError("flush fetch failed: \(error.localizedDescription)")
        }
    }
    
    /// Processes a single outbox operation.
    ///
    /// Behavior (unchanged):
    /// - On success: delete op, save, update lastSyncAt, clear lastSyncError.
    /// - On failure: increment attempts, set lastError, schedule retry with backoff, update lastSyncError.
    private func process(op: KBSyncOp, modelContext: ModelContext, remote: TodoRemoteStore) async {
        do {
            switch op.entityTypeRaw {
            case SyncEntityType.todo.rawValue:
                try await processTodo(op: op, modelContext: modelContext, remote: remote)
                
            case SyncEntityType.todoList.rawValue:
                try await processTodoList(op: op, modelContext: modelContext, remote: remote)
                
            case SyncEntityType.document.rawValue:
                try await processDocument(op: op, modelContext: modelContext, remote: documentRemote)
                
            case SyncEntityType.documentCategory.rawValue:
                try await processDocumentCategory(op: op, modelContext: modelContext, remote: documentCategoryRemote)
                
            case SyncEntityType.event.rawValue:
                throw NSError(domain: "KidBox.Sync", code: -2002,
                              userInfo: [NSLocalizedDescriptionKey: "Event sync not implemented yet"])
                
            case SyncEntityType.familyBundle.rawValue:
                try await self.processFamilyBundle(op: op, modelContext: modelContext)
                
            default:
                throw NSError(domain: "KidBox.Sync", code: -2000,
                              userInfo: [NSLocalizedDescriptionKey: "Unknown entityType: \(op.entityTypeRaw)"])
            }
            
            modelContext.delete(op)
            try modelContext.save()
            try updateFamilyLastSyncAt(
                familyId: op.familyId,
                modelContext: modelContext,
                value: nil,
                error: nil
            )
            
            KBLog.sync.kbDebug("sync op OK entity=\(op.entityTypeRaw) opType=\(op.opType) id=\(op.entityId)")
            
        } catch {
            op.attempts += 1
            op.lastError = error.localizedDescription
            op.nextRetryAt = Date().addingTimeInterval(backoffSeconds(attempts: op.attempts))
            try? modelContext.save()
            
            try? updateFamilyLastSyncAt(
                familyId: op.familyId,
                modelContext: modelContext,
                value: nil,
                error: op.lastError
            )
            
            KBLog.sync.kbError("sync op failed entity=\(op.entityTypeRaw) opType=\(op.opType) id=\(op.entityId) err=\(error.localizedDescription)")
        }
    }
    
    /// Processes a Todo outbox operation.
    ///
    /// Behavior unchanged.
    private func processTodo(op: KBSyncOp, modelContext: ModelContext, remote: TodoRemoteStore) async throws {
        let tid = op.entityId
        let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == tid })
        let todo = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let todo else { return }
            
            todo.syncState = .pendingUpsert
            todo.lastSyncError = nil
            try modelContext.save()
            
            try await remote.upsert(todo: RemoteTodoWrite(
                id: todo.id,
                familyId: todo.familyId,
                childId: todo.childId,
                title: todo.title,
                listId: todo.listId,
                isDone: todo.isDone,
                notes: todo.notes,
                dueAt: todo.dueAt,
                doneAt: todo.doneAt,
                doneBy: todo.doneBy,
                assignedTo: todo.assignedTo,
                createdBy: todo.createdBy,
                priority: todo.priorityRaw
            ))
            
            todo.syncState = .synced
            todo.lastSyncError = nil
            try modelContext.save()
            
        case "delete":
            try await remote.softDelete(todoId: tid, familyId: op.familyId)
            
            if let todo = try? fetchTodo(id: op.entityId, modelContext: modelContext) {
                KBLog.sync.kbInfo("[todo][outbound] delete OK -> HARD DELETE local id=\(todo.id)")
                modelContext.delete(todo)
                try? modelContext.save()
            }
            
        default:
            throw NSError(domain: "KidBox.Sync", code: -2100,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType: \(op.opType)"])
        }
    }
    
    /// Processa un'operazione outbox per una KBTodoList.
    private func processTodoList(op: KBSyncOp, modelContext: ModelContext, remote: TodoRemoteStore) async throws {
        let lid = op.entityId
        let desc = FetchDescriptor<KBTodoList>(predicate: #Predicate { $0.id == lid })
        let list = try modelContext.fetch(desc).first
        
        switch op.opType {
        case "upsert":
            guard let list else { return }
            try await remote.upsertList(list: list)
            
        case "delete":
            try await remote.softDeleteList(listId: lid, familyId: op.familyId)
            
        default:
            throw NSError(domain: "KidBox.Sync", code: -2200,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for todoList: \(op.opType)"])
        }
    }
    
    /// Applica inbound le modifiche alle liste todo da Firestore → SwiftData (LWW).
    private func applyTodoListInbound(
        changes: [TodoListRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let lid = dto.id
                    let desc = FetchDescriptor<KBTodoList>(predicate: #Predicate { $0.id == lid })
                    
                    if let existing = try modelContext.fetch(desc).first {
                        let remoteTs = dto.updatedAt ?? Date.distantPast
                        if remoteTs >= existing.updatedAt {
                            existing.name = dto.name
                            existing.isDeleted = dto.isDeleted
                            existing.updatedAt = remoteTs
                        }
                    } else if !dto.isDeleted {
                        // nuova lista arrivata dal remoto: la creiamo localmente
                        let list = KBTodoList(
                            id: dto.id,
                            familyId: dto.familyId,
                            childId: dto.childId,
                            name: dto.name,
                            createdAt: dto.updatedAt ?? Date(),
                            updatedAt: dto.updatedAt ?? Date(),
                            isDeleted: false
                        )
                        modelContext.insert(list)
                        KBLog.sync.kbDebug("applyTodoListInbound: inserita lista remota name=\(dto.name) id=\(dto.id)")
                    }
                    
                case .remove(let id):
                    let lid = id
                    let desc = FetchDescriptor<KBTodoList>(predicate: #Predicate { $0.id == lid })
                    if let existing = try modelContext.fetch(desc).first {
                        modelContext.delete(existing)
                    }
                }
            }
            
            try modelContext.save()
            
        } catch {
            KBLog.sync.kbError("applyTodoListInbound failed: \(error.localizedDescription)")
        }
    }
    
    private func backoffSeconds(attempts: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempts - 1))), 300.0)
    }
    
    private func updateFamilyLastSyncAt(
        familyId: String,
        modelContext: ModelContext,
        value: Date?,
        error: String?
    ) throws {
        let fid = familyId
        let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        
        if let fam = try modelContext.fetch(desc).first {
            
            if let value {
                if let current = fam.lastSyncAt {
                    if value > current {
                        fam.lastSyncAt = value
                    }
                } else {
                    fam.lastSyncAt = value
                }
            }
            
            fam.lastSyncError = error
            try modelContext.save()
        }
    }
    
    private func fetchFamilyLastSyncAt(familyId: String, modelContext: ModelContext) throws -> Date? {
        let fid = familyId
        let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        return try modelContext.fetch(desc).first?.lastSyncAt
    }
    
    // MARK: - Pull incremental (updatedAt > lastSyncAt)
    
    /// Pulls todos updated since last sync, applies LWW to local, and updates lastSyncAt.
    func pullTodoIncremental(
        familyId: String,
        childId: String,
        modelContext: ModelContext,
        remote: TodoRemoteStore? = nil
    ) async {
        let remote = remote ?? todoRemote
        KBLog.sync.kbInfo("pullTodoIncremental started familyId=\(familyId) childId=\(childId)")
        
        do {
            let since = try fetchFamilyLastSyncAt(
                familyId: familyId,
                modelContext: modelContext
            ) ?? .distantPast
            
            let dtos = try await remote.fetchTodosUpdatedSince(
                familyId: familyId,
                childId: childId,
                since: since
            )
            
            KBLog.sync.kbDebug("pullTodoIncremental dtos=\(dtos.count) since=\(since)")
            
            var maxRemoteUpdatedAt: Date? = nil
            
            for dto in dtos {
                
                let remoteUpdatedAt = dto.updatedAt ?? .distantPast
                
                if maxRemoteUpdatedAt == nil || remoteUpdatedAt > maxRemoteUpdatedAt! {
                    maxRemoteUpdatedAt = remoteUpdatedAt
                }
                
                // 🛡️ isDeleted=true: hard delete locale se esiste, altrimenti skip
                if dto.isDeleted {
                    if let existing = try fetchTodo(id: dto.id, modelContext: modelContext) {
                        modelContext.delete(existing)
                    }
                    continue
                }
                
                let todo = try fetchOrCreateTodo(
                    id: dto.id,
                    familyId: dto.familyId,
                    childId: dto.childId,
                    listId: dto.listId,
                    modelContext: modelContext
                )
                
                if remoteUpdatedAt >= todo.updatedAt {
                    
                    todo.familyId = dto.familyId
                    todo.childId = dto.childId
                    
                    if let lid = dto.listId {
                        todo.listId = lid
                    }
                    
                    todo.title = dto.title
                    todo.isDone = dto.isDone
                    todo.isDeleted = false
                    
                    todo.notes = dto.notes
                    todo.dueAt = dto.dueAt
                    todo.doneAt = dto.doneAt
                    todo.doneBy = dto.doneBy
                    
                    todo.updatedAt = remoteUpdatedAt
                    todo.updatedBy = dto.updatedBy ?? todo.updatedBy
                    
                    todo.assignedTo = dto.assignedTo
                    todo.createdBy = dto.createdBy ?? todo.createdBy
                    todo.priorityRaw = dto.priority ?? 0
                    
                    todo.syncState = .synced
                    todo.lastSyncError = nil
                }
            }
            
            try modelContext.save()
            
            try updateFamilyLastSyncAt(
                familyId: familyId,
                modelContext: modelContext,
                value: maxRemoteUpdatedAt,
                error: nil
            )
            
            KBLog.sync.kbInfo("pullTodoIncremental completed familyId=\(familyId)")
            
        } catch {
            KBLog.sync.kbError("pullTodoIncremental failed: \(error.localizedDescription)")
            try? updateFamilyLastSyncAt(
                familyId: familyId,
                modelContext: modelContext,
                value: nil,
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Apply inbound (Realtime)
    
    /// Applies realtime Todo changes to local SwiftData.
    
    /// Applies realtime Todo changes to local SwiftData.
    private func applyTodoInbound(changes: [TodoRemoteChange], modelContext: ModelContext) {
        guard !changes.isEmpty else { return }
        
        // Batch correlation id (useful when listeners restart and re-emit full snapshots).
        let batch = String(UUID().uuidString.prefix(8))
        
        func dtoSummary(_ dto: TodoRemoteDTO) -> String {
            let ua = dto.updatedAt?.description ?? "nil"
            let ub = dto.updatedBy ?? "nil"
            let lid = dto.listId ?? "nil"
            return "id=\(dto.id) listId=\(lid) childId=\(dto.childId) isDeleted=\(dto.isDeleted) isDone=\(dto.isDone) updatedAt=\(ua) updatedBy=\(ub)"
        }
        
        func todoSummary(_ todo: KBTodoItem) -> String {
            "id=\(todo.id) listId=\(todo.listId ?? "nil") isDeleted=\(todo.isDeleted) isDone=\(todo.isDone) updatedAt=\(todo.updatedAt) syncState=\(String(describing: todo.syncState))"
        }
        
        KBLog.sync.kbInfo("[todo][inbound][\(batch)] START changes=\(changes.count)")
        
        do {
            for change in changes {
                switch change {
                    
                case .upsert(let dto):
                    KBLog.sync.kbDebug("[todo][inbound][\(batch)] CHANGE upsert dto=\(dtoSummary(dto))")
                    
                    // 1) Remote soft-delete sent as an upsert with isDeleted=true
                    if dto.isDeleted {
                        if let existing = try fetchTodo(id: dto.id, modelContext: modelContext) {
                            KBLog.sync.kbInfo("[todo][inbound][\(batch)] remote isDeleted=true -> HARD DELETE local=\(todoSummary(existing))")
                            modelContext.delete(existing)
                            KBLog.sync.kbDebug("[todo][inbound][\(batch)] hard deleted id=\(dto.id)")
                        } else {
                            KBLog.sync.kbDebug("[todo][inbound][\(batch)] remote isDeleted=true but local missing id=\(dto.id)")
                        }
                        continue
                    }
                    
                    // 2) Upsert with anti-resurrect
                    // Fetch existing FIRST (so we can decide to ignore before creating/overwriting).
                    if let existing = try fetchTodo(id: dto.id, modelContext: modelContext) {
                        
                        // ✅ Anti-resurrect: if local is deleted OR pendingDelete, ignore remote "alive" upsert.
                        if existing.isDeleted || existing.syncState == .pendingDelete {
                            KBLog.sync.kbInfo("""
                        [todo][inbound][\(batch)] IGNORE upsert (anti-resurrect) id=\(dto.id)
                        local=\(todoSummary(existing))
                        remote=\(dtoSummary(dto))
                        """)
                            continue
                        }
                        
                        // Compare timestamps safely (nil remote means "unknown/old" -> do not override newer local)
                        let remoteUpdatedAt = dto.updatedAt ?? Date.distantPast
                        let localUpdatedAt  = existing.updatedAt
                        
                        if remoteUpdatedAt >= localUpdatedAt {
                            KBLog.sync.kbDebug("[todo][inbound][\(batch)] APPLY existing remote>=local remoteUpdatedAt=\(remoteUpdatedAt) localUpdatedAt=\(localUpdatedAt)")
                            
                            existing.familyId = dto.familyId
                            existing.childId = dto.childId
                            existing.listId = dto.listId
                            
                            // PII: do not log title/notes, but we still update them.
                            existing.title = dto.title
                            existing.notes = dto.notes
                            
                            existing.isDone = dto.isDone
                            existing.isDeleted = false
                            
                            existing.dueAt = dto.dueAt
                            existing.doneAt = dto.doneAt
                            existing.doneBy = dto.doneBy
                            
                            existing.assignedTo = dto.assignedTo
                            existing.priorityRaw = dto.priority ?? 0
                            
                            // updatedAt/updatedBy safe unwrap
                            existing.updatedAt = remoteUpdatedAt
                            if let ub = dto.updatedBy, !ub.isEmpty {
                                existing.updatedBy = ub
                            }
                            
                            if let cb = dto.createdBy, !cb.isEmpty {
                                existing.createdBy = cb
                            }
                            
                            existing.syncState = .synced
                            existing.lastSyncError = nil
                            
                            KBLog.sync.kbDebug("[todo][inbound][\(batch)] APPLIED -> \(todoSummary(existing))")
                        } else {
                            KBLog.sync.kbDebug("""
                        [todo][inbound][\(batch)] IGNORE existing remote<local
                        remoteUpdatedAt=\(remoteUpdatedAt) localUpdatedAt=\(localUpdatedAt)
                        local=\(todoSummary(existing))
                        remote=\(dtoSummary(dto))
                        """)
                        }
                        
                    } else {
                        // No local existing: create new local todo from dto
                        KBLog.sync.kbDebug("[todo][inbound][\(batch)] CREATE missing local id=\(dto.id) remote=\(dtoSummary(dto))")
                        
                        let created = try fetchOrCreateTodo(
                            id: dto.id,
                            familyId: dto.familyId,
                            childId: dto.childId,
                            listId: dto.listId,
                            modelContext: modelContext
                        )
                        
                        let remoteUpdatedAt = dto.updatedAt ?? Date()
                        
                        created.familyId = dto.familyId
                        created.childId = dto.childId
                        created.listId = dto.listId
                        
                        created.title = dto.title
                        created.notes = dto.notes
                        
                        created.isDone = dto.isDone
                        created.isDeleted = false
                        
                        created.dueAt = dto.dueAt
                        created.doneAt = dto.doneAt
                        created.doneBy = dto.doneBy
                        
                        created.assignedTo = dto.assignedTo
                        created.priorityRaw = dto.priority ?? 0
                        
                        created.updatedAt = remoteUpdatedAt
                        if let ub = dto.updatedBy, !ub.isEmpty {
                            created.updatedBy = ub
                        }
                        if let cb = dto.createdBy, !cb.isEmpty {
                            created.createdBy = cb
                        }
                        
                        created.syncState = .synced
                        created.lastSyncError = nil
                        
                        KBLog.sync.kbDebug("[todo][inbound][\(batch)] CREATED -> \(todoSummary(created))")
                    }
                    
                case .remove(let id):
                    // NOTE: if Firestore query filters out deleted docs,
                    // a remote soft-delete can arrive as `.remove`.
                    KBLog.sync.kbDebug("[todo][inbound][\(batch)] CHANGE remove id=\(id)")
                    
                    if let existing = try fetchTodo(id: id, modelContext: modelContext) {
                        KBLog.sync.kbInfo("[todo][inbound][\(batch)] remove -> HARD DELETE local=\(todoSummary(existing))")
                        modelContext.delete(existing)
                        KBLog.sync.kbDebug("[todo][inbound][\(batch)] hard deleted id=\(id)")
                    } else {
                        KBLog.sync.kbDebug("[todo][inbound][\(batch)] remove for missing id=\(id)")
                    }
                }
            }
            
            do {
                try modelContext.save()
                KBLog.sync.kbInfo("[todo][inbound][\(batch)] SAVE OK")
            } catch {
                KBLog.sync.kbError("[todo][inbound][\(batch)] SAVE FAIL err=\(String(describing: error))")
            }
            
        } catch {
            KBLog.sync.kbError("[todo][inbound][\(batch)] APPLY FAIL err=\(String(describing: error))")
        }
    }
    
    
    private func fetchTodo(id: String, modelContext: ModelContext) throws -> KBTodoItem? {
        let pid = id
        let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == pid })
        return try modelContext.fetch(desc).first
    }
    
    private func fetchOrCreateTodo(
        id: String,
        familyId: String,
        childId: String,
        listId: String?,
        modelContext: ModelContext
    ) throws -> KBTodoItem {
        
        if let existing = try fetchTodo(id: id, modelContext: modelContext) {
            return existing
        }
        
        let now = Date()
        
        let todo = KBTodoItem(
            id: id,
            familyId: familyId,
            childId: childId,
            title: "",
            listId: listId,
            notes: nil,
            dueAt: nil,
            isDone: false,
            doneAt: nil,
            doneBy: nil,
            updatedBy: "remote",
            createdAt: now,
            updatedAt: .distantPast,
            isDeleted: false
        )
        
        todo.syncState = .synced
        todo.lastSyncError = nil
        
        modelContext.insert(todo)
        return todo
    }
}

// MARK: - Remote incremental fetch (same file => can access private db)

extension TodoRemoteStore {
    /// Fetches todos updated after a given date (server-side filter on updatedAt).
    ///
    /// Notes:
    /// - Uses `Timestamp(date: since)` comparison.
    /// - Decodes documents into `TodoRemoteDTO`.
    func fetchTodosUpdatedSince(familyId: String, childId: String, since: Date) async throws -> [TodoRemoteDTO] {
        let snap = try await db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("childId", isEqualTo: childId)
            .whereField("updatedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
            .getDocuments()
        return snap.documents.map { doc in
            let data = doc.data()
            let listId = data["listId"] as? String
            
            return TodoRemoteDTO(
                id: doc.documentID,
                familyId: familyId,
                childId: data["childId"] as? String ?? "",
                title: data["title"] as? String ?? "",
                listId: listId,
                isDone: data["isDone"] as? Bool ?? false,
                isDeleted: data["isDeleted"] as? Bool ?? false,
                notes: data["notes"] as? String,
                dueAt: (data["dueAt"] as? Timestamp)?.dateValue(),
                doneAt: (data["doneAt"] as? Timestamp)?.dateValue(),
                doneBy: data["doneBy"] as? String,
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                updatedBy: data["updatedBy"] as? String,
                assignedTo: data["assignedTo"] as? String,
                createdBy: data["createdBy"] as? String,
                priority: data["priority"] as? Int
            )
        }
    }
}

extension SyncCenter {
    
    /// Internal subject used to notify UI or view models that documents changed for a family.
    private static var _docsChanged = PassthroughSubject<String, Never>()
    
    /// Public publisher for document changes.
    var docsChanged: AnyPublisher<String, Never> {
        Self._docsChanged.eraseToAnyPublisher()
    }
    
    /// Emits a document-changed signal for a family.
    func emitDocsChanged(familyId: String) {
        KBLog.sync.kbDebug("emitDocsChanged familyId=\(familyId)")
        Self._docsChanged.send(familyId)
    }
    
    // MARK: - Member revocation publisher
    
    /// Emitted when the current user is removed or revoked from a family.
    /// Payload is the familyId from which the user was removed.
    private static var _currentUserRevoked = PassthroughSubject<String, Never>()
    
    /// Publisher that fires when the current user is removed/revoked from a family.
    /// Observe this in views to trigger automatic sign-out from the family.
    var currentUserRevoked: AnyPublisher<String, Never> {
        Self._currentUserRevoked.eraseToAnyPublisher()
    }
}

