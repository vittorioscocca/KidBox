//
//  WalletDocumentReminderService.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Promemoria di scadenza per i documenti d'identità acquisiti nel Wallet
//  (Tessera Sanitaria, Carta d'identità, ecc.). Rispecchia esattamente
//  `WalletReminderService`: notifiche locali idempotenti via identificatori
//  deterministici `walletdoc.<documentId>.<offsetSec>`.
//  Un solo promemoria, una settimana prima della scadenza — attivabile per
//  singolo documento tramite il toggle "Avvisami una settimana prima".
//

import Foundation
import UserNotifications

@MainActor
final class WalletDocumentReminderService {

    static let shared = WalletDocumentReminderService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// Un solo promemoria, una settimana prima della scadenza.
    static let defaultOffsets: [TimeInterval] = [-7 * 24 * 3600]

    func scheduleReminders(documentId: String, familyId: String, title: String, kind: KBWalletDocumentKind, expiryDate: Date) async {
        await cancelReminders(documentId: documentId)

        let prefEnabled = (UserDefaults.standard.object(forKey: "kb_notifyOnWalletReminder") as? Bool) ?? true
        guard prefEnabled else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let now = Date()
        for offset in Self.defaultOffsets {
            let fireDate = expiryDate.addingTimeInterval(offset)
            guard fireDate > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(kind.displayName) in scadenza"
            content.body = title.isEmpty ? kind.displayName : title
            content.sound = .default
            content.threadIdentifier = "kidbox.wallet.documents"
            content.userInfo = [
                "type": "wallet_document_reminder",
                "familyId": familyId,
                "documentId": documentId
            ]

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let identifier = Self.identifier(documentId: documentId, offset: offset)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                KBLog.sync.kbError("[WalletDocumentReminder] schedule FAIL \(identifier) err=\(error.localizedDescription)")
            }
        }
    }

    func cancelReminders(documentId: String) async {
        let pending = await center.pendingNotificationRequests()
        let prefix = "walletdoc.\(documentId)."
        let toRemove = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !toRemove.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: toRemove)
    }

    private static func identifier(documentId: String, offset: TimeInterval) -> String {
        "walletdoc.\(documentId).\(Int(offset))"
    }
}
