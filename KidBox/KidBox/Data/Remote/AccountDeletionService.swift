//
//  AccountDeletionService.swift
//  KidBox
//
//  Created by vscocca on 19/02/26.
//

import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFunctions
import FirebaseMessagingInterop

@MainActor
final class AccountDeletionService {
    
    private let modelContext: ModelContext
    private let functions = Functions.functions(region: "europe-west1")
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func deleteMyAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            KBLog.auth.kbError("deleteMyAccount: currentUser is nil")
            throw NSError(domain: "KidBox", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }
        
        KBLog.auth.kbInfo("deleteMyAccount started uid=\(user.uid)")
        
        // 🔹 1️⃣ Forza refresh del token PRIMA di chiamare la function
        let tokenResult = try await user.getIDTokenResult(forcingRefresh: true)
        KBLog.auth.kbDebug("deleteMyAccount: token refreshed, exp=\(tokenResult.expirationDate)")
        
        // 🔹 2️⃣ Ora chiama la Cloud Function
        _ = try await functions.httpsCallable("deleteAccount").call()
        
        // 🔹 3️⃣ Local wipe
        KBLog.persistence.kbInfo("deleteMyAccount local wipe started")
        await KidBoxLocalNotificationsCleanup.cancelAllScheduledAccountReminders()
        SyncCenter.shared.beginLocalWipe()
        defer { SyncCenter.shared.endLocalWipe() }
        
        SyncCenter.shared.stopMembersRealtime()
        SyncCenter.shared.stopTodoRealtime()
        SyncCenter.shared.stopChildrenRealtime()
        SyncCenter.shared.stopFamilyBundleRealtime()
        SyncCenter.shared.stopDocumentsRealtime()
        
        try LocalDataWiper.wipeAll(context: modelContext)
        
        // 🔹 4️⃣ Sign out locale
        try Auth.auth().signOut()
        KBSubscriptionManager.shared.resetOnSignOut()
        
        KBLog.auth.kbInfo("deleteMyAccount completed")
    }
}
