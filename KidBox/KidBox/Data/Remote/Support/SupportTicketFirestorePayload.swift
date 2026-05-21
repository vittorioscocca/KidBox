//
//  SupportTicketFirestorePayload.swift
//  KidBox
//

import FirebaseFirestore
import Foundation
import UIKit

/// Riduce il payload ticket sotto il limite Firestore (1 MiB). Nessun base64 in `conversation`.
enum SupportTicketFirestorePayload {
    static let firestoreMaxBytes = 1_048_576
    private static let safetyMarginBytes = 64_000
    private static let targetMaxBytes = firestoreMaxBytes - safetyMarginBytes
    static let maxLogBytes = 48 * 1024
    static let ticketImageMaxDimension: CGFloat = 720
    static let ticketJpegQuality: CGFloat = 0.78
    private static let maxSingleImageBytes = 180_000

    static func truncateLogs(_ raw: String) -> String {
        guard raw.utf8.count > maxLogBytes else { return raw }
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while !lines.isEmpty {
            let candidate = lines.joined(separator: "\n")
            if candidate.utf8.count <= maxLogBytes { return candidate }
            lines.removeFirst()
        }
        return String(raw.prefix(maxLogBytes))
    }

    static func conversationForFirestore(
        _ messages: [SupportConversationMessagePayload],
    ) -> [[String: Any]] {
        messages.map { msg in
            ["role": msg.role, "content": sanitizeContent(msg.content)]
        }
    }

    static func compactImages(_ base64List: [String]) -> [String] {
        base64List
            .prefix(SupportImageEncoder.maxImages)
            .compactMap { recompressBase64Jpeg($0) }
    }

    static func buildDocumentData(
        ticket: SupportTicketSubmitPayload,
        docId: String,
    ) throws -> [String: Any] {
        var images = compactImages(ticket.imagesBase64)
        var conversation = conversationForFirestore(ticket.conversation)
        var logs: String? = {
            guard ticket.type == "bug", let raw = ticket.rawLogs?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { return nil }
            return truncateLogs(raw)
        }()

        var data = coreFields(ticket: ticket, docId: docId, conversation: conversation, images: images, rawLogs: logs)
        var estimated = estimateMapBytes(data)

        while estimated > targetMaxBytes, !images.isEmpty {
            images.removeLast()
            data = coreFields(ticket: ticket, docId: docId, conversation: conversation, images: images, rawLogs: logs)
            estimated = estimateMapBytes(data)
        }
        while estimated > targetMaxBytes, let logText = logs, !logText.isEmpty {
            let shorter = String(logText.prefix(max(4_096, logText.count * 3 / 4)))
            logs = truncateLogs(shorter)
            data = coreFields(ticket: ticket, docId: docId, conversation: conversation, images: images, rawLogs: logs)
            estimated = estimateMapBytes(data)
            if (logs?.utf8.count ?? 0) <= 4_096 {
                logs = nil
                data = coreFields(ticket: ticket, docId: docId, conversation: conversation, images: images, rawLogs: nil)
                estimated = estimateMapBytes(data)
                break
            }
        }
        while estimated > targetMaxBytes, conversation.count > 2 {
            conversation.removeFirst()
            data = coreFields(ticket: ticket, docId: docId, conversation: conversation, images: images, rawLogs: logs)
            estimated = estimateMapBytes(data)
        }

        if estimated > firestoreMaxBytes {
            throw NSError(
                domain: "SupportTicket",
                code: 413,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Ticket troppo grande per Firestore. Rimuovi qualche screenshot e riprova.",
                ],
            )
        }
        return data
    }

    private static func coreFields(
        ticket: SupportTicketSubmitPayload,
        docId: String,
        conversation: [[String: Any]],
        images: [String],
        rawLogs: String?,
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": docId,
            "familyId": ticket.familyId,
            "uid": ticket.uid,
            "userEmail": ticket.userEmail,
            "type": ticket.type,
            "title": String(ticket.title.prefix(200)),
            "summary": String(ticket.summary.prefix(2000)),
            "conversation": conversation,
            "images": images,
            "platform": "ios",
            "appVersion": ticket.appVersion,
            "osVersion": ticket.osVersion,
            "device": ticket.device,
            "status": "new",
            "createdAt": FieldValue.serverTimestamp(),
        ]
        if let logs = rawLogs, !logs.isEmpty, ticket.type == "bug" {
            data["rawLogs"] = logs
        }
        return data
    }

    private static func sanitizeContent(_ content: Any) -> Any {
        if let text = content as? String {
            return String(text.prefix(16_000))
        }
        if let blocks = content as? [[String: Any]] {
            let imageCount = blocks.filter { ($0["type"] as? String)?.lowercased() == "image" }.count
            let text = blocks
                .filter { ($0["type"] as? String)?.lowercased() == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, imageCount > 0 {
                return "\(text)\n(\(imageCount) screenshot allegati — vedi campo images)"
            }
            if !text.isEmpty { return String(text.prefix(16_000)) }
            if imageCount > 0 { return "(\(imageCount) screenshot allegati — vedi campo images)" }
            return "(messaggio)"
        }
        return String("\(content)".prefix(16_000))
    }

    private static func recompressBase64Jpeg(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let image = UIImage(data: data) else { return nil }
        guard var jpeg = jpegData(from: image, maxDimension: ticketImageMaxDimension, quality: ticketJpegQuality)
        else { return nil }

        var quality = ticketJpegQuality
        while jpeg.count > maxSingleImageBytes, quality > 0.4 {
            quality -= 0.1
            guard let img = UIImage(data: jpeg),
                  let smaller = img.jpegData(compressionQuality: quality) else { break }
            jpeg = smaller
        }
        return jpeg.base64EncodedString()
    }

    private static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat,
        quality: CGFloat,
    ) -> Data? {
        let scaled = scale(image: image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: quality)
    }

    private static func scale(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private static func estimateMapBytes(_ map: [String: Any]) -> Int {
        var total = 128
        for (key, value) in map {
            total += key.utf8.count + 8
            total += estimateValueBytes(value)
        }
        return total
    }

    private static func estimateValueBytes(_ value: Any) -> Int {
        switch value {
        case let s as String: s.utf8.count + 16
        case let n as NSNumber: 16
        case let b as Bool: 8
        case let list as [Any]: list.reduce(0) { $0 + estimateValueBytes($1) } + 32
        case let dict as [String: Any]: estimateMapBytes(dict)
        default: "\(value)".utf8.count + 16
        }
    }
}
