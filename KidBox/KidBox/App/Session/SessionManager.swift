//
//  SessionManager.swift
//  KidBox
//
//  Created by vscocca on 04/02/26.
//

import Foundation
import FirebaseAuth
import SwiftData
import OSLog
import Combine

@MainActor
final class SessionManager: ObservableObject {
    
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var uid: String?
    
    private var handle: AuthStateDidChangeListenerHandle?
    
    func startListening(modelContext: ModelContext) {
        guard handle == nil else { return }
        
        handle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                if let user {
                    self.isAuthenticated = true
                    self.uid = user.uid
                    KBLog.auth.info("Auth state: logged in uid=\(user.uid, privacy: .public)")
                    self.upsertUserProfile(from: user, modelContext: modelContext)
                } else {
                    self.isAuthenticated = false
                    self.uid = nil
                    KBLog.auth.info("Auth state: logged out")
                }
            }
        }
    }
    
    private func upsertUserProfile(from user: User, modelContext: ModelContext) {
        do {
            let uid = user.uid   // ✅ cattura prima
            
            let descriptor = FetchDescriptor<KBUserProfile>(
                predicate: #Predicate { $0.uid == uid }   // ✅ usa uid catturato
            )
            let existing = try modelContext.fetch(descriptor).first
            
            if let existing {
                existing.email = user.email
                existing.displayName = user.displayName
                existing.updatedAt = Date()
                KBLog.data.debug("UserProfile updated uid=\(uid, privacy: .public)")
            } else {
                let profile = KBUserProfile(uid: uid, email: user.email, displayName: user.displayName)
                modelContext.insert(profile)
                KBLog.data.debug("UserProfile created uid=\(uid, privacy: .public)")
            }
            
            try modelContext.save()
        } catch {
            KBLog.data.error("UserProfile upsert failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
