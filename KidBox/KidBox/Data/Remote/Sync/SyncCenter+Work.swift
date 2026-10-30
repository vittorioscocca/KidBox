//
//  SyncCenter+Work.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseAuth
internal import FirebaseFirestoreInternal

// MARK: - Lavoro: realtime + outbox

/// Tre ascolti, tutti vincolati (le rules non filtrano una LIST):
/// la propria scheda, le schede che altri adulti hanno condiviso con me
/// (`array-contains` sul mio uid), e i documenti di ciascun proprietario
/// visibile (`ownerUid ==`).
///
/// Un errore di permessi qui **non** passa da `handleFamilyAccessLost`: quella
/// strada espelle dalla famiglia (vedi `/rules-change`, trappola 1), e un
/// listener di Lavoro che fallisce è un problema della scheda, non della
/// famiglia.
extension SyncCenter {

    func startWorkRealtime(familyId: String, modelContext: ModelContext) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        KBLog.sync.kbInfo("startWorkRealtime familyId=\(familyId)")
        stopWorkRealtime()

        workOwnProfileListener = workRemote.listenOwnProfile(
            familyId: familyId, uid: uid,
            onChange: { [weak self] changes in
                self?.applyWorkProfileInbound(changes: changes, me: uid, modelContext: modelContext)
            },
            onError: { err in
                KBLog.sync.kbError("[work] own profile listener ERROR \(err.localizedDescription)")
            }
        )
        workSharedProfilesListener = workRemote.listenSharedProfiles(
            familyId: familyId, uid: uid,
            onChange: { [weak self] changes in
                self?.applyWorkProfileInbound(changes: changes, me: uid, modelContext: modelContext)
            },
            onError: { err in
                KBLog.sync.kbError("[work] shared profiles listener ERROR \(err.localizedDescription)")
            }
        )
        attachWorkRecordsListener(familyId: familyId, ownerUid: uid, modelContext: modelContext)
    }

    func stopWorkRealtime() {
        workOwnProfileListener?.remove()
        workOwnProfileListener = nil
        workSharedProfilesListener?.remove()
        workSharedProfilesListener = nil
        for (_, l) in workRecordListeners { l.remove() }
        workRecordListeners = [:]
    }

    private func attachWorkRecordsListener(familyId: String, ownerUid: String, modelContext: ModelContext) {
        guard workRecordListeners[ownerUid] == nil else { return }
        workRecordListeners[ownerUid] = workRemote.listenRecords(
            familyId: familyId, ownerUid: ownerUid,
            onChange: { [weak self] changes in
                self?.applyWorkRecordInbound(changes: changes, modelContext: modelContext)
            },
            onError: { err in
                KBLog.sync.kbError("[work] records listener ERROR owner=\(ownerUid) \(err.localizedDescription)")
            }
        )
    }

    // MARK: - Outbox

    func enqueueWorkProfileUpsert(ownerUid: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: SyncEntityType.workProfile.rawValue,
                 entityId: ownerUid, opType: "upsert", modelContext: modelContext)
    }

    func enqueueWorkRecordUpsert(recordId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: SyncEntityType.workRecord.rawValue,
                 entityId: recordId, opType: "upsert", modelContext: modelContext)
    }

    func enqueueWorkRecordDelete(recordId: String, familyId: String, modelContext: ModelContext) {
        upsertOp(familyId: familyId, entityType: SyncEntityType.workRecord.rawValue,
                 entityId: recordId, opType: "delete", modelContext: modelContext)
    }

    func processWorkProfile(op: KBSyncOp, modelContext: ModelContext) async throws {
        let pid = op.entityId
        let desc = FetchDescriptor<KBWorkProfile>(predicate: #Predicate { $0.id == pid })
        guard op.opType == "upsert" else {
            throw NSError(domain: "KidBox.Sync", code: -2440,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for workProfile: \(op.opType)"])
        }
        guard let profile = try? modelContext.fetch(desc).first else { return }
        profile.syncState = .pendingUpsert
        profile.lastSyncError = nil
        try? modelContext.save()

        try await workRemote.upsert(profile: profile)

        profile.syncState = .synced
        profile.lastSyncError = nil
        try modelContext.save()
    }

    func processWorkRecord(op: KBSyncOp, modelContext: ModelContext) async throws {
        let rid = op.entityId
        let desc = FetchDescriptor<KBWorkRecord>(predicate: #Predicate { $0.id == rid })
        let record = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let record else { return }
            record.syncState = .pendingUpsert
            record.lastSyncError = nil
            try? modelContext.save()

            try await workRemote.upsert(record: record)

            record.syncState = .synced
            record.lastSyncError = nil
            try modelContext.save()

        case "delete":
            try await workRemote.softDelete(recordId: rid, familyId: op.familyId)
            if let record {
                modelContext.delete(record)
                try? modelContext.save()
            }

        default:
            throw NSError(domain: "KidBox.Sync", code: -2441,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown opType for workRecord: \(op.opType)"])
        }
    }

    // MARK: - Inbound (LWW)

    func applyWorkProfileInbound(changes: [WorkProfileRemoteChange], me: String, modelContext: ModelContext) {
        do {
            var toAttach: [(String, String)] = []
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let pid = dto.id
                    let desc = FetchDescriptor<KBWorkProfile>(predicate: #Predicate { $0.id == pid })
                    let existing = try modelContext.fetch(desc).first

                    if dto.isDeleted {
                        if let existing { modelContext.delete(existing) }
                        continue
                    }
                    let remoteTs = dto.updatedAt ?? .distantPast
                    let profile: KBWorkProfile
                    if let existing {
                        if existing.syncState == .pendingUpsert { continue }
                        guard remoteTs >= existing.updatedAt else { continue }
                        profile = existing
                    } else {
                        profile = KBWorkProfile(
                            ownerUid: dto.id, familyId: dto.familyId,
                            ownerName: dto.createdByName ?? "",
                            createdAt: dto.createdAt ?? dto.updatedAt ?? .now,
                            updatedAt: dto.updatedAt ?? .now
                        )
                        modelContext.insert(profile)
                    }
                    profile.employerEnc = dto.employerEnc
                    profile.visibilityScope = KBWorkProfile.normalizedScope(dto.visibilityScope)
                    profile.visibilityMemberIds = dto.visibilityMemberIds
                    profile.isDeleted = false
                    if dto.updatedAt != nil { profile.updatedAt = remoteTs }
                    if let cb = dto.createdBy, !cb.isEmpty { profile.createdBy = cb }
                    if let cbn = dto.createdByName, !cbn.isEmpty { profile.createdByName = cbn }
                    if let ub = dto.updatedBy, !ub.isEmpty { profile.updatedBy = ub }
                    if let ubn = dto.updatedByName, !ubn.isEmpty { profile.updatedByName = ubn }
                    profile.syncState = .synced
                    profile.lastSyncError = nil
                    // Una scheda condivisa con me porta con sé i suoi documenti.
                    if dto.id != me { toAttach.append((dto.familyId, dto.id)) }

                case .remove(let id):
                    // Il proprietario ha smesso di condividere (o ha cancellato):
                    // via la scheda e i documenti che avevo in cache.
                    guard id != me else { continue }
                    purgeWorkOwner(id, modelContext: modelContext)
                }
            }
            try modelContext.save()
            for (fid, owner) in toAttach {
                attachWorkRecordsListener(familyId: fid, ownerUid: owner, modelContext: modelContext)
            }
        } catch {
            KBLog.sync.kbError("[work][inbound] profile APPLY FAIL err=\(error.localizedDescription)")
        }
    }

    private func purgeWorkOwner(_ owner: String, modelContext: ModelContext) {
        workRecordListeners[owner]?.remove()
        workRecordListeners[owner] = nil
        if let p = try? modelContext.fetch(FetchDescriptor<KBWorkProfile>(predicate: #Predicate { $0.id == owner })).first {
            modelContext.delete(p)
        }
        for r in (try? modelContext.fetch(FetchDescriptor<KBWorkRecord>(predicate: #Predicate { $0.ownerUid == owner }))) ?? [] {
            modelContext.delete(r)
        }
    }

    func applyWorkRecordInbound(changes: [WorkRecordRemoteChange], modelContext: ModelContext) {
        do {
            for change in changes {
                switch change {
                case .upsert(let dto):
                    let rid = dto.id
                    let desc = FetchDescriptor<KBWorkRecord>(predicate: #Predicate { $0.id == rid })
                    let existing = try modelContext.fetch(desc).first

                    if dto.isDeleted {
                        if let existing { modelContext.delete(existing) }
                        continue
                    }
                    let remoteTs = dto.updatedAt ?? .distantPast
                    let record: KBWorkRecord
                    if let existing {
                        if existing.syncState == .pendingUpsert || existing.syncState == .pendingDelete { continue }
                        guard remoteTs >= existing.updatedAt else { continue }
                        record = existing
                    } else {
                        record = KBWorkRecord(
                            id: dto.id, familyId: dto.familyId, ownerUid: dto.ownerUid,
                            ownerName: dto.createdByName ?? "", kind: dto.kind,
                            referenceDate: dto.referenceDate ?? dto.createdAt ?? .now,
                            createdAt: dto.createdAt ?? dto.updatedAt ?? .now,
                            updatedAt: dto.updatedAt ?? .now
                        )
                        modelContext.insert(record)
                    }
                    record.ownerUid = dto.ownerUid
                    record.kind = dto.kind
                    if let d = dto.referenceDate { record.referenceDate = d }
                    record.fieldsEnc = dto.fieldsEnc
                    record.attachmentDocumentId = dto.attachmentDocumentId
                    record.isDeleted = false
                    if dto.updatedAt != nil { record.updatedAt = remoteTs }
                    if let cb = dto.createdBy, !cb.isEmpty { record.createdBy = cb }
                    if let cbn = dto.createdByName, !cbn.isEmpty { record.createdByName = cbn }
                    if let ub = dto.updatedBy, !ub.isEmpty { record.updatedBy = ub }
                    if let ubn = dto.updatedByName, !ubn.isEmpty { record.updatedByName = ubn }
                    record.syncState = .synced
                    record.lastSyncError = nil

                case .remove(let id):
                    let rid = id
                    if let existing = try modelContext.fetch(FetchDescriptor<KBWorkRecord>(predicate: #Predicate { $0.id == rid })).first {
                        modelContext.delete(existing)
                    }
                }
            }
            try modelContext.save()
        } catch {
            KBLog.sync.kbError("[work][inbound] record APPLY FAIL err=\(error.localizedDescription)")
        }
    }
}
