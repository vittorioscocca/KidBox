//
//  TreatmentNotificationManager.swift
//  KidBox
//
//  Created by vscocca on 03/03/26.
//

import Foundation
import UserNotifications

enum TreatmentNotificationManager {
    
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return settings.authorizationStatus == .authorized
        }
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    
    static func schedule(treatment: KBTreatment, childName: String) {
        cancel(treatmentId: treatment.id)
        guard treatment.reminderEnabled else { return }
        
        let center = UNUserNotificationCenter.current()
        let days   = treatment.isLongTerm ? 30 : treatment.durationDays
        let labels = ["Mattina", "Pranzo", "Sera", "Notte"]
        let cal    = Calendar.current
        
        for dayOffset in 0..<days {
            guard let dayDate = cal.date(byAdding: .day, value: dayOffset, to: treatment.startDate) else { continue }
            for (i, timeStr) in treatment.scheduleTimes.enumerated() {
                let parts = timeStr.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { continue }
                var dc = cal.dateComponents([.year, .month, .day], from: dayDate)
                dc.hour = parts[0]; dc.minute = parts[1]
                guard let fire = cal.date(from: dc), fire > Date() else { continue }
                
                let content = UNMutableNotificationContent()
                content.title = "💊 \(treatment.drugName)"
                content.body  = "\(i < labels.count ? labels[i] : "Dose") · \(treatment.dosageValue) \(treatment.dosageUnit) per \(childName)"
                content.sound = .default
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
                let req = UNNotificationRequest(
                    identifier: "treatment-\(treatment.id)-d\(dayOffset)-s\(i)",
                    content: content,
                    trigger: trigger
                )
                center.add(req)
            }
        }
    }
    
    static func cancel(treatmentId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { reqs in
            let ids = reqs
                .filter { $0.identifier.hasPrefix("treatment-\(treatmentId)-") }
                .map    { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
