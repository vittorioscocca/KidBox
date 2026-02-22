//
//  KBChatMessage.swift
//  KidBox
//
//  Created by vscocca on 21/02/26.
//

import Foundation
import SwiftData

/// Tipo di messaggio supportato dalla chat familiare.
enum KBChatMessageType: String, Codable {
    case text       // messaggio di testo
    case audio      // vocale
    case photo      // foto
    case video      // video
}

/// Modello locale di un messaggio della chat familiare.
///
/// Struttura Firestore:
/// `families/{familyId}/chatMessages/{messageId}`
@Model
final class KBChatMessage {
    @Attribute(.unique) var id: String
    
    // Ownership
    var familyId: String
    var senderId: String        // Firebase UID del mittente
    var senderName: String      // display name al momento dell'invio
    
    // Tipo e contenuto
    var typeRaw: String         // KBChatMessageType.rawValue
    var text: String?           // solo per .text
    
    // Media (foto / video / audio)
    var mediaStoragePath: String?   // path su Firebase Storage
    var mediaURL: String?           // download URL (cache)
    var mediaDurationSeconds: Int?  // solo per .audio e .video
    var mediaThumbnailURL: String?  // solo per .video
    
    // Reazioni: JSON serializzato  es. {"❤️": ["uid1","uid2"], "😂": ["uid3"]}
    var reactionsJSON: String?
    
    // Date
    var createdAt: Date
    var isDeleted: Bool
    
    // Sync
    var syncStateRaw: Int
    var lastSyncError: String?
    
    // MARK: - Computed
    
    var type: KBChatMessageType {
        get { KBChatMessageType(rawValue: typeRaw) ?? .text }
        set { typeRaw = newValue.rawValue }
    }
    
    var syncState: KBSyncState {
        get { KBSyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }
    
    /// Reazioni decodificate: emoji → [userId]
    var reactions: [String: [String]] {
        get {
            guard let json = reactionsJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            if newValue.isEmpty {
                reactionsJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                reactionsJSON = json
            }
        }
    }
    
    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        senderId: String,
        senderName: String,
        type: KBChatMessageType,
        text: String? = nil,
        mediaStoragePath: String? = nil,
        mediaURL: String? = nil,
        mediaDurationSeconds: Int? = nil,
        mediaThumbnailURL: String? = nil,
        createdAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.senderId = senderId
        self.senderName = senderName
        self.typeRaw = type.rawValue
        self.text = text
        self.mediaStoragePath = mediaStoragePath
        self.mediaURL = mediaURL
        self.mediaDurationSeconds = mediaDurationSeconds
        self.mediaThumbnailURL = mediaThumbnailURL
        self.reactionsJSON = nil
        self.createdAt = createdAt
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBChatMessage: HasFamilyId {}
