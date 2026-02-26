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
    @Published var location: Int = 0
    @Published var shopping: Int = 0
    @Published var todos: Int = 0
    
    private var listener: ListenerRegistration?
    
    private init() {}
    
    func startListening(familyId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard !familyId.isEmpty else { return }
        
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
                let locCount  = data["location"] as? Int ?? 0
                let todoCount = data["todos"] as? Int ?? 0
                
                Task { @MainActor in
                    self.chat = chatCount
                    self.documents = docCount
                    self.location = locCount
                    self.todos = todoCount
                    
                    let total = chatCount + docCount + locCount + todoCount
                    UNUserNotificationCenter.current().setBadgeCount(total) { error in
                        if let error {
                            print("Failed to set badge count:", error)
                        }
                    }
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    func refreshAppBadge() {
        let total = chat + documents + location + todos
        UNUserNotificationCenter.current().setBadgeCount(total) { error in
            if let error {
                print("Failed to set badge count:", error)
            }
        }
    }
    
    @MainActor func clearChat() { self.chat = 0 }
    @MainActor func clearDocuments() { self.documents = 0 }
    @MainActor func clearLocation() { self.location = 0 }
    @MainActor func clearTodos() { self.todos = 0 }
}
