//
//  KBSyncOp.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import Foundation
import SwiftData

/// Outbox operation for offline-first sync.
/// One row = one pending operation to be sent to the server (Firestore/Storage).
@Model
final class KBSyncOp {
    @Attribute(.unique) var id: String
    
    // Scope
    var familyId: String
    
    // Routing
    var entityTypeRaw: String          // SyncEntityType.rawValue
    var entityId: String               // id of the entity in SwiftData/Firestore
    var opType: String                 // "upsert" | "delete" (extendable)
    
    // Optional: store minimal payload if you want the op to be self-contained
    var payloadJSON: String?
    
    // Retry metadata
    var createdAt: Date
    var nextRetryAt: Date
    var attempts: Int
    var lastError: String?
    
    // Convenience computed property (not persisted)
    var entityType: SyncEntityType {
        get { SyncEntityType(rawValue: entityTypeRaw) ?? .todo }
        set { entityTypeRaw = newValue.rawValue }
    }
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        entityType: SyncEntityType,
        entityId: String,
        opType: String,
        payloadJSON: String? = nil,
        createdAt: Date = Date(),
        nextRetryAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.entityTypeRaw = entityType.rawValue
        self.entityId = entityId
        self.opType = opType
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.nextRetryAt = nextRetryAt
        self.attempts = attempts
        self.lastError = lastError
    }
    
    /// Backward-compat init if you want to keep current call sites.
    /// You can delete this once you update the call sites to pass `SyncEntityType`.
    convenience init(
        id: String = UUID().uuidString,
        familyId: String,
        entityTypeRaw: String,
        entityId: String,
        opType: String,
        payloadJSON: String? = nil,
        createdAt: Date = Date(),
        nextRetryAt: Date = Date(),
        attempts: Int = 0,
        lastError: String? = nil
    ) {
        self.init(
            id: id,
            familyId: familyId,
            entityType: SyncEntityType(rawValue: entityTypeRaw) ?? .todo,
            entityId: entityId,
            opType: opType,
            payloadJSON: payloadJSON,
            createdAt: createdAt,
            nextRetryAt: nextRetryAt,
            attempts: attempts,
            lastError: lastError
        )
    }
}
