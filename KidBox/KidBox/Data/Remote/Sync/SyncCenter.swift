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

@MainActor
final class SyncCenter: ObservableObject {
    static let shared = SyncCenter()
    private init() {}
    
    // MARK: - Realtime (Inbound)
    
    private var todoListener: ListenerRegistration?
    private var membersListener: ListenerRegistration?
    private let membersRemote = FamilyMemberRemoteStore()
    
    func startTodoRealtime(
        familyId: String,
        childId: String,
        modelContext: ModelContext,
        remote: TodoRemoteStore
    ) {
        stopTodoRealtime()
        
        todoListener = remote.listenTodos(familyId: familyId, childId: childId) { [weak self] changes in
            guard let self else { return }
            self.applyTodoInbound(changes: changes, modelContext: modelContext)
        }
    }
    
    func startMembersRealtime(familyId: String, modelContext: ModelContext) {
        stopMembersRealtime()
        
        // prova a valorizzare il profilo “io” lato firestore (non blocca)
        Task { [familyId] in
            await membersRemote.upsertMyMemberProfileIfNeeded(familyId: familyId)
        }
        
        membersListener = membersRemote.listenMembers(familyId: familyId) { [weak self] changes in
            guard let self else { return }
            Task { @MainActor in
                self.applyMembersInbound(changes: changes, modelContext: modelContext)
            }
        }
    }
    
    func stopMembersRealtime() {
        membersListener?.remove()
        membersListener = nil
    }
    
    private func applyMembersInbound(changes: [FamilyMemberRemoteChange], modelContext: ModelContext) {
        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let mid = dto.id
                    let desc = FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.id == mid })
                    if let local = try modelContext.fetch(desc).first {
                        // LWW (usa updatedAt se c'è, altrimenti applica comunque)
                        let remoteStamp = dto.updatedAt ?? Date.distantPast
                        if dto.updatedAt == nil || remoteStamp >= local.updatedAt {
                            local.familyId = dto.familyId
                            local.userId = dto.userId
                            local.role = dto.role
                            local.displayName = dto.displayName
                            local.email = dto.email
                            local.photoURL = dto.photoURL
                            local.isDeleted = dto.isDeleted
                            
                            local.updatedAt = dto.updatedAt ?? Date()
                            local.updatedBy = dto.updatedBy ?? local.updatedBy
                        }
                    } else {
                        let now = Date()
                        let m = KBFamilyMember(
                            id: dto.id,
                            familyId: dto.familyId,
                            userId: dto.userId,
                            role: dto.role,
                            displayName: dto.displayName,
                            email: dto.email,
                            photoURL: dto.photoURL,
                            updatedBy: dto.updatedBy ?? "remote",
                            createdAt: now,
                            updatedAt: dto.updatedAt ?? now,
                            isDeleted: dto.isDeleted
                        )
                        modelContext.insert(m)
                    }
                    
                case .remove(let id):
                    let mid = id
                    let desc = FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.id == mid })
                    if let local = try modelContext.fetch(desc).first {
                        modelContext.delete(local)
                    }
                }
            }
            
            try modelContext.save()
        } catch {
            KBLog.sync.error("applyMembersInbound failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func stopTodoRealtime() {
        todoListener?.remove()
        todoListener = nil
    }
    
    // MARK: - Remotes (default)
    
    private let todoRemote = TodoRemoteStore()
    
    // MARK: - Auto flush
    
    private var flushTask: Task<Void, Never>?
    
    func flushGlobal(modelContext: ModelContext) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            await self.flush(modelContext: modelContext, remote: self.todoRemote)
        }
    }
    
    func startAutoFlush(modelContext: ModelContext) {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.flush(modelContext: modelContext, remote: self.todoRemote)
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
    }
    
    func stopAutoFlush() {
        flushTask?.cancel()
        flushTask = nil
    }
    
    // MARK: - Outbox
    
    private var isFlushing = false
    
    func enqueueTodoUpsert(todoId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.todo.rawValue,
            entityId: todoId,
            opType: "upsert",
            modelContext: modelContext
        )
    }
    
    func enqueueTodoDelete(todoId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.todo.rawValue,
            entityId: todoId,
            opType: "delete",
            modelContext: modelContext
        )
    }
    
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
            } else {
                let op = KBSyncOp(
                    familyId: familyId,
                    entityTypeRaw: entityType,
                    entityId: entityId,
                    opType: opType
                )
                modelContext.insert(op)
            }
            
            try modelContext.save()
        } catch {
            KBLog.sync.error("enqueue op failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func flush(modelContext: ModelContext, remote: TodoRemoteStore) async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }
        
        do {
            let now = Date()
            let desc = FetchDescriptor<KBSyncOp>(
                predicate: #Predicate { $0.nextRetryAt <= now },
                sortBy: [SortDescriptor(\KBSyncOp.createdAt, order: .forward)]
            )
            
            let ops = try modelContext.fetch(desc)
            for op in ops {
                await process(op: op, modelContext: modelContext, remote: remote)
            }
        } catch {
            KBLog.sync.error("flush fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func process(op: KBSyncOp, modelContext: ModelContext, remote: TodoRemoteStore) async {
        do {
            switch op.entityTypeRaw {
            case SyncEntityType.todo.rawValue:
                try await processTodo(op: op, modelContext: modelContext, remote: remote)
                
            case SyncEntityType.document.rawValue:
                // IMPORTANT: don't silently drop ops you haven't implemented yet
                throw NSError(domain: "KidBox.Sync", code: -2001,
                              userInfo: [NSLocalizedDescriptionKey: "Document sync not implemented yet"])
                
            case SyncEntityType.event.rawValue:
                throw NSError(domain: "KidBox.Sync", code: -2002,
                              userInfo: [NSLocalizedDescriptionKey: "Event sync not implemented yet"])
            case SyncEntityType.familyBundle.rawValue:
                try await self.processFamilyBundle(op: op, modelContext: modelContext)
                
            default:
                throw NSError(domain: "KidBox.Sync", code: -2000,
                              userInfo: [NSLocalizedDescriptionKey: "Unknown entityType: \(op.entityTypeRaw)"])
            }
            
            // ok -> remove op
            modelContext.delete(op)
            try modelContext.save()
            
            try updateFamilyLastSyncAt(familyId: op.familyId, modelContext: modelContext, error: nil)
            
        } catch {
            op.attempts += 1
            op.lastError = error.localizedDescription
            op.nextRetryAt = Date().addingTimeInterval(backoffSeconds(attempts: op.attempts))
            try? modelContext.save()
            
            try? updateFamilyLastSyncAt(familyId: op.familyId, modelContext: modelContext, error: op.lastError)
            
            KBLog.sync.error("sync op failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
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
                isDone: todo.isDone
            ))
            
            todo.syncState = .synced
            todo.lastSyncError = nil
            try modelContext.save()
            
        case "delete":
            try await remote.softDelete(todoId: tid, familyId: op.familyId)
            
            if let todo {
                todo.syncState = .synced
                todo.lastSyncError = nil
                try modelContext.save()
            }
            
        default:
            throw NSError(domain: "KidBox.Sync", code: -2100,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType: \(op.opType)"])
        }
    }
    
    private func backoffSeconds(attempts: Int) -> TimeInterval {
        min(pow(2.0, Double(max(0, attempts - 1))), 300.0)
    }
    
    private func updateFamilyLastSyncAt(familyId: String, modelContext: ModelContext, error: String?) throws {
        let fid = familyId
        let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        if let fam = try modelContext.fetch(desc).first {
            fam.lastSyncAt = Date()
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
    
    func pullTodoIncremental(
        familyId: String,
        childId: String,
        modelContext: ModelContext,
        remote: TodoRemoteStore? = nil
    ) async {
        let remote = remote ?? todoRemote
        
        do {
            let since = try fetchFamilyLastSyncAt(familyId: familyId, modelContext: modelContext) ?? .distantPast
            let dtos = try await remote.fetchTodosUpdatedSince(familyId: familyId, childId: childId, since: since)
            
            for dto in dtos {
                let todo = try fetchOrCreateTodo(id: dto.id, modelContext: modelContext)
                
                let remoteUpdatedAt = dto.updatedAt ?? Date.distantPast
                if remoteUpdatedAt >= todo.updatedAt {
                    todo.familyId = dto.familyId
                    todo.childId = dto.childId
                    todo.title = dto.title
                    todo.isDone = dto.isDone
                    todo.isDeleted = dto.isDeleted
                    todo.updatedAt = remoteUpdatedAt
                    todo.updatedBy = dto.updatedBy ?? todo.updatedBy
                    
                    todo.syncState = .synced
                    todo.lastSyncError = nil
                }
            }
            
            try modelContext.save()
            try updateFamilyLastSyncAt(familyId: familyId, modelContext: modelContext, error: nil)
            
        } catch {
            KBLog.sync.error("pull incremental failed: \(error.localizedDescription, privacy: .public)")
            try? updateFamilyLastSyncAt(familyId: familyId, modelContext: modelContext, error: error.localizedDescription)
        }
    }
    
    // MARK: - Apply inbound (Realtime)
    
    private func applyTodoInbound(changes: [TodoRemoteChange], modelContext: ModelContext) {
        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let todo = try fetchOrCreateTodo(id: dto.id, modelContext: modelContext)
                    
                    let remoteUpdatedAt = dto.updatedAt ?? Date.distantPast
                    if remoteUpdatedAt >= todo.updatedAt {
                        todo.familyId = dto.familyId
                        todo.childId = dto.childId
                        todo.title = dto.title
                        todo.isDone = dto.isDone
                        todo.isDeleted = dto.isDeleted
                        todo.updatedAt = remoteUpdatedAt
                        todo.updatedBy = dto.updatedBy ?? todo.updatedBy
                        
                        todo.syncState = .synced
                        todo.lastSyncError = nil
                    }
                    
                case .remove(let id):
                    // Usually unused (you soft-delete), but keep it safe.
                    if let existing = try fetchTodo(id: id, modelContext: modelContext) {
                        modelContext.delete(existing)
                    }
                }
            }
            
            try modelContext.save()
        } catch {
            KBLog.sync.error("Realtime apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func fetchTodo(id: String, modelContext: ModelContext) throws -> KBTodoItem? {
        let pid = id
        let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == pid })
        return try modelContext.fetch(desc).first
    }
    
    private func fetchOrCreateTodo(id: String, modelContext: ModelContext) throws -> KBTodoItem {
        if let existing = try fetchTodo(id: id, modelContext: modelContext) {
            return existing
        }
        
        let now = Date()
        let todo = KBTodoItem(
            id: id,
            familyId: "",
            childId: "",
            title: "",
            notes: nil,
            dueAt: nil,
            isDone: false,
            doneAt: nil,
            doneBy: nil,
            updatedBy: "remote",
            createdAt: now,
            updatedAt: now,
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
    func fetchTodosUpdatedSince(familyId: String, childId: String, since: Date) async throws -> [TodoRemoteDTO] {
        let snap = try await db.collection("families")
            .document(familyId)
            .collection("todos")
            .whereField("childId", isEqualTo: childId)
            .whereField("updatedAt", isGreaterThan: Timestamp(date: since))
            .getDocuments()
        
        return snap.documents.map { doc in
            let data = doc.data()
            return TodoRemoteDTO(
                id: doc.documentID,
                familyId: familyId,
                childId: data["childId"] as? String ?? "",
                title: data["title"] as? String ?? "",
                isDone: data["isDone"] as? Bool ?? false,
                isDeleted: data["isDeleted"] as? Bool ?? false,
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue(),
                updatedBy: data["updatedBy"] as? String
            )
        }
    }
}
