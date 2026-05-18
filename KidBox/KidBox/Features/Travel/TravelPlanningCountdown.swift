//
//  TravelPlanningCountdown.swift
//  KidBox
//

import Foundation

enum TravelPlanningCountdown {
    /// 1 minuto e 30 secondi ogni 3 giorni di itinerario (indicativo).
    static let secondsPerThreeDays = 90
    /// Messaggi scalati sul limite giornaliero famiglia (allineato a Cloud Functions).
    static let messagesPerThreeDayBlock = 2

    static func planningBlocks(plannedDayCount: Int) -> Int {
        let days = max(plannedDayCount, 1)
        return max(1, (days + 2) / 3)
    }

    /// Es. 1–3 giorni → 2 messaggi; 4–6 → 4; 7–9 → 6.
    static func messageCost(plannedDayCount: Int) -> Int {
        planningBlocks(plannedDayCount: plannedDayCount) * messagesPerThreeDayBlock
    }

    static func totalSeconds(plannedDayCount: Int) -> Int {
        planningBlocks(plannedDayCount: plannedDayCount) * secondsPerThreeDays
    }

    static func estimateLabel(plannedDayCount: Int) -> String {
        let total = totalSeconds(plannedDayCount: plannedDayCount)
        let minutes = total / 60
        let seconds = total % 60
        let messages = messageCost(plannedDayCount: plannedDayCount)
        let timePart: String
        if seconds == 0 {
            timePart = "L'AI può impiegare fino a circa \(minutes) minuti."
        } else {
            timePart = "L'AI può impiegare fino a circa \(minutes) min \(seconds)s."
        }
        return "\(timePart) Conta \(messages) messaggi sul limite AI giornaliero della famiglia. Il contatore è solo indicativo."
    }
}
