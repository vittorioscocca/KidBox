//
//  NotificationService.swift
//  KidBoxNotificationService
//
//  Created by vscocca on 09/04/26.
//

import Foundation
import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    // DEBUG — rimuovere dopo il test
    func debugLog(_ message: String) {
        let defaults = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")
        var logs = defaults?.stringArray(forKey: "notif_debug_log") ?? []
        logs.append("\(Date()): \(message)")
        if logs.count > 20 { logs = Array(logs.suffix(20)) }
        defaults?.set(logs, forKey: "notif_debug_log")
    }
    
    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        debugLog("didReceive called")
        debugLog("userInfo keys: \(request.content.userInfo.keys.map { "\($0)" }.joined(separator: ", "))")
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard
            let content = bestAttemptContent,
            let familyId = content.userInfo["familyId"] as? String,
            let messageId = content.userInfo["messageId"] as? String,
            let uid = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                .string(forKey: "currentUserUID"),
            !uid.isEmpty
        else {
            contentHandler(bestAttemptContent ?? request.content)
            return
        }

        Task {
            do {
                let projectId = "kidbox-42cd7"
                let path = "families/\(familyId)/chatMessages/\(messageId)"
                let urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/\(path)"

                guard let url = URL(string: urlString) else {
                    contentHandler(content)
                    return
                }

                var urlRequest = URLRequest(url: url)
                if let token = UserDefaults(suiteName: "group.it.vittorioscocca.kidbox")?
                    .string(forKey: "firebaseIDToken") {
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                let (data, response) = try await URLSession.shared.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    contentHandler(content)
                    return
                }

                guard
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let fields = json["fields"] as? [String: Any],
                    let textEncField = fields["textEnc"] as? [String: Any],
                    let textEnc = textEncField["stringValue"] as? String,
                    !textEnc.isEmpty
                else {
                    contentHandler(content)
                    return
                }

                if let decrypted = try? NoteCryptoService.decryptString(
                    textEnc, familyId: familyId, userId: uid
                ) {
                    content.body = decrypted
                }
            } catch {
                // Fallback silenzioso
            }

            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
