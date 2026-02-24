//
//  BadgeManager.swift
//  KidBox
//
//  Created by vscocca on 23/02/26.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit
import Combine
import UserNotifications

@MainActor
final class BadgeManager: ObservableObject {
    
    static let shared = BadgeManager()
    
    @Published var chat: Int = 0
    @Published var documents: Int = 0
    
    private var listener: ListenerRegistration?
    
    private init() {}
    
    // MARK: - Start listening
    
    func startListening(familyId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        
        stopListening()
        
        listener = Firestore.firestore()
            .collection("families")
            .document(familyId)
            .collection("counters")
            .document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                
                if let error {
                    print("Badge listener error:", error)
                    return
                }
                
                let data = snap?.data() ?? [:]
                
                let chatCount = data["chat"] as? Int ?? 0
                let docCount  = data["documents"] as? Int ?? 0
                
                Task { @MainActor in
                    self.chat = chatCount
                    self.documents = docCount
                    
                    let total = chatCount + docCount
                    UNUserNotificationCenter.current().setBadgeCount(total) { error in
                        if let error {
                            print("Failed to set badge count:", error)
                        }
                    }
                }
            }
    }
    
    // MARK: - Stop listening
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    // MARK: - Manual reset app badge (safety)
    
    func refreshAppBadge() {
        let total = chat + documents
        UNUserNotificationCenter.current().setBadgeCount(total) { error in
            if let error {
                print("Failed to set badge count:", error)
            }
        }
    }
    
    @MainActor func clearChat() { self.chat = 0 }
    @MainActor func clearDocuments() { self.documents = 0 }
}
