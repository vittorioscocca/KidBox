//
//  KBMemoryFact+Firestore.swift
//  KidBox
//

import Foundation

extension KBMemoryFact {
    /// Scrive o aggiorna questo fatto su Firestore (`families/{familyId}/memoryFacts/{id}`).
    func syncToFirestore() async throws {
        let dto = RemoteMemoryFactDTO(from: self)
        try await MemoryFactRemoteStore().upsert(dto: dto)
    }
}
