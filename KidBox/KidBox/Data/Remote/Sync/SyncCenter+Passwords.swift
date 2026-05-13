//
//  SyncCenter+Passwords.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseAuth
internal import FirebaseFirestoreInternal

extension SyncCenter {

    func startPasswordsRealtime(familyId: String, modelContext: ModelContext) {
        KBLog.sync.kbInfo("startPasswordsRealtime familyId=\(familyId)")
        stopPasswordsRealtime()

        passwordEntriesListener = passwordRemote.listenPasswordEntries(
            familyId: familyId,
            onChange: { changes in
                Task { @MainActor in
                    PasswordsRepository.applyInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "passwords", error: err)
                    }
                }
            }
        )

        passwordGroupsListener = passwordRemote.listenPasswordGroups(
            familyId: familyId,
            onChange: { changes in
                Task { @MainActor in
                    PasswordsRepository.applyInbound(changes: changes, familyId: familyId, modelContext: modelContext)
                }
            },
            onError: { [weak self] err in
                guard let self else { return }
                if Self.isPermissionDenied(err) {
                    Task { @MainActor in
                        self.handleFamilyAccessLost(familyId: familyId, source: "passwordGroups", error: err)
                    }
                }
            }
        )
    }

    func stopPasswordsRealtime() {
        if passwordEntriesListener != nil || passwordGroupsListener != nil {
            KBLog.sync.kbInfo("stopPasswordsRealtime")
        }
        passwordEntriesListener?.remove()
        passwordEntriesListener = nil
        passwordGroupsListener?.remove()
        passwordGroupsListener = nil
    }

    func processPasswordEntry(op: KBSyncOp, modelContext: ModelContext) async throws {
        let eid = op.entityId
        let desc = FetchDescriptor<PasswordEntry>(predicate: #Predicate { $0.id == eid })
        let entry = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let entry else { return }
            entry.lastSyncError = nil
            try? modelContext.save()
            try await passwordRemote.upsert(entry: entry)
            entry.syncState = .synced
            entry.lastSyncError = nil
            try modelContext.save()

        case "delete":
            if let entry {
                try await passwordRemote.softDeleteEntry(entryId: entry.id, familyId: op.familyId)
                modelContext.delete(entry)
                try? modelContext.save()
            } else {
                try await passwordRemote.softDeleteEntry(entryId: eid, familyId: op.familyId)
            }

        default:
            throw NSError(
                domain: "KidBox.Sync",
                code: -2501,
                userInfo: [NSLocalizedDescriptionKey: "Unknown opType for passwordEntry: \(op.opType)"]
            )
        }
    }

    func processPasswordGroup(op: KBSyncOp, modelContext: ModelContext) async throws {
        let gid = op.entityId
        let desc = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.id == gid })
        let group = try? modelContext.fetch(desc).first

        switch op.opType {
        case "upsert":
            guard let group else { return }
            group.lastSyncError = nil
            try? modelContext.save()
            try await passwordRemote.upsert(group: group)
            group.syncState = .synced
            group.lastSyncError = nil
            try modelContext.save()

        case "delete":
            if let group {
                try await passwordRemote.softDeleteGroup(groupId: group.id, familyId: op.familyId)
                group.deletedAt = .now
                group.updatedAt = .now
                group.syncState = .synced
                try? modelContext.save()
            } else {
                try await passwordRemote.softDeleteGroup(groupId: gid, familyId: op.familyId)
            }

        default:
            throw NSError(
                domain: "KidBox.Sync",
                code: -2502,
                userInfo: [NSLocalizedDescriptionKey: "Unknown opType for passwordGroup: \(op.opType)"]
            )
        }
    }
}
