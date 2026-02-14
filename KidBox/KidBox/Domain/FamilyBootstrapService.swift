//
//  FamilyBootstrapService.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftData
import FirebaseAuth
import OSLog

/// Bootstraps the local SwiftData store from the server when the user is authenticated.
///
/// Responsibilities:
/// - Fetch current user's memberships from Firestore (`MembershipRemoteStore`).
/// - Pick the first available family (current MVP behavior).
/// - Download minimal family state (family, children, routines, todos, events).
/// - Upsert everything into SwiftData (local-first).
///
/// Notes:
/// - This service runs on `@MainActor` because it mutates SwiftData (`ModelContext`).
/// - Sync conflict strategy here is simple: upsert by id; timestamps are not deeply reconciled
///   (logic unchanged).
@MainActor
final class FamilyBootstrapService {
    
    // MARK: - Dependencies
    
    private let memberships: MembershipRemoteStore
    private let readRemote: FamilyReadRemoteStore
    private let modelContext: ModelContext
    
    /// Creates a bootstrap service.
    ///
    /// - Parameters:
    ///   - memberships: Optional dependency injection for testing.
    ///   - readRemote: Optional dependency injection for testing.
    ///   - modelContext: SwiftData context used for local persistence.
    init(
        memberships: MembershipRemoteStore? = nil,
        readRemote: FamilyReadRemoteStore? = nil,
        modelContext: ModelContext
    ) {
        self.memberships = memberships ?? MembershipRemoteStore()
        self.readRemote = readRemote ?? FamilyReadRemoteStore()
        self.modelContext = modelContext
        
        KBLog.sync.kbDebug("FamilyBootstrapService init")
    }
    
    // MARK: - Public API
    
    /// If the current user has at least one membership, downloads the family data and upserts locally.
    ///
    /// Behavior (unchanged):
    /// - Uses the first membership only (MVP).
    /// - Fetches remote family/children/routines/todos/events.
    /// - Upserts locally and saves.
    func bootstrapIfNeeded() async {
        KBLog.sync.kbDebug("bootstrapIfNeeded called")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbDebug("bootstrapIfNeeded skipped: not authenticated")
            return
        }
        
        do {
            KBLog.sync.kbInfo("Fetching memberships for current user")
            let list = try await memberships.fetchMembershipsForCurrentUser()
            
            guard let first = list.first else {
                KBLog.sync.kbInfo("Bootstrap: no memberships uid=\(uid)")
                return
            }
            
            let familyId = first.familyId
            KBLog.sync.kbInfo("Bootstrap: found membership familyId=\(familyId)")
            
            // Fetch remote state
            KBLog.sync.kbInfo("Bootstrap: fetching remote family bundle familyId=\(familyId)")
            let remoteFamily   = try await readRemote.fetchFamily(familyId: familyId)
            let remoteChildren = try await readRemote.fetchChildren(familyId: familyId)
            let remoteRoutines = try await readRemote.fetchRoutines(familyId: familyId)
            let remoteTodos    = try await readRemote.fetchTodos(familyId: familyId)
            let remoteEvents   = try await readRemote.fetchEvents(familyId: familyId)
            
            KBLog.sync.kbDebug(
                "Bootstrap: remote fetched children=\(remoteChildren.count) routines=\(remoteRoutines.count) todos=\(remoteTodos.count) events=\(remoteEvents.count)"
            )
            
            try upsertAll(
                uid: uid,
                family: remoteFamily,
                children: remoteChildren,
                routines: remoteRoutines,
                todos: remoteTodos,
                events: remoteEvents
            )
            
            try modelContext.save()
            KBLog.sync.kbInfo("Bootstrap OK familyId=\(familyId)")
            
        } catch {
            KBLog.sync.kbError("Bootstrap failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Upsert helpers
    
    /// Upserts family + children + routines + todos + events into SwiftData.
    ///
    /// - Important: Logic is unchanged; this method does not remove missing server entities
    ///   (except where other flows do so).
    private func upsertAll(
        uid: String,
        family: RemoteFamilyRead,
        children: [RemoteChildRead],
        routines: [RemoteRoutineRead],
        todos: [RemoteTodoRead],
        events: [RemoteEventRead]
    ) throws {
        
        // ✅ capture string BEFORE predicate
        let fid = family.id
        KBLog.sync.kbDebug("upsertAll start familyId=\(fid) children=\(children.count)")
        
        // Family
        let famDesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        let existingFamily = try modelContext.fetch(famDesc).first
        
        let localFamily: KBFamily
        if let existingFamily {
            localFamily = existingFamily
            localFamily.name = family.name
            localFamily.updatedBy = uid
            localFamily.updatedAt = Date()
            KBLog.sync.kbDebug("upsertAll updated existing family familyId=\(fid)")
        } else {
            localFamily = KBFamily(
                id: fid,
                name: family.name,
                createdBy: family.ownerUid,
                updatedBy: uid,
                createdAt: Date(),
                updatedAt: Date()
            )
            modelContext.insert(localFamily)
            KBLog.sync.kbDebug("upsertAll created local family familyId=\(fid)")
        }
        
        // Children
        var localChildrenById: [String: KBChild] = [:]
        for c in localFamily.children {
            localChildrenById[c.id] = c
        }
        
        var upsertedChildren = 0
        
        for rc in children {
            let childId = rc.id
            
            if let lc = localChildrenById[childId] {
                lc.name = rc.name
                lc.birthDate = rc.birthDate
                if lc.family == nil { lc.family = localFamily }
                upsertedChildren += 1
            } else {
                let newChild = KBChild(
                    id: childId,
                    familyId: fid,
                    name: rc.name,
                    birthDate: rc.birthDate,
                    createdBy: family.ownerUid,
                    createdAt: Date(),
                    updatedBy: uid,
                    updatedAt: Date()
                )
                newChild.family = localFamily
                localFamily.children.append(newChild)
                modelContext.insert(newChild)
                upsertedChildren += 1
            }
        }
        
        KBLog.sync.kbDebug("upsertAll children upserted=\(upsertedChildren)")
        
        try upsertRoutines(routines, familyId: fid, fallbackUpdatedBy: uid)
        try upsertTodos(todos, familyId: fid, fallbackUpdatedBy: uid)
        try upsertEvents(events, familyId: fid, fallbackUpdatedBy: uid)
        
        KBLog.sync.kbDebug("upsertAll completed familyId=\(fid)")
    }
    
    /// Upserts routines by id.
    private func upsertRoutines(_ items: [RemoteRoutineRead], familyId: String, fallbackUpdatedBy: String) throws {
        KBLog.sync.kbDebug("upsertRoutines start familyId=\(familyId) count=\(items.count)")
        
        for r in items {
            let rid = r.id
            let desc = FetchDescriptor<KBRoutine>(predicate: #Predicate { $0.id == rid })
            let existing = try modelContext.fetch(desc).first
            
            if let existing {
                existing.familyId = familyId
                existing.childId = r.childId
                existing.title = r.title
                existing.isActive = r.isActive
                existing.sortOrder = r.sortOrder
                existing.isDeleted = r.isDeleted
                existing.updatedAt = r.updatedAt ?? Date()
                existing.updatedBy = r.updatedBy ?? fallbackUpdatedBy
            } else {
                let routine = KBRoutine(
                    id: rid,
                    familyId: familyId,
                    childId: r.childId,
                    title: r.title,
                    isActive: r.isActive,
                    sortOrder: r.sortOrder,
                    updatedBy: r.updatedBy ?? fallbackUpdatedBy,
                    createdAt: Date(),
                    updatedAt: r.updatedAt ?? Date(),
                    isDeleted: r.isDeleted
                )
                modelContext.insert(routine)
            }
        }
        
        KBLog.sync.kbDebug("upsertRoutines completed familyId=\(familyId)")
    }
    
    /// Upserts todos by id.
    private func upsertTodos(_ items: [RemoteTodoRead], familyId: String, fallbackUpdatedBy: String) throws {
        KBLog.sync.kbDebug("upsertTodos start familyId=\(familyId) count=\(items.count)")
        
        for t in items {
            let tid = t.id
            let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == tid })
            let existing = try modelContext.fetch(desc).first
            
            if let existing {
                existing.familyId = familyId
                existing.childId = t.childId
                existing.title = t.title
                existing.notes = t.notes
                existing.dueAt = t.dueAt
                existing.isDone = t.isDone
                existing.doneAt = t.doneAt
                existing.doneBy = t.doneBy
                existing.isDeleted = t.isDeleted
                existing.updatedAt = t.updatedAt ?? Date()
                existing.updatedBy = t.updatedBy ?? fallbackUpdatedBy
            } else {
                let todo = KBTodoItem(
                    id: tid,
                    familyId: familyId,
                    childId: t.childId,
                    title: t.title,
                    notes: t.notes,
                    dueAt: t.dueAt,
                    isDone: t.isDone,
                    doneAt: t.doneAt,
                    doneBy: t.doneBy,
                    updatedBy: t.updatedBy ?? fallbackUpdatedBy,
                    createdAt: Date(),
                    updatedAt: t.updatedAt ?? Date(),
                    isDeleted: t.isDeleted
                )
                modelContext.insert(todo)
            }
        }
        
        KBLog.sync.kbDebug("upsertTodos completed familyId=\(familyId)")
    }
    
    /// Upserts events by id.
    private func upsertEvents(_ items: [RemoteEventRead], familyId: String, fallbackUpdatedBy: String) throws {
        KBLog.sync.kbDebug("upsertEvents start familyId=\(familyId) count=\(items.count)")
        
        for e in items {
            let eid = e.id
            let desc = FetchDescriptor<KBEvent>(predicate: #Predicate { $0.id == eid })
            let existing = try modelContext.fetch(desc).first
            
            if let existing {
                existing.familyId = familyId
                existing.childId = e.childId
                existing.type = e.type
                existing.title = e.title
                existing.startAt = e.startAt
                existing.endAt = e.endAt
                existing.notes = e.notes
                existing.isDeleted = e.isDeleted
                existing.updatedAt = e.updatedAt ?? Date()
                existing.updatedBy = e.updatedBy ?? fallbackUpdatedBy
            } else {
                let event = KBEvent(
                    id: eid,
                    familyId: familyId,
                    childId: e.childId,
                    type: e.type,
                    title: e.title,
                    startAt: e.startAt,
                    endAt: e.endAt,
                    notes: e.notes,
                    updatedBy: e.updatedBy ?? fallbackUpdatedBy,
                    createdAt: Date(),
                    updatedAt: e.updatedAt ?? Date(),
                    isDeleted: e.isDeleted
                )
                modelContext.insert(event)
            }
        }
        
        KBLog.sync.kbDebug("upsertEvents completed familyId=\(familyId)")
    }
}
