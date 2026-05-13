//
//  PasswordEntry.swift
//  KidBox
//
//  SwiftData model per le password di famiglia, cifratura lato client (`PasswordCypher`).
//
//  **Architettura v1**
//  - Persistenza: solo **Firestore** (sync) + **SwiftData** sul dispositivo. Nessun backup
//    su file, iCloud Drive o esportazioni dedicate in questa iterazione.
//  - **Visibilità**: `family`, `members`, `onlyCreator` / `"private"`.
//  - UI: `KBTheme`, `VisibilityPickerSheet` con `allowedScopes` ristretti, card Home come gli altri moduli.
//  - Nessun integrazione Watch, Credential Provider o Share Extension nel core iniziale.
//

import Foundation
import SwiftData

/// Voce password salvata in SwiftData; campi sensibili sono blob AES-GCM (`combined` CryptoKit).
@Model
final class PasswordEntry {
    @Attribute(.unique) var id: String
    var familyId: String
    /// UID Firebase del creatore.
    var createdBy: String
    /// `KBVisibilityScope.family` | `KBVisibilityScope.onlyCreator` (stored `"private"`).
    var visibility: String
    /// UID autorizzati quando `visibility == "members"`.
    var visibilityMemberIds: [String] = []
    var groupId: String?

    var titleCipher: Data
    var usernameCipher: Data?
    var passwordCipher: Data
    var websiteCipher: Data?
    var notesCipher: Data?
    var otpConfigCipher: Data?

    var iconURL: String?
    var lastUsedAt: Date?
    var passwordUpdatedAt: Date
    var expiresAt: Date?
    /// Numero di occorrenze HIBP (k-anonymity). `nil` = mai controllata.
    var pwnedCount: Int?
    /// Timestamp ultimo check HIBP riuscito.
    var pwnedCheckedAt: Date?

    var createdAt: Date
    var updatedAt: Date
    /// Soft delete LWW: valorizzato quando la voce è eliminata (tombstone remoto).
    var deletedAt: Date?
    /// Preferita in app (sincronizzata su Firestore, non cifrata).
    var isFavorite: Bool = false

    // MARK: - Sync (outbox / stato push come Wallet)
    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        createdBy: String,
        visibility: String,
        visibilityMemberIds: [String] = [],
        groupId: String? = nil,
        titleCipher: Data,
        usernameCipher: Data? = nil,
        passwordCipher: Data,
        websiteCipher: Data? = nil,
        notesCipher: Data? = nil,
        otpConfigCipher: Data? = nil,
        iconURL: String? = nil,
        lastUsedAt: Date? = nil,
        passwordUpdatedAt: Date = .now,
        expiresAt: Date? = nil,
        pwnedCount: Int? = nil,
        pwnedCheckedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        isFavorite: Bool = false,
        syncStateRaw: Int = KBSyncState.synced.rawValue,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.createdBy = createdBy
        self.visibility = Self.normalizedPasswordVisibility(visibility)
        self.visibilityMemberIds = visibilityMemberIds
        self.groupId = groupId
        self.titleCipher = titleCipher
        self.usernameCipher = usernameCipher
        self.passwordCipher = passwordCipher
        self.websiteCipher = websiteCipher
        self.notesCipher = notesCipher
        self.otpConfigCipher = otpConfigCipher
        self.iconURL = iconURL
        self.lastUsedAt = lastUsedAt
        self.passwordUpdatedAt = passwordUpdatedAt
        self.expiresAt = expiresAt
        self.pwnedCount = pwnedCount
        self.pwnedCheckedAt = pwnedCheckedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.isFavorite = isFavorite
        self.syncStateRaw = syncStateRaw
        self.lastSyncError = lastSyncError
    }

    static func normalizedPasswordVisibility(_ raw: String?) -> String {
        KBVisibilityScope.normalized(raw)
    }

    func isVisible(to currentUid: String?) -> Bool {
        KBVisibilityScope.isVisible(
            scope: Self.normalizedPasswordVisibility(visibility),
            memberIds: visibilityMemberIds,
            createdBy: createdBy.isEmpty ? nil : createdBy,
            currentUid: currentUid
        )
    }
}

/// Gruppo / cartella opzionale per organizzare le voci (nome cifrato con chiave di famiglia).
@Model
final class PasswordGroup {
    @Attribute(.unique) var id: String
    var familyId: String
    var nameCipher: Data
    var icon: String
    var color: String
    var visibility: String
    var visibilityMemberIds: [String] = []
    var createdBy: String
    /// Gruppi seed di sistema (modificabili, soft-delete).
    var isSystem: Bool = false
    /// Ordinamento custom futuro.
    var sortIndex: Int = 0
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    var syncStateRaw: Int
    var lastSyncError: String?

    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        familyId: String,
        nameCipher: Data,
        icon: String = "folder.fill",
        color: String = "#7C6FDE",
        visibility: String,
        visibilityMemberIds: [String] = [],
        createdBy: String,
        isSystem: Bool = false,
        sortIndex: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        syncStateRaw: Int = KBSyncState.synced.rawValue,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.nameCipher = nameCipher
        self.icon = icon
        self.color = color
        self.visibility = PasswordEntry.normalizedPasswordVisibility(visibility)
        self.visibilityMemberIds = visibilityMemberIds
        self.createdBy = createdBy
        self.isSystem = isSystem
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncStateRaw = syncStateRaw
        self.lastSyncError = lastSyncError
    }

    func isVisible(to currentUid: String?) -> Bool {
        KBVisibilityScope.isVisible(
            scope: PasswordEntry.normalizedPasswordVisibility(visibility),
            memberIds: visibilityMemberIds,
            createdBy: createdBy.isEmpty ? nil : createdBy,
            currentUid: currentUid
        )
    }
}
