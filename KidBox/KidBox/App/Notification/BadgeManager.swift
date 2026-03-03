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
    var activeSections: Set<String> = []
    
    @Published var chat: Int = 0
    @Published var documents: Int = 0
    @Published var location: Int = 0
    @Published var shopping: Int = 0
    @Published var todos: Int = 0
    @Published var notes: Int = 0      // ← NEW
    
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
                
                let chatCount     = data["chat"]      as? Int ?? 0
                let docCount      = data["documents"] as? Int ?? 0
                let locCount      = data["location"]  as? Int ?? 0
                let todoCount     = data["todos"]     as? Int ?? 0
                let shoppingCount = data["shopping"]  as? Int ?? 0   // ← NEW
                let notesCount    = data["notes"]     as? Int ?? 0   // ← NEW
                
                DispatchQueue.main.async {
                    if !self.activeSections.contains("chat")      { self.chat      = chatCount }
                    if !self.activeSections.contains("documents") { self.documents = docCount }
                    if !self.activeSections.contains("location")  { self.location  = locCount }
                    if !self.activeSections.contains("todos")     { self.todos     = todoCount }
                    if !self.activeSections.contains("shopping")  { self.shopping  = shoppingCount }
                    if !self.activeSections.contains("notes")     { self.notes     = notesCount }
                    
                    let total = self.chat + self.documents + self.location + self.todos + self.shopping + self.notes
                    UNUserNotificationCenter.current().setBadgeCount(total) { error in
                        if let error { print("Failed to set badge count:", error) }
                    }
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    func refreshAppBadge() {
        let total = chat + documents + location + todos + shopping + notes
        UNUserNotificationCenter.current().setBadgeCount(total) { error in
            if let error {
                print("Failed to set badge count:", error)
            }
        }
    }
    
    @MainActor func clearChat()      { self.chat      = 0 }
    @MainActor func clearDocuments() { self.documents = 0 }
    @MainActor func clearLocation()  { self.location  = 0 }
    @MainActor func clearTodos()     { self.todos     = 0 }
    @MainActor func clearShopping()  { self.shopping  = 0 }   // ← NEW
    @MainActor func clearNotes()     { self.notes     = 0 }   // ← NEW
}
