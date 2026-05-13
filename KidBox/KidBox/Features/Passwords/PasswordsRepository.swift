//
//  PasswordsRepository.swift
//  KidBox
//
//  Applica snapshot Firestore → SwiftData (LWW su `updatedAt`) e accoda operazioni di sync.
//

import Foundation
import SwiftData
import FirebaseAuth

@MainActor
enum PasswordsRepository {

    /// Applica un batch di cambiamenti **passwords** o **passwordGroups** dalla replica remota.
    static func applyInbound(
        changes: [PasswordRemoteChange],
        familyId: String,
        modelContext: ModelContext
    ) {
        let uid = Auth.auth().currentUser?.uid ?? ""
        do {
            for change in changes {
                switch change {
                case .upsertEntry(let dto):
                    try applyEntryDTO(dto, familyId: familyId, currentUid: uid, modelContext: modelContext)
                case .removeEntry(let id):
                    try removeEntryLocal(id: id, modelContext: modelContext)
                case .upsertGroup(let dto):
                    try applyGroupDTO(dto, familyId: familyId, currentUid: uid, modelContext: modelContext)
                case .removeGroup(let id):
                    try removeGroupLocal(id: id, modelContext: modelContext)
                }
            }
            try modelContext.save()
            AutoFillSnapshotWriter.scheduleRebuild(modelContext: modelContext)
        } catch {
            KBLog.sync.kbError("[passwords][inbound] apply failed: \(error.localizedDescription)")
        }
    }

    private static func dataFromB64(_ s: String?) -> Data? {
        guard let s, !s.isEmpty, let d = Data(base64Encoded: s) else { return nil }
        return d
    }

    private static func applyEntryDTO(
        _ dto: PasswordEntryDTO,
        familyId: String,
        currentUid: String,
        modelContext: ModelContext
    ) throws {
        let vis = PasswordEntry.normalizedPasswordVisibility(dto.visibility)
        guard KBVisibilityScope.isVisible(scope: vis, memberIds: dto.visibilityMemberIds, createdBy: dto.createdBy, currentUid: currentUid) else {
            return
        }

        if dto.deletedAt != nil {
            let pid = dto.id
            let desc = FetchDescriptor<PasswordEntry>(predicate: #Predicate { $0.id == pid })
            if let existing = try modelContext.fetch(desc).first {
                let remoteTs = dto.updatedAt ?? .distantPast
                if remoteTs >= existing.updatedAt {
                    Task { await NotificationManager.shared.cancelPasswordExpiryNotifications(forEntryId: pid) }
                    modelContext.delete(existing)
                }
            } else {
                Task { await NotificationManager.shared.cancelPasswordExpiryNotifications(forEntryId: pid) }
            }
            return
        }

        guard
            let titleD = dataFromB64(dto.titleCipherB64),
            let passD = dataFromB64(dto.passwordCipherB64)
        else {
            KBLog.sync.kbError("[passwords][inbound] missing cipher id=\(dto.id)")
            return
        }

        let remoteTs = dto.updatedAt ?? dto.createdAt ?? .distantPast
        let pid = dto.id
        let desc = FetchDescriptor<PasswordEntry>(predicate: #Predicate { $0.id == pid })

        if let existing = try modelContext.fetch(desc).first {
            if existing.syncState == .pendingDelete { return }
            if existing.syncState == .pendingUpsert && existing.updatedAt > remoteTs {
                KBLog.sync.kbDebug("[passwords][inbound] IGNORE remote<local pendingUpsert id=\(dto.id)")
                return
            }
            guard remoteTs >= existing.updatedAt else { return }

            existing.familyId = dto.familyId
            existing.createdBy = dto.createdBy
            existing.visibility = vis
            existing.visibilityMemberIds = dto.visibilityMemberIds
            existing.groupId = dto.groupId
            existing.titleCipher = titleD
            existing.usernameCipher = dataFromB64(dto.usernameCipherB64)
            existing.passwordCipher = passD
            existing.websiteCipher = dataFromB64(dto.websiteCipherB64)
            existing.notesCipher = dataFromB64(dto.notesCipherB64)
            existing.otpConfigCipher = dataFromB64(dto.otpConfigCipherB64)
            existing.iconURL = dto.iconURL
            existing.lastUsedAt = dto.lastUsedAt
            if let pu = dto.passwordUpdatedAt { existing.passwordUpdatedAt = pu }
            existing.expiresAt = dto.expiresAt
            existing.pwnedCount = dto.pwnedCount
            existing.pwnedCheckedAt = dto.pwnedCheckedAt
            existing.isFavorite = dto.isFavorite
            if let ca = dto.createdAt { existing.createdAt = ca }
            existing.updatedAt = remoteTs
            existing.deletedAt = nil
            existing.syncState = .synced
            existing.lastSyncError = nil
            Task { await NotificationManager.shared.syncPasswordExpiryNotifications(for: existing) }
        } else {
            let created = dto.createdAt ?? remoteTs
            let entry = PasswordEntry(
                id: dto.id,
                familyId: familyId,
                createdBy: dto.createdBy,
                visibility: vis,
                visibilityMemberIds: dto.visibilityMemberIds,
                groupId: dto.groupId,
                titleCipher: titleD,
                usernameCipher: dataFromB64(dto.usernameCipherB64),
                passwordCipher: passD,
                websiteCipher: dataFromB64(dto.websiteCipherB64),
                notesCipher: dataFromB64(dto.notesCipherB64),
                otpConfigCipher: dataFromB64(dto.otpConfigCipherB64),
                iconURL: dto.iconURL,
                lastUsedAt: dto.lastUsedAt,
                passwordUpdatedAt: dto.passwordUpdatedAt ?? remoteTs,
                expiresAt: dto.expiresAt,
                pwnedCount: dto.pwnedCount,
                pwnedCheckedAt: dto.pwnedCheckedAt,
                createdAt: created,
                updatedAt: remoteTs,
                deletedAt: nil,
                isFavorite: dto.isFavorite,
                syncStateRaw: KBSyncState.synced.rawValue,
                lastSyncError: nil
            )
            modelContext.insert(entry)
            Task { await NotificationManager.shared.syncPasswordExpiryNotifications(for: entry) }
        }
    }

    private static func applyGroupDTO(
        _ dto: PasswordGroupDTO,
        familyId: String,
        currentUid: String,
        modelContext: ModelContext
    ) throws {
        let vis = PasswordEntry.normalizedPasswordVisibility(dto.visibility)
        guard KBVisibilityScope.isVisible(scope: vis, memberIds: dto.visibilityMemberIds, createdBy: dto.createdBy, currentUid: currentUid) else {
            return
        }

        if dto.deletedAt != nil {
            let gid = dto.id
            let desc = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.id == gid })
            if let existing = try modelContext.fetch(desc).first {
                let remoteTs = dto.updatedAt ?? .distantPast
                if remoteTs >= existing.updatedAt {
                    let unassignedId = PasswordGroupsService.resolveUnassignedGroup(familyId: familyId, modelContext: modelContext)?.id
                    let entriesDesc = FetchDescriptor<PasswordEntry>(predicate: #Predicate { $0.familyId == familyId && $0.deletedAt == nil })
                    let affected = (try? modelContext.fetch(entriesDesc)) ?? []
                    for entry in affected where entry.groupId == existing.id {
                        entry.groupId = unassignedId
                        entry.updatedAt = .now
                        entry.syncState = .pendingUpsert
                        enqueuePasswordEntryUpsert(entryId: entry.id, familyId: familyId, modelContext: modelContext)
                    }
                    existing.deletedAt = dto.deletedAt
                    existing.updatedAt = remoteTs
                    existing.syncState = .synced
                }
            }
            return
        }

        guard let nameD = dataFromB64(dto.nameCipherB64) else {
            KBLog.sync.kbError("[passwords][inbound] group missing name cipher id=\(dto.id)")
            return
        }

        let remoteTs = dto.updatedAt ?? dto.createdAt ?? .distantPast
        let gid = dto.id
        let desc = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.id == gid })

        if let existing = try modelContext.fetch(desc).first {
            if existing.syncState == .pendingDelete { return }
            if existing.syncState == .pendingUpsert && existing.updatedAt > remoteTs {
                KBLog.sync.kbDebug("[passwordGroups][inbound] IGNORE remote<local pendingUpsert id=\(dto.id)")
                return
            }
            guard remoteTs >= existing.updatedAt else { return }
            existing.familyId = dto.familyId
            existing.createdBy = dto.createdBy
            existing.visibility = vis
            existing.visibilityMemberIds = dto.visibilityMemberIds
            existing.nameCipher = nameD
            existing.icon = dto.icon ?? existing.icon
            existing.color = dto.color ?? existing.color
            existing.isSystem = dto.isSystem
            existing.sortIndex = dto.sortIndex
            if let ca = dto.createdAt { existing.createdAt = ca }
            existing.updatedAt = remoteTs
            existing.deletedAt = nil
            existing.syncState = .synced
            existing.lastSyncError = nil
        } else {
            let created = dto.createdAt ?? remoteTs
            let group = PasswordGroup(
                id: dto.id,
                familyId: familyId,
                nameCipher: nameD,
                icon: dto.icon ?? "folder.fill",
                color: dto.color ?? "#7C6FDE",
                visibility: vis,
                visibilityMemberIds: dto.visibilityMemberIds,
                createdBy: dto.createdBy,
                isSystem: dto.isSystem,
                sortIndex: dto.sortIndex,
                createdAt: created,
                updatedAt: remoteTs,
                deletedAt: nil,
                syncStateRaw: KBSyncState.synced.rawValue,
                lastSyncError: nil
            )
            modelContext.insert(group)
        }
    }

    private static func removeEntryLocal(id: String, modelContext: ModelContext) throws {
        Task { await NotificationManager.shared.cancelPasswordExpiryNotifications(forEntryId: id) }
        let desc = FetchDescriptor<PasswordEntry>(predicate: #Predicate { $0.id == id })
        if let e = try modelContext.fetch(desc).first {
            modelContext.delete(e)
        }
    }

    private static func removeGroupLocal(id: String, modelContext: ModelContext) throws {
        let desc = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.id == id })
        if let g = try modelContext.fetch(desc).first {
            g.deletedAt = .now
            g.updatedAt = .now
            g.syncState = .synced
        }
    }

    // MARK: - Outbox (chiamate da UI / use case quando saranno esposte)

    static func enqueuePasswordEntryUpsert(entryId: String, familyId: String, modelContext: ModelContext) {
        SyncCenter.shared.upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.passwordEntry.rawValue,
            entityId: entryId,
            opType: "upsert",
            modelContext: modelContext
        )
        AutoFillSnapshotWriter.scheduleRebuild(modelContext: modelContext)
    }

    static func enqueuePasswordEntryDelete(entryId: String, familyId: String, modelContext: ModelContext) {
        SyncCenter.shared.upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.passwordEntry.rawValue,
            entityId: entryId,
            opType: "delete",
            modelContext: modelContext
        )
        AutoFillSnapshotWriter.scheduleRebuild(modelContext: modelContext)
    }

    static func enqueuePasswordGroupUpsert(groupId: String, familyId: String, modelContext: ModelContext) {
        SyncCenter.shared.upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.passwordGroup.rawValue,
            entityId: groupId,
            opType: "upsert",
            modelContext: modelContext
        )
    }

    static func enqueuePasswordGroupDelete(groupId: String, familyId: String, modelContext: ModelContext) {
        SyncCenter.shared.upsertOp(
            familyId: familyId,
            entityType: SyncEntityType.passwordGroup.rawValue,
            entityId: groupId,
            opType: "delete",
            modelContext: modelContext
        )
    }
}
