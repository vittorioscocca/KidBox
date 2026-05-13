import Foundation
import SwiftData
import FirebaseAuth

@MainActor
enum PasswordGroupsService {
    static let unassignedSlug = "unassigned"
    private static let seededKeyPrefix = "kb.passwords.defaultGroupsSeeded."

    struct SeedDefinition {
        let slug: String
        let localizationKey: String
        let icon: String
        let color: String
        let sortIndex: Int
    }

    static let seedDefinitions: [SeedDefinition] = [
        .init(slug: "unassigned", localizationKey: "passwords.group.unassigned", icon: "tray", color: "#8E8E93", sortIndex: 0),
        .init(slug: "work", localizationKey: "passwords.group.work", icon: "briefcase.fill", color: "#0A84FF", sortIndex: 1),
        .init(slug: "personal", localizationKey: "passwords.group.personal", icon: "person.fill", color: "#34C759", sortIndex: 2),
        .init(slug: "social", localizationKey: "passwords.group.social", icon: "bubble.left.and.bubble.right.fill", color: "#FF9500", sortIndex: 3),
        .init(slug: "finance", localizationKey: "passwords.group.finance", icon: "creditcard.fill", color: "#5E5CE6", sortIndex: 4),
        .init(slug: "family", localizationKey: "passwords.group.family", icon: "house.fill", color: "#FF2D55", sortIndex: 5),
    ]

    static func groupId(familyId: String, slug: String) -> String {
        "kb.password.group.\(familyId).\(slug)"
    }

    static func isUnassigned(_ group: PasswordGroup, familyId: String) -> Bool {
        group.id == groupId(familyId: familyId, slug: unassignedSlug)
    }

    static func localizedDefaultName(for key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func seedDefaultGroupsIfNeeded(familyId: String, modelContext: ModelContext) {
        let userDefaultsKey = seededKeyPrefix + familyId
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else { return }
        guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else { return }

        var touched = false
        for seed in seedDefinitions {
            let id = groupId(familyId: familyId, slug: seed.slug)
            let descriptor = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.id == id })
            if (try? modelContext.fetch(descriptor).first) != nil {
                continue
            }
            do {
                let name = localizedDefaultName(for: seed.localizationKey)
                let cipher = try PasswordCypher.encrypt(name, familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid)
                let group = PasswordGroup(
                    id: id,
                    familyId: familyId,
                    nameCipher: cipher,
                    icon: seed.icon,
                    color: seed.color,
                    visibility: KBVisibilityScope.family,
                    visibilityMemberIds: [],
                    createdBy: uid,
                    isSystem: true,
                    sortIndex: seed.sortIndex,
                    createdAt: .now,
                    updatedAt: .now,
                    deletedAt: nil,
                    syncStateRaw: KBSyncState.pendingUpsert.rawValue,
                    lastSyncError: nil
                )
                modelContext.insert(group)
                PasswordsRepository.enqueuePasswordGroupUpsert(groupId: group.id, familyId: familyId, modelContext: modelContext)
                touched = true
            } catch {
                KBLog.sync.kbError("[passwords][seed] failed \(seed.slug): \(error.localizedDescription)")
            }
        }

        if touched {
            try? modelContext.save()
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        }
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    static func resolveUnassignedGroup(familyId: String, modelContext: ModelContext) -> PasswordGroup? {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let unassignedId = groupId(familyId: familyId, slug: unassignedSlug)
        let descriptor = FetchDescriptor<PasswordGroup>(predicate: #Predicate { $0.id == unassignedId })
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        guard !uid.isEmpty else { return nil }
        do {
            let plain = localizedDefaultName(for: "passwords.group.unassigned")
            let cipher = try PasswordCypher.encrypt(plain, familyId: familyId, visibility: KBVisibilityScope.family, createdBy: uid)
            let group = PasswordGroup(
                id: unassignedId,
                familyId: familyId,
                nameCipher: cipher,
                icon: "tray",
                color: "#8E8E93",
                visibility: KBVisibilityScope.family,
                visibilityMemberIds: [],
                createdBy: uid,
                isSystem: true,
                sortIndex: 0
            )
            group.syncState = .pendingUpsert
            modelContext.insert(group)
            PasswordsRepository.enqueuePasswordGroupUpsert(groupId: group.id, familyId: familyId, modelContext: modelContext)
            try? modelContext.save()
            return group
        } catch {
            KBLog.sync.kbError("[passwords][groups] cannot create unassigned: \(error.localizedDescription)")
            return nil
        }
    }
}

