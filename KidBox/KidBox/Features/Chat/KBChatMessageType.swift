//
//  KBChatMessageType.swift
//  KidBox
//
//  Created by vscocca on 10/03/26.
//
//Target Membership: KidBox + KidBoxShareExtension
//

import Foundation

/// Tipo di messaggio supportato dalla chat familiare.
enum KBChatMessageType: String, Codable {
    case text
    case audio
    case photo
    case video
    case document
    case location
}
