//
//  FamilyJoinService.swift
//  KidBox
//
//  Created by vscocca on 05/02/26.
//

import Foundation
import SwiftData
import FirebaseAuth
import OSLog
import FirebaseFirestore

@MainActor
final class FamilyJoinService {
    private let inviteRemote: InviteRemoteStore
    private let readRemote: FamilyReadRemoteStore
    private let modelContext: ModelContext
    
    init(inviteRemote: InviteRemoteStore, readRemote: FamilyReadRemoteStore, modelContext: ModelContext) {
        self.inviteRemote = inviteRemote
        self.readRemote = readRemote
        self.modelContext = modelContext
    }
    
    func joinFamily(code rawCode: String) async throws {
        let code = rawCode
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "-" }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        // 1) Resolve invite -> familyId
        let familyId = try await inviteRemote.resolveInvite(code: code)
        
        Task { @MainActor in
            do {
                let snap = try await Firestore.firestore()
                    .collection("families")
                    .document(familyId)
                    .getDocument()
                
                guard let data = snap.data() else { return }
                
                let remoteName = data["name"] as? String ?? ""
                let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                let remoteUpdatedBy = data["updatedBy"] as? String
                
                let remoteHeroURL = data["heroPhotoURL"] as? String
                let remoteHeroUpdatedAt = (data["heroPhotoUpdatedAt"] as? Timestamp)?.dateValue()
                
                // UPSERT locale (crea family se manca)
                let fid = familyId
                let desc = FetchDescriptor<KBFamily>(predicate: #Predicate { $0.id == fid })
                let fam = try modelContext.fetch(desc).first ?? {
                    let now = Date()
                    let created = KBFamily(
                        id: fid,
                        name: remoteName,
                        createdBy: remoteUpdatedBy ?? "remote",
                        updatedBy: remoteUpdatedBy ?? "remote", createdAt: now,
                        updatedAt: remoteUpdatedAt
                    )
                    modelContext.insert(created)
                    return created
                }()
                
                // aggiorna i campi (LWW)
                if remoteUpdatedAt >= fam.updatedAt {
                    fam.name = remoteName
                    fam.updatedAt = remoteUpdatedAt
                    fam.updatedBy = remoteUpdatedBy ?? fam.updatedBy
                }
                
                let remoteHeroStamp = remoteHeroUpdatedAt ?? remoteUpdatedAt
                let localHeroStamp = fam.heroPhotoUpdatedAt ?? .distantPast
                if remoteHeroStamp >= localHeroStamp {
                    fam.heroPhotoURL = remoteHeroURL
                    fam.heroPhotoUpdatedAt = remoteHeroStamp
                }
                
                try modelContext.save()
            } catch {
                KBLog.sync.error("family one-shot refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        
        // 2) Become member on server
        try await inviteRemote.addMember(familyId: familyId, role: "member")
        
        // 3) Read minimal family state
        let remoteFamily = try await readRemote.fetchFamily(familyId: familyId)
        let remoteChildren = try await readRemote.fetchChildren(familyId: familyId)
        let remoteRoutines = try await readRemote.fetchRoutines(familyId: familyId)
        let remoteTodos    = try await readRemote.fetchTodos(familyId: familyId)
        let remoteEvents   = try await readRemote.fetchEvents(familyId: familyId)
        
        // 4) Upsert local KBFamily
        let familyDescriptor = FetchDescriptor<KBFamily>(
            predicate: #Predicate { $0.id == familyId }
        )
        let existingFamily = try modelContext.fetch(familyDescriptor).first
        
        let family: KBFamily
        if let existingFamily {
            family = existingFamily
            family.name = remoteFamily.name
            family.updatedBy = uid
            family.updatedAt = Date()
        } else {
            let now = Date()
            family = KBFamily(
                id: remoteFamily.id,
                name: remoteFamily.name,
                createdBy: remoteFamily.ownerUid, // meglio ownerUid come origine
                updatedBy: uid,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(family)
        }
        
        // 5) Upsert children by id (no removeAll)
        var localById: [String: KBChild] = [:]
        for c in family.children {
            localById[c.id] = c
        }
        
        var seenIds = Set<String>()
        for rc in remoteChildren {
            seenIds.insert(rc.id)
            if let lc = localById[rc.id] {
                lc.name = rc.name
                lc.birthDate = rc.birthDate
                if lc.family == nil { lc.family = family }
            } else {
                let now = Date()
                let child = KBChild(
                    id: rc.id,
                    familyId: family.id,
                    name: rc.name,
                    birthDate: rc.birthDate,
                    createdBy: remoteFamily.ownerUid,
                    createdAt: Date(),
                    updatedBy: uid,
                    updatedAt: now
                )
                child.family = family
                family.children.append(child)
                modelContext.insert(child)
            }
        }
        
        // 6) (MVP) opzionale: elimina children locali non più presenti sul server
        // Se per ora NON vuoi cancellare, commenta questo blocco.
        let toDelete = family.children.filter { !seenIds.contains($0.id) }
        for lc in toDelete {
            family.children.removeAll { $0.id == lc.id }
            modelContext.delete(lc)
        }
        try upsertRoutines(remoteRoutines, familyId: familyId, fallbackUpdatedBy: uid)
        try upsertTodos(remoteTodos, familyId: familyId, fallbackUpdatedBy: uid)
        try upsertEvents(remoteEvents, familyId: familyId, fallbackUpdatedBy: uid)
        
        try modelContext.save()
        KBLog.sync.info("Join family OK familyId=\(familyId, privacy: .public)")
        try modelContext.save()
        KBLog.sync.info("Join family OK familyId=\(familyId, privacy: .public)")
        
        // 7) start realtime bundle for the joined family (NOW we are member)
        SyncCenter.shared.stopFamilyBundleRealtime() // se hai un metodo stop, evita doppi listener
        SyncCenter.shared.startFamilyBundleRealtime(familyId: familyId, modelContext: modelContext)
        
        // 8) flush to pull inbound immediately
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        SyncCenter.shared.startMembersRealtime(familyId: familyId, modelContext: modelContext)
        
        // 9) (optional) update memberships/local active family cache
        await FamilyBootstrapService(modelContext: modelContext).bootstrapIfNeeded()
    }
    
    private func upsertRoutines(_ items: [RemoteRoutineRead], familyId: String, fallbackUpdatedBy: String) throws {
        for r in items {
            let rid = r.id   // ✅ cattura prima
            
            let desc = FetchDescriptor<KBRoutine>(
                predicate: #Predicate { $0.id == rid }   // ✅ usa rid, non r.id
            )
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
    }
    
    private func upsertTodos(_ items: [RemoteTodoRead], familyId: String, fallbackUpdatedBy: String) throws {
        for t in items {
            let tid = t.id   // ✅ cattura prima
            
            let desc = FetchDescriptor<KBTodoItem>(
                predicate: #Predicate { $0.id == tid }   // ✅ usa tid
            )
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
    }
    
    private func upsertEvents(_ items: [RemoteEventRead], familyId: String, fallbackUpdatedBy: String) throws {
        for e in items {
            let eid = e.id   // ✅ cattura prima
            
            let desc = FetchDescriptor<KBEvent>(
                predicate: #Predicate { $0.id == eid }   // ✅ usa eid, non e.id
            )
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
    }
}
