//
//  FamilyJoinService.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import SwiftUI
import SwiftData
import FirebaseAuth
import OSLog
import FirebaseFirestore

/// Joins an existing family using an invite code and bootstraps local state.
///
/// Responsibilities:
/// - Normalize and resolve invite codes.
/// - Ensure user becomes a member on Firestore.
/// - Perform a one-shot family doc refresh (including hero fields).
/// - Fetch and upsert minimal family bundle (family, children, routines, todos, events) into SwiftData.
/// - Pin the joined family as active via `AppCoordinator.setActiveFamily(_:)` BEFORE any bootstrap.
/// - Start realtime listeners and trigger a global flush.
///
/// Notes:
/// - This service is `@MainActor` because it mutates SwiftData (`ModelContext`) and triggers UI-affecting flows.
@MainActor
final class FamilyJoinService {
    // MARK: - Dependencies
    
    private let inviteRemote: InviteRemoteStore
    private let readRemote: FamilyReadRemoteStore
    private let modelContext: ModelContext
    
    /// Creates a `FamilyJoinService` with required remote stores and a SwiftData context.
    init(inviteRemote: InviteRemoteStore, readRemote: FamilyReadRemoteStore, modelContext: ModelContext) {
        self.inviteRemote = inviteRemote
        self.readRemote = readRemote
        self.modelContext = modelContext
        KBLog.sync.kbDebug("FamilyJoinService init")
    }
    
    // MARK: - Public API
    
    /// Joins a family from an invite `code` and bootstraps local data.
    ///
    /// Behavior:
    /// 1) Normalize code, ensure authenticated.
    /// 2) Resolve invite -> familyId.
    /// 3) One-shot refresh of family doc fields (name + hero) in a detached Task.
    /// 4) Add member on server.
    /// 5) Fetch minimal family bundle from server.
    /// 6) Upsert local family + children + routines/todos/events.
    /// 7) **Pin `familyId` as active on the coordinator** — this must happen before
    ///    bootstrap so that RootHostView does not flip back to the old family.
    /// 8) Start realtime bundle + members; flush.
    /// 9) Bootstrap remaining memberships (syncs old families in background, does NOT change active).
    func joinFamily(code rawCode: String, coordinator: AppCoordinator) async throws {
        let code = rawCode
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
        
        KBLog.sync.kbInfo("joinFamily start normalizedCodeLen=\(code.count)")
        
        guard let uid = Auth.auth().currentUser?.uid else {
            KBLog.auth.kbError("joinFamily failed: not authenticated")
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]
            )
        }
        
        // 1) Resolve invite -> familyId
        KBLog.sync.kbDebug("Resolving invite code")
        let familyId = try await inviteRemote.resolveInvite(code: code)
        KBLog.sync.kbInfo("Invite resolved familyId=\(familyId)")
        
        // ─────────────────────────────────────────────────────────────────────
        // PIN SUBITO — prima di qualsiasi Task detached o save su SwiftData.
        // Il Task di one-shot refresh qui sotto chiama modelContext.save(),
        // che può toccare updatedAt di altre famiglie e triggerare un re-render
        // di RootHostView prima che setActiveFamily() venga chiamato al punto 7.
        // Settandolo qui, RootHostView è già vincolata alla famiglia corretta
        // per tutto il resto del flusso.
        // ─────────────────────────────────────────────────────────────────────
        KBLog.sync.kbInfo("Pinning joined family as active (early) familyId=\(familyId)")
        coordinator.setActiveFamily(familyId)
        
        // One-shot family refresh (best effort, non-blocking)
        Task { @MainActor in
            KBLog.sync.kbDebug("Family one-shot refresh started familyId=\(familyId)")
            do {
                let snap = try await Firestore.firestore()
                    .collection("families")
                    .document(familyId)
                    .getDocument()
                
                guard let data = snap.data() else {
                    KBLog.sync.kbDebug("Family one-shot refresh: missing data familyId=\(familyId)")
                    return
                }
                
                let remoteName = data["name"] as? String ?? ""
                let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                let remoteUpdatedBy = data["updatedBy"] as? String
                
                let remoteHeroURL = data["heroPhotoURL"] as? String
                let remoteHeroUpdatedAt = (data["heroPhotoUpdatedAt"] as? Timestamp)?.dateValue()
                
                let fid = familyId
                let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
                let fam = try modelContext.fetch(desc).first ?? {
                    let now = Date()
                    let created = KBFamily(
                        id: fid,
                        name: remoteName,
                        createdBy: remoteUpdatedBy ?? "remote",
                        updatedBy: remoteUpdatedBy ?? "remote",
                        createdAt: now,
                        updatedAt: remoteUpdatedAt
                    )
                    modelContext.insert(created)
                    KBLog.sync.kbDebug("Family one-shot refresh: created local family familyId=\(fid)")
                    return created
                }()
                
                if remoteUpdatedAt >= fam.updatedAt {
                    fam.name = remoteName
                    fam.updatedAt = remoteUpdatedAt
                    fam.updatedBy = remoteUpdatedBy ?? fam.updatedBy
                    KBLog.sync.kbDebug("Family one-shot refresh: applied name/meta familyId=\(fid)")
                }
                
                let remoteHeroStamp = remoteHeroUpdatedAt ?? remoteUpdatedAt
                let localHeroStamp = fam.heroPhotoUpdatedAt ?? .distantPast
                if remoteHeroStamp >= localHeroStamp {
                    fam.heroPhotoURL = remoteHeroURL
                    fam.heroPhotoUpdatedAt = remoteHeroStamp
                    KBLog.sync.kbDebug("Family one-shot refresh: applied hero hasURL=\(remoteHeroURL != nil) familyId=\(fid)")
                }
                
                try modelContext.save()
                KBLog.sync.kbInfo("Family one-shot refresh completed familyId=\(fid)")
            } catch {
                KBLog.sync.kbError("family one-shot refresh failed: \(error.localizedDescription)")
            }
        }
        
        // 2) Become member on server
        KBLog.sync.kbDebug("Adding member on server familyId=\(familyId)")
        try await inviteRemote.addMember(familyId: familyId, role: "member")
        KBLog.sync.kbInfo("Member added on server familyId=\(familyId)")
        
        // 3) Read minimal family state
        KBLog.sync.kbDebug("Fetching remote family bundle familyId=\(familyId)")
        let remoteFamily = try await readRemote.fetchFamily(familyId: familyId)
        let remoteChildren = try await readRemote.fetchChildren(familyId: familyId)
        let remoteRoutines = try await readRemote.fetchRoutines(familyId: familyId)
        let remoteTodos    = try await readRemote.fetchTodos(familyId: familyId)
        let remoteEvents   = try await readRemote.fetchEvents(familyId: familyId)
        KBLog.sync.kbInfo("Remote bundle fetched familyId=\(familyId) children=\(remoteChildren.count) routines=\(remoteRoutines.count) todos=\(remoteTodos.count) events=\(remoteEvents.count)")
        
        // 4) Upsert local KBFamily
        let familyDescriptor = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == familyId })
        let existingFamily = try modelContext.fetch(familyDescriptor).first
        
        let family: KBFamily
        if let existingFamily {
            family = existingFamily
            family.name = remoteFamily.name
            family.updatedBy = uid
            family.updatedAt = Date()
            KBLog.sync.kbDebug("Local family updated familyId=\(familyId)")
        } else {
            let now = Date()
            family = KBFamily(
                id: remoteFamily.id,
                name: remoteFamily.name,
                createdBy: remoteFamily.ownerUid,
                updatedBy: uid,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(family)
            KBLog.sync.kbDebug("Local family created familyId=\(familyId)")
        }
        
        // 5) Upsert children by id (no removeAll)
        var localById: [String: KBChild] = [:]
        for c in family.children {
            localById[c.id] = c
        }
        
        var seenIds = Set<String>()
        for rc in remoteChildren {
            let childId = rc.id
            seenIds.insert(childId)
            
            if let lc = localById[childId] {
                lc.name = rc.name
                lc.birthDate = rc.birthDate
                if lc.family == nil { lc.family = family }
            } else {
                let newChild = KBChild(
                    id: childId,
                    familyId: familyId,
                    name: rc.name,
                    birthDate: rc.birthDate,
                    createdBy: remoteFamily.ownerUid,
                    createdAt: Date(),
                    updatedBy: uid,
                    updatedAt: Date()
                )
                newChild.family = family
                family.children.append(newChild)
                modelContext.insert(newChild)
            }
        }
        
        let toDelete = family.children.filter { !seenIds.contains($0.id) }
        if !toDelete.isEmpty {
            KBLog.sync.kbDebug("Deleting local children not on server count=\(toDelete.count) familyId=\(familyId)")
        }
        for lc in toDelete {
            family.children.removeAll { $0.id == lc.id }
            modelContext.delete(lc)
        }
        
        KBLog.sync.kbDebug("Upserting routines/todos/events familyId=\(familyId)")
        try upsertRoutines(remoteRoutines, familyId: familyId, fallbackUpdatedBy: uid)
        try upsertTodos(remoteTodos, familyId: familyId, fallbackUpdatedBy: uid)
        try upsertEvents(remoteEvents, familyId: familyId, fallbackUpdatedBy: uid)
        
        try modelContext.save()
        KBLog.sync.kbInfo("Join family local data saved familyId=\(familyId)")
        
        // 8) Start realtime for the joined family
        KBLog.sync.kbDebug("Restarting family bundle realtime familyId=\(familyId)")
        SyncCenter.shared.stopFamilyBundleRealtime()
        SyncCenter.shared.startFamilyBundleRealtime(familyId: familyId, modelContext: modelContext)
        
        KBLog.sync.kbDebug("FlushGlobal requested after join familyId=\(familyId)")
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        KBLog.sync.kbDebug("Starting members realtime after join familyId=\(familyId)")
        SyncCenter.shared.startMembersRealtime(familyId: familyId, modelContext: modelContext)
        
        // 9) Bootstrap remaining memberships — fire-and-forget.
        //    Non usiamo await per non bloccare il ritorno al chiamante.
        //    bootstrapIfNeeded NON tocca activeFamilyId (già pinnato sopra).
        KBLog.sync.kbDebug("Bootstrap after join requested (fire-and-forget, will NOT change active family)")
        Task { @MainActor in
            await FamilyBootstrapService(modelContext: self.modelContext).bootstrapIfNeeded()
        }
        
        KBLog.sync.kbInfo("joinFamily completed familyId=\(familyId)")
    }
    
    // MARK: - Private helpers (Upserts)
    
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
                    id: r.id,
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
        KBLog.sync.kbDebug("upsertRoutines done familyId=\(familyId)")
    }
    
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
                    id: t.id,
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
        KBLog.sync.kbDebug("upsertTodos done familyId=\(familyId)")
    }
    
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
                    id: e.id,
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
        KBLog.sync.kbDebug("upsertEvents done familyId=\(familyId)")
    }
}
