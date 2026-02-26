//
//  TodoReminderService.swift
//  KidBox
//
//  Created by vscocca on 26/02/26.
//

import Foundation
import UserNotifications
import OSLog

enum TodoReminderService {
    
    static func ensurePermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                KBLog.app.kbError("[Reminder] requestAuthorization FAIL err=\(error.localizedDescription)")
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
    
    static func schedule(todoId: String, title: String, dueAt: Date) async throws -> String {
        let allowed = await ensurePermission()
        guard allowed else {
            throw NSError(domain: "KidBox", code: 401, userInfo: [NSLocalizedDescriptionKey: "Notifiche non autorizzate"])
        }
        
        let id = "todo.reminder.\(todoId)"   // stabile: 1 notifica per todo
        let content = UNMutableNotificationContent()
        content.title = "Promemoria"
        content.body = title
        content.sound = .default
        content.userInfo = ["todoId": todoId]
        
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: dueAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(req)
        
        KBLog.todo.kbInfo("[Reminder] scheduled id=\(id) dueAt=\(dueAt)")
        return id
    }
    
    static func cancel(reminderId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderId])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [reminderId])
        KBLog.todo.kbInfo("[Reminder] cancelled id=\(reminderId)")
    }
}
