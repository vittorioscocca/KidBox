//
//  FamilyRequestNotifications.swift
//  KidBox
//
//  Azioni «Ci penso io» / «Non posso» sulla push di una richiesta.
//
//  Il server manda `aps.category = "FAMILY_REQUEST"` (functions/familyRequests.js):
//  registrata la categoria, iOS mostra i due bottoni sotto la notifica.
//  «Ci penso io» apre l'app (`.foreground`) e poi il foglio della richiesta,
//  che dice com'è andata: magari qualcuno ha risposto prima. «Non posso» resta
//  in background; se la risposta non parte, una notifica locale lo dice e il
//  suo tap riapre la richiesta. Una risposta non deve mai perdersi in silenzio.
//

import Foundation
import UserNotifications
internal import os

enum FamilyRequestNotificationCategory {
    static let identifier = "FAMILY_REQUEST"
    static let actionYes = "FAMILY_REQUEST_YES"
    static let actionNo = "FAMILY_REQUEST_NO"

    /// `data.type` delle push di una richiesta.
    static let typeNew = "family_request"
    static let typeResolved = "family_request_resolved"

    static var category: UNNotificationCategory {
        let yes = UNNotificationAction(
            identifier: actionYes,
            title: NSLocalizedString("🙋 Ci penso io", comment: "Family request notification action: I'll do it"),
            options: [.foreground]
        )
        let no = UNNotificationAction(
            identifier: actionNo,
            title: NSLocalizedString("Non posso", comment: "Family request notification action: I can't"),
            options: [.authenticationRequired]
        )
        return UNNotificationCategory(
            identifier: identifier,
            actions: [yes, no],
            intentIdentifiers: [],
            options: []
        )
    }
}

enum FamilyRequestActionHandler {

    /// - Returns: `true` se era una delle due azioni (non un tap normale).
    static func handle(response: UNNotificationResponse) async -> Bool {
        let actionId = response.actionIdentifier
        guard actionId == FamilyRequestNotificationCategory.actionYes
                || actionId == FamilyRequestNotificationCategory.actionNo
        else { return false }

        let content = response.notification.request.content
        let userInfo = content.userInfo
        guard let familyId = userInfo["familyId"] as? String,
              let requestId = userInfo["requestId"] as? String
        else {
            KBLog.todo.kbError("FamilyRequestActionHandler: payload senza familyId/requestId")
            return true
        }

        let yes = actionId == FamilyRequestNotificationCategory.actionYes
        do {
            _ = try await FamilyRequestService.respond(familyId: familyId, requestId: requestId, yes: yes)
        } catch {
            await scheduleRetryNotice(familyId: familyId, requestId: requestId, body: content.body)
        }
        if yes {
            // L'app è in primo piano: il foglio mostra l'esito vero.
            await MainActor.run {
                NotificationManager.shared.handleNotificationUserInfo(userInfo)
            }
        }
        return true
    }

    private static func scheduleRetryNotice(familyId: String, requestId: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Risposta non inviata")
        content.body = body.isEmpty
            ? String(localized: "Tocca per riprovare.")
            : String(localized: "Tocca per riprovare: \(body)")
        content.sound = .default
        content.userInfo = [
            "type": FamilyRequestNotificationCategory.typeNew,
            "familyId": familyId,
            "requestId": requestId,
        ]
        let request = UNNotificationRequest(
            identifier: "family-request-retry-\(requestId)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            KBLog.todo.kbError("FamilyRequestActionHandler: avviso di riprova non creato err=\(error.localizedDescription)")
        }
    }
}
