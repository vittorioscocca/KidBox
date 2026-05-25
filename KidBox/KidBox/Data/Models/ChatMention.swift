//
//  ChatMention.swift
//  KidBox
//
//  Estratto da `KBChatMessage.swift` per essere condivisibile con la
//  `KidBoxShareExtension`, dove `KBChatMessage` (modello SwiftData) non è
//  incluso. Lo store remoto (`ChatRemoteStore`) decodifica le menzioni dal
//  payload Firestore e ne ha quindi bisogno anche dal target della extension.
//

import Foundation

/// Riferimento a un membro citato all'interno del testo di un messaggio.
/// `uid` punta al `KBFamilyMember.userId` del membro citato.
/// `displayName` è lo snapshot del nome al momento dell'invio: serve a
/// localizzare l'occorrenza nel testo per evidenziarla e a fare da fallback se
/// il membro è stato rimosso dalla famiglia.
struct ChatMention: Codable, Equatable, Hashable {
    let uid: String
    let displayName: String
}
