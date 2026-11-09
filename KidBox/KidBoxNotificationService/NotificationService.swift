//
//  NotificationService.swift
//  KidBoxNotificationService
//

import UserNotifications
import OSLog

/// Notification Service Extension — decrypts chat messages before display,
/// e il testo delle push dei documenti sigillati (`secure`, vedi `applySecureText`).
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

        // Push di un documento sigillato (to-do, evento, spesa…): il testo
        // dell'utente arriva cifrato in `secure` e va decifrato qui.
        if let blob = userInfo["secure"] as? String, !blob.isEmpty {
            applySecureText(best, blob: blob, userInfo: userInfo)
            contentHandler(best)
            return
        }

        // Only handle our own chat pushes. Le menzioni usano lo stesso payload
        // di un messaggio normale ma con `type == "chat_mention"`: la NSE deve
        // decrittare comunque il `textEnc` e, se presente, sovrascrivere il
        // titolo per evidenziare che si tratta di una citazione diretta.
        let type = (userInfo["type"] as? String) ?? ""
        guard type == "new_chat_message" || type == "chat_mention" else {
            log.info("Non-chat push — passing through unchanged")
            contentHandler(best)
            return
        }
        let isMention = type == "chat_mention"

        let msgType = userInfo["msgType"] as? String ?? "text"

        // Non-text messages: the Cloud Function already set the correct emoji body.
        guard msgType == "text" else {
            log.info("Non-text chat push msgType=\(msgType) isMention=\(isMention) — passing through")
            if isMention {
                applyMentionTitleIfNeeded(best, userInfo: userInfo)
            }
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
            if isMention {
                applyMentionTitleIfNeeded(best, userInfo: userInfo)
            }
        } catch {
            log.error("Decrypt failed: \(error.localizedDescription, privacy: .public)")
            applyFallback(best, userInfo: userInfo)
            if isMention {
                applyMentionTitleIfNeeded(best, userInfo: userInfo)
            }
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

    /// Decifra il JSON di `secure` con la chiave di famiglia (come `textEnc`
    /// della chat) e riempie `titleTpl`/`bodyTpl`, già tradotti dal server.
    /// Qualunque intoppo (chiave, decifratura, segnaposto senza valore):
    /// restano titolo e testo generici arrivati con la push.
    /// Specifica: `internal/cifratura-sezioni.md`, secondo giro § 5.
    private func applySecureText(
        _ content: UNMutableNotificationContent,
        blob: String,
        userInfo: [AnyHashable: Any]
    ) {
        let coll = userInfo["secureColl"] as? String ?? ""
        guard
            let familyId = userInfo["secureFamilyId"] as? String, !familyId.isEmpty,
            let uid = UserDefaults(suiteName: appGroupId)?.string(forKey: "currentUserUID"), !uid.isEmpty
        else {
            log.error("Secure push coll=\(coll, privacy: .public): familyId o uid mancanti — testo generico")
            return
        }
        guard
            let json = try? NoteCryptoService.decryptString(blob, familyId: familyId, userId: uid),
            let values = SecurePushTemplate.values(fromJSON: json)
        else {
            log.error("Secure push coll=\(coll, privacy: .public): decifratura fallita — testo generico")
            return
        }
        guard let rendered = SecurePushTemplate.render(
            titleTemplate: userInfo["titleTpl"] as? String,
            bodyTemplate: userInfo["bodyTpl"] as? String,
            values: values
        ) else {
            log.info("Secure push coll=\(coll, privacy: .public): segnaposto senza valore — testo generico")
            return
        }
        if let title = rendered.title { content.title = title }
        if let body = rendered.body {
            content.body = body.count > 180 ? String(body.prefix(177)) + "…" : body
        }
        log.info("Secure push coll=\(coll, privacy: .public) decifrata")
    }

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

    /// Completa il titolo delle push `chat_mention`.
    ///
    /// Il titolo lo scrive già la Cloud Function, nella lingua scelta
    /// dal destinatario: riscriverlo qui lo riporterebbe in italiano, perché
    /// questa estensione non ha un proprio catalogo di stringhe. Resta solo il
    /// sottotitolo, anch'esso tradotto a monte e passato nel payload.
    private func applyMentionTitleIfNeeded(
        _ content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any]
    ) {
        if content.title.isEmpty {
            content.title = (userInfo["senderName"] as? String) ?? ""
        }
        if let subtitle = userInfo["mentionSubtitle"] as? String, !subtitle.isEmpty {
            content.subtitle = subtitle
        }
    }
}
