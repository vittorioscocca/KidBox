import Foundation
import SwiftData

/// Tipo di messaggio supportato dalla chat familiare.
enum KBChatMessageType: String, Codable {
    case text
    case audio
    case photo
    case video
}

/// Modello locale di un messaggio della chat familiare.
@Model
final class KBChatMessage {
    @Attribute(.unique) var id: String
    
    var familyId: String
    var senderId: String
    var senderName: String
    
    var typeRaw: String
    var text: String?
    
    var mediaStoragePath: String?
    var mediaURL: String?
    var mediaDurationSeconds: Int?
    var mediaThumbnailURL: String?
    
    var reactionsJSON: String?
    
    /// JSON serializzato degli UID che hanno letto il messaggio.
    /// Es. ["uid1", "uid2"]
    var readByJSON: String?
    
    var createdAt: Date
    var isDeleted: Bool
    
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
    
    /// UID degli utenti che hanno letto il messaggio.
    var readBy: [String] {
        get {
            guard let json = readByJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if newValue.isEmpty {
                readByJSON = nil
            } else if let data = try? JSONEncoder().encode(newValue),
                      let json = String(data: data, encoding: .utf8) {
                readByJSON = json
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
        self.readByJSON = nil
        self.createdAt = createdAt
        self.isDeleted = isDeleted
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBChatMessage: HasFamilyId {}
