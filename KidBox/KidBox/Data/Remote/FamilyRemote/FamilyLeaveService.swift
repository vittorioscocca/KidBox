//
//  FamilyLeaveService.swift
//  KidBox
//
//  Created by vscocca on 10/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData

@MainActor
final class FamilyLeaveService {
    private let db = Firestore.firestore()
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func leaveFamily(familyId: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "KidBox", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        // 🔒 1) BLOCCA SYNC
        SyncCenter.shared.beginLocalWipe()
        
        // 2) stop listeners prima (così non “riscrivono” roba mentre wipi)
        SyncCenter.shared.stopFamilyBundleRealtime()
        
        // ⏳ 3) piccolo yield per far morire snapshot pendenti
        try await Task.sleep(nanoseconds: 150_000_000) // 150 ms
        
        // 4) server: remove member doc
        try await db
            .collection("families")
            .document(familyId)
            .collection("members")
            .document(uid)
            .delete()
        
        // 🧹 5) wipe locale family
        try LocalDataWiper.wipeFamily(
            familyId: familyId,
            context: modelContext
        )
        
        // 5) opzionale: membership index (se lo usi)
        try? await db
            .collection("users")
            .document(uid)
            .collection("memberships")
            .document(familyId)
            .delete()
        
        try modelContext.save()
        
        // 🔓 6) riabilita sync
        SyncCenter.shared.endLocalWipe()
        
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }
}
