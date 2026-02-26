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
/// ## Responsibilities
/// - Fetch current user's memberships from Firestore (`MembershipRemoteStore`).
/// - Pick the first available family (current MVP behavior).
/// - Download minimal family state (family, children, routines, todos, events) via `FamilyReadRemoteStore`.
/// - Upsert everything into SwiftData (local-first).
///
/// ## Threading
/// Runs on `@MainActor` because it mutates SwiftData (`ModelContext`).
///
/// ## Conflict strategy (unchanged)
/// - Upsert by id.
/// - Uses remote timestamps when present, otherwise fallback to `Date()`.
/// - Does not remove local entities that are missing on server (deletions are handled elsewhere).
///
/// ## Logging policy
/// - Avoids logging PII: no names/titles/notes.
/// - Logs ids, counts, and important state flags (isDeleted/isDone/listId presence, updatedAt presence).
@MainActor
final class FamilyBootstrapService {
    
    // MARK: - Dependencies
    
    private let memberships: MembershipRemoteStore
    private let readRemote: FamilyReadRemoteStore
    private let modelContext: ModelContext
    
    // MARK: - Init
    
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
        let trace = Self.trace("boot:")
        let t0 = Self.now()
        
        KBLog.sync.kbInfo("[\(trace)] bootstrapIfNeeded START")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbDebug("[\(trace)] bootstrapIfNeeded SKIP: not authenticated")
            return
        }
        
        do {
            KBLog.sync.kbInfo("[\(trace)] Fetching memberships for current user")
            
            let tMem = Self.now()
            let list = try await memberships.fetchMembershipsForCurrentUser()
            KBLog.sync.kbInfo("[\(trace)] memberships fetched count=\(list.count) ms=\(Self.msSince(tMem))")
            
            guard let first = list.first else {
                KBLog.sync.kbInfo("[\(trace)] Bootstrap: no memberships (uid present) ms=\(Self.msSince(t0))")
                return
            }
            
            let familyId = first.familyId
            KBLog.sync.kbInfo("[\(trace)] Bootstrap: using first membership familyId=\(familyId)")
            
            // Fetch remote state (timed)
            KBLog.sync.kbInfo("[\(trace)] Bootstrap: fetching remote family bundle familyId=\(familyId)")
            
            let tFam = Self.now()
            let remoteFamily = try await readRemote.fetchFamily(familyId: familyId)
            KBLog.sync.kbInfo("[\(trace)] fetchFamily OK familyId=\(familyId) ms=\(Self.msSince(tFam))")
            
            let tChildren = Self.now()
            let remoteChildren = try await readRemote.fetchChildren(familyId: familyId)
            KBLog.sync.kbInfo("[\(trace)] fetchChildren OK count=\(remoteChildren.count) ms=\(Self.msSince(tChildren))")
            
            let tRoutines = Self.now()
            let remoteRoutines = try await readRemote.fetchRoutines(familyId: familyId)
            KBLog.sync.kbInfo("[\(trace)] fetchRoutines OK count=\(remoteRoutines.count) ms=\(Self.msSince(tRoutines))")
            
            let tTodos = Self.now()
            let remoteTodos = try await readRemote.fetchTodos(familyId: familyId)
            KBLog.sync.kbInfo("[\(trace)] fetchTodos OK count=\(remoteTodos.count) ms=\(Self.msSince(tTodos))")
            // subito dopo: let remoteTodos    = try await readRemote.fetchTodos(familyId: familyId)
            
            let delCount = remoteTodos.filter { $0.isDeleted }.count
            let listNilCount = remoteTodos.filter { $0.listId == nil }.count
            let listEmptyCount = remoteTodos.filter { ($0.listId ?? "") == "" }.count - listNilCount
            let listValCount = remoteTodos.count - listNilCount - listEmptyCount
            let updatedNilCount = remoteTodos.filter { $0.updatedAt == nil }.count
            let childEmptyCount = remoteTodos.filter { $0.childId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            
            KBLog.sync.kbInfo("""
[\(trace)] Bootstrap Todos stats:
total=\(remoteTodos.count)
isDeletedTrue=\(delCount)
listId.nil=\(listNilCount) listId.empty="\(listEmptyCount)" listId.value=\(listValCount)
updatedAt.nil=\(updatedNilCount)
childId.empty=\(childEmptyCount)
""")
            
            let suspicious = remoteTodos
                .filter { $0.isDeleted || ($0.listId ?? "") == "" || $0.updatedAt == nil || $0.childId.isEmpty }
                .prefix(12)
                .map { t in
                    let lid = t.listId == nil ? "nil" : ((t.listId ?? "") == "" ? "\"\"" : "val")
                    return "\(t.id){del=\(t.isDeleted),done=\(t.isDone),listId=\(lid),uaNil=\(t.updatedAt == nil),childEmpty=\(t.childId.isEmpty)}"
                }
                .joined(separator: " | ")
            
            if !suspicious.isEmpty {
                KBLog.sync.kbDebug("[\(trace)] Bootstrap Todos suspicious sample: \(suspicious)")
            }
            let tEvents = Self.now()
            let remoteEvents = try await readRemote.fetchEvents(familyId: familyId)
            KBLog.sync.kbInfo("[\(trace)] fetchEvents OK count=\(remoteEvents.count) ms=\(Self.msSince(tEvents))")
            
            KBLog.sync.kbDebug("""
            [\(trace)] Bootstrap: remote fetched
            children=\(remoteChildren.count) routines=\(remoteRoutines.count) todos=\(remoteTodos.count) events=\(remoteEvents.count)
            """)
            
            let tUpsert = Self.now()
            try upsertAll(
                trace: trace,
                uid: uid,
                family: remoteFamily,
                children: remoteChildren,
                routines: remoteRoutines,
                todos: remoteTodos,
                events: remoteEvents
            )
            KBLog.sync.kbInfo("[\(trace)] upsertAll OK ms=\(Self.msSince(tUpsert))")
            
            do {
                let tSave = Self.now()
                try modelContext.save()
                KBLog.sync.kbInfo("[\(trace)] SwiftData save OK ms=\(Self.msSince(tSave)) totalMs=\(Self.msSince(t0))")
                KBLog.sync.kbInfo("[\(trace)] Bootstrap OK familyId=\(familyId)")
            } catch {
                KBLog.sync.kbError("[\(trace)] SwiftData save FAIL err=\(String(describing: error)) totalMs=\(Self.msSince(t0))")
            }
            
        } catch {
            KBLog.sync.kbError("[\(trace)] Bootstrap failed err=\(error.localizedDescription) totalMs=\(Self.msSince(t0))")
        }
    }
    
    // MARK: - Upsert helpers
    
    /// Upserts family + children + routines + todos + events into SwiftData.
    ///
    /// - Important: Logic unchanged. Does not remove missing server entities.
    private func upsertAll(
        trace: String,
        uid: String,
        family: RemoteFamilyRead,
        children: [RemoteChildRead],
        routines: [RemoteRoutineRead],
        todos: [RemoteTodoRead],
        events: [RemoteEventRead]
    ) throws {
        
        // capture string BEFORE predicate
        let fid = family.id
        KBLog.sync.kbDebug("[\(trace)] upsertAll START familyId=\(fid) children=\(children.count) routines=\(routines.count) todos=\(todos.count) events=\(events.count)")
        
        // Family
        let famDesc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
        let existingFamily = try modelContext.fetch(famDesc).first
        
        let localFamily: KBFamily
        if let existingFamily {
            localFamily = existingFamily
            // Do not log family.name (PII)
            localFamily.name = family.name
            localFamily.updatedBy = uid
            localFamily.updatedAt = Date()
            KBLog.sync.kbDebug("[\(trace)] upsertAll Family UPDATE existing familyId=\(fid)")
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
            KBLog.sync.kbDebug("[\(trace)] upsertAll Family INSERT new familyId=\(fid)")
        }
        
        // Children
        var localChildrenById: [String: KBChild] = [:]
        for c in localFamily.children { localChildrenById[c.id] = c }
        
        var upsertedChildren = 0
        var insertedChildren = 0
        var updatedChildren = 0
        
        let sampleChildIds = children.prefix(10).map(\.id).joined(separator: ",")
        KBLog.sync.kbDebug("[\(trace)] upsertAll Children incoming=\(children.count) sampleIds=[\(sampleChildIds)]")
        
        for rc in children {
            let childId = rc.id
            if childId.isEmpty {
                KBLog.sync.kbInfo("[\(trace)] upsertAll Children WARN: empty childId from remote")
            }
            
            if let lc = localChildrenById[childId] {
                lc.name = rc.name // do not log
                lc.birthDate = rc.birthDate
                if lc.family == nil { lc.family = localFamily }
                upsertedChildren += 1
                updatedChildren += 1
            } else {
                let newChild = KBChild(
                    id: childId,
                    familyId: fid,
                    name: rc.name, // do not log
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
                insertedChildren += 1
            }
        }
        
        KBLog.sync.kbInfo("[\(trace)] upsertAll Children done upserted=\(upsertedChildren) inserted=\(insertedChildren) updated=\(updatedChildren) localTotal=\(localFamily.children.count)")
        
        try upsertRoutines(trace, routines, familyId: fid, fallbackUpdatedBy: uid)
        try upsertTodos(trace, todos, familyId: fid, fallbackUpdatedBy: uid)
        try upsertEvents(trace, events, familyId: fid, fallbackUpdatedBy: uid)
        
        KBLog.sync.kbDebug("[\(trace)] upsertAll COMPLETED familyId=\(fid)")
    }
    
    /// Upserts routines by id.
    private func upsertRoutines(_ trace: String, _ items: [RemoteRoutineRead], familyId: String, fallbackUpdatedBy: String) throws {
        KBLog.sync.kbDebug("[\(trace)] upsertRoutines START familyId=\(familyId) count=\(items.count)")
        let t0 = Self.now()
        
        var updated = 0
        var inserted = 0
        
        let sample = items.prefix(10).map(\.id).joined(separator: ",")
        KBLog.sync.kbDebug("[\(trace)] upsertRoutines sampleIds=[\(sample)]")
        
        for r in items {
            let rid = r.id
            let desc = FetchDescriptor<KBRoutine>(predicate: #Predicate { $0.id == rid })
            let existing = try modelContext.fetch(desc).first
            
            if let existing {
                existing.familyId = familyId
                existing.childId = r.childId
                existing.title = r.title // do not log
                existing.isActive = r.isActive
                existing.sortOrder = r.sortOrder
                existing.isDeleted = r.isDeleted
                existing.updatedAt = r.updatedAt ?? Date()
                existing.updatedBy = r.updatedBy ?? fallbackUpdatedBy
                updated += 1
            } else {
                let routine = KBRoutine(
                    id: rid,
                    familyId: familyId,
                    childId: r.childId,
                    title: r.title, // do not log
                    isActive: r.isActive,
                    sortOrder: r.sortOrder,
                    updatedBy: r.updatedBy ?? fallbackUpdatedBy,
                    createdAt: Date(),
                    updatedAt: r.updatedAt ?? Date(),
                    isDeleted: r.isDeleted
                )
                modelContext.insert(routine)
                inserted += 1
            }
        }
        
        KBLog.sync.kbInfo("[\(trace)] upsertRoutines DONE familyId=\(familyId) updated=\(updated) inserted=\(inserted) ms=\(Self.msSince(t0))")
    }
    
    /// Upserts todos by id.
    private func upsertTodos(_ trace: String, _ items: [RemoteTodoRead], familyId: String, fallbackUpdatedBy: String) throws {
        KBLog.sync.kbDebug("[\(trace)] upsertTodos START familyId=\(familyId) count=\(items.count)")
        let t0 = Self.now()
        
        // Stats utili a diagnosticare resurrect / filtri listId
        let delCount = items.filter { $0.isDeleted }.count
        let listNilCount = items.filter { $0.listId == nil }.count
        let listEmptyCount = items.filter { ($0.listId ?? "") == "" }.count - listNilCount
        let listValCount = items.count - listNilCount - listEmptyCount
        let updatedNilCount = items.filter { $0.updatedAt == nil }.count
        let childEmptyCount = items.filter { $0.childId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        
        KBLog.sync.kbInfo("""
    [\(trace)] upsertTodos STATS familyId=\(familyId)
    total=\(items.count)
    isDeletedTrue=\(delCount)
    listId.nil=\(listNilCount) listId.empty="\(listEmptyCount)" listId.value=\(listValCount)
    updatedAt.nil=\(updatedNilCount)
    childId.empty=\(childEmptyCount)
    """)
        
        // Sample “sospetti”
        let suspicious = items
            .filter { $0.isDeleted || ($0.listId ?? "") == "" || $0.updatedAt == nil || $0.childId.isEmpty }
            .prefix(12)
            .map { t in
                let lid = t.listId == nil ? "nil" : ((t.listId ?? "") == "" ? "\"\"" : "val")
                return "\(t.id){del=\(t.isDeleted),done=\(t.isDone),listId=\(lid),uaNil=\(t.updatedAt == nil),childEmpty=\(t.childId.isEmpty)}"
            }
            .joined(separator: " | ")
        
        if !suspicious.isEmpty {
            KBLog.sync.kbDebug("[\(trace)] upsertTodos suspicious sample: \(suspicious)")
        }
        
        var updated = 0
        var inserted = 0
        
        // Tracking extra: quante volte sovrascriviamo local state “controintuitivamente”
        var resurrectedLocally = 0   // local isDeleted=true ma remote arriva isDeleted=false
        var deletedByRemote = 0      // remote arriva isDeleted=true e local era false
        var listIdMutations = 0      // remote cambia listId (nil/""/val)
        
        for t in items {
            let tid = t.id
            if tid.isEmpty { KBLog.sync.kbInfo("[\(trace)] upsertTodos WARN: empty todoId from remote") }
            
            let remoteListIdNorm: String? = {
                // normalizziamo: se remoto salva "" lo trattiamo come nil per comparazioni/log
                let v = t.listId
                if v == nil { return nil }
                if (v ?? "") == "" { return nil }
                return v
            }()
            
            let desc = FetchDescriptor<KBTodoItem>(predicate: #Predicate { $0.id == tid })
            let existing = try modelContext.fetch(desc).first
            
            if let existing {
                // snapshot pre-update per log differenze
                let localWasDeleted = existing.isDeleted
                let localListNorm: String? = {
                    let v = existing.listId
                    if v == nil { return nil }
                    if (v ?? "") == "" { return nil }
                    return v
                }()
                
                if localWasDeleted && !t.isDeleted { resurrectedLocally += 1 }
                if !localWasDeleted && t.isDeleted { deletedByRemote += 1 }
                if localListNorm != remoteListIdNorm { listIdMutations += 1 }
                
                // Upsert (come prima)
                existing.familyId = familyId
                existing.childId = t.childId
                existing.title = t.title              // no log
                existing.listId = t.listId            // manteniamo il dato raw (anche "" se arriva così)
                existing.notes = t.notes              // no log
                existing.dueAt = t.dueAt
                existing.isDone = t.isDone
                existing.doneAt = t.doneAt
                existing.doneBy = t.doneBy
                existing.isDeleted = t.isDeleted
                existing.updatedAt = t.updatedAt ?? Date()
                existing.updatedBy = t.updatedBy ?? fallbackUpdatedBy
                updated += 1
                
                // Log “diff” SOLO per casi sospetti (no PII)
                if localWasDeleted != t.isDeleted || localListNorm != remoteListIdNorm {
                    let lidLocal = localListNorm ?? "nil/\"\""
                    let lidRemote = remoteListIdNorm ?? "nil/\"\""
                    KBLog.sync.kbDebug("[\(trace)] upsertTodos DIFF todoId=\(tid) del \(localWasDeleted)->\(t.isDeleted) listId \(lidLocal)->\(lidRemote) uaNil=\(t.updatedAt == nil)")
                }
            } else {
                let todo = KBTodoItem(
                    id: tid,
                    familyId: familyId,
                    childId: t.childId,
                    title: t.title,             // no log
                    listId: t.listId,
                    notes: t.notes,             // no log
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
                inserted += 1
                
                // Log inserimenti “strani” (tipo: inserisco già deleted o listId vuota)
                if t.isDeleted || (t.listId ?? "") == "" || t.updatedAt == nil {
                    let lid = t.listId == nil ? "nil" : ((t.listId ?? "") == "" ? "\"\"" : "val")
                    KBLog.sync.kbInfo("[\(trace)] upsertTodos INSERT suspicious todoId=\(tid) del=\(t.isDeleted) done=\(t.isDone) listId=\(lid) uaNil=\(t.updatedAt == nil) childEmpty=\(t.childId.isEmpty)")
                }
            }
        }
        
        KBLog.sync.kbInfo("[\(trace)] upsertTodos DELTA resurrectedLocally=\(resurrectedLocally) deletedByRemote=\(deletedByRemote) listIdMutations=\(listIdMutations)")
        KBLog.sync.kbInfo("[\(trace)] upsertTodos DONE familyId=\(familyId) updated=\(updated) inserted=\(inserted) ms=\(Self.msSince(t0))")
    }
    
    /// Upserts events by id.
    private func upsertEvents(_ trace: String, _ items: [RemoteEventRead], familyId: String, fallbackUpdatedBy: String) throws {
        KBLog.sync.kbDebug("[\(trace)] upsertEvents START familyId=\(familyId) count=\(items.count)")
        let t0 = Self.now()
        
        var updated = 0
        var inserted = 0
        
        let sample = items.prefix(10).map { e in
            // title/notes are PII-ish, avoid
            "\(e.id){type=\(e.type),del=\(e.isDeleted),ua=\(e.updatedAt != nil)}"
        }.joined(separator: " | ")
        KBLog.sync.kbDebug("[\(trace)] upsertEvents sample=\(sample)")
        
        for e in items {
            let eid = e.id
            let desc = FetchDescriptor<KBEvent>(predicate: #Predicate { $0.id == eid })
            let existing = try modelContext.fetch(desc).first
            
            if let existing {
                existing.familyId = familyId
                existing.childId = e.childId
                existing.type = e.type
                existing.title = e.title     // do not log
                existing.startAt = e.startAt
                existing.endAt = e.endAt
                existing.notes = e.notes     // do not log
                existing.isDeleted = e.isDeleted
                existing.updatedAt = e.updatedAt ?? Date()
                existing.updatedBy = e.updatedBy ?? fallbackUpdatedBy
                updated += 1
            } else {
                let event = KBEvent(
                    id: eid,
                    familyId: familyId,
                    childId: e.childId,
                    type: e.type,
                    title: e.title,           // do not log
                    startAt: e.startAt,
                    endAt: e.endAt,
                    notes: e.notes,           // do not log
                    updatedBy: e.updatedBy ?? fallbackUpdatedBy,
                    createdAt: Date(),
                    updatedAt: e.updatedAt ?? Date(),
                    isDeleted: e.isDeleted
                )
                modelContext.insert(event)
                inserted += 1
            }
        }
        
        KBLog.sync.kbInfo("[\(trace)] upsertEvents DONE familyId=\(familyId) updated=\(updated) inserted=\(inserted) ms=\(Self.msSince(t0))")
    }
}

// MARK: - Internal helpers

private extension FamilyBootstrapService {
    static func trace(_ prefix: String) -> String { "\(prefix)\(String(UUID().uuidString.prefix(8)))" }
    static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }
    static func msSince(_ start: CFAbsoluteTime) -> Int { Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0) }
}
