//
//  WalletPDFParser.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import Foundation
import PDFKit
import Vision

struct WalletParsedTicketData {
    let suggestedTitle: String
    let kind: KBWalletTicketKind
    let emitter: String?
    let eventDate: Date?
    let eventEndDate: Date?
    let location: String?
    let bookingCode: String?
    let addToAppleWalletURL: String?
    let barcodeText: String?
    let barcodeFormat: String?
    let notes: String?
}

enum WalletPDFParser {

    static func parse(pdfData: Data, fileName: String?) -> WalletParsedTicketData {
        guard let doc = PDFDocument(data: pdfData) else {
            let fallbackTitle = fallbackTitle(from: fileName)
            return WalletParsedTicketData(
                suggestedTitle: fallbackTitle,
                kind: .other,
                emitter: nil,
                eventDate: nil,
                eventEndDate: nil,
                location: nil,
                bookingCode: nil,
                addToAppleWalletURL: nil,
                barcodeText: nil,
                barcodeFormat: nil,
                notes: nil
            )
        }

        let text = extractText(from: doc)
        let detection = WalletEmitterDetector.detect(from: text)
        let (barcodeText, barcodeFormat) = extractBarcode(from: doc)
        let eventDate = extractDate(from: text)
        let addToWalletURL = extractWalletURL(from: doc, fullText: text)
        let location = extractLocation(from: text)
        let suggestedTitle = buildTitle(
            fileName: fileName,
            detection: detection,
            eventDate: eventDate,
            fallbackText: text
        )

        return WalletParsedTicketData(
            suggestedTitle: suggestedTitle,
            kind: detection.kind,
            emitter: detection.emitter,
            eventDate: eventDate,
            eventEndDate: nil,
            location: location,
            bookingCode: detection.bookingCode,
            addToAppleWalletURL: addToWalletURL,
            barcodeText: barcodeText,
            barcodeFormat: barcodeFormat,
            notes: extractShortNotes(from: text)
        )
    }

    private static func extractText(from doc: PDFDocument) -> String {
        var chunks: [String] = []
        let maxPages = min(doc.pageCount, 8)
        guard maxPages > 0 else { return "" }

        for idx in 0..<maxPages {
            if let pageText = doc.page(at: idx)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pageText.isEmpty {
                chunks.append(pageText)
            }
        }
        return chunks.joined(separator: "\n")
    }

    private static func extractBarcode(from doc: PDFDocument) -> (String?, String?) {
        let maxPages = min(doc.pageCount, 3)
        guard maxPages > 0 else { return (nil, nil) }

        for idx in 0..<maxPages {
            guard let page = doc.page(at: idx) else { continue }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 1800), for: .cropBox)
            guard let cg = image.cgImage else { continue }
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                if let obs = request.results?.first as? VNBarcodeObservation,
                   let payload = obs.payloadStringValue, !payload.isEmpty {
                    return (payload, obs.symbology.rawValue)
                }
            } catch {
                continue
            }
        }
        return (nil, nil)
    }

    private static func extractDate(from text: String) -> Date? {
        let patterns = [
            #"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})(?:\s+(\d{1,2}:\d{2}))?"#,
            #"(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}))?"#
        ]

        var candidates: [Date] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                guard let dateRange = Range(match.range(at: 1), in: text) else { continue }
                let datePart = String(text[dateRange])
                let timePart: String? = {
                    guard match.numberOfRanges > 2,
                          let range = Range(match.range(at: 2), in: text) else { return nil }
                    return String(text[range])
                }()
                if let parsed = parseDate(datePart: datePart, timePart: timePart) {
                    candidates.append(parsed)
                }
            }
        }

        let now = Date().addingTimeInterval(-24 * 3600)
        return candidates.filter { $0 >= now }.sorted().first ?? candidates.sorted().first
    }

    private static func parseDate(datePart: String, timePart: String?) -> Date? {
        let locale = Locale(identifier: "it_IT")
        let calendar = Calendar(identifier: .gregorian)
        let normalized = datePart.replacingOccurrences(of: "-", with: "/")
        let formats = [
            "d/M/yyyy HH:mm", "d/M/yy HH:mm",
            "dd/MM/yyyy HH:mm", "dd/MM/yy HH:mm",
            "yyyy/MM/dd HH:mm",
            "d/M/yyyy", "d/M/yy", "dd/MM/yyyy", "dd/MM/yy",
            "yyyy/MM/dd"
        ]

        let base = timePart.map { "\(normalized) \($0)" } ?? normalized
        for format in formats {
            if format.contains("HH:mm") != (timePart != nil) { continue }
            let f = DateFormatter()
            f.locale = locale
            f.calendar = calendar
            f.dateFormat = format
            if let d = f.date(from: base) { return d }
        }
        return nil
    }

    private static func extractWalletURL(from doc: PDFDocument, fullText: String) -> String? {
        let maxPages = min(doc.pageCount, 5)
        for idx in 0..<maxPages {
            guard let page = doc.page(at: idx) else { continue }
            for annotation in page.annotations {
                if let url = annotation.url?.absoluteString,
                   isAppleWalletURL(url) {
                    return url
                }
            }
        }

        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s\)"]+"#) else { return nil }
        let matches = regex.matches(in: fullText, range: NSRange(fullText.startIndex..., in: fullText))
        for match in matches {
            guard let range = Range(match.range, in: fullText) else { continue }
            let candidate = String(fullText[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            if isAppleWalletURL(candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isAppleWalletURL(_ value: String) -> Bool {
        let lower = value.lowercased()
        return lower.contains(".pkpass") || (lower.contains("wallet") && lower.contains("apple"))
    }

    private static func extractLocation(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for line in lines where line.count > 3 {
            let lower = line.lowercased()
            if lower.hasPrefix("da ") || lower.hasPrefix("a ") || lower.contains("stazione") || lower.contains("gate") {
                return line
            }
        }
        return nil
    }

    private static func extractShortNotes(from text: String) -> String? {
        let compact = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "\n")
        return compact.isEmpty ? nil : compact
    }

    private static func buildTitle(
        fileName: String?,
        detection: WalletEmitterDetection,
        eventDate: Date?,
        fallbackText: String
    ) -> String {
        if let emitter = detection.emitter {
            if let eventDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "it_IT")
                formatter.dateFormat = "dd MMM"
                return "\(emitter) • \(formatter.string(from: eventDate))"
            }
            return emitter
        }

        let fallback = fallbackTitle(from: fileName)
        if fallback != "Biglietto" { return fallback }

        let firstLine = fallbackText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.count <= 80 })
        return firstLine ?? "Biglietto"
    }

    private static func fallbackTitle(from fileName: String?) -> String {
        guard let fileName, !fileName.isEmpty else { return "Biglietto" }
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? "Biglietto" : base
    }
}
