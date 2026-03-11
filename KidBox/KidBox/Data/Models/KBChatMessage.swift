import Foundation
import SwiftData

enum KBTranscriptStatus: String, Codable {
    case none
    case processing
    case completed
    case failed
}

enum KBTranscriptSource: String, Codable {
    case appleSpeechAnalyzer
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
    
    var latitude: Double?
    var longitude: Double?
    
    var mediaStoragePath: String?
    var mediaURL: String?
    var mediaDurationSeconds: Int?
    var mediaThumbnailURL: String?
    var replyToId: String? = nil
    
    var mediaLocalPath: String?
    
    var reactionsJSON: String?
    
    /// JSON serializzato degli UID che hanno letto il messaggio.
    /// Es. ["uid1", "uid2"]
    var readByJSON: String?
    
    // MARK: - Transcript
    
    /// Trascrizione automatica del messaggio audio
    var transcriptText: String?
    
    /// Stato della trascrizione
    var transcriptStatusRaw: String
    
    /// Origine della trascrizione
    var transcriptSourceRaw: String?
    
    /// Locale usata, es. it-IT
    var transcriptLocaleIdentifier: String?
    
    /// true quando il risultato è definitivo
    var transcriptIsFinal: Bool
    
    /// ultimo aggiornamento transcript
    var transcriptUpdatedAt: Date?
    
    /// eventuale errore
    var transcriptErrorMessage: String?
    
    var createdAt: Date
    var editedAt: Date?
    var isDeleted: Bool
    
    /// true quando il messaggio è stato eliminato per tutti i partecipanti.
    /// A differenza di `isDeleted` (elimina solo per me), questo campo
    /// mantiene il messaggio visibile come tombstone ("Messaggio eliminato").
    var isDeletedForEveryone: Bool = false
    
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
    
    var transcriptStatus: KBTranscriptStatus {
        get { KBTranscriptStatus(rawValue: transcriptStatusRaw) ?? .none }
        set { transcriptStatusRaw = newValue.rawValue }
    }
    
    var transcriptSource: KBTranscriptSource? {
        get {
            guard let transcriptSourceRaw else { return nil }
            return KBTranscriptSource(rawValue: transcriptSourceRaw)
        }
        set {
            transcriptSourceRaw = newValue?.rawValue
        }
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
    
    var isEdited: Bool { editedAt != nil }
    
    var hasTranscriptText: Bool {
        guard let transcriptText else { return false }
        return !transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var shouldShowTranscript: Bool {
        guard type == .audio else { return false }
        switch transcriptStatus {
        case .none:
            return hasTranscriptText
        case .processing, .completed, .failed:
            return true
        }
    }
    
    var transcriptPreviewText: String? {
        guard let transcriptText else { return nil }
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    
    // MARK: - Init
    
    init(
        id: String = UUID().uuidString,
        familyId: String,
        senderId: String,
        senderName: String,
        type: KBChatMessageType,
        text: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        mediaStoragePath: String? = nil,
        mediaURL: String? = nil,
        mediaDurationSeconds: Int? = nil,
        mediaThumbnailURL: String? = nil,
        transcriptText: String? = nil,
        mediaLocalPath: String? = nil,
        transcriptStatus: KBTranscriptStatus = .none,
        transcriptSource: KBTranscriptSource? = nil,
        transcriptLocaleIdentifier: String? = nil,
        transcriptIsFinal: Bool = false,
        transcriptUpdatedAt: Date? = nil,
        transcriptErrorMessage: String? = nil,
        createdAt: Date = Date(),
        editedAt: Date? = nil,
        isDeleted: Bool = false,
        isDeletedForEveryone: Bool = false
    ) {
        self.id = id
        self.familyId = familyId
        self.senderId = senderId
        self.senderName = senderName
        self.typeRaw = type.rawValue
        self.text = text
        
        self.latitude = latitude
        self.longitude = longitude
        self.mediaLocalPath = mediaLocalPath
        
        self.mediaStoragePath = mediaStoragePath
        self.mediaURL = mediaURL
        self.mediaDurationSeconds = mediaDurationSeconds
        self.mediaThumbnailURL = mediaThumbnailURL
        self.replyToId = nil
        
        self.reactionsJSON = nil
        self.readByJSON = nil
        
        self.transcriptText = transcriptText
        self.transcriptStatusRaw = transcriptStatus.rawValue
        self.transcriptSourceRaw = transcriptSource?.rawValue
        self.transcriptLocaleIdentifier = transcriptLocaleIdentifier
        self.transcriptIsFinal = transcriptIsFinal
        self.transcriptUpdatedAt = transcriptUpdatedAt
        self.transcriptErrorMessage = transcriptErrorMessage
        
        self.createdAt = createdAt
        self.editedAt = editedAt
        self.isDeleted = isDeleted
        self.isDeletedForEveryone = isDeletedForEveryone
        
        self.syncStateRaw = KBSyncState.pendingUpsert.rawValue
        self.lastSyncError = nil
    }
}

extension KBChatMessage: HasFamilyId {}
