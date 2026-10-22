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
    @Published var calendar: Int = 0
    @Published var expenses: Int = 0   // ← NEW
    @Published var wallet: Int = 0     // ← NEW (biglietti Wallet non letti / in arrivo)
    
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
            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snap, error in
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
                let shoppingCount = data["shopping"]  as? Int ?? 0
                let notesCount    = data["notes"]     as? Int ?? 0
                let calendarCount = data["calendar"]  as? Int ?? 0
                let expensesCount = data["expenses"]  as? Int ?? 0
                let walletCount   = data["wallet"]    as? Int ?? 0
                
                // Al giro dopo del run loop, non in un Task: il job del MainActor
                // può girare mentre SwiftUI aggiorna le viste («Publishing changes
                // from within view updates», nove avvisi a ogni avvio).
                DispatchQueue.main.async {
                    if !self.activeSections.contains("chat")      { self.update(\.chat, chatCount) }
                    if !self.activeSections.contains("documents") { self.update(\.documents, docCount) }
                    if !self.activeSections.contains("location")  { self.update(\.location, locCount) }
                    if !self.activeSections.contains("todos")     { self.update(\.todos, todoCount) }
                    if !self.activeSections.contains("shopping")  { self.update(\.shopping, shoppingCount) }
                    if !self.activeSections.contains("notes")     { self.update(\.notes, notesCount) }
                    if !self.activeSections.contains("calendar")  { self.update(\.calendar, calendarCount) }
                    if !self.activeSections.contains("expenses")  { self.update(\.expenses, expensesCount) }
                    if !self.activeSections.contains("wallet")    { self.update(\.wallet, walletCount) }
                    self.refreshAppBadge()
                }
            }
    }
    
    func stopListening() {
        listener?.remove()
        listener = nil
    }
    
    func refreshAppBadge() {
        let total = chat + documents + location + todos + shopping + notes + calendar + expenses + wallet
        UNUserNotificationCenter.current().setBadgeCount(total) { error in
            if let error {
                print("Failed to set badge count:", error)
            }
        }
    }
    
    /// Pubblica solo se il valore cambia: ogni assegnazione a un `@Published`
    /// ridisegna chi lo osserva, anche quando il numero è lo stesso.
    private func update(_ keyPath: ReferenceWritableKeyPath<BadgeManager, Int>, _ value: Int) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    /// Gli azzeramenti arrivano spesso da `onAppear`, cioè durante
    /// l'aggiornamento delle viste: si applicano al giro dopo.
    private func clear(_ keyPath: ReferenceWritableKeyPath<BadgeManager, Int>) {
        guard self[keyPath: keyPath] != 0 else { return }
        DispatchQueue.main.async {
            self.update(keyPath, 0)
            self.refreshAppBadge()
        }
    }

    @MainActor func clearChat()      { clear(\.chat) }
    @MainActor func clearDocuments() { clear(\.documents) }
    @MainActor func clearLocation()  { clear(\.location) }
    @MainActor func clearTodos()     { clear(\.todos) }
    @MainActor func clearShopping()  { clear(\.shopping) }
    @MainActor func clearNotes()     { clear(\.notes) }
    @MainActor func clearCalendar()  { clear(\.calendar) }
    @MainActor func clearExpenses()  { clear(\.expenses) }
    @MainActor func clearWallet()    { clear(\.wallet) }
}
