//
//  MultiFamilyService.swift
//  KidBox
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class MultiFamilyService {
    private let modelContext: ModelContext
    private let coordinator: AppCoordinator

    init(modelContext: ModelContext, coordinator: AppCoordinator) {
        self.modelContext = modelContext
        self.coordinator = coordinator
    }

    /// Crea una nuova famiglia senza figli (caso adulto / famiglia d'origine).
    /// Non cambia la famiglia attiva.
    func createEmptyFamily(name: String) async throws -> String {
        let familyId = UUID().uuidString
        let now = Date()
        let uid = coordinator.uid ?? Auth.auth().currentUser?.uid ?? ""
        guard !uid.isEmpty else {
            throw NSError(
                domain: "KidBox",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Utente non autenticato"]
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw NSError(
                domain: "KidBox",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Nome famiglia obbligatorio"]
            )
        }

        let family = KBFamily(
            id: familyId,
            name: trimmedName,
            createdBy: uid,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(family)

        // id = uid: allineato a Firestore members/{uid} e al listener SyncCenter.
        let member = KBFamilyMember(
            id: uid,
            familyId: familyId,
            userId: uid,
            role: "owner",
            displayName: Auth.auth().currentUser?.displayName,
            email: Auth.auth().currentUser?.email,
            photoURL: Auth.auth().currentUser?.photoURL?.absoluteString,
            updatedBy: uid,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(member)
        // Rimuovi eventuali righe legacy (id = "{familyId}_{uid}") dalla stessa famiglia.
        let legacyId = "\(familyId)_\(uid)"
        let legacyDesc = FetchDescriptor<KBFamilyMember>(
            predicate: #Predicate { $0.id == legacyId && $0.familyId == familyId }
        )
        if let legacy = try? modelContext.fetch(legacyDesc).first {
            modelContext.delete(legacy)
        }
        try modelContext.save()

        let capturedName = trimmedName
        Task.detached {
            let db = Firestore.firestore()
            let familyData: [String: Any] = [
                "id": familyId,
                "name": capturedName,
                "ownerUid": uid,
                "createdBy": uid,
                "updatedBy": uid,
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
            ]
            try? await db.collection("families").document(familyId).setData(familyData)

            let memberData: [String: Any] = [
                "familyId": familyId,
                "userId": uid,
                "uid": uid,
                "role": "owner",
                "createdAt": Timestamp(date: now),
                "updatedAt": Timestamp(date: now),
                "updatedBy": uid,
            ]
            try? await db.collection("families").document(familyId)
                .collection("members").document(uid).setData(memberData)

            try? await db.collection("users").document(uid)
                .collection("memberships").document(familyId)
                .setData([
                    "familyId": familyId,
                    "role": "owner",
                    "createdAt": Timestamp(date: now),
                ])
        }

        return familyId
    }

    func switchToFamily(_ familyId: String) {
        coordinator.setActiveFamily(familyId, force: true)
    }

    func allFamilies() throws -> [KBFamily] {
        let descriptor = FetchDescriptor<KBFamily>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
