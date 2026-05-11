//
//  HousePaymentReminderService.swift
//  KidBox
//

import Foundation
import SwiftData
import UserNotifications

/// Notifica locale 3 giorni prima della prossima scadenza rilevante.
/// La prossima occorrenza viene ricalcolata all’apertura app (come cure) così rate e bollette “rigenerano” ogni mese.
@MainActor
final class HousePaymentReminderService {

    static let shared = HousePaymentReminderService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    func cancelAll(paymentId: String) async {
        let prefix = Self.idPrefix(paymentId: paymentId)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
        KBLog.sync.kbDebug("[HousePaymentReminder] cancelled count=\(ids.count) paymentId=\(paymentId)")
    }

    /// Riprogramma tutti i pagamenti locali (es. dopo sync o foreground).
    func rescheduleAllActive(modelContext: ModelContext) async {
        let desc = FetchDescriptor<KBHousePayment>(
            predicate: #Predicate { $0.isDeleted == false && $0.reminderOn == true }
        )
        guard let rows = try? modelContext.fetch(desc) else { return }
        for p in rows {
            await scheduleNext(for: p)
        }
        KBLog.sync.kbDebug("[HousePaymentReminder] rescheduleAllActive count=\(rows.count)")
    }

    func scheduleNext(for payment: KBHousePayment) async {
        await cancelAll(paymentId: payment.id)

        guard payment.reminderOn, !payment.isDeleted else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            KBLog.sync.kbDebug("[HousePaymentReminder] notifications not authorized — skip id=\(payment.id)")
            return
        }

        guard let fire = Self.nextReminderFireDate(for: payment, after: Date()) else { return }

        let interval = fire.timeIntervalSinceNow
        guard interval > 2 else {
            KBLog.sync.kbDebug("[HousePaymentReminder] skip past fire id=\(payment.id)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Scadenza in arrivo"
        content.body = "\(payment.name) — tra 3 giorni."
        content.sound = .default
        content.threadIdentifier = "kidbox.housePayments"
        content.userInfo = [
            "type": "house_payment_reminder",
            "familyId": payment.familyId,
            "paymentId": payment.id,
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = "\(Self.idPrefix(paymentId: payment.id))next"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            KBLog.sync.kbDebug("[HousePaymentReminder] scheduled id=\(identifier) fire=\(fire)")
        } catch {
            KBLog.sync.kbError("[HousePaymentReminder] schedule FAIL id=\(payment.id) err=\(error.localizedDescription)")
        }
    }

    private static func idPrefix(paymentId: String) -> String { "housePayment.\(paymentId)." }

    /// Prossimo istante (con ora 09:00) in cui mostrare “3 giorni prima” rispetto a una delle scadenze gestite.
    static func nextReminderFireDate(for payment: KBHousePayment, after from: Date) -> Date? {
        let cal = Calendar.current
        var candidates: [Date] = []

        if let day = payment.giornoDiScadenzaMensile {
            for off in 0..<36 {
                guard let deadline = monthlyDeadline(day: day, monthOffset: off, from: from) else { continue }
                if let fire = reminderFire(deadline: deadline, calendar: cal), fire > from {
                    candidates.append(fire)
                    break
                }
            }
        }

        if let ref = payment.dataScadenza {
            for yOff in 0..<4 {
                guard let deadline = annualDeadline(reference: ref, yearOffset: yOff, from: from) else { continue }
                if let fire = reminderFire(deadline: deadline, calendar: cal), fire > from {
                    candidates.append(fire)
                    break
                }
            }
        }

        if let end = payment.dataScadenzaContratto {
            let deadline = cal.startOfDay(for: end)
            if let fire = reminderFire(deadline: deadline, calendar: cal), fire > from {
                candidates.append(fire)
            }
        }

        return candidates.min()
    }

    private static func reminderFire(deadline: Date, calendar cal: Calendar) -> Date? {
        guard let threeDaysBefore = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: deadline)) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: threeDaysBefore)
        comps.hour = 9
        comps.minute = 0
        return cal.date(from: comps)
    }

    private static func monthlyDeadline(day: Int, monthOffset: Int, from today: Date) -> Date? {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: today)
        guard let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: t0)) else { return nil }
        guard let monthStart = cal.date(byAdding: .month, value: monthOffset, to: startMonth) else { return nil }
        guard let domRange = cal.range(of: .day, in: .month, for: monthStart) else { return nil }
        let dom = min(max(1, day), domRange.count)
        var comps = cal.dateComponents([.year, .month], from: monthStart)
        comps.day = dom
        return cal.date(from: comps)
    }

    private static func annualDeadline(reference: Date, yearOffset: Int, from today: Date) -> Date? {
        let cal = Calendar.current
        let t0 = cal.startOfDay(for: today)
        let y = cal.component(.year, from: today) + yearOffset
        let m = cal.component(.month, from: reference)
        let d = cal.component(.day, from: reference)
        var comps = DateComponents(year: y, month: m, day: 1)
        guard let monthStart = cal.date(from: comps),
              let domRange = cal.range(of: .day, in: .month, for: monthStart)
        else { return nil }
        let dom = min(max(1, d), domRange.count)
        comps.day = dom
        guard let candidate = cal.date(from: comps) else { return nil }
        return cal.startOfDay(for: candidate) >= t0 ? candidate : nil
    }
}
