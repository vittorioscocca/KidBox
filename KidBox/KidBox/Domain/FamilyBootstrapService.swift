//
//  FamilyBootstrapService.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import SwiftData
import FirebaseAuth
import OSLog

@MainActor
final class FamilyBootstrapService {
    
    private let memberships: MembershipRemoteStore
    private let readRemote: FamilyReadRemoteStore
    private let modelContext: ModelContext
    
    init(
        memberships: MembershipRemoteStore? = nil,
        readRemote: FamilyReadRemoteStore? = nil,
        modelContext: ModelContext
    ) {
        self.memberships = memberships ?? MembershipRemoteStore()
        self.readRemote = readRemote ?? FamilyReadRemoteStore()
        self.modelContext = modelContext
    }
    
    /// If user has memberships, downloads the family data and upserts locally.
    func bootstrapIfNeeded() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        do {
            let list = try await memberships.fetchMembershipsForCurrentUser()
            guard let first = list.first else {
                KBLog.sync.info("Bootstrap: no memberships for uid=\(uid, privacy: .public)")
                return
            }
            
            let familyId = first.familyId
            KBLog.sync.info("Bootstrap: found membership familyId=\(familyId, privacy: .public)")
            
            // Fetch remote state
            let remoteFamily   = try await readRemote.fetchFamily(familyId: familyId)
            let remoteChildren = try await readRemote.fetchChildren(familyId: familyId)
            let remoteRoutines = try await readRemote.fetchRoutines(familyId: familyId)
            let remoteTodos    = try await readRemote.fetchTodos(familyId: familyId)
            let remoteEvents   = try await readRemote.fetchEvents(familyId: familyId)
            
            try upsertAll(
                uid: uid,
                family: remoteFamily,
                children: remoteChildren,
                routines: remoteRoutines,
                todos: remoteTodos,
                events: remoteEvents
            )
            
            try modelContext.save()
            KBLog.sync.info("Bootstrap OK familyId=\(familyId, privacy: .public)")
            
        } catch {
            KBLog.sync.error("Bootstrap failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Upsert helpers
    
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
        
        // Family
        let famDesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        let existingFamily = try modelContext.fetch(famDesc).first
        
        let localFamily: KBFamily
        if let existingFamily {
            localFamily = existingFamily
            localFamily.name = family.name
            localFamily.updatedBy = uid
            localFamily.updatedAt = Date()
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
        }
        
        // Children
        var localChildrenById: [String: KBChild] = [:]
        for c in localFamily.children {
            localChildrenById[c.id] = c
        }
        
        for rc in children {
            let childId = rc.id
            
            if let lc = localChildrenById[childId] {
                lc.name = rc.name
                lc.birthDate = rc.birthDate
                if lc.family == nil { lc.family = localFamily }
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
            }
        }
        
        try upsertRoutines(routines, familyId: fid, fallbackUpdatedBy: uid)
        try upsertTodos(todos, familyId: fid, fallbackUpdatedBy: uid)
        try upsertEvents(events, familyId: fid, fallbackUpdatedBy: uid)
    }
    
    private func upsertRoutines(_ items: [RemoteRoutineRead], familyId: String, fallbackUpdatedBy: String) throws {
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
    }
    
    private func upsertTodos(_ items: [RemoteTodoRead], familyId: String, fallbackUpdatedBy: String) throws {
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
    }
    
    private func upsertEvents(_ items: [RemoteEventRead], familyId: String, fallbackUpdatedBy: String) throws {
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
    }
}
