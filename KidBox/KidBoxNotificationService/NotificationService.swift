//
//  NotificationService.swift
//  KidBoxNotificationService
//

import UserNotifications
import OSLog

/// Notification Service Extension — decrypts chat messages before display.
///
/// Flow:
///   1. FCM delivers a push with `mutable-content: 1` (set by the Cloud Function).
///   2. iOS invokes this extension, giving it up to 30 s to mutate the content.
///   3. We read `textEnc` (AES-GCM base64) from the data payload, load the
///      family key via `NoteCryptoService` / `FamilyKeychainStore`, decrypt, and
///      replace `bestAttemptContent.body` with the plaintext.
///   4. Non-text message types (photo, video, audio, …) pass through unchanged —
///      their body was already set correctly by the Cloud Function.
///
/// Keychain access: the main app and this extension share the keychain access group
/// `$(AppIdentifierPrefix)it.vittorioscocca.KidBox` (declared in both entitlements
/// files), so `FamilyKeychainStore.loadFamilyKey` works identically here.
final class NotificationService: UNNotificationServiceExtension {

    private let log = Logger(
        subsystem: "it.vittorioscocca.kidbox.notif",
        category: "Extension"
    )
    private let appGroupId = "group.it.vittorioscocca.kidbox"

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let best = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttemptContent = best

        let userInfo = request.content.userInfo

        // Only handle our own chat pushes.
        guard (userInfo["type"] as? String) == "new_chat_message" else {
            log.info("Non-chat push — passing through unchanged")
            contentHandler(best)
            return
        }

        let msgType = userInfo["msgType"] as? String ?? "text"

        // Non-text messages: the Cloud Function already set the correct emoji body.
        guard msgType == "text" else {
            log.info("Non-text chat push msgType=\(msgType) — passing through")
            contentHandler(best)
            return
        }

        // Read textEnc from the data payload (set by the Cloud Function).
        guard
            let textEnc = userInfo["textEnc"] as? String, !textEnc.isEmpty
        else {
            log.info("No textEnc in payload — keeping server-side body")
            applyFallback(best, userInfo: userInfo)
            contentHandler(best)
            return
        }

        guard
            let familyId = userInfo["familyId"] as? String, !familyId.isEmpty
        else {
            log.error("Missing familyId in chat push — cannot decrypt")
            applyFallback(best, userInfo: userInfo)
            contentHandler(best)
            return
        }

        // currentUserUID is written to the App Group by the main app on login.
        guard
            let uid = UserDefaults(suiteName: appGroupId)?
                .string(forKey: "currentUserUID"),
            !uid.isEmpty
        else {
            log.error("currentUserUID not found in App Group — cannot load family key")
            applyFallback(best, userInfo: userInfo)
            contentHandler(best)
            return
        }

        // Decrypt inline — no network call needed since textEnc is in the payload.
        do {
            let plaintext = try NoteCryptoService.decryptString(
                textEnc,
                familyId: familyId,
                userId: uid
            )
            log.info("Chat text decrypted successfully len=\(plaintext.count)")

            best.body = plaintext.count > 180
                ? String(plaintext.prefix(177)) + "…"
                : plaintext

            if let senderName = userInfo["senderName"] as? String, !senderName.isEmpty {
                best.title = senderName
            }
        } catch {
            log.error("Decrypt failed: \(error.localizedDescription, privacy: .public)")
            applyFallback(best, userInfo: userInfo)
        }

        contentHandler(best)
    }

    override func serviceExtensionTimeWillExpire() {
        // Time budget exhausted — deliver whatever we have so far.
        if let handler = contentHandler, let best = bestAttemptContent {
            handler(best)
        }
    }

    // MARK: - Helpers

    /// Sets the best-attempt body to the server-side fallback text (e.g. "Nuovo messaggio")
    /// that the Cloud Function computed and included as `fallbackBody` in the data payload.
    private func applyFallback(
        _ content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        if let fb = userInfo["fallbackBody"] as? String, !fb.isEmpty {
            content.body = fb
        }
    }
}
